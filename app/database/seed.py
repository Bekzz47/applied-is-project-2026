from sqlalchemy import text
from sqlmodel import Session, select
from app.database.db import engine, init_db
from app.database.models import Category, Supplier, Item, StockTransaction

def seed():
    init_db()
    with Session(engine) as session:
        # Serialize seed runs so concurrent starts cannot duplicate demo records.
        session.execute(text("BEGIN IMMEDIATE"))
        categories = []
        for name in ("Электроника", "Одежда", "Канцелярия"):
            category = session.exec(select(Category).where(Category.name == name)).first()
            if category is None:
                category = Category(name=name)
                session.add(category)
            categories.append(category)

        suppliers = []
        for name, email in (
            ("Tech Supply", "tech@example.com"),
            ("Fashion Trade", "fashion@example.com"),
            ("Office Goods", "office@example.com"),
        ):
            supplier = session.exec(select(Supplier).where(Supplier.name == name)).first()
            if supplier is None:
                supplier = Supplier(name=name, email=email)
                session.add(supplier)
            suppliers.append(supplier)
        session.flush()
        data = [
            ("Ноутбук", 320000, 10, 0, 0),
            ("Мышь", 6500, 25, 0, 0),
            ("Футболка", 8500, 30, 1, 1),
            ("Ручка", 350, 100, 2, 2),
            ("Блокнот", 1200, 50, 2, 2),
        ]
        for name, price, quantity, category_index, supplier_index in data:
            category_id = categories[category_index].id
            supplier_id = suppliers[supplier_index].id
            item = session.exec(select(Item).where(
                Item.name == name,
                Item.category_id == category_id,
                Item.supplier_id == supplier_id,
            )).first()
            if item is None:
                item = Item(
                    name=name, price=price, quantity=quantity,
                    category_id=category_id, supplier_id=supplier_id,
                )
                session.add(item)
                session.flush()
                session.add(StockTransaction(
                    item_id=item.id, transaction_type="in", quantity=quantity,
                ))
        session.commit()
        print("Demo data ready: 3 categories, 3 suppliers and 5 items with initial transactions")

if __name__ == "__main__":
    seed()
