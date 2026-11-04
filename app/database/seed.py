from sqlmodel import Session, select
from app.database.db import engine, init_db
from app.database.models import Category, Supplier, Item, StockTransaction

def seed():
    init_db()
    with Session(engine) as session:
        if session.exec(select(Category)).first():
            print("Database already seeded")
            return
        categories = [Category(name=n) for n in ("Электроника", "Одежда", "Канцелярия")]
        suppliers = [Supplier(name=n, email=e) for n, e in (
            ("Tech Supply", "tech@example.com"),
            ("Fashion Trade", "fashion@example.com"),
            ("Office Goods", "office@example.com"),
        )]
        session.add_all(categories + suppliers)
        session.flush()
        data = [
            ("Ноутбук", 320000, 10, 0, 0),
            ("Мышь", 6500, 25, 0, 0),
            ("Футболка", 8500, 30, 1, 1),
            ("Ручка", 350, 100, 2, 2),
            ("Блокнот", 1200, 50, 2, 2),
        ]
        items = [Item(name=n, price=p, quantity=q, category_id=categories[c].id, supplier_id=suppliers[s].id) for n, p, q, c, s in data]
        session.add_all(items)
        session.flush()
        session.add_all([StockTransaction(item_id=i.id, transaction_type="in", quantity=i.quantity) for i in items])
        session.commit()
        print("Seeded 3 categories, 3 suppliers, 5 items and 5 transactions")

if __name__ == "__main__":
    seed()
