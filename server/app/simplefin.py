"""SimpleFIN Bridge integration. Access URLs remain encrypted and server-side."""
from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import json
import logging
import os
import re
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from urllib.parse import unquote, urlsplit, urlunsplit

import httpx
from cryptography.fernet import Fernet, InvalidToken
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, Field

from .db import db, many, new_id, now_iso, one
from .classifier import classify_transaction

log = logging.getLogger("family.simplefin")
MAX_DAYS = 90
OVERLAP_DAYS = 5
MIN_REQUEST_SECONDS = 3600
AUTO_SYNC_HOURS = 20
TRUSTED_DOMAIN = "simplefin.org"
MAX_PROVIDER_BYTES = 8 * 1024 * 1024
MAX_ACCOUNTS = 100
MAX_TRANSACTIONS = 10_000


class ConnectBody(BaseModel):
    setup_token: str = Field(min_length=8, max_length=4096)


def _fernet() -> Fernet:
    key = os.environ.get("SIMPLEFIN_ENCRYPTION_KEY", "")
    if not key:
        raise HTTPException(503, "SimpleFIN is not configured on the server.")
    try:
        return Fernet(key.encode("ascii"))
    except (ValueError, UnicodeEncodeError):
        raise HTTPException(503, "SimpleFIN encryption is not configured correctly.")


def _encryption_configured() -> bool:
    try:
        _fernet()
        return True
    except HTTPException:
        return False


def _trusted_https_url(raw: str, *, claim: bool = False) -> str:
    try:
        parts = urlsplit(raw.strip())
        host = (parts.hostname or "").lower().rstrip(".")
        allowed = host == TRUSTED_DOMAIN or host.endswith("." + TRUSTED_DOMAIN)
        if parts.scheme != "https" or not allowed or not parts.path.startswith("/"):
            raise ValueError
        if parts.query or parts.fragment:
            raise ValueError
        if parts.port not in (None, 443):
            raise ValueError
        if claim and (parts.username is not None or parts.password is not None):
            raise ValueError
        if claim and not (
            parts.path.rstrip("/") == "/simplefin/claim"
            or parts.path.startswith("/simplefin/claim/")
        ):
            raise ValueError
        return raw.strip()
    except Exception:
        raise HTTPException(400, "The SimpleFIN token or Access URL is invalid.")


def _decode_setup_token(token: str) -> str:
    try:
        encoded = token.strip()
        padded = encoded + "=" * (-len(encoded) % 4)
        raw = base64.b64decode(padded.encode("ascii"), altchars=b"-_", validate=True).decode("utf-8").strip()
    except (ValueError, UnicodeError, binascii.Error):
        raise HTTPException(400, "The SimpleFIN Setup Token is invalid.")
    return _trusted_https_url(raw, claim=True)


def _validate_access_url(raw: str) -> str:
    safe = _trusted_https_url(raw)
    parts = urlsplit(safe)
    if not parts.username or not parts.password:
        raise HTTPException(502, "SimpleFIN returned an invalid Access URL.")
    if parts.query or parts.fragment:
        raise HTTPException(502, "SimpleFIN returned an invalid Access URL.")
    # Store exactly what Bridge returned; never return it to the phone.
    return safe


def _access_parts(raw: str) -> tuple[str, httpx.BasicAuth]:
    parts = urlsplit(_trusted_https_url(raw))
    host = parts.hostname or ""
    port = f":{parts.port}" if parts.port else ""
    path = parts.path.rstrip("/") + "/accounts"
    url = urlunsplit(("https", host + port, path, "", ""))
    return url, httpx.BasicAuth(unquote(parts.username or ""), unquote(parts.password or ""))


def _date_timestamp(day: date) -> int:
    return int(datetime(day.year, day.month, day.day, tzinfo=timezone.utc).timestamp())


def _posted_day(value) -> str | None:
    try:
        stamp = int(value)
        return datetime.fromtimestamp(stamp, timezone.utc).date().isoformat()
    except (TypeError, ValueError, OverflowError, OSError):
        return None


