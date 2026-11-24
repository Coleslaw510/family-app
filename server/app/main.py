"""Family App API. One family, a handful of people, SQLite on disk."""

from __future__ import annotations

import asyncio
import calendar
import ipaddress
import logging
import os
import secrets
import sqlite3
import time
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import budget as budget_math
from .classifier import classify_transaction
from .db import db, hash_secret, many, month_bounds, new_id, now_iso, one, plus_days, plus_hours, seed_categories

log = logging.getLogger("family")
VERSION = "1.4.0"
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
EXTRA_COLORS = ["#2563eb", "#0f766e", "#b45309", "#0369a1", "#7c3aed", "#be185d", "#ea580c", "#475569"]


class AttemptLimiter:
    def __init__(self) -> None:
        self.fails: dict[str, list[float]] = {}

    def ensure(self, bucket: str, limit: int, window: int) -> None:
        now = time.time()
        arr = [stamp for stamp in self.fails.get(bucket, []) if now - stamp < window]
        self.fails[bucket] = arr
        if len(arr) >= limit:
            raise HTTPException(status_code=429, detail="Too many attempts. Try again later.")

    def fail(self, bucket: str) -> None:
        self.fails.setdefault(bucket, []).append(time.time())


def create_app() -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        with db():
            pass
        from .v11 import feed_poller
        from .simplefin import simplefin_poller

        poller = asyncio.create_task(feed_poller())
        simplefin_task = asyncio.create_task(simplefin_poller())
        log.info("Family App API %s ready", VERSION)
        try:
            yield
        finally:
            poller.cancel()
            simplefin_task.cancel()

    app = FastAPI(title="Family App", version=VERSION, lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.state.limiter = AttemptLimiter()

    @app.get("/health")
    def health():
        return {"ok": True, "version": VERSION}

    @app.get("/")
    def root():
        return {"name": "Family App", "version": VERSION, "health": "/health", "docs": "/docs"}

    @app.post("/v1/families")
    def create_family(body: CreateFamilyIn, request: Request):
        ip = client_ip(request)
        limiter: AttemptLimiter = request.app.state.limiter
        limit = int(os.environ.get("CREATE_MAX_ATTEMPTS", "8"))
        window = int(os.environ.get("CREATE_WINDOW_SECONDS", "3600"))
        limiter.ensure(f"create:{ip}", limit, window)
        limiter.fail(f"create:{ip}")
        name = clean_name(body.name)
        family_name = clean_name(body.family_name) if body.family_name else f"{name.split()[0]}'s family"
        with db() as conn:
            family_id = new_id()
            member_id = new_id()
            created = now_iso()
            conn.execute(
                "INSERT INTO families (id, name, created_at, flower_nudge_days) VALUES (?, ?, ?, 14)",
                (family_id, family_name, created),
            )
            conn.execute(
                "INSERT INTO members (id, family_id, name, created_at) VALUES (?, ?, ?, ?)",
                (member_id, family_id, name, created),
            )
            seed_categories(conn, family_id)
            token, exp = issue_session(conn, member_id)
            code, code_exp = issue_code(conn, family_id)
            family = one(conn, "SELECT * FROM families WHERE id = ?", (family_id,))
            member = one(conn, "SELECT * FROM members WHERE id = ?", (member_id,))
        return {
            "token": token,
            "token_expires_at": exp,
            "join_code": code,
            "join_code_expires_at": code_exp,
            "family": family_out(family),
            "member": member_out(member),
            "members": [member_out(member)],
        }

    @app.post("/v1/families/join")
    def join_family(body: JoinIn, request: Request):
        ip = client_ip(request)
        limiter: AttemptLimiter = request.app.state.limiter
        limit = int(os.environ.get("JOIN_MAX_ATTEMPTS", "8"))
        window = int(os.environ.get("JOIN_WINDOW_SECONDS", "900"))
        limiter.ensure(f"join:{ip}", limit, window)
        code = normalize_code(body.code)
        if len(code) < 4:
            limiter.fail(f"join:{ip}")
            raise HTTPException(400, "That code is invalid or expired.")
        name = clean_name(body.name)
        code_hash = hash_secret(code)
        with db() as conn:
            row = one(
                conn,
                """
                SELECT * FROM join_codes
                WHERE code_hash = ? AND used_at IS NULL
                ORDER BY created_at DESC LIMIT 1
                """,
                (code_hash,),
            )
            now = now_iso()
            if row is None or row["expires_at"] < now:
                limiter.fail(f"join:{ip}")
                raise HTTPException(400, "That code is invalid or expired.")
            count = one(conn, "SELECT COUNT(*) AS n FROM members WHERE family_id = ?", (row["family_id"],))
            if int(count["n"]) >= 12:
                raise HTTPException(400, "This family is full.")
            member_id = new_id()
            conn.execute(
                "INSERT INTO members (id, family_id, name, created_at) VALUES (?, ?, ?, ?)",
                (member_id, row["family_id"], name, now),
            )
            conn.execute(
                "UPDATE join_codes SET used_at = ?, used_by = ? WHERE id = ?",
                (now, member_id, row["id"]),
            )
            token, exp = issue_session(conn, member_id)
            family = one(conn, "SELECT * FROM families WHERE id = ?", (row["family_id"],))
            member = one(conn, "SELECT * FROM members WHERE id = ?", (member_id,))
            members = many(conn, "SELECT * FROM members WHERE family_id = ? ORDER BY created_at", (row["family_id"],))
        return {
            "token": token,
            "token_expires_at": exp,
            "join_code": None,
            "join_code_expires_at": None,
            "family": family_out(family),
            "member": member_out(member),
            "members": [member_out(m) for m in members],
        }

    @app.post("/v1/budget-app/pairing-code")
    def create_budget_pairing_code(auth=Depends(require_user)):
        code = "".join(secrets.choice(ALPHABET) for _ in range(12))
        created = now_iso()
        expires = (datetime.now(timezone.utc) + timedelta(minutes=10)).strftime("%Y-%m-%dT%H:%M:%SZ")
        with db() as conn:
            conn.execute("DELETE FROM budget_pairings WHERE member_id = ?", (auth["member_id"],))
            conn.execute(
                "INSERT INTO budget_pairings (code_hash, family_id, member_id, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
                (hash_secret(code), auth["family_id"], auth["member_id"], created, expires),
            )
        return {"pairing_code": code, "expires_at": expires}

    @app.post("/v1/budget-app/redeem")
    def redeem_budget_pairing(body: PairingRedeemIn, request: Request):
        ip = client_ip(request)
        limiter: AttemptLimiter = request.app.state.limiter
        limiter.ensure(f"budget-pair:{ip}", limit=8, window=900)
        code = normalize_code(body.code)
        if len(code) != 12:
            limiter.fail(f"budget-pair:{ip}")
            raise HTTPException(400, "That pairing code is invalid, expired, or already used.")
        with db() as conn:
            conn.execute("BEGIN IMMEDIATE")
            row = one(conn, "SELECT * FROM budget_pairings WHERE code_hash = ?", (hash_secret(code),))
            now = now_iso()
            if row is None or row["used_at"] is not None or row["expires_at"] < now:
                limiter.fail(f"budget-pair:{ip}")
                raise HTTPException(400, "That pairing code is invalid, expired, or already used.")
            member = one(conn, "SELECT * FROM members WHERE id = ? AND family_id = ?", (row["member_id"], row["family_id"]))
            family = one(conn, "SELECT * FROM families WHERE id = ?", (row["family_id"],))
            if member is None or family is None:
                limiter.fail(f"budget-pair:{ip}")
                raise HTTPException(400, "That pairing code is invalid, expired, or already used.")
            changed = conn.execute(
                "UPDATE budget_pairings SET used_at = ? WHERE code_hash = ? AND used_at IS NULL",
                (now, row["code_hash"]),
            ).rowcount
            if not changed:
                limiter.fail(f"budget-pair:{ip}")
                raise HTTPException(400, "That pairing code is invalid, expired, or already used.")
            token, expires = issue_session(conn, member["id"])
            members = many(conn, "SELECT * FROM members WHERE family_id = ? ORDER BY created_at", (family["id"],))
        return {
            "token": token,
            "token_expires_at": expires,
            "join_code": None,
            "join_code_expires_at": None,
            "family": family_out(family),
            "member": member_out(member),
            "members": [member_out(item) for item in members],
        }

    @app.post("/v1/logout")
    def logout(authorization: Annotated[str | None, Header()] = None):
        token = parse_bearer(authorization)
        with db() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash = ?", (hash_secret(token),))
        return {"ok": True}

    @app.get("/v1/me")
    def me(auth=Depends(require_user)):
        with db() as conn:
            return profile(conn, auth)

    @app.patch("/v1/me")
    def patch_me(body: NameIn, auth=Depends(require_user)):
        name = clean_name(body.name)
        with db() as conn:
            conn.execute("UPDATE members SET name = ? WHERE id = ?", (name, auth["member_id"]))
            return profile(conn, auth)

    @app.patch("/v1/family")
    def patch_family(body: FamilyPatch, auth=Depends(require_user)):
        with db() as conn:
            if body.name is not None:
                conn.execute(
                    "UPDATE families SET name = ? WHERE id = ?",
                    (clean_name(body.name), auth["family_id"]),
                )
            return profile(conn, auth)

    @app.post("/v1/join-codes")
    def new_join_code(auth=Depends(require_user)):
        with db() as conn:
            since = plus_hours(-24)
            count = one(
                conn,
                "SELECT COUNT(*) AS n FROM join_codes WHERE family_id = ? AND created_at >= ?",
                (auth["family_id"], since),
            )
            if int(count["n"]) >= 10:
                raise HTTPException(429, "Too many join codes today.")
            code, exp = issue_code(conn, auth["family_id"])
        return {"join_code": code, "join_code_expires_at": exp}

    @app.get("/v1/dashboard")
    def dashboard(
        today: str | None = None,
        auth=Depends(require_user),
    ):
        day = parse_today(today)
        with db() as conn:
            return build_dashboard(conn, auth, day)

    @app.get("/v1/budget")
    def get_budget(month: str | None = None, today: str | None = None, auth=Depends(require_user)):
        day = parse_today(today)
        key = month or day.strftime("%Y-%m")
        parse_month(key)
        with db() as conn:
            return budget_math.build_budget(conn, auth["family_id"], key, day)

    @app.post("/v1/budget/suggest")
    def post_suggest(body: SuggestIn, auth=Depends(require_user)):
        parse_month(body.month)
        day = parse_today(body.today)
        with db() as conn:
            result = budget_math.suggest(conn, auth["family_id"], body.month, day, body.apply)
        return result

    @app.get("/v1/categories")
    def list_categories(auth=Depends(require_user)):
        with db() as conn:
            rows = many(
                conn,
                "SELECT * FROM categories WHERE family_id = ? AND archived = 0 ORDER BY sort_order, name",
                (auth["family_id"],),
            )
        return {"categories": [category_out(r) for r in rows]}

    @app.post("/v1/categories")
    def create_category(body: CategoryIn, auth=Depends(require_user)):
        with db() as conn:
            cid = insert_category(conn, auth["family_id"], body.name, body.color, body.icon, body.default_budget_cents or 0)
            row = one(conn, "SELECT * FROM categories WHERE id = ?", (cid,))
        return category_out(row)

    @app.patch("/v1/categories/{category_id}")
    def patch_category(category_id: str, body: CategoryPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_category(conn, auth["family_id"], category_id)
            name = clean_text(body.name, "Name", 60) if body.name is not None else row["name"]
            color = clean_color(body.color) if body.color is not None else row["color"]
            icon = clean_text(body.icon, "Icon", 40) if body.icon is not None else row["icon"]
            default_budget = row["default_budget_cents"]
            if body.default_budget_cents is not None:
                check_cents(body.default_budget_cents)
                default_budget = body.default_budget_cents
            sort_order = row["sort_order"] if body.sort_order is None else int(body.sort_order)
            conn.execute(
                """
                UPDATE categories
                SET name = ?, color = ?, icon = ?, default_budget_cents = ?, sort_order = ?
                WHERE id = ?
                """,
                (name, color, icon, default_budget, sort_order, category_id),
            )
            row = one(conn, "SELECT * FROM categories WHERE id = ?", (category_id,))
        return category_out(row)

    @app.delete("/v1/categories/{category_id}")
    def delete_category(
        category_id: str,
        reassign_to: str | None = None,
        auth=Depends(require_user),
    ):
        with db() as conn:
            own_category(conn, auth["family_id"], category_id)
            count = one(
                conn,
                "SELECT COUNT(*) AS n FROM transactions WHERE family_id = ? AND category_id = ?",
                (auth["family_id"], category_id),
            )
            txn_count = int(count["n"])
            if txn_count and reassign_to is None:
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": "Choose where this category's transactions should go.",
                        "transaction_count": txn_count,
                    },
                )
            target = None
            if reassign_to and reassign_to not in {"uncategorized", "none"}:
                if reassign_to == category_id:
                    raise HTTPException(400, "Pick a different category.")
                own_category(conn, auth["family_id"], reassign_to)
                target = reassign_to
            conn.execute(
                "UPDATE transactions SET category_id = ? WHERE category_id = ? AND family_id = ?",
                (target, category_id, auth["family_id"]),
            )
            conn.execute(
                "DELETE FROM category_rules WHERE category_id = ? AND family_id = ?",
                (category_id, auth["family_id"]),
            )
            conn.execute("DELETE FROM transaction_rules WHERE category_id = ? AND family_id = ?", (category_id, auth["family_id"]))
            conn.execute("DELETE FROM category_budgets WHERE category_id = ?", (category_id,))
            conn.execute("DELETE FROM categories WHERE id = ?", (category_id,))
        return {"ok": True, "moved": txn_count, "reassign_to": target}

    @app.put("/v1/categories/{category_id}/budget")
    def put_budget(category_id: str, body: BudgetSetIn, auth=Depends(require_user)):
        parse_month(body.month)
        check_cents(body.amount_cents)
        with db() as conn:
            own_category(conn, auth["family_id"], category_id)
            conn.execute(
                """
                INSERT INTO category_budgets (category_id, month, amount_cents)
                VALUES (?, ?, ?)
                ON CONFLICT(category_id, month) DO UPDATE SET amount_cents = excluded.amount_cents
                """,
                (category_id, body.month, body.amount_cents),
            )
            if body.set_default:
                conn.execute(
                    "UPDATE categories SET default_budget_cents = ? WHERE id = ?",
                    (body.amount_cents, category_id),
                )
        return {"ok": True, "month": body.month, "amount_cents": body.amount_cents}

    @app.get("/v1/transactions")
    def list_txns(
        month: str | None = None,
        category_id: str | None = None,
        limit: int = Query(default=200, ge=1, le=1000),
        auth=Depends(require_user),
    ):
        start = end = None
        if month:
            parse_month(month)
            span_start, span_end = month_bounds(month)
            start, end = span_start.isoformat(), span_end.isoformat()
        with db() as conn:
            if category_id:
                own_category(conn, auth["family_id"], category_id)
            return {
                "transactions": budget_math._transactions(
                    conn, auth["family_id"], start, end, limit, category_id=category_id
                )
            }

    @app.post("/v1/transactions")
    def create_txn(body: TxnIn, auth=Depends(require_user)):
        occurred = parse_date(body.occurred_on)
        check_cents(body.amount_cents)
        kind = clean_kind(body.kind)
        direction = clean_direction(body.direction or ("inflow" if kind == "income" else "outflow"))
        merchant = clean_text(body.merchant, "Merchant", 80)
        category_id = body.category_id or None
        if kind != "expense":
            category_id = None
        with db() as conn:
            if category_id:
                own_category(conn, auth["family_id"], category_id)
            tid = new_id()
            conn.execute(
                """
                INSERT INTO transactions (
                    id, family_id, category_id, member_id, merchant, amount_cents,
                    kind, direction, occurred_on, note, source, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'manual', ?)
                """,
                (
                    tid,
                    auth["family_id"],
                    category_id,
                    auth["member_id"],
                    merchant,
                    body.amount_cents,
                    kind,
                    direction,
                    occurred,
                    blank(body.note),
                    now_iso(),
                ),
            )
            return txn_by_id(conn, auth["family_id"], tid)

    @app.patch("/v1/transactions/{txn_id}")
    def patch_txn(txn_id: str, body: TxnPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "transactions", txn_id, auth["family_id"])
            merchant = clean_text(body.merchant, "Merchant", 80) if body.merchant is not None else row["merchant"]
            amount = row["amount_cents"]
            if body.amount_cents is not None:
                check_cents(body.amount_cents)
                amount = body.amount_cents
            kind = clean_kind(body.kind) if body.kind is not None else row["kind"]
            direction = clean_direction(body.direction) if body.direction is not None else row["direction"]
            if body.direction is None and body.kind == "income":
                direction = "inflow"
            elif body.direction is None and body.kind == "expense":
                direction = "outflow"
            occurred = parse_date(body.occurred_on) if body.occurred_on is not None else row["occurred_on"]
            category_id = row["category_id"]
            if "category_id" in body.model_fields_set:
                category_id = body.category_id or None
                if category_id:
                    own_category(conn, auth["family_id"], category_id)
            if kind != "expense":
                category_id = None
            note = row["note"] if body.note is None and "note" not in body.model_fields_set else blank(body.note)
            if "note" in body.model_fields_set:
                note = blank(body.note)
            conn.execute(
                """
                UPDATE transactions
                SET merchant = ?, amount_cents = ?, kind = ?, direction = ?, occurred_on = ?, category_id = ?, note = ?
                WHERE id = ? AND family_id = ?
                """,
                (merchant, amount, kind, direction, occurred, category_id, note, txn_id, auth["family_id"]),
            )
            return txn_by_id(conn, auth["family_id"], txn_id)

    @app.delete("/v1/transactions/{txn_id}")
    def delete_txn(txn_id: str, auth=Depends(require_user)):
        with db() as conn:
            removed = conn.execute(
                "DELETE FROM transactions WHERE id = ? AND family_id = ?",
                (txn_id, auth["family_id"]),
            ).rowcount
        if not removed:
            raise HTTPException(404, "Not found")
        return {"ok": True}

    @app.post("/v1/transactions/import")
    def import_txns(body: ImportIn, auth=Depends(require_user)):
        if not body.rows:
            raise HTTPException(400, "Nothing to import.")
        if len(body.rows) > 5000:
            raise HTTPException(400, "Import up to 5000 rows at a time.")
        prepared = []
        for index, row in enumerate(body.rows, start=1):
            try:
                occurred = parse_date(row.date)
                merchant = clean_text(row.merchant, "Merchant", 80)
                check_cents(row.amount_cents)
                kind = clean_kind(row.kind or "expense")
            except HTTPException as exc:
                raise HTTPException(400, f"Row {index}: {exc.detail}") from exc
            direction = "inflow" if kind == "income" else "outflow"
            prepared.append((occurred, merchant, row.amount_cents, kind, direction, blank(row.category)))
        with db() as conn:
            imported = 0
            skipped = 0
            created_categories = 0
            for occurred, merchant, amount, initial_kind, direction, category_name in prepared:
                kind, category_id, matched_rule = classify_transaction(
                    conn, auth["family_id"], merchant, initial_kind, direction
                )
                if category_name and kind == "expense" and matched_rule is None:
                    imported_category_id, made = match_or_create_category(conn, auth["family_id"], category_name)
                    created_categories += int(made)
                    if imported_category_id:
                        category_id = imported_category_id
                existing = one(
                    conn,
                    """
                    SELECT id FROM transactions
                    WHERE family_id = ? AND occurred_on = ? AND merchant = ?
                      AND amount_cents = ? AND direction = ? AND source = 'import'
                    """,
                    (auth["family_id"], occurred, merchant, amount, direction),
                )
                if existing:
                    skipped += 1
                    continue
                conn.execute(
                    """
                    INSERT INTO transactions (
                        id, family_id, category_id, member_id, merchant, amount_cents,
                        kind, direction, occurred_on, note, source, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 'import', ?)
                    """,
                    (
                        new_id(),
                        auth["family_id"],
                        category_id,
                        auth["member_id"],
                        merchant,
                        amount,
                        kind,
                        direction,
                        occurred,
                        now_iso(),
                    ),
                )
                imported += 1
        return {"imported": imported, "skipped": skipped, "created_categories": created_categories}

    @app.get("/v1/income")
    def list_income(month: str | None = None, auth=Depends(require_user)):
        if month:
            parse_month(month)
        with db() as conn:
            return {"income": budget_math._income(conn, auth["family_id"], month)}

    @app.post("/v1/income")
    def create_income(body: IncomeIn, auth=Depends(require_user)):
        parse_month(body.month)
        check_cents(body.expected_cents)
        check_cents(body.received_cents or 0)
        label = clean_text(body.label, "Label", 80)
        expected_on = parse_date(body.expected_on) if body.expected_on else None
        received_on = parse_date(body.received_on) if body.received_on else None
        with db() as conn:
            if body.member_id:
                own_member(conn, auth["family_id"], body.member_id)
            iid = new_id()
            conn.execute(
                """
                INSERT INTO income_entries (
                    id, family_id, member_id, label, month, expected_cents, received_cents,
                    expected_on, received_on, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    iid,
                    auth["family_id"],
                    body.member_id or auth["member_id"],
                    label,
                    body.month,
                    body.expected_cents,
                    body.received_cents or 0,
                    expected_on,
                    received_on,
                    now_iso(),
                ),
            )
        return {"ok": True}

    @app.patch("/v1/income/{income_id}")
    def patch_income(income_id: str, body: IncomePatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "income_entries", income_id, auth["family_id"])
            label = clean_text(body.label, "Label", 80) if body.label is not None else row["label"]
            month = parse_month(body.month) if body.month is not None else row["month"]
            expected = row["expected_cents"]
            received = row["received_cents"]
            if body.expected_cents is not None:
                check_cents(body.expected_cents)
                expected = body.expected_cents
            if body.received_cents is not None:
                check_cents(body.received_cents)
                received = body.received_cents
            expected_on = parse_date(body.expected_on) if body.expected_on else row["expected_on"]
            received_on = parse_date(body.received_on) if body.received_on else row["received_on"]
            if "expected_on" in body.model_fields_set:
                expected_on = parse_date(body.expected_on) if body.expected_on else None
            if "received_on" in body.model_fields_set:
                received_on = parse_date(body.received_on) if body.received_on else None
            member_id = row["member_id"]
            if body.member_id:
                own_member(conn, auth["family_id"], body.member_id)
                member_id = body.member_id
            conn.execute(
                """
                UPDATE income_entries
                SET label = ?, month = ?, expected_cents = ?, received_cents = ?,
                    expected_on = ?, received_on = ?, member_id = ?
                WHERE id = ?
                """,
                (label, month, expected, received, expected_on, received_on, member_id, income_id),
            )
            return {"ok": True}

    @app.delete("/v1/income/{income_id}")
    def delete_income(income_id: str, auth=Depends(require_user)):
        return delete_scoped("income_entries", income_id, auth["family_id"])

    @app.get("/v1/bills")
    def list_bills(auth=Depends(require_user)):
        with db() as conn:
            return {"bills": budget_math._bills(conn, auth["family_id"])}

    @app.post("/v1/bills")
    def create_bill(body: BillIn, auth=Depends(require_user)):
        due = parse_date(body.due_on)
        check_cents(body.amount_cents)
        name = clean_text(body.name, "Name", 80)
        cadence = body.cadence if body.cadence in {"once", "monthly", "yearly"} else "once"
        with db() as conn:
            if body.category_id:
                own_category(conn, auth["family_id"], body.category_id)
            bid = new_id()
            conn.execute(
                """
                INSERT INTO bills (
                    id, family_id, name, amount_cents, due_on, category_id, cadence, paid, notes, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
                """,
                (bid, auth["family_id"], name, body.amount_cents, due, body.category_id, cadence, blank(body.notes), now_iso()),
            )
            return {"ok": True, "id": bid}

    @app.patch("/v1/bills/{bill_id}")
    def patch_bill(bill_id: str, body: BillPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "bills", bill_id, auth["family_id"])
            name = clean_text(body.name, "Name", 80) if body.name is not None else row["name"]
            amount = row["amount_cents"]
            if body.amount_cents is not None:
                check_cents(body.amount_cents)
                amount = body.amount_cents
            due = parse_date(body.due_on) if body.due_on is not None else row["due_on"]
            cadence = row["cadence"]
            if body.cadence is not None:
                cadence = body.cadence if body.cadence in {"once", "monthly", "yearly"} else row["cadence"]
            category_id = row["category_id"]
            if "category_id" in body.model_fields_set:
                category_id = body.category_id or None
                if category_id:
                    own_category(conn, auth["family_id"], category_id)
            notes = row["notes"]
            if "notes" in body.model_fields_set:
                notes = blank(body.notes)
            paid = int(row["paid"])
            if body.paid is True and not row["paid"]:
                conn.execute(
                    """
                    INSERT INTO transactions (
                        id, family_id, category_id, member_id, merchant, amount_cents,
                        kind, occurred_on, note, source, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, 'expense', ?, ?, 'bill', ?)
                    """,
                    (
                        new_id(),
                        auth["family_id"],
                        category_id,
                        auth["member_id"],
                        name,
                        amount,
                        due if date.fromisoformat(due) <= date.today() else date.today().isoformat(),
                        "Paid bill",
                        now_iso(),
                    ),
                )
                if cadence == "monthly":
                    due = add_months(date.fromisoformat(due), 1).isoformat()
                    paid = 0
                else:
                    paid = 1
            elif body.paid is False:
                paid = 0
            conn.execute(
                """
                UPDATE bills
                SET name = ?, amount_cents = ?, due_on = ?, category_id = ?, cadence = ?, paid = ?, notes = ?
                WHERE id = ? AND family_id = ?
                """,
                (name, amount, due, category_id, cadence, paid, notes, bill_id, auth["family_id"]),
            )
        return {"ok": True}

    @app.delete("/v1/bills/{bill_id}")
    def delete_bill(bill_id: str, auth=Depends(require_user)):
        return delete_scoped("bills", bill_id, auth["family_id"])

    @app.get("/v1/accounts")
    def list_accounts(auth=Depends(require_user)):
        with db() as conn:
            return {"accounts": budget_math._accounts(conn, auth["family_id"])}

    @app.post("/v1/accounts")
    def create_account(body: AccountIn, auth=Depends(require_user)):
        check_balance(body.balance_cents)
        name = clean_text(body.name, "Name", 80)
        kind = body.kind if body.kind in {"checking", "savings", "credit", "other"} else "checking"
        with db() as conn:
            aid = new_id()
            conn.execute(
                """
                INSERT INTO accounts (id, family_id, name, institution, balance_cents, kind, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (aid, auth["family_id"], name, blank(body.institution), body.balance_cents, kind, now_iso()),
            )
        return {"ok": True, "id": aid}

    @app.patch("/v1/accounts/{account_id}")
    def patch_account(account_id: str, body: AccountPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "accounts", account_id, auth["family_id"])
            name = clean_text(body.name, "Name", 80) if body.name is not None else row["name"]
            institution = row["institution"] if "institution" not in body.model_fields_set else blank(body.institution)
            balance = row["balance_cents"]
            if body.balance_cents is not None:
                check_balance(body.balance_cents)
                balance = body.balance_cents
            kind = row["kind"]
            if body.kind is not None and body.kind in {"checking", "savings", "credit", "other"}:
                kind = body.kind
            conn.execute(
                """
                UPDATE accounts SET name = ?, institution = ?, balance_cents = ?, kind = ?
                WHERE id = ? AND family_id = ?
                """,
                (name, institution, balance, kind, account_id, auth["family_id"]),
            )
        return {"ok": True}

    @app.delete("/v1/accounts/{account_id}")
    def delete_account(account_id: str, auth=Depends(require_user)):
        return delete_scoped("accounts", account_id, auth["family_id"])

    @app.get("/v1/marriage")
    def get_marriage(auth=Depends(require_user)):
        with db() as conn:
            return marriage_bundle(conn, auth)

    @app.put("/v1/marriage")
    def put_marriage(body: MarriageIn, auth=Depends(require_user)):
        with db() as conn:
            family = one(conn, "SELECT * FROM families WHERE id = ?", (auth["family_id"],))
            anniversary = family["anniversary_date"]
            first = family["first_date"]
            nudge = family["flower_nudge_days"]
            if "anniversary_date" in body.model_fields_set:
                anniversary = parse_date(body.anniversary_date) if body.anniversary_date else None
            if "first_date" in body.model_fields_set:
                first = parse_date(body.first_date) if body.first_date else None
            if body.flower_nudge_days is not None:
                if not 1 <= body.flower_nudge_days <= 365:
                    raise HTTPException(400, "Nudge days should be between 1 and 365.")
                nudge = body.flower_nudge_days
            conn.execute(
                """
                UPDATE families
                SET anniversary_date = ?, first_date = ?, flower_nudge_days = ?
                WHERE id = ?
                """,
                (anniversary, first, nudge, auth["family_id"]),
            )
            return marriage_bundle(conn, auth)

    @app.post("/v1/birthdays")
    def create_birthday(body: BirthdayIn, auth=Depends(require_user)):
        if not 1 <= body.month <= 12 or not 1 <= body.day <= 31:
            raise HTTPException(400, "That date doesn't look right.")
        name = clean_text(body.name, "Name", 80)
        with db() as conn:
            if body.member_id:
                own_member(conn, auth["family_id"], body.member_id)
            bid = new_id()
            conn.execute(
                """
                INSERT INTO birthdays (id, family_id, name, month, day, year, member_id, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (bid, auth["family_id"], name, body.month, body.day, body.year, body.member_id, now_iso()),
            )
        return {"ok": True, "id": bid}

    @app.patch("/v1/birthdays/{birthday_id}")
    def patch_birthday(birthday_id: str, body: BirthdayPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "birthdays", birthday_id, auth["family_id"])
            name = clean_text(body.name, "Name", 80) if body.name is not None else row["name"]
            month = body.month if body.month is not None else row["month"]
            day = body.day if body.day is not None else row["day"]
            if not 1 <= int(month) <= 12 or not 1 <= int(day) <= 31:
                raise HTTPException(400, "That date doesn't look right.")
            year = row["year"] if "year" not in body.model_fields_set else body.year
            conn.execute(
                "UPDATE birthdays SET name = ?, month = ?, day = ?, year = ? WHERE id = ?",
                (name, month, day, year, birthday_id),
            )
        return {"ok": True}

    @app.delete("/v1/birthdays/{birthday_id}")
    def delete_birthday(birthday_id: str, auth=Depends(require_user)):
        return delete_scoped("birthdays", birthday_id, auth["family_id"])

    @app.post("/v1/flowers")
    def log_flowers(body: FlowerIn, auth=Depends(require_user)):
        bought = parse_date(body.bought_on)
        with db() as conn:
            fid = new_id()
            conn.execute(
                """
                INSERT INTO flower_logs (id, family_id, member_id, bought_on, note, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (fid, auth["family_id"], auth["member_id"], bought, blank(body.note), now_iso()),
            )
            return marriage_bundle(conn, auth)

    @app.delete("/v1/flowers/{flower_id}")
    def delete_flower(flower_id: str, auth=Depends(require_user)):
        with db() as conn:
            removed = conn.execute(
                "DELETE FROM flower_logs WHERE id = ? AND family_id = ? AND member_id = ?",
                (flower_id, auth["family_id"], auth["member_id"]),
            ).rowcount
        if not removed:
            raise HTTPException(404, "Not found")
        return {"ok": True}

    @app.post("/v1/dates")
    def create_date(body: DateNightIn, auth=Depends(require_user)):
        starts = parse_dt(body.starts_at)
        title = clean_text(body.title, "Title", 80)
        with db() as conn:
            did = new_id()
            conn.execute(
                """
                INSERT INTO date_nights (id, family_id, title, starts_at, location, notes, created_by, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (did, auth["family_id"], title, starts, blank(body.location), blank(body.notes), auth["member_id"], now_iso()),
            )
        return {"ok": True, "id": did}

    @app.patch("/v1/dates/{date_id}")
    def patch_date(date_id: str, body: DateNightPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "date_nights", date_id, auth["family_id"])
            title = clean_text(body.title, "Title", 80) if body.title is not None else row["title"]
            starts = parse_dt(body.starts_at) if body.starts_at is not None else row["starts_at"]
            location = row["location"] if "location" not in body.model_fields_set else blank(body.location)
            notes = row["notes"] if "notes" not in body.model_fields_set else blank(body.notes)
            conn.execute(
                "UPDATE date_nights SET title = ?, starts_at = ?, location = ?, notes = ? WHERE id = ?",
                (title, starts, location, notes, date_id),
            )
        return {"ok": True}

    @app.delete("/v1/dates/{date_id}")
    def delete_date(date_id: str, auth=Depends(require_user)):
        return delete_scoped("date_nights", date_id, auth["family_id"])

    @app.post("/v1/checkins")
    def upsert_checkin(body: CheckinIn, auth=Depends(require_user)):
        week = parse_date(body.week_start)
        if date.fromisoformat(week).weekday() != 0:
            raise HTTPException(400, "Week starts on Monday.")
        note = blank(body.note)
        if note and len(note) > 2000:
            raise HTTPException(400, "Note is too long.")
        with db() as conn:
            existing = one(
                conn,
                "SELECT id FROM checkins WHERE family_id = ? AND member_id = ? AND week_start = ?",
                (auth["family_id"], auth["member_id"], week),
            )
            if existing:
                conn.execute(
                    """
                    UPDATE checkins
                    SET connection = ?, appreciation = ?, fun = ?, note = ?, created_at = ?
                    WHERE id = ?
                    """,
                    (body.connection, body.appreciation, body.fun, note, now_iso(), existing["id"]),
                )
                cid = existing["id"]
            else:
                cid = new_id()
                conn.execute(
                    """
                    INSERT INTO checkins (
                        id, family_id, member_id, week_start, connection, appreciation, fun, note, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (cid, auth["family_id"], auth["member_id"], week, body.connection, body.appreciation, body.fun, note, now_iso()),
                )
        return {"ok": True, "id": cid, "completed": True}

    @app.delete("/v1/checkins/{checkin_id}")
    def delete_checkin(checkin_id: str, auth=Depends(require_user)):
        with db() as conn:
            removed = conn.execute(
                "DELETE FROM checkins WHERE id = ? AND family_id = ? AND member_id = ?",
                (checkin_id, auth["family_id"], auth["member_id"]),
            ).rowcount
        if not removed:
            raise HTTPException(404, "Not found")
        return {"ok": True}

    @app.post("/v1/love-notes")
    def create_note(body: LoveNoteIn, auth=Depends(require_user)):
        text = clean_text(body.body, "Note", 2000)
        with db() as conn:
            nid = new_id()
            conn.execute(
                "INSERT INTO love_notes (id, family_id, author_id, body, created_at) VALUES (?, ?, ?, ?, ?)",
                (nid, auth["family_id"], auth["member_id"], text, now_iso()),
            )
        return {"ok": True, "id": nid}

    @app.delete("/v1/love-notes/{note_id}")
    def delete_love_note(note_id: str, auth=Depends(require_user)):
        with db() as conn:
            removed = conn.execute(
                "DELETE FROM love_notes WHERE id = ? AND family_id = ? AND author_id = ?",
                (note_id, auth["family_id"], auth["member_id"]),
            ).rowcount
        if not removed:
            raise HTTPException(404, "Not found")
        return {"ok": True}

    @app.get("/v1/household")
    def household(auth=Depends(require_user)):
        with db() as conn:
            return household_bundle(conn, auth["family_id"])

    @app.post("/v1/chores")
    def create_chore(body: ChoreIn, auth=Depends(require_user)):
        title = clean_text(body.title, "Title", 120)
        due = parse_date(body.due_on) if body.due_on else None
        recurrence = clean_chore_recurrence(body.recurrence)
        if recurrence != "none" and due is None:
            raise HTTPException(400, "A due date is required for recurring chores.")
        with db() as conn:
            if body.assignee_id:
                own_member(conn, auth["family_id"], body.assignee_id)
            cid = new_id()
            conn.execute(
                """
                INSERT INTO chores (id, family_id, title, assignee_id, done, due_on, recurrence, created_by, completed_at, created_at)
                VALUES (?, ?, ?, ?, 0, ?, ?, ?, NULL, ?)
                """,
                (cid, auth["family_id"], title, body.assignee_id, due, recurrence, auth["member_id"], now_iso()),
            )
        return {"ok": True, "id": cid}

    @app.patch("/v1/chores/{chore_id}")
    def patch_chore(chore_id: str, body: ChorePatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "chores", chore_id, auth["family_id"])
            title = clean_text(body.title, "Title", 120) if body.title is not None else row["title"]
            assignee = row["assignee_id"]
            if body.clear_assignee:
                assignee = None
            elif "assignee_id" in body.model_fields_set:
                assignee = body.assignee_id
                if assignee:
                    own_member(conn, auth["family_id"], assignee)
            due = row["due_on"]
            if body.clear_due_on:
                due = None
            elif "due_on" in body.model_fields_set:
                due = parse_date(body.due_on) if body.due_on else None
            recurrence = row["recurrence"]
            if body.recurrence is not None:
                recurrence = clean_chore_recurrence(body.recurrence)
            if recurrence != "none" and due is None:
                raise HTTPException(400, "A due date is required for recurring chores.")
            done = int(row["done"])
            completed = row["completed_at"]
            expected_due = parse_date(body.expected_due_on) if body.expected_due_on else None
            stale_recurring_completion = (
                body.done is True
                and recurrence != "none"
                and expected_due is not None
                and expected_due != row["due_on"]
            )
            if body.done is not None:
                if body.done and recurrence != "none" and not stale_recurring_completion:
                    due = next_chore_due(due, recurrence, date.today())
                    done = 0
                    completed = None
                elif not stale_recurring_completion:
                    done = 1 if body.done else 0
                    completed = now_iso() if body.done else None
            conn.execute(
                """
                UPDATE chores
                SET title = ?, assignee_id = ?, due_on = ?, recurrence = ?, done = ?, completed_at = ?
                WHERE id = ?
                """,
                (title, assignee, due, recurrence, done, completed, chore_id),
            )
        return {"ok": True}

    @app.delete("/v1/chores/{chore_id}")
    def delete_chore(chore_id: str, auth=Depends(require_user)):
        return delete_scoped("chores", chore_id, auth["family_id"])

    @app.post("/v1/important-dates")
    def create_important(body: ImportantIn, auth=Depends(require_user)):
        title = clean_text(body.title, "Title", 120)
        date_on = parse_date(body.date_on)
        with db() as conn:
            iid = new_id()
            conn.execute(
                """
                INSERT INTO important_dates (id, family_id, title, date_on, repeats_yearly, notes, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (iid, auth["family_id"], title, date_on, 1 if body.repeats_yearly else 0, blank(body.notes), now_iso()),
            )
        return {"ok": True, "id": iid}

    @app.patch("/v1/important-dates/{item_id}")
    def patch_important(item_id: str, body: ImportantPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "important_dates", item_id, auth["family_id"])
            title = clean_text(body.title, "Title", 120) if body.title is not None else row["title"]
            date_on = parse_date(body.date_on) if body.date_on is not None else row["date_on"]
            repeats = row["repeats_yearly"] if body.repeats_yearly is None else (1 if body.repeats_yearly else 0)
            notes = row["notes"] if "notes" not in body.model_fields_set else blank(body.notes)
            conn.execute(
                "UPDATE important_dates SET title = ?, date_on = ?, repeats_yearly = ?, notes = ? WHERE id = ?",
                (title, date_on, repeats, notes, item_id),
            )
        return {"ok": True}

    @app.delete("/v1/important-dates/{item_id}")
    def delete_important(item_id: str, auth=Depends(require_user)):
        return delete_scoped("important_dates", item_id, auth["family_id"])

    @app.post("/v1/notes")
    def create_shared(body: SharedNoteIn, auth=Depends(require_user)):
        kind = body.kind if body.kind in {"note", "grocery"} else "note"
        text = clean_text(body.body, "Note", 500)
        with db() as conn:
            nid = new_id()
            conn.execute(
                """
                INSERT INTO shared_notes (id, family_id, kind, body, done, created_by, created_at)
                VALUES (?, ?, ?, ?, 0, ?, ?)
                """,
                (nid, auth["family_id"], kind, text, auth["member_id"], now_iso()),
            )
        return {"ok": True, "id": nid}

    @app.patch("/v1/notes/{note_id}")
    def patch_shared(note_id: str, body: SharedNotePatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "shared_notes", note_id, auth["family_id"])
            text = clean_text(body.body, "Note", 500) if body.body is not None else row["body"]
            done = int(row["done"]) if body.done is None else (1 if body.done else 0)
            conn.execute("UPDATE shared_notes SET body = ?, done = ? WHERE id = ?", (text, done, note_id))
        return {"ok": True}

    @app.delete("/v1/notes/{note_id}")
    def delete_shared(note_id: str, auth=Depends(require_user)):
        return delete_scoped("shared_notes", note_id, auth["family_id"])

    @app.get("/v1/events")
    def list_events(start: str | None = None, end: str | None = None, auth=Depends(require_user)):
        with db() as conn:
            return {"events": events_between(conn, auth["family_id"], start, end)}

    @app.post("/v1/events")
    def create_event(body: EventIn, auth=Depends(require_user)):
        title = clean_text(body.title, "Title", 120)
        starts = parse_dt(body.starts_at)
        ends = parse_dt(body.ends_at) if body.ends_at else None
        color = clean_color(body.color or "#2563eb")
        with db() as conn:
            eid = new_id()
            conn.execute(
                """
                INSERT INTO events (
                    id, family_id, title, starts_at, ends_at, all_day, location, notes, color, created_by, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    eid,
                    auth["family_id"],
                    title,
                    starts,
                    ends,
                    1 if body.all_day else 0,
                    blank(body.location),
                    blank(body.notes),
                    color,
                    auth["member_id"],
                    now_iso(),
                ),
            )
        return {"ok": True, "id": eid}

    @app.patch("/v1/events/{event_id}")
    def patch_event(event_id: str, body: EventPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "events", event_id, auth["family_id"])
            title = clean_text(body.title, "Title", 120) if body.title is not None else row["title"]
            starts = parse_dt(body.starts_at) if body.starts_at is not None else row["starts_at"]
            ends = row["ends_at"] if "ends_at" not in body.model_fields_set else (parse_dt(body.ends_at) if body.ends_at else None)
            all_day = row["all_day"] if body.all_day is None else (1 if body.all_day else 0)
            location = row["location"] if "location" not in body.model_fields_set else blank(body.location)
            notes = row["notes"] if "notes" not in body.model_fields_set else blank(body.notes)
            color = clean_color(body.color) if body.color is not None else row["color"]
            conn.execute(
                """
                UPDATE events
                SET title = ?, starts_at = ?, ends_at = ?, all_day = ?, location = ?, notes = ?, color = ?
                WHERE id = ?
                """,
                (title, starts, ends, all_day, location, notes, color, event_id),
            )
        return {"ok": True}

    @app.delete("/v1/events/{event_id}")
    def delete_event(event_id: str, auth=Depends(require_user)):
        return delete_scoped("events", event_id, auth["family_id"])

    @app.get("/v1/trips")
    def list_trips(auth=Depends(require_user)):
        with db() as conn:
            return {"trips": all_trips(conn, auth["family_id"])}

    @app.post("/v1/trips")
    def create_trip(body: TripIn, auth=Depends(require_user)):
        name = clean_text(body.name, "Name", 80)
        start = parse_date(body.start_date)
        end = parse_date(body.end_date)
        if end < start:
            raise HTTPException(400, "The trip ends before it starts.")
        check_cents(body.savings_cents or 0)
        check_cents(body.goal_cents or 0)
        with db() as conn:
            tid = new_id()
            conn.execute(
                """
                INSERT INTO trips (
                    id, family_id, name, destination, start_date, end_date,
                    savings_cents, goal_cents, notes, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    tid,
                    auth["family_id"],
                    name,
                    blank(body.destination),
                    start,
                    end,
                    body.savings_cents or 0,
                    body.goal_cents or 0,
                    blank(body.notes),
                    now_iso(),
                ),
            )
            trip = trip_by_id(conn, auth["family_id"], tid)
        just = (body.goal_cents or 0) > 0 and (body.savings_cents or 0) >= (body.goal_cents or 0)
        trip["goal_just_reached"] = just
        return trip

    @app.patch("/v1/trips/{trip_id}")
    def patch_trip(trip_id: str, body: TripPatch, auth=Depends(require_user)):
        with db() as conn:
            row = own_row(conn, "trips", trip_id, auth["family_id"])
            name = clean_text(body.name, "Name", 80) if body.name is not None else row["name"]
            destination = row["destination"] if "destination" not in body.model_fields_set else blank(body.destination)
            start = parse_date(body.start_date) if body.start_date is not None else row["start_date"]
            end = parse_date(body.end_date) if body.end_date is not None else row["end_date"]
            if end < start:
                raise HTTPException(400, "The trip ends before it starts.")
            savings = row["savings_cents"]
            goal = row["goal_cents"]
            if body.savings_cents is not None:
                check_cents(body.savings_cents)
                savings = body.savings_cents
            if body.goal_cents is not None:
                check_cents(body.goal_cents)
                goal = body.goal_cents
            notes = row["notes"] if "notes" not in body.model_fields_set else blank(body.notes)
            conn.execute(
                """
                UPDATE trips
                SET name = ?, destination = ?, start_date = ?, end_date = ?,
                    savings_cents = ?, goal_cents = ?, notes = ?
                WHERE id = ?
                """,
                (name, destination, start, end, savings, goal, notes, trip_id),
            )
            trip = trip_by_id(conn, auth["family_id"], trip_id)
        crossed = goal > 0 and savings >= goal and int(row["savings_cents"]) < goal
        trip["goal_just_reached"] = crossed
        return trip

    @app.delete("/v1/trips/{trip_id}")
    def delete_trip(trip_id: str, auth=Depends(require_user)):
        with db() as conn:
            own_row(conn, "trips", trip_id, auth["family_id"])
            conn.execute("DELETE FROM packing_items WHERE trip_id = ?", (trip_id,))
            conn.execute("DELETE FROM itinerary_items WHERE trip_id = ?", (trip_id,))
            conn.execute("DELETE FROM trips WHERE id = ?", (trip_id,))
        return {"ok": True}

    @app.post("/v1/trips/{trip_id}/packing")
    def add_packing(trip_id: str, body: TitleIn, auth=Depends(require_user)):
        title = clean_text(body.title, "Item", 120)
        with db() as conn:
            own_row(conn, "trips", trip_id, auth["family_id"])
            pid = new_id()
            sort = one(conn, "SELECT COALESCE(MAX(sort_order), 0) + 1 AS n FROM packing_items WHERE trip_id = ?", (trip_id,))
            conn.execute(
                "INSERT INTO packing_items (id, trip_id, title, done, sort_order) VALUES (?, ?, ?, 0, ?)",
                (pid, trip_id, title, int(sort["n"])),
            )
        return {"ok": True, "id": pid}

    @app.patch("/v1/packing/{item_id}")
    def patch_packing(item_id: str, body: PackingPatch, auth=Depends(require_user)):
        with db() as conn:
            row = packing_owned(conn, item_id, auth["family_id"])
            title = clean_text(body.title, "Item", 120) if body.title is not None else row["title"]
            done = int(row["done"]) if body.done is None else (1 if body.done else 0)
            conn.execute("UPDATE packing_items SET title = ?, done = ? WHERE id = ?", (title, done, item_id))
        return {"ok": True}

    @app.delete("/v1/packing/{item_id}")
    def delete_packing(item_id: str, auth=Depends(require_user)):
        with db() as conn:
            packing_owned(conn, item_id, auth["family_id"])
            conn.execute("DELETE FROM packing_items WHERE id = ?", (item_id,))
        return {"ok": True}

    @app.post("/v1/trips/{trip_id}/itinerary")
    def add_itinerary(trip_id: str, body: ItineraryIn, auth=Depends(require_user)):
        title = clean_text(body.title, "Title", 120)
        day_on = parse_date(body.day_on) if body.day_on else None
        with db() as conn:
            own_row(conn, "trips", trip_id, auth["family_id"])
            iid = new_id()
            sort = one(
                conn,
                "SELECT COALESCE(MAX(sort_order), 0) + 1 AS n FROM itinerary_items WHERE trip_id = ?",
                (trip_id,),
            )
            conn.execute(
                "INSERT INTO itinerary_items (id, trip_id, day_on, title, body, sort_order) VALUES (?, ?, ?, ?, ?, ?)",
                (iid, trip_id, day_on, title, blank(body.body), int(sort["n"])),
            )
        return {"ok": True, "id": iid}

    @app.patch("/v1/itinerary/{item_id}")
    def patch_itinerary(item_id: str, body: ItineraryPatch, auth=Depends(require_user)):
        with db() as conn:
            row = itinerary_owned(conn, item_id, auth["family_id"])
            title = clean_text(body.title, "Title", 120) if body.title is not None else row["title"]
            day_on = row["day_on"] if "day_on" not in body.model_fields_set else (parse_date(body.day_on) if body.day_on else None)
            text = row["body"] if "body" not in body.model_fields_set else blank(body.body)
            conn.execute(
                "UPDATE itinerary_items SET title = ?, day_on = ?, body = ? WHERE id = ?",
                (title, day_on, text, item_id),
            )
        return {"ok": True}

    @app.delete("/v1/itinerary/{item_id}")
    def delete_itinerary(item_id: str, auth=Depends(require_user)):
        with db() as conn:
            itinerary_owned(conn, item_id, auth["family_id"])
            conn.execute("DELETE FROM itinerary_items WHERE id = ?", (item_id,))
        return {"ok": True}

    from .v11 import register_v11
    from .simplefin import register_routes as register_simplefin_routes

    register_v11(app)
    register_simplefin_routes(app, require_user)
    return app


# --- models ---


class CreateFamilyIn(BaseModel):
    name: str
    family_name: str | None = None


class JoinIn(BaseModel):
    code: str
    name: str


class PairingRedeemIn(BaseModel):
    code: str


class NameIn(BaseModel):
    name: str


class FamilyPatch(BaseModel):
    name: str | None = None


class SuggestIn(BaseModel):
    month: str
    apply: bool = True
    today: str | None = None


class CategoryIn(BaseModel):
    name: str
    color: str | None = None
    icon: str | None = None
    default_budget_cents: int | None = 0


class CategoryPatch(BaseModel):
    name: str | None = None
    color: str | None = None
    icon: str | None = None
    default_budget_cents: int | None = None
    sort_order: int | None = None


class BudgetSetIn(BaseModel):
    month: str
    amount_cents: int
    set_default: bool = False


class TxnIn(BaseModel):
    merchant: str
    amount_cents: int
    kind: str = "expense"
    direction: str | None = None
    occurred_on: str
    category_id: str | None = None
    note: str | None = None


class TxnPatch(BaseModel):
    merchant: str | None = None
    amount_cents: int | None = None
    kind: str | None = None
    direction: str | None = None
    occurred_on: str | None = None
    category_id: str | None = None
    note: str | None = None


class ImportRow(BaseModel):
    date: str
    merchant: str
    amount_cents: int
    category: str | None = None
    kind: str | None = "expense"


class ImportIn(BaseModel):
    rows: list[ImportRow]


class IncomeIn(BaseModel):
    label: str
    month: str
    expected_cents: int
    received_cents: int | None = 0
    expected_on: str | None = None
    received_on: str | None = None
    member_id: str | None = None


class IncomePatch(BaseModel):
    label: str | None = None
    month: str | None = None
    expected_cents: int | None = None
    received_cents: int | None = None
    expected_on: str | None = None
    received_on: str | None = None
    member_id: str | None = None


class BillIn(BaseModel):
    name: str
    amount_cents: int
    due_on: str
    category_id: str | None = None
    cadence: str = "monthly"
    notes: str | None = None


class BillPatch(BaseModel):
    name: str | None = None
    amount_cents: int | None = None
    due_on: str | None = None
    category_id: str | None = None
    cadence: str | None = None
    paid: bool | None = None
    notes: str | None = None


class AccountIn(BaseModel):
    name: str
    institution: str | None = None
    balance_cents: int = 0
    kind: str = "checking"


class AccountPatch(BaseModel):
    name: str | None = None
    institution: str | None = None
    balance_cents: int | None = None
    kind: str | None = None


class MarriageIn(BaseModel):
    anniversary_date: str | None = None
    first_date: str | None = None
    flower_nudge_days: int | None = None


class BirthdayIn(BaseModel):
    name: str
    month: int
    day: int
    year: int | None = None
    member_id: str | None = None


class BirthdayPatch(BaseModel):
    name: str | None = None
    month: int | None = None
    day: int | None = None
    year: int | None = None


class FlowerIn(BaseModel):
    bought_on: str
    note: str | None = None


class DateNightIn(BaseModel):
    title: str
    starts_at: str
    location: str | None = None
    notes: str | None = None


class DateNightPatch(BaseModel):
    title: str | None = None
    starts_at: str | None = None
    location: str | None = None
    notes: str | None = None


class CheckinIn(BaseModel):
    week_start: str
    connection: int = Field(ge=1, le=5)
    appreciation: int = Field(ge=1, le=5)
    fun: int = Field(ge=1, le=5)
    note: str | None = None


class LoveNoteIn(BaseModel):
    body: str


class ChoreIn(BaseModel):
    title: str
    assignee_id: str | None = None
    due_on: str | None = None
    recurrence: str = "none"


class ChorePatch(BaseModel):
    title: str | None = None
    assignee_id: str | None = None
    clear_assignee: bool = False
    due_on: str | None = None
    clear_due_on: bool = False
    recurrence: str | None = None
    done: bool | None = None
    expected_due_on: str | None = None


class ImportantIn(BaseModel):
    title: str
    date_on: str
    repeats_yearly: bool = False
    notes: str | None = None


class ImportantPatch(BaseModel):
    title: str | None = None
    date_on: str | None = None
    repeats_yearly: bool | None = None
    notes: str | None = None


class SharedNoteIn(BaseModel):
    body: str
    kind: str = "note"


class SharedNotePatch(BaseModel):
    body: str | None = None
    done: bool | None = None


class EventIn(BaseModel):
    title: str
    starts_at: str
    ends_at: str | None = None
    all_day: bool = False
    location: str | None = None
    notes: str | None = None
    color: str | None = None


class EventPatch(BaseModel):
    title: str | None = None
    starts_at: str | None = None
    ends_at: str | None = None
    all_day: bool | None = None
    location: str | None = None
    notes: str | None = None
    color: str | None = None


class TripIn(BaseModel):
    name: str
    destination: str | None = None
    start_date: str
    end_date: str
    savings_cents: int | None = 0
    goal_cents: int | None = 0
    notes: str | None = None


class TripPatch(BaseModel):
    name: str | None = None
    destination: str | None = None
    start_date: str | None = None
    end_date: str | None = None
    savings_cents: int | None = None
    goal_cents: int | None = None
    notes: str | None = None


class TitleIn(BaseModel):
    title: str


class PackingPatch(BaseModel):
    title: str | None = None
    done: bool | None = None


class ItineraryIn(BaseModel):
    title: str
    day_on: str | None = None
    body: str | None = None


class ItineraryPatch(BaseModel):
    title: str | None = None
    day_on: str | None = None
    body: str | None = None


# --- helpers ---


def require_user(authorization: Annotated[str | None, Header()] = None) -> dict:
    token = parse_bearer(authorization)
    with db() as conn:
        row = one(
            conn,
            """
            SELECT s.expires_at, m.id AS member_id, m.name AS member_name, m.family_id
            FROM sessions s
            JOIN members m ON m.id = s.member_id
            WHERE s.token_hash = ?
            """,
            (hash_secret(token),),
        )
    if row is None or row["expires_at"] < now_iso():
        raise HTTPException(401, "Sign in again.")
    return {"member_id": row["member_id"], "name": row["member_name"], "family_id": row["family_id"]}


def parse_bearer(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Sign in again.")
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(401, "Sign in again.")
    return token


def client_ip(request: Request) -> str:
    peer = request.client.host if request.client else ""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded and _private(peer):
        return forwarded.split(",")[0].strip() or peer or "unknown"
    return peer or "unknown"


def _private(ip: str) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return addr.is_private or addr.is_loopback


def clean_name(value: str) -> str:
    return clean_text(value, "Name", 80)


def clean_text(value: str | None, label: str, limit: int) -> str:
    text = " ".join((value or "").split())
    if not text:
        raise HTTPException(400, f"{label} is required.")
    if len(text) > limit:
        raise HTTPException(400, f"{label} is too long.")
    return text


def blank(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip()
    return text or None


def clean_color(value: str | None) -> str:
    if not value:
        return "#2563eb"
    text = value.strip()
    if len(text) == 7 and text.startswith("#"):
        try:
            int(text[1:], 16)
            return text.lower()
        except ValueError:
            pass
    return "#2563eb"


def clean_kind(value: str) -> str:
    if value not in {"expense", "income", "transfer"}:
        raise HTTPException(400, "Kind must be expense, income, or transfer.")
    return value


def clean_direction(value: str) -> str:
    if value not in {"inflow", "outflow"}:
        raise HTTPException(400, "Direction must be inflow or outflow.")
    return value


def clean_chore_recurrence(value: str | None) -> str:
    recurrence = value or "none"
    if recurrence not in {"none", "daily", "weekly", "monthly"}:
        raise HTTPException(400, "Recurrence must be none, daily, weekly, or monthly.")
    return recurrence


def next_chore_due(due_on: str | None, recurrence: str, today: date) -> str:
    if not due_on or recurrence == "none":
        raise HTTPException(400, "A due date is required for recurring chores.")
    scheduled = date.fromisoformat(due_on)

    def advance(day: date) -> date:
        if recurrence == "daily":
            return day + timedelta(days=1)
        if recurrence == "weekly":
            return day + timedelta(days=7)
        return add_months(day, 1)

    next_day = advance(scheduled)
    while next_day <= today:
        next_day = advance(next_day)
    return next_day.isoformat()


def check_cents(value: int) -> None:
    if value < 0 or value > 100_000_000_00:
        raise HTTPException(400, "Amount is out of range.")


def check_balance(value: int) -> None:
    if abs(value) > 100_000_000_00:
        raise HTTPException(400, "Amount is out of range.")


def parse_date(value: str | None) -> str:
    if not value:
        raise HTTPException(400, "Date is required.")
    try:
        date.fromisoformat(value[:10])
    except ValueError as exc:
        raise HTTPException(400, "Dates must be YYYY-MM-DD.") from exc
    return value[:10]


def parse_month(value: str) -> str:
    try:
        datetime.strptime(value, "%Y-%m")
    except ValueError as exc:
        raise HTTPException(400, "Month must be YYYY-MM.") from exc
    return value


def parse_today(value: str | None) -> date:
    if not value:
        return datetime.now(timezone.utc).date()
    try:
        return date.fromisoformat(value[:10])
    except ValueError as exc:
        raise HTTPException(400, "Dates must be YYYY-MM-DD.") from exc


def parse_dt(value: str) -> str:
    raw = value.strip()
    if len(raw) == 10:
        parse_date(raw)
        return raw + "T00:00:00"
    candidate = raw.replace("Z", "+00:00")
    try:
        datetime.fromisoformat(candidate)
    except ValueError as exc:
        raise HTTPException(400, "Use a date and time like 2026-11-21T19:00:00.") from exc
    return raw


def add_months(day: date, count: int) -> date:
    month = day.month - 1 + count
    year = day.year + month // 12
    month = month % 12 + 1
    last = calendar.monthrange(year, month)[1]
    return date(year, month, min(day.day, last))


def issue_session(conn, member_id: str) -> tuple[str, str]:
    token = secrets.token_urlsafe(32)
    days = int(os.environ.get("SESSION_DAYS", "400"))
    exp = plus_days(days)
    conn.execute(
        "INSERT INTO sessions (token_hash, member_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
        (hash_secret(token), member_id, now_iso(), exp),
    )
    return token, exp


def issue_code(conn, family_id: str) -> tuple[str, str]:
    hours = int(os.environ.get("JOIN_CODE_TTL_HOURS", "24"))
    exp = plus_hours(hours)
    for _ in range(5):
        code = "".join(secrets.choice(ALPHABET) for _ in range(6))
        digest = hash_secret(code)
        clash = one(conn, "SELECT id FROM join_codes WHERE code_hash = ? AND used_at IS NULL", (digest,))
        if clash:
            continue
        conn.execute(
            """
            INSERT INTO join_codes (id, family_id, code_hash, created_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (new_id(), family_id, digest, now_iso(), exp),
        )
        return code, exp
    raise HTTPException(500, "Could not create a join code.")


def normalize_code(code: str) -> str:
    return "".join(code.split()).upper().replace("-", "")


def family_out(row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "anniversary_date": row["anniversary_date"],
        "first_date": row["first_date"],
        "flower_nudge_days": int(row["flower_nudge_days"]),
        "created_at": row["created_at"],
    }


def member_out(row) -> dict:
    return {"id": row["id"], "name": row["name"], "created_at": row["created_at"]}


def category_out(row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "color": row["color"],
        "icon": row["icon"],
        "default_budget_cents": int(row["default_budget_cents"]),
        "sort_order": int(row["sort_order"]),
    }


def profile(conn, auth: dict) -> dict:
    family = one(conn, "SELECT * FROM families WHERE id = ?", (auth["family_id"],))
    member = one(conn, "SELECT * FROM members WHERE id = ?", (auth["member_id"],))
    members = many(conn, "SELECT * FROM members WHERE family_id = ? ORDER BY created_at", (auth["family_id"],))
    return {
        "family": family_out(family),
        "member": member_out(member),
        "members": [member_out(m) for m in members],
    }


def own_row(conn, table: str, row_id: str, family_id: str):
    row = one(conn, f"SELECT * FROM {table} WHERE id = ? AND family_id = ?", (row_id, family_id))
    if row is None:
        raise HTTPException(404, "Not found")
    return row


def own_category(conn, family_id: str, category_id: str):
    row = one(
        conn,
        "SELECT * FROM categories WHERE id = ? AND family_id = ? AND archived = 0",
        (category_id, family_id),
    )
    if row is None:
        raise HTTPException(400, "Unknown category.")
    return row


def own_member(conn, family_id: str, member_id: str):
    row = one(conn, "SELECT * FROM members WHERE id = ? AND family_id = ?", (member_id, family_id))
    if row is None:
        raise HTTPException(400, "Unknown family member.")
    return row


def delete_scoped(table: str, row_id: str, family_id: str) -> dict:
    with db() as conn:
        removed = conn.execute(
            f"DELETE FROM {table} WHERE id = ? AND family_id = ?",
            (row_id, family_id),
        ).rowcount
    if not removed:
        raise HTTPException(404, "Not found")
    return {"ok": True}


def insert_category(conn, family_id: str, name: str, color: str | None, icon: str | None, default_budget: int) -> str:
    check_cents(default_budget)
    label = clean_text(name, "Name", 60)
    sort = one(conn, "SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM categories WHERE family_id = ?", (family_id,))
    cid = new_id()
    conn.execute(
        """
        INSERT INTO categories (id, family_id, name, color, icon, default_budget_cents, sort_order, archived)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0)
        """,
        (
            cid,
            family_id,
            label,
            clean_color(color),
            clean_text(icon, "Icon", 40) if icon else "tag.fill",
            default_budget,
            int(sort["n"]),
        ),
    )
    return cid


def match_or_create_category(conn, family_id: str, name: str) -> tuple[str, bool]:
    row = one(
        conn,
        "SELECT id FROM categories WHERE family_id = ? AND archived = 0 AND lower(name) = lower(?)",
        (family_id, name),
    )
    if row:
        return row["id"], False
    count = one(conn, "SELECT COUNT(*) AS n FROM categories WHERE family_id = ?", (family_id,))
    color = EXTRA_COLORS[int(count["n"]) % len(EXTRA_COLORS)]
    return insert_category(conn, family_id, name, color, "tag.fill", 0), True


def txn_by_id(conn, family_id: str, txn_id: str) -> dict:
    row = one(
        conn,
        """
        SELECT t.*, c.name AS category_name, c.color AS category_color, c.icon AS category_icon,
               m.name AS member_name
        FROM transactions t
        LEFT JOIN categories c ON c.id = t.category_id
        LEFT JOIN members m ON m.id = t.member_id
        WHERE t.family_id = ? AND t.id = ?
        """,
        (family_id, txn_id),
    )
    if row is None:
        raise HTTPException(404, "Not found")
    return budget_math._txn(row)


def build_dashboard(conn, auth: dict, today: date) -> dict:
    month = today.strftime("%Y-%m")
    summary = budget_math.build_budget(conn, auth["family_id"], month, today)
    me = profile(conn, auth)
    chores = many(conn, "SELECT * FROM chores WHERE family_id = ? ORDER BY done, created_at", (auth["family_id"],))
    chore_items = []
    open_first = [c for c in chores if not c["done"]] + [c for c in chores if c["done"]]
    members = {m["id"]: m["name"] for m in me["members"]}
    for chore in open_first[:4]:
        chore_items.append(
            {
                "id": chore["id"],
                "title": chore["title"],
                "done": bool(chore["done"]),
                "assignee_id": chore["assignee_id"],
                "assignee_name": members.get(chore["assignee_id"]),
            }
        )
    events = events_between(conn, auth["family_id"], today.isoformat(), None)[:4]
    dates = many(
        conn,
        """
        SELECT * FROM date_nights
        WHERE family_id = ? AND starts_at >= ?
        ORDER BY starts_at LIMIT 1
        """,
        (auth["family_id"], today.isoformat()),
    )
    next_date = None
    if dates:
        row = dates[0]
        next_date = {
            "id": row["id"],
            "title": row["title"],
            "starts_at": row["starts_at"],
            "location": row["location"],
        }
    trip = pick_trip(all_trips(conn, auth["family_id"]), today)
    insight = summary["insights"][0] if summary["insights"] else None
    return {
        "family": me["family"],
        "member": me["member"],
        "members": me["members"],
        "budget": {
            "month": summary["month"],
            "month_label": summary["month_label"],
            "spent_cents": summary["spent_cents"],
            "budget_cents": summary["budget_cents"],
            "remaining_cents": summary["remaining_cents"],
            "pace": summary["pace"],
            "insight": insight,
            "recent": budget_math.recent_expenses(conn, auth["family_id"], 3),
        },
        "chores": {
            "done": sum(1 for c in chores if c["done"]),
            "total": len(chores),
            "items": chore_items,
        },
        "events": events,
        "next_date": next_date,
        "trip": trip,
    }


def marriage_bundle(conn, auth: dict) -> dict:
    family = one(conn, "SELECT * FROM families WHERE id = ?", (auth["family_id"],))
    birthdays = many(conn, "SELECT * FROM birthdays WHERE family_id = ? ORDER BY month, day, name", (auth["family_id"],))
    flowers = many(
        conn,
        """
        SELECT * FROM flower_logs
        WHERE family_id = ? AND member_id = ?
        ORDER BY bought_on DESC, created_at DESC
        """,
        (auth["family_id"], auth["member_id"]),
    )
    dates = many(
        conn,
        "SELECT * FROM date_nights WHERE family_id = ? ORDER BY starts_at DESC",
        (auth["family_id"],),
    )
    checkins = many(
        conn,
        """
        SELECT c.*, m.name AS member_name
        FROM checkins c
        JOIN members m ON m.id = c.member_id
        WHERE c.family_id = ?
        ORDER BY c.week_start DESC, m.created_at
        LIMIT 80
        """,
        (auth["family_id"],),
    )
    notes = many(
        conn,
        """
        SELECT n.*, m.name AS author_name
        FROM love_notes n
        JOIN members m ON m.id = n.author_id
        WHERE n.family_id = ?
        ORDER BY n.created_at DESC
        LIMIT 100
        """,
        (auth["family_id"],),
    )
    return {
        "anniversary_date": family["anniversary_date"],
        "first_date": family["first_date"],
        "flower_nudge_days": int(family["flower_nudge_days"]),
        "birthdays": [
            {
                "id": b["id"],
                "name": b["name"],
                "month": int(b["month"]),
                "day": int(b["day"]),
                "year": b["year"],
                "member_id": b["member_id"],
            }
            for b in birthdays
        ],
        "flowers": {
            "nudge_after_days": int(family["flower_nudge_days"]),
            "logs": [
                {"id": f["id"], "bought_on": f["bought_on"], "note": f["note"], "created_at": f["created_at"]}
                for f in flowers
            ],
        },
        "dates": [
            {
                "id": d["id"],
                "title": d["title"],
                "starts_at": d["starts_at"],
                "location": d["location"],
                "notes": d["notes"],
                "created_by": d["created_by"],
            }
            for d in dates
        ],
        "checkins": [
            {
                "id": c["id"],
                "member_id": c["member_id"],
                "member_name": c["member_name"],
                "week_start": c["week_start"],
                "connection": int(c["connection"]),
                "appreciation": int(c["appreciation"]),
                "fun": int(c["fun"]),
                "note": c["note"],
                "created_at": c["created_at"],
            }
            for c in checkins
        ],
        "love_notes": [
            {
                "id": n["id"],
                "author_id": n["author_id"],
                "author_name": n["author_name"],
                "body": n["body"],
                "created_at": n["created_at"],
            }
            for n in notes
        ],
    }


def household_bundle(conn, family_id: str) -> dict:
    members = many(conn, "SELECT * FROM members WHERE family_id = ? ORDER BY created_at", (family_id,))
    names = {m["id"]: m["name"] for m in members}
    chores = many(conn, "SELECT * FROM chores WHERE family_id = ? ORDER BY done, due_on, created_at", (family_id,))
    dates = many(conn, "SELECT * FROM important_dates WHERE family_id = ? ORDER BY date_on", (family_id,))
    notes = many(
        conn,
        "SELECT * FROM shared_notes WHERE family_id = ? ORDER BY done, created_at DESC",
        (family_id,),
    )
    return {
        "chores": [
            {
                "id": c["id"],
                "title": c["title"],
                "assignee_id": c["assignee_id"],
                "assignee_name": names.get(c["assignee_id"]),
                "done": bool(c["done"]),
                "due_on": c["due_on"],
                "recurrence": c["recurrence"],
                "created_by": c["created_by"],
                "completed_at": c["completed_at"],
            }
            for c in chores
        ],
        "important_dates": [
            {
                "id": d["id"],
                "title": d["title"],
                "date_on": d["date_on"],
                "repeats_yearly": bool(d["repeats_yearly"]),
                "notes": d["notes"],
            }
            for d in dates
        ],
        "notes": [
            {
                "id": n["id"],
                "kind": n["kind"],
                "body": n["body"],
                "done": bool(n["done"]),
                "created_by": n["created_by"],
                "author_name": names.get(n["created_by"]),
                "created_at": n["created_at"],
            }
            for n in notes
        ],
    }


def _feed_events(conn, family_id: str, start: str | None, end: str | None) -> list[dict]:
    try:
        sql = """
            SELECT e.*, f.color AS feed_color, f.name AS feed_name
            FROM feed_events e
            JOIN calendar_feeds f ON f.id = e.feed_id
            WHERE f.family_id = ?
        """
        args: list = [family_id]
        if start:
            sql += " AND e.starts_at >= ?"
            args.append(start)
        if end:
            sql += " AND e.starts_at <= ?"
            args.append(end if "T" in end else end + "T23:59:59")
        sql += " ORDER BY e.starts_at LIMIT 400"
        rows = many(conn, sql, tuple(args))
    except sqlite3.OperationalError:
        return []
    return [
        {
            "id": "feed:" + row["id"],
            "title": row["title"],
            "starts_at": row["starts_at"],
            "ends_at": row["ends_at"],
            "all_day": bool(row["all_day"]),
            "location": row["location"],
            "notes": row["feed_name"],
            "color": row["feed_color"],
            "created_by": None,
            "source": "feed",
            "read_only": True,
        }
        for row in rows
    ]


def events_between(conn, family_id: str, start: str | None, end: str | None) -> list[dict]:
    sql = "SELECT * FROM events WHERE family_id = ?"
    args: list = [family_id]
    if start:
        sql += " AND starts_at >= ?"
        args.append(start)
    if end:
        sql += " AND starts_at <= ?"
        args.append(end if "T" in end else end + "T23:59:59")
    sql += " ORDER BY starts_at LIMIT 400"
    rows = many(conn, sql, tuple(args))
    return [
        {
            "id": r["id"],
            "title": r["title"],
            "starts_at": r["starts_at"],
            "ends_at": r["ends_at"],
            "all_day": bool(r["all_day"]),
            "location": r["location"],
            "notes": r["notes"],
            "color": r["color"],
            "created_by": r["created_by"],
            "source": "family",
            "read_only": False,
        }
        for r in rows
    ] + _feed_events(conn, family_id, start, end)


def all_trips(conn, family_id: str) -> list[dict]:
    rows = many(conn, "SELECT * FROM trips WHERE family_id = ? ORDER BY start_date", (family_id,))
    trips = []
    for row in rows:
        trips.append(trip_dict(conn, row))
    return trips


def trip_by_id(conn, family_id: str, trip_id: str) -> dict:
    row = own_row(conn, "trips", trip_id, family_id)
    return trip_dict(conn, row)


def trip_dict(conn, row) -> dict:
    packing = many(conn, "SELECT * FROM packing_items WHERE trip_id = ? ORDER BY sort_order", (row["id"],))
    stops = many(conn, "SELECT * FROM itinerary_items WHERE trip_id = ? ORDER BY sort_order", (row["id"],))
    return {
        "id": row["id"],
        "name": row["name"],
        "destination": row["destination"],
        "start_date": row["start_date"],
        "end_date": row["end_date"],
        "savings_cents": int(row["savings_cents"]),
        "goal_cents": int(row["goal_cents"]),
        "notes": row["notes"],
        "packing": [
            {"id": p["id"], "title": p["title"], "done": bool(p["done"]), "sort_order": int(p["sort_order"])}
            for p in packing
        ],
        "itinerary": [
            {
                "id": s["id"],
                "day_on": s["day_on"],
                "title": s["title"],
                "body": s["body"],
                "sort_order": int(s["sort_order"]),
            }
            for s in stops
        ],
    }


def pick_trip(trips: list[dict], today: date) -> dict | None:
    current = []
    upcoming = []
    for trip in trips:
        start = date.fromisoformat(trip["start_date"])
        end = date.fromisoformat(trip["end_date"])
        if start <= today <= end:
            current.append(trip)
        elif start > today:
            upcoming.append(trip)
    if current:
        current.sort(key=lambda t: t["end_date"])
        chosen = dict(current[0])
        chosen["days_until"] = 0
        return chosen
    if upcoming:
        upcoming.sort(key=lambda t: t["start_date"])
        chosen = dict(upcoming[0])
        chosen["days_until"] = (date.fromisoformat(chosen["start_date"]) - today).days
        return chosen
    return None


def packing_owned(conn, item_id: str, family_id: str):
    row = one(
        conn,
        """
        SELECT p.* FROM packing_items p
        JOIN trips t ON t.id = p.trip_id
        WHERE p.id = ? AND t.family_id = ?
        """,
        (item_id, family_id),
    )
    if row is None:
        raise HTTPException(404, "Not found")
    return row


def itinerary_owned(conn, item_id: str, family_id: str):
    row = one(
        conn,
        """
        SELECT i.* FROM itinerary_items i
        JOIN trips t ON t.id = i.trip_id
        WHERE i.id = ? AND t.family_id = ?
        """,
        (item_id, family_id),
    )
    if row is None:
        raise HTTPException(404, "Not found")
    return row


app = create_app()
