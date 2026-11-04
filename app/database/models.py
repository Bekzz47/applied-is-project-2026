from datetime import datetime, timezone
from typing import Optional
from sqlmodel import SQLModel, Field, Relationship

class Category(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True, unique=True)
    items: list["Item"] = Relationship(back_populates="category")

class Supplier(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    email: Optional[str] = None
    items: list["Item"] = Relationship(back_populates="supplier")

class Item(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    price: float = Field(ge=0)
    quantity: int = Field(default=0, ge=0)
    category_id: int = Field(foreign_key="category.id")
    supplier_id: int = Field(foreign_key="supplier.id")
    category: Optional[Category] = Relationship(back_populates="items")
    supplier: Optional[Supplier] = Relationship(back_populates="items")
    transactions: list["StockTransaction"] = Relationship(
        back_populates="item", cascade_delete=True
    )

class StockTransaction(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    item_id: int = Field(foreign_key="item.id")
    transaction_type: str
    quantity: int = Field(gt=0)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    item: Optional[Item] = Relationship(back_populates="transactions")