def _amount(raw) -> tuple[int, str] | None:
    try:
        value = Decimal(str(raw))
        cents = int((value * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        if cents == 0 or abs(cents) > 100_000_000:
            return None
        return abs(cents), "income" if cents > 0 else "expense"
    except (InvalidOperation, ValueError, TypeError):
        return None


def _categorize(conn, family_id: str, description: str, kind: str) -> str | None:
    direction = "inflow" if kind == "income" else "outflow"
    _, category_id, _ = classify_transaction(conn, family_id, description, kind, direction)
    return category_id


def _parse_provider_accounts(payload) -> list[dict]:
    if not isinstance(payload, dict) or not isinstance(payload.get("accounts"), list):
        raise ValueError("invalid payload")
    accounts = payload["accounts"]
    if len(accounts) > MAX_ACCOUNTS:
        raise ValueError("too many accounts")
    total = sum(len(a.get("transactions", [])) for a in accounts if isinstance(a, dict) and isinstance(a.get("transactions", []), list))
    if total > MAX_TRANSACTIONS:
        raise ValueError("too many transactions")
    return [account for account in accounts if isinstance(account, dict)]


def _identity_key(value) -> str | None:
    raw = str(value or "")
    if not raw or len(raw) > 2048:
        return None
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _sync_family(family_id: str, *, force: bool = False) -> dict:
    with db() as conn:
        conn.execute("BEGIN IMMEDIATE")
        connection = one(conn, "SELECT * FROM simplefin_connections WHERE family_id = ?", (family_id,))
        if connection is None:
            raise HTTPException(404, "SimpleFIN is not connected.")
        now = datetime.now(timezone.utc)
        if connection["last_attempt_at"]:
            try:
                last_attempt = datetime.fromisoformat(connection["last_attempt_at"].replace("Z", "+00:00"))
                if (now - last_attempt).total_seconds() < MIN_REQUEST_SECONDS:
                    raise HTTPException(429, "Please wait before syncing SimpleFIN again.")
            except ValueError:
                pass
        if not force and connection["last_synced_at"]:
            last = datetime.fromisoformat(connection["last_synced_at"].replace("Z", "+00:00"))
            if (now - last).total_seconds() < AUTO_SYNC_HOURS * 3600:
                return {"ok": True, "imported": 0, "skipped": 0, "last_synced_at": connection["last_synced_at"]}
        encrypted = connection["access_url_encrypted"]
        conn.execute("UPDATE simplefin_connections SET last_attempt_at = ?, last_error = NULL WHERE family_id = ?", (now_iso(), family_id))
    try:
        access_url = _fernet().decrypt(encrypted.encode("ascii")).decode("utf-8")
        url, auth = _access_parts(access_url)
        start_day = (now.date() - timedelta(days=30))
        if connection["last_synced_at"]:
            try:
                previous = datetime.fromisoformat(connection["last_synced_at"].replace("Z", "+00:00")).date()
                start_day = previous - timedelta(days=OVERLAP_DAYS)
            except ValueError:
                pass
        start_day = max(start_day, now.date() - timedelta(days=MAX_DAYS))
        params = {"version": "2", "start-date": str(_date_timestamp(start_day)), "end-date": str(int(now.timestamp()))}
        raw_payload = bytearray()
        with httpx.Client(timeout=25, follow_redirects=False, verify=True) as client:
            with client.stream("GET", url, params=params, auth=auth) as response:
                if response.status_code == 403:
                    raise PermissionError("revoked")
                if response.status_code == 402:
                    raise RuntimeError("payment")
                response.raise_for_status()
                declared_length = response.headers.get("content-length")
                if declared_length and int(declared_length) > MAX_PROVIDER_BYTES:
                    raise ValueError("response too large")
                for chunk in response.iter_bytes():
                    if len(raw_payload) + len(chunk) > MAX_PROVIDER_BYTES:
                        raise ValueError("response too large")
                    raw_payload.extend(chunk)
        accounts = _parse_provider_accounts(json.loads(raw_payload))
    except HTTPException:
        raise
    except (httpx.HTTPError, ValueError, TypeError, InvalidToken, UnicodeError, PermissionError, RuntimeError, json.JSONDecodeError):
        with db() as conn:
            conn.execute("UPDATE simplefin_connections SET last_error = ? WHERE family_id = ?", ("SimpleFIN could not be reached or authorized. Reconnect if needed.", family_id))
        raise HTTPException(502, "SimpleFIN sync failed. Check the connection and try again later.")

    imported = skipped = 0
    with db() as conn:
        for account in accounts:
            account_id = _identity_key(account.get("id"))
            txns = account.get("transactions", [])
            if not account_id or not isinstance(txns, list):
                continue
            for item in txns:
                if not isinstance(item, dict):
                    continue
                txn_id = _identity_key(item.get("id"))
                if not txn_id or item.get("pending") is True:
                    continue
                day = _posted_day(item.get("posted"))
                parsed = _amount(item.get("amount"))
                description = re.sub(r"\s+", " ", str(item.get("description") or "SimpleFIN transaction")).strip()[:80] or "SimpleFIN transaction"
                if not day or not parsed:
                    continue
                cents, initial_kind = parsed
                direction = "inflow" if initial_kind == "income" else "outflow"
                kind, category_id, _ = classify_transaction(
                    conn, family_id, description, initial_kind, direction
                )
                row_id = new_id()
                mapping = conn.execute(
                    "INSERT OR IGNORE INTO simplefin_transaction_ids (family_id, connection_id, account_identity, transaction_identity, transaction_id) VALUES (?, ?, ?, ?, ?)",
                    (family_id, connection["connection_id"], account_id, txn_id, row_id),
                )
                if mapping.rowcount == 0:
                    skipped += 1
                    continue
                conn.execute("""
                    INSERT INTO transactions (id, family_id, category_id, member_id, merchant, amount_cents, kind, direction, occurred_on, note, source, created_at)
                    VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?, NULL, 'simplefin', ?)
                """, (row_id, family_id, category_id, description, cents, kind, direction, day, now_iso()))
                imported += 1
        synced = now_iso()
        conn.execute("UPDATE simplefin_connections SET last_synced_at = ?, last_error = NULL WHERE family_id = ?", (synced, family_id))
    return {"ok": True, "imported": imported, "skipped": skipped, "last_synced_at": synced}


def register_routes(app: FastAPI, require_user) -> None:
    @app.get("/v1/simplefin/status")
    def simplefin_status(auth=Depends(require_user)):
        with db() as conn:
            row = one(conn, "SELECT last_synced_at, last_error FROM simplefin_connections WHERE family_id = ?", (auth["family_id"],))
        return {"connected": row is not None, "encryption_configured": _encryption_configured(), "last_synced_at": row["last_synced_at"] if row else None, "last_error": row["last_error"] if row else None}

    @app.post("/v1/simplefin/connect")
    def connect_simplefin(body: ConnectBody, auth=Depends(require_user)):
        fernet = _fernet()
        claim_url = _decode_setup_token(body.setup_token)
        try:
            with httpx.Client(timeout=20, follow_redirects=False, verify=True) as client:
                response = client.post(claim_url)
            response.raise_for_status()
            access_url = _validate_access_url(response.text)
        except HTTPException:
            raise
        except httpx.HTTPError:
            raise HTTPException(400, "SimpleFIN could not claim that Setup Token. Use a fresh token and try again.")
        encrypted = fernet.encrypt(access_url.encode("utf-8")).decode("ascii")
        with db() as conn:
            conn.execute("""
                INSERT INTO simplefin_connections (family_id, connection_id, access_url_encrypted, created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(family_id) DO UPDATE SET access_url_encrypted = excluded.access_url_encrypted,
                    created_at = excluded.created_at, last_synced_at = NULL, last_attempt_at = NULL, last_error = NULL
            """, (auth["family_id"], new_id(), encrypted, now_iso()))
        return {"connected": True, "message": "SimpleFIN connected. Sync transactions to get started."}

    @app.post("/v1/simplefin/sync")
    def sync_simplefin(auth=Depends(require_user)):
        return _sync_family(auth["family_id"], force=True)

    @app.delete("/v1/simplefin/connection")
    def disconnect_simplefin(auth=Depends(require_user)):
        with db() as conn:
            conn.execute("DELETE FROM simplefin_connections WHERE family_id = ?", (auth["family_id"],))
        return {"ok": True}


async def simplefin_poller() -> None:
    while True:
        try:
            with db() as conn:
                families = [row["family_id"] for row in many(conn, "SELECT family_id FROM simplefin_connections")]
            for family_id in families:
                try:
                    await asyncio.to_thread(_sync_family, family_id)
                except HTTPException:
                    pass
                except Exception:
                    log.warning("Scheduled SimpleFIN sync failed for a household")
        except Exception:
            log.warning("SimpleFIN poll cycle failed")
        await asyncio.sleep(3600)
