"""Budget math: pace, envelopes, history, suggestions, and rule-based insights."""

from __future__ import annotations

import calendar
from datetime import date

from .db import many, month_bounds, one


def money(cents: int) -> str:
    sign = "-" if cents < 0 else ""
    cents = abs(int(cents))
    if cents % 100 == 0:
        return f"{sign}${cents // 100:,}"
    return f"{sign}${cents // 100:,}.{cents % 100:02d}"


def month_name(month: str) -> str:
    year, mon = (int(part) for part in month.split("-"))
    return f"{calendar.month_name[mon]} {year}"


def effective_budget(conn, category_row, month: str) -> int:
    override = one(
        conn,
        "SELECT amount_cents FROM category_budgets WHERE category_id = ? AND month = ?",
        (category_row["id"], month),
    )
    if override is not None:
        return int(override["amount_cents"])
    return int(category_row["default_budget_cents"])


def _spent_by_category(conn, family_id: str, start: date, end: date) -> dict[str, int]:
    rows = many(
        conn,
        """
        SELECT category_id, COALESCE(SUM(amount_cents), 0) AS spent
        FROM transactions
        WHERE family_id = ? AND kind = 'expense'
          AND occurred_on >= ? AND occurred_on <= ?
          AND category_id IS NOT NULL
        GROUP BY category_id
        """,
        (family_id, start.isoformat(), end.isoformat()),
    )
    return {row["category_id"]: int(row["spent"]) for row in rows}


def _sum_spent(conn, family_id: str, start: date, end: date) -> int:
    row = one(
        conn,
        """
        SELECT COALESCE(SUM(amount_cents), 0) AS spent
        FROM transactions
        WHERE family_id = ? AND kind = 'expense'
          AND occurred_on >= ? AND occurred_on <= ?
        """,
        (family_id, start.isoformat(), end.isoformat()),
    )
    return int(row["spent"])


def _income_txn_sum(conn, family_id: str, start: date, end: date) -> int:
    row = one(
        conn,
        """
        SELECT COALESCE(SUM(amount_cents), 0) AS received
        FROM transactions
        WHERE family_id = ? AND kind = 'income'
          AND occurred_on >= ? AND occurred_on <= ?
        """,
        (family_id, start.isoformat(), end.isoformat()),
    )
    return int(row["received"])


def pace_for(spent: int, budget: int, today: date, start: date, end: date) -> str:
    if budget <= 0:
        return "no_budget"
    if today < start:
        return "on_pace" if spent <= budget else "over"
    if spent > budget:
        return "over"
    days_in = (end - start).days + 1
    if today >= end:
        elapsed = days_in
    else:
        elapsed = (today - start).days + 1
    expected = budget * (elapsed / days_in)
    if spent > expected * 1.1:
        return "watch"
    return "on_pace"


def _history_last_month(month: str, today: date) -> int:
    year = int(month[:4])
    selected = int(month[5:7])
    if year == today.year:
        return max(today.month, min(selected, 12)) if selected <= today.month else today.month
    if year < today.year:
        return 12
    return selected


