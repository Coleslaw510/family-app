import base64
import json
import sqlite3
from datetime import datetime, timezone

import httpx
import pytest

from app import simplefin
from app.db import db
from test_api import create_family


class MockResponse:
    def __init__(self, *, text="", payload=None, status_code=200):
        self.text = text
        self.payload = payload or {}
        self.status_code = status_code
        self.headers = {}

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def iter_bytes(self):
        yield json.dumps(self.payload).encode()

    def json(self):
        return self.payload

    def raise_for_status(self):
        if self.status_code >= 400:
            request = httpx.Request("GET", "https://bridge.simplefin.org/simplefin/accounts")
            response = httpx.Response(self.status_code, request=request)
            raise httpx.HTTPStatusError("provider error", request=request, response=response)


class MockClient:
    def __init__(self, accounts_payload=None, claim_text="https://user:pass@bridge.simplefin.org/simplefin"):
        self.accounts_payload = accounts_payload or {"accounts": []}
        self.claim_text = claim_text
        self.get_calls = []
        self.fail_claim = False

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def post(self, url):
        if self.fail_claim:
            raise httpx.ConnectError("sensitive-provider-url")
        return MockResponse(text=self.claim_text)

    def stream(self, method, url, *, params, auth):
        self.get_calls.append((url, params, auth))
        return MockResponse(payload=self.accounts_payload)


def setup_token():
    url = "https://bridge.simplefin.org/simplefin/claim/token"
    return base64.b64encode(url.encode()).decode()


def test_migration_is_idempotent_and_preserves_existing_transaction(client, monkeypatch):
    _, headers = create_family(client)
    created = client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Existing purchase", "amount_cents": 1234, "occurred_on": "2026-11-20", "kind": "expense"},
    )
    assert created.status_code == 200, created.text
    txn_id = created.json()["id"]
    with db() as conn:
        conn.execute("DROP TABLE simplefin_transaction_ids")
        conn.execute("DROP TABLE simplefin_connections")
        conn.execute("DELETE FROM schema_migrations WHERE version = 12")
    status = client.get("/v1/simplefin/status", headers=headers)
    assert status.status_code == 200
    with db() as conn:
        row = conn.execute("SELECT merchant, amount_cents FROM transactions WHERE id = ?", (txn_id,)).fetchone()
        assert (row["merchant"], row["amount_cents"]) == ("Existing purchase", 1234)
        assert conn.execute("SELECT COUNT(*) FROM schema_migrations WHERE version = 12").fetchone()[0] == 1


def test_provider_bounds_and_identity_keys():
    assert simplefin._identity_key("x" * 240) != simplefin._identity_key("x" * 239 + "y")
    assert simplefin._identity_key("x" * 2049) is None
    with pytest.raises(ValueError):
        simplefin._parse_provider_accounts({"accounts": [{}] * (simplefin.MAX_ACCOUNTS + 1)})
    with pytest.raises(ValueError):
        simplefin._parse_provider_accounts({"accounts": [{"transactions": [{}] * (simplefin.MAX_TRANSACTIONS + 1)}]})


def test_failed_claim_is_sanitized_and_wrong_host_is_rejected(client, monkeypatch):
    _, headers = create_family(client)
    monkeypatch.setenv("SIMPLEFIN_ENCRYPTION_KEY", simplefin.Fernet.generate_key().decode())
    mock = MockClient()
    mock.fail_claim = True
    monkeypatch.setattr(simplefin.httpx, "Client", lambda **_kwargs: mock)
    failed = client.post("/v1/simplefin/connect", headers=headers, json={"setup_token": setup_token()})
    assert failed.status_code == 400
    assert "sensitive-provider-url" not in failed.text
    assert client.post(
        "/v1/simplefin/connect",
        headers=headers,
        json={"setup_token": base64.b64encode(b"https://evil.example/simplefin/claim").decode()},
    ).status_code == 400


