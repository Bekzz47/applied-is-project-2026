"""HTTP-level checks use the real router, SQLModel and a private SQLite file."""

from concurrent.futures import ThreadPoolExecutor
from secrets import token_urlsafe

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event, text
from sqlmodel import Session, create_engine, select

from app.database import db
from app.database import seed as seed_module
from app.database.models import Item, StockTransaction
from app.main import app


@pytest.fixture
def warehouse(tmp_path, monkeypatch):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'warehouse.db'}", connect_args={"check_same_thread": False},
        hide_parameters=True,
    )
    event.listen(engine, "connect", db.enable_foreign_keys)
    monkeypatch.setattr(db, "engine", engine)
    monkeypatch.setattr(seed_module, "engine", engine)
    admin = ("admin", token_urlsafe(24))
    reader = ("reader", token_urlsafe(24))
    monkeypatch.setenv("WAREHOUSE_ADMIN_PASSWORD", admin[1])
    monkeypatch.setenv("WAREHOUSE_READER_PASSWORD", reader[1])
    seed_module.seed()
    try:
        with TestClient(app) as client:
            yield client, engine, admin, reader
    finally:
        engine.dispose()


def movement(item, quantity, kind="out"):
    return {"item_id": item["id"], "transaction_type": kind, "quantity": quantity}


def test_item_crud_and_full_replacement(warehouse):
    client, engine, admin, _ = warehouse
    sample = client.get("/items").json()[0]
    payload = {k: v for k, v in sample.items() if k != "id"}
    response = client.post("/items", auth=admin, json=payload)
    assert response.status_code == 201
    item_id = response.json()["id"]
    url = f"/items/{item_id}"
    payload.pop("quantity")
    response = client.put(url, auth=admin, json={**payload, "name": "Replacement"})
    assert response.status_code == 200
    assert response.json()["quantity"] == 0
    assert client.get(url).json() == response.json()
    with Session(engine) as session:
        assert session.get(Item, item_id).name == "Replacement"
    assert client.delete(url, auth=admin).status_code == 200
    assert client.get(url).status_code == 404


@pytest.mark.parametrize(("kind", "delta"), [("in", 3), ("out", -3)])
def test_movement_commits_balance_and_history(warehouse, kind, delta):
    client, engine, admin, reader = warehouse
    item = client.get("/items").json()[0]
    response = client.post("/stock/movements", json=movement(item, 3, kind), auth=admin)
    assert response.status_code == 201
    row = response.json()
    assert row == client.get("/stock/movements", auth=reader).json()[-1]
    with Session(engine) as session:
        assert session.get(Item, item["id"]).quantity == item["quantity"] + delta
        assert session.get(StockTransaction, row["id"]).transaction_type == kind


def test_insufficient_balance_writes_nothing(warehouse):
    client, _, admin, reader = warehouse
    item = client.get("/items").json()[0]
    before = client.get("/stock/movements", auth=reader).json()
    response = client.post("/stock/movements", json=movement(item, item["quantity"] + 1), auth=admin)
    assert response.status_code == 409
    assert client.get("/stock/movements", auth=reader).json() == before
    assert client.get(f"/items/{item['id']}").json() == item


def test_failure_to_write_journal_rolls_back_balance(warehouse):
    client, engine, admin, _ = warehouse
    item = client.get("/items").json()[0]
    with engine.begin() as connection:
        connection.execute(text("""
            CREATE TRIGGER reject_test_movement BEFORE INSERT ON stocktransaction
            BEGIN SELECT RAISE(ABORT, 'fixture rejected journal row'); END
        """))
    response = client.post("/stock/movements", json=movement(item, 1), auth=admin)
    assert response.status_code == 409
    assert response.json() == {"detail": "Movement could not be recorded"}
    with Session(engine) as session:
        assert session.get(Item, item["id"]).quantity == item["quantity"]
        assert len(session.exec(select(StockTransaction)).all()) == 5


def test_concurrent_withdrawals_cannot_overdraw(warehouse):
    client, _, admin, reader = warehouse
    item = client.get("/items").json()[0]

    def withdraw():
        return client.post("/stock/movements", json=movement(item, item["quantity"]), auth=admin)

    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(withdraw) for _ in range(2)]
    assert sorted(result.result().status_code for result in futures) == [201, 409]
    assert client.get(f"/items/{item['id']}").json()["quantity"] == 0
    assert len(client.get("/stock/movements", auth=reader).json()) == 6


def test_missing_item(warehouse):
    client, _, admin, _ = warehouse
    response = client.post("/stock/movements", json=movement({"id": 99999}, 1), auth=admin)
    assert response.status_code == 404
    assert response.json() == {"detail": "Item not found"}


@pytest.mark.parametrize("body", [{}, {"item_id": 1, "transaction_type": "in", "quantity": 0}])
def test_invalid_movement_is_rejected(warehouse, body):
    client, _, admin, reader = warehouse
    assert client.post("/stock/movements", json=body, auth=admin).status_code == 422
    assert len(client.get("/stock/movements", auth=reader).json()) == 5


def test_malformed_json(warehouse):
    client, _, admin, _ = warehouse
    response = client.post(
        "/stock/movements", content=b"{", headers={"Content-Type": "application/json"}, auth=admin
    )
    assert response.status_code == 400
    assert response.json() == {"detail": "Malformed JSON"}


@pytest.mark.parametrize("case", ["missing", "empty", "unknown_user", "wrong_password"])
def test_invalid_credentials(warehouse, case):
    client, _, admin, _ = warehouse
    credentials = {
        "missing": None, "empty": ("admin", ""),
        "unknown_user": ("other", admin[1]), "wrong_password": ("admin", token_urlsafe(20)),
    }[case]
    response = client.get("/stock/movements", auth=credentials)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Basic"
    assert response.json() == {"detail": "Authentication required"}


def test_weak_configured_password_cannot_authorize(warehouse, monkeypatch):
    client, _, _, _ = warehouse
    weak = "short"
    monkeypatch.setenv("WAREHOUSE_ADMIN_PASSWORD", weak)
    response = client.get("/stock/movements", auth=("admin", weak))
    assert response.status_code == 401


def test_reader_cannot_write_by_either_route(warehouse):
    client, _, _, reader = warehouse
    item = client.get("/items").json()[0]
    response = client.post("/stock/movements", json=movement(item, 1), auth=reader)
    assert response.status_code == 403
    url = f"/items/{item['id']}"
    assert client.patch(url, json={"quantity": 0}, auth=reader).status_code == 403
    assert client.delete(url).status_code == 401
    assert client.get(url).json() == item


def test_credentials_do_not_appear_in_errors_or_logs(warehouse, caplog):
    client, _, _, _ = warehouse
    secret = token_urlsafe(24)
    response = client.get("/stock/movements", auth=("admin", secret))
    assert response.status_code == 401
    assert secret not in response.text
    assert secret not in caplog.text


def test_mobile_roles_and_catalog_options(warehouse):
    client, _, admin, reader = warehouse
    for auth in (reader, admin):
        assert client.get("/auth/me", auth=auth).json() == {"username": auth[0]}
    assert client.get("/auth/me").status_code == 401
    response = client.get("/catalog/references")
    assert response.status_code == 200
    options = response.json()
    assert len(options["categories"]) == len(options["suppliers"]) == 3
    assert all(set(row) == {"id", "name"} for row in options["suppliers"])