def build_budget(conn, family_id: str, month: str, today: date) -> dict:
    start, end = month_bounds(month)
    categories = many(
        conn,
        """
        SELECT * FROM categories
        WHERE family_id = ? AND archived = 0
        ORDER BY sort_order, name
        """,
        (family_id,),
    )
    spent_map = _spent_by_category(conn, family_id, start, end)
    cat_out = []
    budget_total = 0
    for cat in categories:
        budget = effective_budget(conn, cat, month)
        budget_total += budget
        cat_out.append(
            {
                "id": cat["id"],
                "name": cat["name"],
                "color": cat["color"],
                "icon": cat["icon"],
                "spent_cents": spent_map.get(cat["id"], 0),
                "budget_cents": budget,
                "default_budget_cents": int(cat["default_budget_cents"]),
            }
        )

    spent_total = _sum_spent(conn, family_id, start, end)
    uncategorized = one(
        conn,
        """
        SELECT COALESCE(SUM(amount_cents), 0) AS spent
        FROM transactions
        WHERE family_id = ? AND kind = 'expense'
          AND occurred_on >= ? AND occurred_on <= ?
          AND category_id IS NULL
        """,
        (family_id, start.isoformat(), end.isoformat()),
    )
    remaining = budget_total - spent_total
    days_in = (end - start).days + 1
    if today < start:
        elapsed = 0
        days_left = days_in
    elif today > end:
        elapsed = days_in
        days_left = 0
    else:
        elapsed = (today - start).days + 1
        days_left = (end - today).days + 1

    bills = _bills(conn, family_id)
    upcoming_bills = []
    upcoming_sum = 0
    for bill in bills:
        due = date.fromisoformat(bill["due_on"])
        if bill["paid"]:
            continue
        if start <= due <= end and due >= today:
            upcoming_bills.append(bill)
            upcoming_sum += bill["amount_cents"]
    # Also surface near-term bills that fall just outside the viewed month
    # when the viewed month is the current one. The list itself is global.
    soon = [b for b in bills if not b["paid"] and b["due_on"] >= today.isoformat()]
    soon.sort(key=lambda b: b["due_on"])

    flexible = remaining - upcoming_sum
    if days_left <= 0:
        per_day = 0
    else:
        per_day = int(round(max(0, flexible) / days_left))

    income_entries = _income(conn, family_id, month)
    expected = sum(item["expected_cents"] for item in income_entries)
    received = sum(item["received_cents"] for item in income_entries)
    income_from_txns = _income_txn_sum(conn, family_id, start, end)
    using_entries = len(income_entries) > 0
    if not using_entries:
        received = income_from_txns
        expected = 0

    projected_leftover = None
    if using_entries and budget_total > 0:
        projected_leftover = expected - budget_total

    history, history_budget = _history(conn, family_id, month, today, categories)
    trends = _trends(conn, family_id, month, today, cat_out, history)
    insights = _insights(conn, family_id, month, today, start, end, cat_out, soon, trends, remaining, budget_total)

    txns = _transactions(conn, family_id, start.isoformat(), end.isoformat(), limit=300)
    import_count = one(
        conn,
        "SELECT COUNT(*) AS n FROM transactions WHERE family_id = ? AND source = 'import'",
        (family_id,),
    )["n"]

    return {
        "month": month,
        "month_label": month_name(month),
        "spent_cents": spent_total,
        "budget_cents": budget_total,
        "remaining_cents": remaining,
        "uncategorized_cents": int(uncategorized["spent"]),
        "income_received_cents": received,
        "income_expected_cents": expected,
        "income_from_transactions_cents": income_from_txns,
        "projected_leftover_cents": projected_leftover,
        "days_in_month": days_in,
        "days_elapsed": elapsed,
        "days_left": days_left,
        "pace": pace_for(spent_total, budget_total, today, start, end),
        "safe_to_spend_cents": max(0, flexible) if days_left else 0,
        "safe_per_day_cents": per_day,
        "upcoming_bills_cents": upcoming_sum,
        "categories": cat_out,
        "income_entries": income_entries,
        "bills": soon[:12],
        "transactions": txns,
        "accounts": _accounts(conn, family_id),
        "history": history,
        "history_budget_cents": history_budget,
        "trends": trends,
        "insights": insights,
        "import_count": int(import_count),
        "placeholders": {
            "bank_sync": "Connect SimpleFIN in Settings to sync transactions automatically.",
            "ai": "Ask Gemini for a closer look when a key is configured on the server.",
        },
    }


def _history(conn, family_id: str, month: str, today: date, categories) -> tuple[list[dict], int]:
    year = int(month[:4])
    last = _history_last_month(month, today)
    selected_budget = 0
    points = []
    for mon in range(1, last + 1):
        key = f"{year}-{mon:02d}"
        start, end = month_bounds(key)
        spent = _sum_spent(conn, family_id, start, end)
        budget = 0
        for cat in categories:
            budget += effective_budget(conn, cat, key)
        if key == month:
            selected_budget = budget
        points.append(
            {
                "month": key,
                "spent_cents": spent,
                "budget_cents": budget,
                "is_current": key == today.strftime("%Y-%m"),
            }
        )
    if selected_budget == 0 and points:
        selected_budget = points[-1]["budget_cents"]
    return points, selected_budget


def _trends(conn, family_id: str, month: str, today: date, cat_out: list[dict], history: list[dict]) -> list[dict]:
    ranked = sorted(cat_out, key=lambda c: c["spent_cents"], reverse=True)
    ranked = [c for c in ranked if c["spent_cents"] > 0][:3]
    if not ranked:
        ranked = cat_out[:3]
    start, end = month_bounds(month)
    days_in = (end - start).days + 1
    if today < start:
        elapsed = 0
    elif today > end:
        elapsed = days_in
    else:
        elapsed = (today - start).days + 1
    is_current = month == today.strftime("%Y-%m")
    out = []
    for cat in ranked:
        points = []
        for point in history:
            h_start, h_end = month_bounds(point["month"])
            spent_map = _spent_by_category(conn, family_id, h_start, h_end)
            points.append(spent_map.get(cat["id"], 0))
        baseline_vals = []
        for point, value in zip(history, points):
            if point["month"] == month:
                continue
            if point["month"] > today.strftime("%Y-%m"):
                continue
            # Only average months where the family recorded any spending,
            # so an empty future chart doesn't drag the average to zero.
            if point["spent_cents"] > 0:
                baseline_vals.append(value)
        current = next((v for p, v in zip(history, points) if p["month"] == month), cat["spent_cents"])
        if is_current and elapsed > 0:
            projected = int(round(current / elapsed * days_in))
        else:
            projected = current
        if baseline_vals:
            avg = sum(baseline_vals) / len(baseline_vals)
        else:
            avg = 0
        if avg <= 0:
            direction = "flat"
            label = "Not enough history yet"
        else:
            pct = (projected - avg) / avg * 100
            if pct >= 8:
                direction = "up"
                label = f"+{round(pct)}% this month"
            elif pct <= -8:
                direction = "down"
                label = "On pace, under avg" if is_current else f"{round(pct)}% vs average"
            else:
                direction = "flat"
                label = "Steady vs average"
        out.append(
            {
                "category_id": cat["id"],
                "name": cat["name"],
                "color": cat["color"],
                "points": points,
                "delta_label": label,
                "direction": direction,
            }
        )
    return out


