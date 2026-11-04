import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import event, inspect, text
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, create_engine, select

from app.database import db
from app.database import seed as seed_module
from app.database.models import Category, Item, StockTransaction, Supplier
from app.main import app


class LaboratoryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        database_path = Path(self.directory.name) / "test.db"
        self.engine = create_engine(
            f"sqlite:///{database_path}",
            connect_args={"check_same_thread": False},
        )
        event.listen(self.engine, "connect", db.enable_foreign_keys)
        self.addCleanup(self.directory.cleanup)
        self.addCleanup(self.engine.dispose)
        self.enterContext(patch.object(db, "engine", self.engine))
        self.enterContext(patch.object(seed_module, "engine", self.engine))
        seed_module.seed()
        self.client = self.enterContext(TestClient(app))
        self.items = self.client.get("/items").json()
        first = self.items[0]
        self.payload = {
            "name": "Тестовый товар",
            "price": 1500,
            "quantity": 4,
            "category_id": first["category_id"],
            "supplier_id": first["supplier_id"],
        }

    def test_tables_relationships_and_repeated_seed(self):
        seed_module.seed()
        self.assertEqual(
            set(inspect(self.engine).get_table_names()),
            {"category", "supplier", "item", "stocktransaction"},
        )
        with Session(self.engine) as session:
            for model, count in ((Category, 3), (Supplier, 3), (Item, 5), (StockTransaction, 5)):
                self.assertEqual(len(session.exec(select(model)).all()), count)
            item = session.exec(select(Item)).first()
            self.assertEqual(item.category.id, item.category_id)
            self.assertEqual(item.supplier.id, item.supplier_id)
            self.assertEqual(item.transactions[0].item.id, item.id)

    def test_root_and_swagger(self):
        self.assertEqual(self.client.get("/").json()["status"], "ok")
        self.assertEqual(self.client.get("/docs").status_code, 200)
        paths = self.client.get("/openapi.json").json()["paths"]
        self.assertTrue({"get", "post"}.issubset(paths["/items"]))
        self.assertTrue({"get", "patch", "delete"}.issubset(paths["/items/{item_id}"]))

    def test_get_list_and_item(self):
        self.assertEqual(len(self.items), 5)
        item = self.items[0]
        self.assertEqual(self.client.get(f"/items/{item['id']}").json(), item)

    def test_create_patch_delete_lifecycle(self):
        response = self.client.post("/items", json=self.payload)
        self.assertEqual(response.status_code, 201)
        created = response.json()
        url = f"/items/{created['id']}"
        updated = self.client.patch(url, json={"price": 2000})
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.json(), {**created, "price": 2000})
        self.assertEqual(self.client.get(url).json(), updated.json())
        self.assertEqual(self.client.delete(url).status_code, 200)
        for method, kwargs in (("get", {}), ("patch", {"json": {"price": 1}}), ("delete", {})):
            self.assertEqual(getattr(self.client, method)(url, **kwargs).status_code, 404)

    def test_delete_seeded_item_removes_dependent_transactions(self):
        item_id = self.items[0]["id"]
        self.assertEqual(self.client.delete(f"/items/{item_id}").status_code, 200)
        with Session(self.engine) as session:
            self.assertIsNone(session.get(Item, item_id))
            self.assertEqual(session.exec(select(StockTransaction).where(StockTransaction.item_id == item_id)).all(), [])
            self.assertEqual(len(session.exec(select(Category)).all()), 3)
            self.assertEqual(len(session.exec(select(Supplier)).all()), 3)
        self.assertEqual(self.client.patch(f"/items/{item_id}", json={"price": 100}).status_code, 404)

    def test_invalid_create_does_not_save_data(self):
        for changes in ({"price": -1}, {"name": ""}, {"name": "   "}, {"quantity": -1}, {"category_id": 99999}, {"supplier_id": 99999}, {"id": 123}):
            with self.subTest(changes=changes):
                self.assertEqual(self.client.post("/items", json={**self.payload, **changes}).status_code, 422)
        self.assertEqual(len(self.client.get("/items").json()), 5)

    def test_invalid_patch_is_atomic(self):
        original = self.items[0]
        url = f"/items/{original['id']}"
        for changes in ({"price": -1}, {"name": "   "}, {"price": None}, {"quantity": -1}, {"price": 1, "category_id": 99999}, {"supplier_id": 99999}, {"id": 99}):
            with self.subTest(changes=changes):
                self.assertEqual(self.client.patch(url, json=changes).status_code, 422)
                self.assertEqual(self.client.get(url).json(), original)
        self.assertEqual(self.client.patch(url, json={}).json(), original)

    def test_filtering_and_literal_search(self):
        self.assertEqual([i["name"] for i in self.client.get("/items", params={"search": "утбол"}).json()], ["Футболка"])
        results = self.client.get("/items", params={"min_price": 1200, "max_price": 8500}).json()
        self.assertEqual({i["name"] for i in results}, {"Блокнот", "Мышь", "Футболка"})
        self.assertEqual(self.client.get("/items", params={"search": "Мыш", "min_price": 6500, "max_price": 6500}).json()[0]["name"], "Мышь")
        for search in ("' OR 1=1 --", "%", "_"):
            self.assertEqual(self.client.get("/items", params={"search": search}).json(), [])
        for params in ({"min_price": -1}, {"max_price": -1}, {"min_price": 2, "max_price": 1}, {"min_price": "nan"}, {"max_price": "inf"}):
            self.assertEqual(self.client.get("/items", params=params).status_code, 422)

    def test_missing_ids(self):
        for method, kwargs in (("get", {}), ("patch", {"json": {"price": 1}}), ("delete", {})):
            self.assertEqual(getattr(self.client, method)("/items/99999", **kwargs).status_code, 404)

    def test_database_enforces_foreign_keys(self):
        with self.engine.begin() as connection:
            self.assertEqual(connection.exec_driver_sql("PRAGMA foreign_keys").scalar(), 1)
            with self.assertRaises(IntegrityError):
                connection.execute(text("INSERT INTO item (name, price, quantity, category_id, supplier_id) VALUES ('bad', 1, 0, 99999, 99999)"))

    def test_seed_completes_a_partially_filled_database(self):
        with self.engine.begin() as connection:
            connection.execute(text("DELETE FROM stocktransaction"))
            connection.execute(text("DELETE FROM item"))
            connection.execute(text("DELETE FROM supplier"))
        seed_module.seed()
        with Session(self.engine) as session:
            self.assertEqual(len(session.exec(select(Category)).all()), 3)
            self.assertEqual(len(session.exec(select(Supplier)).all()), 3)
            self.assertEqual(len(session.exec(select(Item)).all()), 5)
            self.assertEqual(len(session.exec(select(StockTransaction)).all()), 5)


if __name__ == "__main__":
    unittest.main()