def test_connect_sync_signed_conversion_overlap_dedup_and_family_isolation(client, monkeypatch):
    created, headers = create_family(client)
    _other, other_headers = create_family(client, "Other", "Other Family")
    monkeypatch.setenv("SIMPLEFIN_ENCRYPTION_KEY", simplefin.Fernet.generate_key().decode())
    timestamp = int(datetime(2026, 11, 22, 15, 30, tzinfo=timezone.utc).timestamp())
    mock = MockClient({"accounts": [{
        "id": "acct-1",
        "name": "Checking",
        "transactions": [
            {"id": "tx-expense", "posted": timestamp, "amount": "-12.34", "description": "Kroger groceries", "pending": False},
            {"id": "tx-income", "posted": timestamp, "amount": "1250.00", "description": "Payroll", "pending": False},
            {"id": "tx-card-payment", "posted": timestamp, "amount": "-250.00", "description": "Credit Card Payment - Visa", "pending": False},
            {"id": "tx-venmo", "posted": timestamp, "amount": "42.50", "description": "Venmo from a friend", "pending": False},
            {"id": "tx-pending", "posted": timestamp, "amount": "-88.00", "description": "Pending", "pending": True},
        ],
    }]})
    monkeypatch.setattr(simplefin.httpx, "Client", lambda **_kwargs: mock)
    connected = client.post("/v1/simplefin/connect", headers=headers, json={"setup_token": setup_token()})
    assert connected.status_code == 200, connected.text
    own_status = client.get("/v1/simplefin/status", headers=headers).json()
    assert own_status["connected"] is True
    assert client.get("/v1/simplefin/status", headers=other_headers).json()["connected"] is False

    first = client.post("/v1/simplefin/sync", headers=headers)
    assert first.status_code == 200, first.text
    assert first.json()["imported"] == 4
    txns = client.get("/v1/transactions", headers=headers).json()["transactions"]
    by_merchant = {item["merchant"]: item for item in txns}
    expense = by_merchant["Kroger groceries"]
    income = by_merchant["Payroll"]
    card_payment = by_merchant["Credit Card Payment - Visa"]
    venmo = by_merchant["Venmo from a friend"]
    assert (expense["amount_cents"], expense["kind"], expense["occurred_on"], expense["source"]) == (1234, "expense", "2026-11-22", "simplefin")
    assert expense["category_name"] == "Groceries"
    assert (income["amount_cents"], income["kind"]) == (125000, "income")
    assert (card_payment["amount_cents"], card_payment["kind"], card_payment["direction"]) == (25000, "transfer", "outflow")
    assert (venmo["amount_cents"], venmo["kind"], venmo["direction"]) == (4250, "income", "inflow")
    budget = client.get("/v1/budget?month=2026-11&today=2026-11-22", headers=headers).json()
    assert budget["spent_cents"] == 1234
    assert budget["income_from_transactions_cents"] == 129250

    limited = client.post("/v1/simplefin/sync", headers=headers)
    assert limited.status_code == 429
    with db() as conn:
        conn.execute("UPDATE simplefin_connections SET last_attempt_at = '2026-11-23T00:00:00Z' WHERE family_id = ?", (created["family"]["id"],))
    second = client.post("/v1/simplefin/sync", headers=headers)
    assert second.status_code == 200, second.text
    assert second.json()["imported"] == 0
    assert second.json()["skipped"] == 4
    url, params, _auth = mock.get_calls[-1]
    assert url.endswith("/accounts")
    assert params["version"] == "2"
    assert int(params["end-date"]) - int(params["start-date"]) <= 90 * 24 * 60 * 60
    assert len(txns) == 4


def test_v14_reclassifies_historical_card_payment_but_not_purchases(client):
    _created, headers = create_family(client)
    payment = client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Payment Thank You - Card", "amount_cents": 40000, "occurred_on": "2026-11-19", "kind": "expense"},
    ).json()
    purchase = client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Card purchase at Market", "amount_cents": 12000, "occurred_on": "2026-11-19", "kind": "expense"},
    ).json()
    with db() as conn:
        conn.execute("DELETE FROM schema_migrations WHERE version = 14")
    txns = client.get("/v1/transactions", headers=headers).json()["transactions"]
    by_id = {txn["id"]: txn for txn in txns}
    assert by_id[payment["id"]]["kind"] == "transfer"
    assert by_id[purchase["id"]]["kind"] == "expense"


def test_disconnect_is_household_scoped(client, monkeypatch):
    _, headers_a = create_family(client, "A", "Family A")
    _, headers_b = create_family(client, "B", "Family B")
    monkeypatch.setenv("SIMPLEFIN_ENCRYPTION_KEY", simplefin.Fernet.generate_key().decode())
    mock = MockClient()
    monkeypatch.setattr(simplefin.httpx, "Client", lambda **_kwargs: mock)
    assert client.post("/v1/simplefin/connect", headers=headers_a, json={"setup_token": setup_token()}).status_code == 200
    assert client.delete("/v1/simplefin/connection", headers=headers_b).status_code == 200
    assert client.get("/v1/simplefin/status", headers=headers_a).json()["connected"] is True