def _insights(conn, family_id, month, today, start, end, cat_out, soon, trends, remaining, budget_total) -> list[dict]:
    insights = []
    overs = [c for c in cat_out if c["budget_cents"] > 0 and c["spent_cents"] > c["budget_cents"]]
    overs.sort(key=lambda c: c["spent_cents"] - c["budget_cents"], reverse=True)
    for cat in overs[:2]:
        over = cat["spent_cents"] - cat["budget_cents"]
        latest = one(
            conn,
            """
            SELECT merchant, amount_cents FROM transactions
            WHERE family_id = ? AND category_id = ? AND kind = 'expense'
              AND occurred_on >= ? AND occurred_on <= ?
            ORDER BY occurred_on DESC, created_at DESC LIMIT 1
            """,
            (family_id, cat["id"], start.isoformat(), end.isoformat()),
        )
        body = f"{money(cat['spent_cents'])} spent of a {money(cat['budget_cents'])} budget."
        if latest:
            body = (
                f"{money(cat['spent_cents'])} spent of a {money(cat['budget_cents'])} budget, "
                f"led by {latest['merchant']} ({money(latest['amount_cents'])})."
            )
        insights.append(
            {
                "level": "bad",
                "title": f"You're {money(over)} over on {cat['name'].lower()} this month.",
                "body": body,
            }
        )

    for bill in soon:
        due = date.fromisoformat(bill["due_on"])
        if (due - today).days > 10:
            continue
        insights.append(
            {
                "level": "warn",
                "title": f"{bill['name']}, {money(bill['amount_cents'])}, is due {due.strftime('%b')} {due.day}.",
                "body": "Upcoming bills are set aside in safe-to-spend.",
            }
        )
        if len([i for i in insights if i["level"] == "warn"]) >= 1:
            break

    for trend in trends:
        if trend["direction"] == "down":
            insights.append(
                {
                    "level": "good",
                    "title": f"{trend['name']} is trending under.",
                    "body": trend["delta_label"] + ".",
                }
            )
            break

    if budget_total <= 0:
        insights.append(
            {
                "level": "warn",
                "title": "Set category budgets to see pace.",
                "body": "Import a CSV of past spending, then tap Suggest budgets.",
            }
        )
    elif not overs:
        insights.append(
            {
                "level": "good",
                "title": f"{money(max(remaining, 0))} still in the {month_name(month).split()[0]} budget.",
                "body": "You're inside the plan so far." if remaining >= 0 else "Spending is past the plan.",
            }
        )
    return insights[:4]


def suggest(conn, family_id: str, month: str, today: date, apply: bool) -> dict:
    """Average monthly spend per category across earlier months that have any spending."""
    categories = many(
        conn,
        "SELECT * FROM categories WHERE family_id = ? AND archived = 0 ORDER BY sort_order, name",
        (family_id,),
    )
    rows = many(
        conn,
        """
        SELECT substr(occurred_on, 1, 7) AS month, category_id, SUM(amount_cents) AS spent
        FROM transactions
        WHERE family_id = ? AND kind = 'expense' AND occurred_on < ?
        GROUP BY 1, 2
        """,
        (family_id, month + "-01"),
    )
    months = sorted({row["month"] for row in rows})
    by_cat: dict[str, int] = {}
    for row in rows:
        if row["category_id"]:
            by_cat[row["category_id"]] = by_cat.get(row["category_id"], 0) + int(row["spent"])
    suggestions = []
    for cat in categories:
        if not months:
            avg = 0
        else:
            avg = int(round(by_cat.get(cat["id"], 0) / len(months) / 100.0) * 100)
        suggestions.append(
            {
                "category_id": cat["id"],
                "name": cat["name"],
                "average_cents": avg,
                "months_counted": len(months),
            }
        )
        if apply:
            conn.execute(
                "UPDATE categories SET default_budget_cents = ? WHERE id = ?",
                (avg, cat["id"]),
            )
            conn.execute(
                """
                INSERT INTO category_budgets (category_id, month, amount_cents)
                VALUES (?, ?, ?)
                ON CONFLICT(category_id, month) DO UPDATE SET amount_cents = excluded.amount_cents
                """,
                (cat["id"], month, avg),
            )
    return {
        "month": month,
        "months_counted": len(months),
        "applied": apply,
        "suggestions": suggestions,
        "message": (
            "No earlier transactions to average yet. Import a CSV first."
            if not months
            else f"Suggested from {len(months)} month{'s' if len(months) != 1 else ''} of history."
        ),
    }


