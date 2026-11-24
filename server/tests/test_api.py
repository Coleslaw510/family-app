"""API coverage for auth, isolation, budget, and the household features."""

import os
import sqlite3

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("DB_PATH", str(tmp_path / "family.db"))
    monkeypatch.setenv("JOIN_MAX_ATTEMPTS", "3")
    monkeypatch.setenv("JOIN_WINDOW_SECONDS", "900")
    monkeypatch.setenv("CREATE_MAX_ATTEMPTS", "20")
    monkeypatch.setenv("JOIN_CODE_TTL_HOURS", "24")
    app = create_app()
    with TestClient(app) as test_client:
        yield test_client


def create_family(client, name="Cole", family="Cole & Partner"):
    response = client.post("/v1/families", json={"name": name, "family_name": family})
    assert response.status_code == 200, response.text
    data = response.json()
    headers = {"Authorization": f"Bearer {data['token']}"}
    return data, headers


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert client.get("/v1/me").status_code == 401


def test_create_join_and_reuse(client):
    created, headers = create_family(client)
    assert len(created["join_code"]) == 6
    assert created["family"]["name"] == "Cole & Partner"
    me = client.get("/v1/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["member"]["name"] == "Cole"

    renamed = client.patch("/v1/me", json={"name": "Cole McClintock"}, headers=headers)
    assert renamed.json()["member"]["name"] == "Cole McClintock"

    joined = client.post("/v1/families/join", json={"code": created["join_code"].lower(), "name": "Partner"})
    assert joined.status_code == 200, joined.text
    assert len(joined.json()["members"]) == 2
    again = client.post("/v1/families/join", json={"code": created["join_code"], "name": "Someone"})
    assert again.status_code == 400

    fresh = client.post("/v1/join-codes", headers=headers)
    assert fresh.status_code == 200
    assert len(fresh.json()["join_code"]) == 6


def test_budget_app_pairing_code_is_one_use_and_expires(client):
    _created, headers = create_family(client)
    issued = client.post("/v1/budget-app/pairing-code", headers=headers)
    assert issued.status_code == 200, issued.text
    code = issued.json()["pairing_code"]
    redeemed = client.post("/v1/budget-app/redeem", json={"code": code})
    assert redeemed.status_code == 200, redeemed.text
    assert redeemed.json()["family"]["name"] == "Cole & Partner"
    assert client.get("/v1/me", headers={"Authorization": f"Bearer {redeemed.json()['token']}"}).status_code == 200
    assert client.post("/v1/budget-app/redeem", json={"code": code}).status_code == 400

    second = client.post("/v1/budget-app/pairing-code", headers=headers).json()["pairing_code"]
    conn = sqlite3.connect(os.environ["DB_PATH"])
    conn.execute("UPDATE budget_pairings SET expires_at = '2000-01-01T00:00:00Z' WHERE code_hash = ?", (__import__("hashlib").sha256(second.encode()).hexdigest(),))
    conn.commit()
    conn.close()
    assert client.post("/v1/budget-app/redeem", json={"code": second}).status_code == 400


def test_join_rate_limit_and_expiry(client):
    created, _headers = create_family(client)
    for _ in range(3):
        bad = client.post("/v1/families/join", json={"code": "ZZZZZZ", "name": "Nope"})
        assert bad.status_code == 400
    blocked = client.post("/v1/families/join", json={"code": "ZZZZZZ", "name": "Nope"})
    assert blocked.status_code == 429

    conn = sqlite3.connect(os.environ["DB_PATH"])
    conn.execute("UPDATE join_codes SET expires_at = '2000-01-01T00:00:00Z'")
    conn.commit()
    conn.close()
    # A new client IP is not available through TestClient, so use a fresh limiter via a second app
    # on the same database. Expiry must fail even when the rate limit has room.
    app = create_app()
    with TestClient(app) as other:
        expired = other.post("/v1/families/join", json={"code": created["join_code"], "name": "Late"})
        assert expired.status_code == 400


def test_family_isolation(client):
    _a, headers_a = create_family(client, "Cole", "Cole & Partner")
    _b, headers_b = create_family(client, "Other", "Other Family")
    categories = client.get("/v1/categories", headers=headers_a).json()["categories"]
    groceries = next(item for item in categories if item["name"] == "Groceries")
    created = client.post(
        "/v1/transactions",
        headers=headers_a,
        json={
            "merchant": "Market Fresh",
            "amount_cents": 8642,
            "occurred_on": "2026-11-20",
            "category_id": groceries["id"],
        },
    )
    assert created.status_code == 200, created.text
    txn_id = created.json()["id"]
    assert created.json()["member_name"] == "Cole"
    leaked = client.patch(
        f"/v1/transactions/{txn_id}",
        headers=headers_b,
        json={"merchant": "Stolen"},
    )
    assert leaked.status_code == 404
    other_budget = client.get("/v1/budget?month=2026-11&today=2026-11-21", headers=headers_b)
    assert other_budget.json()["spent_cents"] == 0
    mine = client.get("/v1/budget?month=2026-11&today=2026-11-21", headers=headers_a)
    assert mine.json()["spent_cents"] == 8642


def test_budget_math_import_and_suggest(client):
    _created, headers = create_family(client)
    categories = client.get("/v1/categories", headers=headers).json()["categories"]
    by_name = {item["name"]: item["id"] for item in categories}
    client.put(
        f"/v1/categories/{by_name['Groceries']}/budget",
        headers=headers,
        json={"month": "2026-11", "amount_cents": 10000, "set_default": True},
    )
    client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Market", "amount_cents": 4000, "occurred_on": "2026-11-02", "category_id": by_name["Groceries"]},
    )
    client.post(
        "/v1/bills",
        headers=headers,
        json={"name": "Phone plan", "amount_cents": 1000, "due_on": "2026-11-24", "cadence": "once", "category_id": by_name["Bills / Utilities"]},
    )
    summary = client.get("/v1/budget?month=2026-11&today=2026-11-21", headers=headers).json()
    assert summary["budget_cents"] == 10000
    assert summary["remaining_cents"] == 6000
    assert summary["days_left"] == 10
    assert summary["safe_per_day_cents"] == 500
    assert summary["pace"] == "on_pace"
    assert summary["upcoming_bills_cents"] == 1000

    client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Dinner", "amount_cents": 9000, "occurred_on": "2026-11-18", "category_id": by_name["Groceries"]},
    )
    over = client.get("/v1/budget?month=2026-11&today=2026-11-21", headers=headers).json()
    assert over["pace"] == "over"
    assert over["insights"][0]["level"] == "bad"
    assert "Groceries" in over["insights"][0]["title"] or "groceries" in over["insights"][0]["title"]

    imported = client.post(
        "/v1/transactions/import",
        headers=headers,
        json={
            "rows": [
                {"date": "2026-01-05", "merchant": "Market Fresh", "amount_cents": 10000, "category": "Groceries"},
                {"date": "2026-02-05", "merchant": "Market Fresh", "amount_cents": 30000, "category": "Groceries"},
                {"date": "2026-02-05", "merchant": "Market Fresh", "amount_cents": 30000, "category": "Groceries"},
            ]
        },
    )
    assert imported.status_code == 200, imported.text
    assert imported.json()["imported"] == 2
    assert imported.json()["skipped"] == 1

    suggested = client.post("/v1/budget/suggest", headers=headers, json={"month": "2026-03", "apply": True, "today": "2026-03-01"})
    assert suggested.status_code == 200, suggested.text
    groceries = next(item for item in suggested.json()["suggestions"] if item["name"] == "Groceries")
    # Jan 100, Feb 300, and November's 130 is excluded because it is not before March.
    assert groceries["average_cents"] == 20000
    march = client.get("/v1/budget?month=2026-03&today=2026-03-01", headers=headers).json()
    march_groceries = next(item for item in march["categories"] if item["name"] == "Groceries")
    assert march_groceries["budget_cents"] == 20000


