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


def init_db(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)


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
