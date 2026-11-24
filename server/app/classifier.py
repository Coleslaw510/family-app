"""Shared, family-scoped transaction classification for bank and file imports."""

from __future__ import annotations

from .db import many, one


DEFAULT_CATEGORIES = [
    (("kroger", "walmart", "costco", "trader joe", "grocery", "market"), "Groceries"),
    (("doordash", "uber eats", "restaurant", "cafe", "coffee"), "Dining"),
    (("shell", "chevron", "exxon", "fuel", "gas station"), "Fuel"),
    (("netflix", "electric", "water bill", "insurance", "utility", "internet"), "Bills / Utilities"),
]

DEFAULT_TRANSFER_PATTERNS = (
    "credit card payment",
    "credit card pmt",
    "credit card autopay",
    "card payment",
    "card pmt",
    "payment thank you",
    "autopay credit card",
)


def match_transaction_rule(conn, family_id: str, merchant: str, flow_direction: str):
    """Return the most-specific applicable family rule, if one matches."""
    rules = many(
        conn,
        """
        SELECT id, pattern, kind, flow_direction, category_id
        FROM transaction_rules
        WHERE family_id = ?
        ORDER BY length(pattern) DESC,
                 CASE WHEN flow_direction = 'any' THEN 0 ELSE 1 END DESC,
                 created_at DESC, id DESC
        """,
        (family_id,),
    )
    lowered = merchant.casefold()
    for rule in rules:
        if rule["flow_direction"] not in {"any", flow_direction}:
            continue
        if rule["pattern"].casefold() in lowered:
            return rule
    return None


def classify_transaction(
    conn,
    family_id: str,
    merchant: str,
    kind: str,
    flow_direction: str,
    fallback_category_id: str | None = None,
) -> tuple[str, str | None, str | None]:
    """Return (kind, category_id, matched_rule_id)."""
    rule = match_transaction_rule(conn, family_id, merchant, flow_direction)
    if rule is not None:
        category_id = rule["category_id"] if rule["kind"] == "expense" else None
        return rule["kind"], category_id, rule["id"]

    lowered = merchant.casefold()
    if flow_direction == "outflow" and any(pattern in lowered for pattern in DEFAULT_TRANSFER_PATTERNS):
        return "transfer", None, "default:credit-card-payment"

    if kind == "expense":
        legacy = many(
            conn,
            """
            SELECT r.id, r.pattern, r.category_id
            FROM category_rules r
            JOIN categories c ON c.id = r.category_id AND c.family_id = r.family_id
            WHERE r.family_id = ? AND c.archived = 0
            ORDER BY length(r.pattern) DESC, r.created_at DESC, r.id DESC
            """,
            (family_id,),
        )
        for rule in legacy:
            if rule["pattern"].casefold() in lowered:
                return kind, rule["category_id"], f"legacy:{rule['id']}"

        for needles, category_name in DEFAULT_CATEGORIES:
            if any(needle in lowered for needle in needles):
                category = one(
                    conn,
                    "SELECT id FROM categories WHERE family_id = ? AND lower(name) = lower(?) AND archived = 0",
                    (family_id, category_name),
                )
                if category:
                    return kind, category["id"], None

    return kind, fallback_category_id, None


def apply_rule_to_existing(conn, family_id: str, rule_id: str) -> int:
    """Apply the winning current rule to existing rows; preserve each row's original flow."""
    rule = one(
        conn,
        "SELECT * FROM transaction_rules WHERE id = ? AND family_id = ?",
        (rule_id, family_id),
    )
    if rule is None:
        return 0

    rows = many(
        conn,
        "SELECT id, merchant, kind, category_id, direction FROM transactions WHERE family_id = ?",
        (family_id,),
    )
    changed = 0
    for row in rows:
        matched = match_transaction_rule(conn, family_id, row["merchant"], row["direction"])
        if matched is None or matched["id"] != rule_id:
            continue
        category_id = matched["category_id"] if matched["kind"] == "expense" else None
        if row["kind"] == matched["kind"] and row["category_id"] == category_id:
            continue
        conn.execute(
            "UPDATE transactions SET kind = ?, category_id = ? WHERE id = ? AND family_id = ?",
            (matched["kind"], category_id, row["id"], family_id),
        )
        changed += 1
    return changed