def test_transfer_rows_do_not_count_as_spending_and_income_is_irregular(client):
    _created, headers = create_family(client)
    groceries = next(
        item for item in client.get("/v1/categories", headers=headers).json()["categories"]
        if item["name"] == "Groceries"
    )
    purchase = client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Card purchase at Market", "amount_cents": 25000, "occurred_on": "2026-11-20", "kind": "expense", "category_id": groceries["id"]},
    )
    payment = client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Pay credit card", "amount_cents": 25000, "occurred_on": "2026-11-21", "kind": "transfer", "direction": "outflow"},
    )
    venmo = client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Venmo from friend", "amount_cents": 4000, "occurred_on": "2026-11-21", "kind": "income"},
    )
    assert (purchase.json()["kind"], payment.json()["kind"], venmo.json()["direction"]) == ("expense", "transfer", "inflow")
    summary = client.get("/v1/budget?month=2026-11&today=2026-11-21", headers=headers).json()
    assert summary["spent_cents"] == 25000
    assert summary["income_from_transactions_cents"] == 4000
    assert {row["kind"] for row in summary["transactions"]} >= {"expense", "transfer", "income"}


def test_income_bill_payment_and_account(client):
    _created, headers = create_family(client)
    created = client.post(
        "/v1/income",
        headers=headers,
        json={
            "label": "Paycheck",
            "month": "2026-11",
            "expected_cents": 370000,
            "received_cents": 185000,
            "expected_on": "2026-11-21",
            "received_on": "2026-11-07",
        },
    )
    assert created.status_code == 200
    summary = client.get("/v1/budget?month=2026-11&today=2026-11-21", headers=headers).json()
    assert summary["income_expected_cents"] == 370000
    assert summary["income_received_cents"] == 185000

    bill = client.post(
        "/v1/bills",
        headers=headers,
        json={"name": "Auto insurance", "amount_cents": 14200, "due_on": "2020-01-15", "cadence": "monthly"},
    )
    bill_id = bill.json()["id"]
    paid = client.patch(f"/v1/bills/{bill_id}", headers=headers, json={"paid": True})
    assert paid.status_code == 200
    bills = client.get("/v1/bills", headers=headers).json()["bills"]
    assert bills[0]["due_on"] == "2020-02-15"
    assert bills[0]["paid"] is False
    txns = client.get("/v1/transactions?month=2020-01", headers=headers).json()["transactions"]
    assert txns[0]["merchant"] == "Auto insurance"
    assert txns[0]["source"] == "bill"

    account = client.post(
        "/v1/accounts",
        headers=headers,
        json={"name": "Rewards credit card", "institution": "Northside Card", "balance_cents": -110245, "kind": "credit"},
    )
    assert account.status_code == 200
    accounts = client.get("/v1/accounts", headers=headers).json()["accounts"]
    assert accounts[0]["balance_cents"] == -110245
    client.delete(f"/v1/accounts/{account.json()['id']}", headers=headers)
    assert client.get("/v1/accounts", headers=headers).json()["accounts"] == []


