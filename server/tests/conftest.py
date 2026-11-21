import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("DB_PATH", str(tmp_path / "family.db"))
    monkeypatch.setenv("JOIN_MAX_ATTEMPTS", "8")
    monkeypatch.setenv("JOIN_WINDOW_SECONDS", "900")
    monkeypatch.setenv("CREATE_MAX_ATTEMPTS", "30")
    monkeypatch.setenv("JOIN_CODE_TTL_HOURS", "24")
    monkeypatch.setenv("FEED_POLL_SECONDS", "3600")
    app = create_app()
    with TestClient(app) as test_client:
        yield test_client
