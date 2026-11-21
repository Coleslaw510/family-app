"""v1.1 additions. Existing rows are never dropped."""

import io

from openpyxl import Workbook

from app.v11 import mask_url, parse_ics, simulate_mortgage


def test_migration_keeps_categories(client):
    _created, headers = client_family(client)
    first = client.get("/v1/categories", headers=headers).json()["categories"]
    again = client.get("/v1/categories", headers=headers).json()["categories"]
    assert [item["id"] for item in again] == [item["id"] for item in first]
    assert len(first) == 8


def test_category_reorder_and_reassign_delete(client):
    _created, headers = client_family(client)
    categories = client.get("/v1/categories", headers=headers).json()["categories"]
    groceries = next(item for item in categories if item["name"] == "Groceries")
    dining = next(item for item in categories if item["name"] == "Dining")
    order = [item["id"] for item in categories]
    order.remove(dining["id"])
    order.insert(0, dining["id"])
    moved = client.put("/v1/categories/order", headers=headers, json={"ids": order})
    assert moved.status_code == 200, moved.text
    renamed = client.patch(
        f"/v1/categories/{dining['id']}",
        headers=headers,
        json={"name": "Eating out", "color": "#e11d48", "icon": "fork.knife"},
    )
    assert renamed.json()["name"] == "Eating out"
    client.post(
        "/v1/transactions",
        headers=headers,
        json={"merchant": "Cafe", "amount_cents": 1200, "occurred_on": "2026-11-02", "category_id": dining["id"]},
    )
    blocked = client.delete(f"/v1/categories/{dining['id']}", headers=headers)
    assert blocked.status_code == 409
    assert blocked.json()["detail"]["transaction_count"] == 1
    gone = client.delete(
        f"/v1/categories/{dining['id']}?reassign_to={groceries['id']}",
        headers=headers,
    )
    assert gone.status_code == 200, gone.text
    txns = client.get("/v1/transactions?month=2026-11", headers=headers).json()["transactions"]
    assert txns[0]["category_id"] == groceries["id"]


