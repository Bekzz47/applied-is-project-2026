from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session, SQLModel, Field, select
from app.database.db import get_session
from app.database.models import Item

router = APIRouter(prefix="/items", tags=["Items"])
SessionDep = Annotated[Session, Depends(get_session)]

class ItemCreate(SQLModel):
    name: str = Field(min_length=1)
    price: float = Field(ge=0)
    quantity: int = Field(default=0, ge=0)
    category_id: int
    supplier_id: int

class ItemUpdate(SQLModel):
    name: str | None = Field(default=None, min_length=1)
    price: float | None = Field(default=None, ge=0)
    quantity: int | None = Field(default=None, ge=0)
    category_id: int | None = None
    supplier_id: int | None = None

@router.get("", response_model=list[Item])
def list_items(session: SessionDep, search: str | None = None, min_price: float | None = Query(default=None, ge=0), max_price: float | None = Query(default=None, ge=0)):
    if min_price is not None and max_price is not None and min_price > max_price:
        raise HTTPException(status_code=422, detail="min_price must be <= max_price")
    statement = select(Item)
    if search:
        statement = statement.where(Item.name.contains(search))
    if min_price is not None:
        statement = statement.where(Item.price >= min_price)
    if max_price is not None:
        statement = statement.where(Item.price <= max_price)
    return session.exec(statement).all()

@router.get("/{item_id}", response_model=Item)
def get_item(item_id: int, session: SessionDep):
    item = session.get(Item, item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    return item

@router.post("", response_model=Item, status_code=status.HTTP_201_CREATED)
def create_item(data: ItemCreate, session: SessionDep):
    item = Item.model_validate(data)
    session.add(item)
    try:
        session.commit()
        session.refresh(item)
    except Exception:
        session.rollback()
        raise HTTPException(status_code=422, detail="Invalid category or supplier")
    return item

@router.patch("/{item_id}", response_model=Item)
def update_item(item_id: int, data: ItemUpdate, session: SessionDep):
    item = session.get(Item, item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    changes = data.model_dump(exclude_unset=True)
    if any(value is None for value in changes.values()):
        raise HTTPException(status_code=422, detail="Fields cannot be null")
    item.sqlmodel_update(changes)
    session.add(item)
    try:
        session.commit()
        session.refresh(item)
    except Exception:
        session.rollback()
        raise HTTPException(status_code=422, detail="Invalid category or supplier")
    return item

@router.delete("/{item_id}")
def delete_item(item_id: int, session: SessionDep):
    item = session.get(Item, item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    if item.transactions:
        raise HTTPException(status_code=409, detail="Item has stock transactions")
    session.delete(item)
    session.commit()
    return {"message": "Item deleted"}
