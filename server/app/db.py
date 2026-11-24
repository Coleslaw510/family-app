"""SQLite connection, schema, and small helpers."""

from __future__ import annotations

import hashlib
import os
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone

DEFAULT_CATEGORIES = [
    ("Groceries", "#0d9488", "cart.fill", 0),
    ("Dining", "#e11d48", "fork.knife", 1),
    ("Fuel", "#d97706", "fuelpump.fill", 2),
    ("Bills / Utilities", "#475569", "house.fill", 3),
    ("Kids / Family", "#7c3aed", "person.2.fill", 4),
    ("Date Night", "#be185d", "heart.fill", 5),
    ("Shopping", "#4f46e5", "tag.fill", 6),
    ("Vacation fund", "#ea580c", "paperplane.fill", 7),
]

SCHEMA = """
CREATE TABLE IF NOT EXISTS families (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    anniversary_date TEXT,
    first_date TEXT,
    flower_nudge_days INTEGER NOT NULL DEFAULT 14
);

CREATE TABLE IF NOT EXISTS members (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_members_family ON members(family_id, created_at);

CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    member_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_member ON sessions(member_id);

CREATE TABLE IF NOT EXISTS join_codes (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    used_by TEXT
);
CREATE INDEX IF NOT EXISTS idx_join_family ON join_codes(family_id, created_at);
CREATE INDEX IF NOT EXISTS idx_join_hash ON join_codes(code_hash);

CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    icon TEXT NOT NULL,
    default_budget_cents INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_categories_family ON categories(family_id, sort_order);

CREATE TABLE IF NOT EXISTS category_budgets (
    category_id TEXT NOT NULL,
    month TEXT NOT NULL,
    amount_cents INTEGER NOT NULL,
    PRIMARY KEY (category_id, month)
);

CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    category_id TEXT,
    member_id TEXT,
    merchant TEXT NOT NULL,
    amount_cents INTEGER NOT NULL,
    kind TEXT NOT NULL,
    occurred_on TEXT NOT NULL,
    note TEXT,
    source TEXT NOT NULL DEFAULT 'manual',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_txn_family_date ON transactions(family_id, occurred_on);

CREATE TABLE IF NOT EXISTS income_entries (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    member_id TEXT,
    label TEXT NOT NULL,
    month TEXT NOT NULL,
    expected_cents INTEGER NOT NULL,
    received_cents INTEGER NOT NULL DEFAULT 0,
    expected_on TEXT,
    received_on TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_income_family ON income_entries(family_id, month);

CREATE TABLE IF NOT EXISTS bills (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    name TEXT NOT NULL,
    amount_cents INTEGER NOT NULL,
    due_on TEXT NOT NULL,
    category_id TEXT,
    cadence TEXT NOT NULL DEFAULT 'once',
    paid INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_bills_family ON bills(family_id, due_on);

CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    name TEXT NOT NULL,
    institution TEXT,
    balance_cents INTEGER NOT NULL DEFAULT 0,
    kind TEXT NOT NULL DEFAULT 'checking',
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_accounts_family ON accounts(family_id);

CREATE TABLE IF NOT EXISTS birthdays (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    name TEXT NOT NULL,
    month INTEGER NOT NULL,
    day INTEGER NOT NULL,
    year INTEGER,
    member_id TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_birthdays_family ON birthdays(family_id);

CREATE TABLE IF NOT EXISTS flower_logs (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    bought_on TEXT NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_flowers_member ON flower_logs(family_id, member_id, bought_on);

CREATE TABLE IF NOT EXISTS date_nights (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    title TEXT NOT NULL,
    starts_at TEXT NOT NULL,
    location TEXT,
    notes TEXT,
    created_by TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dates_family ON date_nights(family_id, starts_at);

CREATE TABLE IF NOT EXISTS checkins (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    week_start TEXT NOT NULL,
    connection INTEGER NOT NULL,
    appreciation INTEGER NOT NULL,
    fun INTEGER NOT NULL,
    note TEXT,
    created_at TEXT NOT NULL,
    UNIQUE (family_id, member_id, week_start)
);

CREATE TABLE IF NOT EXISTS love_notes (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    author_id TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notes_love ON love_notes(family_id, created_at);

CREATE TABLE IF NOT EXISTS chores (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    title TEXT NOT NULL,
    assignee_id TEXT,
    done INTEGER NOT NULL DEFAULT 0,
    due_on TEXT,
    created_by TEXT,
    completed_at TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chores_family ON chores(family_id, done);

CREATE TABLE IF NOT EXISTS important_dates (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    title TEXT NOT NULL,
    date_on TEXT NOT NULL,
    repeats_yearly INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_important_family ON important_dates(family_id, date_on);

CREATE TABLE IF NOT EXISTS shared_notes (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    body TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0,
    created_by TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_shared_notes ON shared_notes(family_id, kind);

CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    title TEXT NOT NULL,
    starts_at TEXT NOT NULL,
    ends_at TEXT,
    all_day INTEGER NOT NULL DEFAULT 0,
    location TEXT,
    notes TEXT,
    color TEXT NOT NULL DEFAULT '#2563eb',
    created_by TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_family ON events(family_id, starts_at);

CREATE TABLE IF NOT EXISTS trips (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    name TEXT NOT NULL,
    destination TEXT,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    savings_cents INTEGER NOT NULL DEFAULT 0,
    goal_cents INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_trips_family ON trips(family_id, start_date);

CREATE TABLE IF NOT EXISTS packing_items (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL,
    title TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_packing_trip ON packing_items(trip_id, sort_order);

CREATE TABLE IF NOT EXISTS itinerary_items (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL,
    day_on TEXT,
    title TEXT NOT NULL,
    body TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_itinerary_trip ON itinerary_items(trip_id, sort_order);
"""