def test_csv_and_excel_import_dedupes_and_categorizes(client, monkeypatch):
    _created, headers = client_family(client)
    csv_body = "Date,Description,Amount\n2026-03-02,Kroger Market,42.10\n2026-03-02,Kroger Market,42.10\n"
    first = client.post(
        "/v1/imports/parse",
        headers=headers,
        files={"file": ("bank.csv", csv_body, "text/csv")},
    )
    assert first.status_code == 200, first.text
    payload = first.json()
    assert payload["suggested"]["date_column"] == 0
    assert "url" not in payload
    commit = client.post(
        f"/v1/imports/{payload['import_id']}/commit",
        headers=headers,
        json={
            "date_column": 0,
            "description_column": 1,
            "amount_column": 2,
            "flip_signs": False,
            "has_header": True,
        },
    )
    assert commit.status_code == 200, commit.text
    assert commit.json()["imported"] == 1
    assert commit.json()["skipped"] == 1
    assert commit.json()["categorized"] == 1

    book = Workbook()
    sheet = book.active
    sheet.append(["Posted", "Memo", "Debit", "Credit"])
    sheet.append(["03/04/2026", "Shell Fuel", 40, None])
    sheet.append(["03/05/2026", "Paycheck", None, 1500])
    buffer = io.BytesIO()
    book.save(buffer)
    excel = client.post(
        "/v1/imports/parse",
        headers=headers,
        files={"file": ("card.xlsx", buffer.getvalue(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
    )
    assert excel.status_code == 200, excel.text
    done = client.post(
        f"/v1/imports/{excel.json()['import_id']}/commit",
        headers=headers,
        json={
            "date_column": 0,
            "description_column": 1,
            "debit_column": 2,
            "credit_column": 3,
        },
    )
    assert done.json()["imported"] == 2
    march = client.get("/v1/transactions?month=2026-03", headers=headers).json()["transactions"]
    kinds = {item["merchant"]: item["kind"] for item in march}
    assert kinds["Shell Fuel"] == "expense"
    assert kinds["Paycheck"] == "income"


def test_feed_url_is_masked_and_ics_parses(client, monkeypatch):
    monkeypatch.setattr("app.v11._refresh_feed_id", lambda _feed_id: None)
    _created, headers = client_family(client)
    secret = "https://calendar.example.com/private/abc123secret"
    created = client.post(
        "/v1/calendar-feeds",
        headers=headers,
        json={"name": "School", "color": "#7c3aed", "url": secret},
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert secret not in str(body)
    assert body["url_masked"].startswith("https://calendar.example.com/")
    assert "secret" not in body["url_masked"]
    events = parse_ics(
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:evt-1\nSUMMARY:Practice\nDTSTART;VALUE=DATE:20261121\nEND:VEVENT\nEND:VCALENDAR\n"
    )
    assert events[0]["title"] == "Practice"
    assert events[0]["all_day"] is True
    assert mask_url(secret) != secret


def test_mortgage_math_and_quiet_rentcast(client, monkeypatch):
    monkeypatch.delenv("RENTCAST_API_KEY", raising=False)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    _created, headers = client_family(client)
    saved = client.put(
        "/v1/mortgage",
        headers=headers,
        json={
            "loan_cents": 12000000,
            "annual_rate_percent": 6,
            "term_months": 360,
            "start_date": "2020-01-01",
            "payment_cents": 71946,
            "extra_cents": 0,
            "address": "1 Main St",
        },
    )
    assert saved.status_code == 200, saved.text
    summary = saved.json()["summary"]
    assert summary["balance_cents"] < 12000000
    assert summary["interest_paid_cents"] > 0
    assert summary["payoff_date"]
    assert saved.json()["rentcast_active"] is False
    status = client.get("/v1/integrations", headers=headers).json()
    assert status["gemini_configured"] is False
    assert status["rentcast_active"] is False
    asked = client.post(
        "/v1/budget/ask",
        headers=headers,
        json={"month": "2026-11", "question": "How are we doing?", "today": "2026-11-21"},
    )
    assert asked.status_code == 503
    walk = simulate_mortgage(100000, 0, 1000, 0)
    assert walk["payoff_months"] == 100
    assert walk["interest_paid_cents"] == 0


def test_food_is_per_member_and_import_skips_personal_defaults(client):
    created, headers = client_family(client)
    logged = client.post(
        "/v1/food/entries",
        headers=headers,
        json={"day_on": "2026-11-21", "name": "Oats", "meal": "Breakfast", "calories": 320, "protein": 12, "carbs": 50, "fat": 6},
    )
    assert logged.status_code == 200, logged.text
    bundle = client.get("/v1/food?day=2026-11-21", headers=headers).json()
    assert bundle["totals"]["calories"] == 320
    assert bundle["goals"]["calories"] == 2000
    partner = client.post("/v1/families/join", json={"code": created["join_code"], "name": "Ada"})
    partner_headers = {"Authorization": f"Bearer {partner.json()['token']}"}
    theirs = client.get(f"/v1/food?day=2026-11-21&member_id={created['member']['id']}", headers=partner_headers)
    assert theirs.json()["entries"][0]["name"] == "Oats"
    imported = client.post(
        "/v1/food/import",
        headers=partner_headers,
        json={
            "schemaVersion": 4,
            "profile": {"name": "Someone", "age": 40, "calories": 1900, "protein": 100, "carbs": 180, "fat": 60, "water": 8},
            "days": [{"id": "2026-11-20", "water": 6, "foods": [{"name": "Soup", "meal": "Lunch", "calories": 400, "protein": 20, "carbs": 40, "fat": 12}]}],
            "favorites": [{"name": "Soup", "meal": "Lunch", "calories": 400, "protein": 20, "carbs": 40, "fat": 12}],
            "weights": [{"pounds": 245}],
            "days_workouts_ignored": True,
        },
    )
    assert imported.status_code == 200, imported.text
    after = client.get("/v1/food?day=2026-11-20", headers=partner_headers).json()
    assert after["entries"][0]["name"] == "Soup"
    assert after["water_cups"] == 6
    assert after["goals"]["calories"] == 1900
    assert after["favorites"][0]["name"] == "Soup"
    dinner = client.post(
        "/v1/dinners",
        headers=headers,
        json={"day_on": "2026-11-21", "title": "Chili", "notes": "Extra beans"},
    )
    dinner_id = dinner.json()["id"]
    grocery = client.post(
        f"/v1/dinners/{dinner_id}/grocery",
        headers=headers,
        json={"items": ["Beans", "Tortillas"]},
    )
    assert grocery.json()["added"] == 2
    board = client.get("/v1/household", headers=headers).json()
    assert {item["body"] for item in board["notes"]} >= {"Beans", "Tortillas"}


def client_family(client):
    response = client.post("/v1/families", json={"name": "Cole", "family_name": "Mini McClintocks"})
    assert response.status_code == 200, response.text
    data = response.json()
    return data, {"Authorization": f"Bearer {data['token']}"}