def test_flowers_are_personal_and_checkins_are_shared(client):
    created, cole = create_family(client)
    partner = client.post("/v1/families/join", json={"code": created["join_code"], "name": "Partner"})
    partner_headers = {"Authorization": f"Bearer {partner.json()['token']}"}

    logged = client.post("/v1/flowers", headers=cole, json={"bought_on": "2026-11-01", "note": "peonies"})
    assert logged.status_code == 200
    assert logged.json()["flowers"]["logs"][0]["note"] == "peonies"
    partner_view = client.get("/v1/marriage", headers=partner_headers).json()
    assert partner_view["flowers"]["logs"] == []
    flower_id = logged.json()["flowers"]["logs"][0]["id"]
    assert client.delete(f"/v1/flowers/{flower_id}", headers=partner_headers).status_code == 404

    monday = client.post(
        "/v1/checkins",
        headers=cole,
        json={"week_start": "2026-11-16", "connection": 5, "appreciation": 4, "fun": 5, "note": "Walk after dinner"},
    )
    assert monday.status_code == 200
    bad_day = client.post(
        "/v1/checkins",
        headers=partner_headers,
        json={"week_start": "2026-11-17", "connection": 3, "appreciation": 3, "fun": 3},
    )
    assert bad_day.status_code == 400
    client.post(
        "/v1/checkins",
        headers=partner_headers,
        json={"week_start": "2026-11-16", "connection": 4, "appreciation": 5, "fun": 4, "note": "More weekends"},
    )
    shared = client.get("/v1/marriage", headers=cole).json()["checkins"]
    assert len(shared) == 2
    assert {item["member_name"] for item in shared} == {"Cole", "Partner"}

    note = client.post("/v1/love-notes", headers=cole, json={"body": "You make ordinary Tuesdays good."})
    note_id = note.json()["id"]
    visible = client.get("/v1/marriage", headers=partner_headers).json()["love_notes"]
    assert visible[0]["body"].startswith("You make")
    assert client.delete(f"/v1/love-notes/{note_id}", headers=partner_headers).status_code == 404
    assert client.delete(f"/v1/love-notes/{note_id}", headers=cole).status_code == 200

    saved = client.put(
        "/v1/marriage",
        headers=cole,
        json={"anniversary_date": "2019-01-06", "first_date": "2016-06-12", "flower_nudge_days": 21},
    )
    assert saved.json()["anniversary_date"] == "2019-01-06"
    assert saved.json()["flower_nudge_days"] == 21