def db_path() -> str:
    raw = os.environ.get("DB_PATH")
    if not raw:
        raw = os.path.join(os.path.dirname(__file__), "..", "data", "family.db")
    path = os.path.abspath(raw)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def plus_hours(hours: int) -> str:
    return (datetime.now(timezone.utc) + timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")


def plus_days(days: int) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")


def new_id() -> str:
    return str(uuid.uuid4())


def hash_secret(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def one(conn: sqlite3.Connection, sql: str, args: tuple = ()):
    return conn.execute(sql, args).fetchone()


def many(conn: sqlite3.Connection, sql: str, args: tuple = ()):
    return conn.execute(sql, args).fetchall()


V11_SQL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS category_rules (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    pattern TEXT NOT NULL,
    category_id TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rules_family ON category_rules(family_id);

CREATE TABLE IF NOT EXISTS import_sessions (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    filename TEXT,
    headers_json TEXT NOT NULL,
    rows_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS calendar_feeds (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    url TEXT NOT NULL,
    last_fetched_at TEXT,
    last_error TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_feeds_family ON calendar_feeds(family_id);

CREATE TABLE IF NOT EXISTS feed_events (
    id TEXT PRIMARY KEY,
    feed_id TEXT NOT NULL,
    uid TEXT NOT NULL,
    title TEXT NOT NULL,
    starts_at TEXT NOT NULL,
    ends_at TEXT,
    all_day INTEGER NOT NULL DEFAULT 0,
    location TEXT,
    UNIQUE (feed_id, uid)
);
CREATE INDEX IF NOT EXISTS idx_feed_events_feed ON feed_events(feed_id, starts_at);

CREATE TABLE IF NOT EXISTS mortgages (
    family_id TEXT PRIMARY KEY,
    loan_cents INTEGER NOT NULL,
    annual_rate_percent REAL NOT NULL,
    term_months INTEGER NOT NULL,
    start_date TEXT NOT NULL,
    payment_cents INTEGER NOT NULL,
    extra_cents INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS home_profiles (
    family_id TEXT PRIMARY KEY,
    address TEXT,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS home_values (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    valued_on TEXT NOT NULL,
    value_cents INTEGER NOT NULL,
    source TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_home_values_family ON home_values(family_id, valued_on);

CREATE TABLE IF NOT EXISTS integration_status (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS food_goals (
    member_id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    calories INTEGER NOT NULL,
    protein INTEGER NOT NULL,
    carbs INTEGER NOT NULL,
    fat INTEGER NOT NULL,
    water INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS food_entries (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    day_on TEXT NOT NULL,
    name TEXT NOT NULL,
    meal TEXT NOT NULL,
    calories INTEGER NOT NULL,
    protein INTEGER NOT NULL,
    carbs INTEGER NOT NULL,
    fat INTEGER NOT NULL,
    serving TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_food_member_day ON food_entries(member_id, day_on);

CREATE TABLE IF NOT EXISTS food_favorites (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    name TEXT NOT NULL,
    meal TEXT NOT NULL,
    calories INTEGER NOT NULL,
    protein INTEGER NOT NULL,
    carbs INTEGER NOT NULL,
    fat INTEGER NOT NULL,
    serving TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_fav_member ON food_favorites(member_id);

CREATE TABLE IF NOT EXISTS water_logs (
    member_id TEXT NOT NULL,
    day_on TEXT NOT NULL,
    cups INTEGER NOT NULL,
    PRIMARY KEY (member_id, day_on)
);

CREATE TABLE IF NOT EXISTS dinner_plans (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    day_on TEXT NOT NULL,
    title TEXT NOT NULL,
    notes TEXT,
    created_by TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dinner_family ON dinner_plans(family_id, day_on);
"""

SIMPLEFIN_SQL = """
CREATE TABLE IF NOT EXISTS simplefin_connections (
    family_id TEXT PRIMARY KEY,
    connection_id TEXT NOT NULL UNIQUE,
    access_url_encrypted TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_synced_at TEXT,
    last_attempt_at TEXT,
    last_error TEXT
);
CREATE TABLE IF NOT EXISTS simplefin_transaction_ids (
    family_id TEXT NOT NULL,
    connection_id TEXT NOT NULL,
    account_identity TEXT NOT NULL,
    transaction_identity TEXT NOT NULL,
    transaction_id TEXT NOT NULL,
    PRIMARY KEY (family_id, connection_id, account_identity, transaction_identity)
);
CREATE INDEX IF NOT EXISTS idx_simplefin_txn_transaction ON simplefin_transaction_ids(transaction_id);
"""

V13_SQL = """
CREATE TABLE IF NOT EXISTS transaction_rules (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    pattern TEXT NOT NULL,
    kind TEXT NOT NULL,
    flow_direction TEXT NOT NULL DEFAULT 'any',
    category_id TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_transaction_rules_family ON transaction_rules(family_id);
CREATE TABLE IF NOT EXISTS budget_pairings (
    code_hash TEXT PRIMARY KEY,
    family_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    used_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_budget_pairings_member ON budget_pairings(member_id, created_at);
"""


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.executescript(V11_SQL)
    row = conn.execute("SELECT 1 FROM schema_migrations WHERE version = 11").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO schema_migrations (version, applied_at) VALUES (11, ?)",
            (now_iso(),),
        )
    conn.commit()
    conn.execute("BEGIN IMMEDIATE")
    try:
        for statement in SIMPLEFIN_SQL.split(";"):
            if statement.strip():
                conn.execute(statement)
        row = conn.execute("SELECT 1 FROM schema_migrations WHERE version = 12").fetchone()
        if row is None:
            conn.execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (12, ?)",
                (now_iso(),),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    conn.execute("BEGIN IMMEDIATE")
    try:
        if conn.execute("SELECT 1 FROM schema_migrations WHERE version = 13").fetchone() is None:
            columns = {row[1] for row in conn.execute("PRAGMA table_info(transactions)")}
            if "direction" not in columns:
                conn.execute("ALTER TABLE transactions ADD COLUMN direction TEXT NOT NULL DEFAULT 'outflow'")
                conn.execute(
                    "UPDATE transactions SET direction = CASE WHEN kind = 'income' THEN 'inflow' ELSE 'outflow' END"
                )
            for statement in V13_SQL.split(";"):
                if statement.strip():
                    conn.execute(statement)
            conn.execute(
                """
                INSERT OR IGNORE INTO transaction_rules (id, family_id, pattern, kind, flow_direction, category_id, created_at)
                SELECT id, family_id, pattern, 'expense', 'outflow', category_id, created_at
                FROM category_rules
                """
            )
            conn.execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (13, ?)",
                (now_iso(),),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise

    conn.execute("BEGIN IMMEDIATE")
    try:
        if conn.execute("SELECT 1 FROM schema_migrations WHERE version = 14").fetchone() is None:
            card_payment_patterns = (
                "credit card payment",
                "credit card pmt",
                "credit card autopay",
                "card payment",
                "card pmt",
                "payment thank you",
                "autopay credit card",
            )
            for pattern in card_payment_patterns:
                conn.execute(
                    "UPDATE transactions SET kind = 'transfer', category_id = NULL WHERE kind = 'expense' AND direction = 'outflow' AND lower(merchant) LIKE ?",
                    (f"%{pattern}%",),
                )
            conn.execute(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (14, ?)",
                (now_iso(),),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise


@contextmanager
def db():
    conn = sqlite3.connect(db_path(), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    try:
        init_db(conn)
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def month_bounds(month: str) -> tuple[date, date]:
    year, mon = (int(part) for part in month.split("-"))
    start = date(year, mon, 1)
    if mon == 12:
        end = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        end = date(year, mon + 1, 1) - timedelta(days=1)
    return start, end


def seed_categories(conn: sqlite3.Connection, family_id: str) -> None:
    for name, color, icon, sort_order in DEFAULT_CATEGORIES:
        conn.execute(
            """
            INSERT INTO categories (id, family_id, name, color, icon, default_budget_cents, sort_order, archived)
            VALUES (?, ?, ?, ?, ?, 0, ?, 0)
            """,
            (new_id(), family_id, name, color, icon, sort_order),
        )