def _transactions(conn, family_id: str, start: str | None, end: str | None, limit: int) -> list[dict]:
    sql = """
        SELECT t.*, c.name AS category_name, c.color AS category_color, c.icon AS category_icon,
               m.name AS member_name
        FROM transactions t
        LEFT JOIN categories c ON c.id = t.category_id
        LEFT JOIN members m ON m.id = t.member_id
        WHERE t.family_id = ?
    """
    args: list = [family_id]
    if start and end:
        sql += " AND t.occurred_on >= ? AND t.occurred_on <= ?"
        args.extend([start, end])
    sql += " ORDER BY t.occurred_on DESC, t.created_at DESC LIMIT ?"
    args.append(limit)
    return [_txn(row) for row in many(conn, sql, tuple(args))]


def recent_expenses(conn, family_id: str, limit: int = 3) -> list[dict]:
    rows = many(
        conn,
        """
        SELECT t.*, c.name AS category_name, c.color AS category_color, c.icon AS category_icon,
               m.name AS member_name
        FROM transactions t
        LEFT JOIN categories c ON c.id = t.category_id
        LEFT JOIN members m ON m.id = t.member_id
        WHERE t.family_id = ? AND t.kind = 'expense'
        ORDER BY t.occurred_on DESC, t.created_at DESC
        LIMIT ?
        """,
        (family_id, limit),
    )
    return [_txn(row) for row in rows]


def _txn(row) -> dict:
    return {
        "id": row["id"],
        "category_id": row["category_id"],
        "category_name": row["category_name"],
        "category_color": row["category_color"],
        "category_icon": row["category_icon"],
        "member_id": row["member_id"],
        "member_name": row["member_name"],
        "merchant": row["merchant"],
        "amount_cents": int(row["amount_cents"]),
        "kind": row["kind"],
        "direction": row["direction"],
        "occurred_on": row["occurred_on"],
        "note": row["note"],
        "source": row["source"],
        "created_at": row["created_at"],
    }


def _income(conn, family_id: str, month: str | None) -> list[dict]:
    sql = """
        SELECT i.*, m.name AS member_name
        FROM income_entries i
        LEFT JOIN members m ON m.id = i.member_id
        WHERE i.family_id = ?
    """
    args: list = [family_id]
    if month:
        sql += " AND i.month = ?"
        args.append(month)
    sql += " ORDER BY i.expected_on IS NULL, i.expected_on, i.created_at"
    out = []
    for row in many(conn, sql, tuple(args)):
        out.append(
            {
                "id": row["id"],
                "member_id": row["member_id"],
                "member_name": row["member_name"],
                "label": row["label"],
                "month": row["month"],
                "expected_cents": int(row["expected_cents"]),
                "received_cents": int(row["received_cents"]),
                "expected_on": row["expected_on"],
                "received_on": row["received_on"],
            }
        )
    return out


def _bills(conn, family_id: str) -> list[dict]:
    rows = many(
        conn,
        """
        SELECT b.*, c.name AS category_name
        FROM bills b
        LEFT JOIN categories c ON c.id = b.category_id
        WHERE b.family_id = ?
        ORDER BY b.due_on
        """,
        (family_id,),
    )
    return [_bill(row) for row in rows]


def _bill(row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "amount_cents": int(row["amount_cents"]),
        "due_on": row["due_on"],
        "category_id": row["category_id"],
        "category_name": row["category_name"],
        "cadence": row["cadence"],
        "paid": bool(row["paid"]),
        "notes": row["notes"],
    }


def _accounts(conn, family_id: str) -> list[dict]:
    rows = many(
        conn,
        "SELECT * FROM accounts WHERE family_id = ? ORDER BY created_at",
        (family_id,),
    )
    return [
        {
            "id": row["id"],
            "name": row["name"],
            "institution": row["institution"],
            "balance_cents": int(row["balance_cents"]),
            "kind": row["kind"],
        }
        for row in rows
    ]