def test_household_calendar_and_trips(client):
    created, headers = create_family(client)
    member_id = created["member"]["id"]
    chore = client.post("/v1/chores", headers=headers, json={"title": "Walk the dog", "assignee_id": member_id})
    chore_id = chore.json()["id"]
    client.patch(f"/v1/chores/{chore_id}", headers=headers, json={"done": True})
    client.post("/v1/notes", headers=headers, json={"kind": "grocery", "body": "Oat milk"})
    client.post(
        "/v1/important-dates",
        headers=headers,
        json={"title": "Passport expiry", "date_on": "2028-04-02", "repeats_yearly": False},
    )
    board = client.get("/v1/household", headers=headers).json()
    assert board["chores"][0]["done"] is True
    assert board["chores"][0]["assignee_name"] == "Cole"
    assert board["notes"][0]["kind"] == "grocery"
    assert board["important_dates"][0]["title"] == "Passport expiry"

    event = client.post(
        "/v1/events",
        headers=headers,
        json={"title": "Family dinner", "starts_at": "2026-11-21T18:30:00", "color": "#4285F4"},
    )
    assert event.status_code == 200
    listed = client.get("/v1/events?start=2026-11-21&end=2026-11-21", headers=headers).json()["events"]
    assert listed[0]["title"] == "Family dinner"
    client.delete(f"/v1/events/{event.json()['id']}", headers=headers)

    trip = client.post(
        "/v1/trips",
        headers=headers,
        json={
            "name": "Coastal weekend",
            "destination": "The coast",
            "start_date": "2027-01-22",
            "end_date": "2027-01-24",
            "savings_cents": 240000,
            "goal_cents": 400000,
        },
    )
    assert trip.status_code == 200, trip.text
    trip_id = trip.json()["id"]
    assert trip.json()["goal_just_reached"] is False
    packed = client.post(f"/v1/trips/{trip_id}/packing", headers=headers, json={"title": "Sweaters"})
    client.patch(f"/v1/packing/{packed.json()['id']}", headers=headers, json={"done": True})
    client.post(
        f"/v1/trips/{trip_id}/itinerary",
        headers=headers,
        json={"title": "Drive out", "day_on": "2027-01-22", "body": "Leave after breakfast"},
    )
    reached = client.patch(f"/v1/trips/{trip_id}", headers=headers, json={"savings_cents": 400000})
    assert reached.json()["goal_just_reached"] is True
    assert reached.json()["packing"][0]["done"] is True
    assert reached.json()["itinerary"][0]["title"] == "Drive out"

    dash = client.get("/v1/dashboard?today=2026-11-21", headers=headers).json()
    assert dash["family"]["name"] == "Cole & Partner"
    assert dash["chores"]["done"] == 1
    assert dash["trip"]["name"] == "Coastal weekend"
    assert dash["trip"]["days_until"] > 0

    logged_out = client.post("/v1/logout", headers=headers)
    assert logged_out.status_code == 200
    assert client.get("/v1/me", headers=headers).status_code == 401


def test_transaction_edit_and_delete(client):
    _created, headers = create_family(client)
    created = client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "City Fuel", "amount_cents": 5210, "occurred_on": "2026-11-19", "kind": "expense"},
    )
    txn_id = created.json()["id"]
    edited = client.patch(
        f"/v1/transactions/{txn_id}",
        headers=headers,
        json={"merchant": "City Fuel Co", "amount_cents": 5300},
    )
    assert edited.json()["merchant"] == "City Fuel Co"
    assert edited.json()["amount_cents"] == 5300
    assert client.delete(f"/v1/transactions/{txn_id}", headers=headers).status_code == 200
    assert client.delete(f"/v1/transactions/{txn_id}", headers=headers).status_code == 404
