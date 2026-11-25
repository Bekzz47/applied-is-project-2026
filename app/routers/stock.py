from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import update
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.database.db import get_session
from app.database.models import Item, StockTransaction
from app.security import get_role, require_admin

router = APIRouter(prefix="/stock/movements", tags=["Stock movements"])
SessionDep = Annotated[Session, Depends(get_session)]


class MovementCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    item_id: int = Field(gt=0, le=2**63 - 1)
    transaction_type: Literal["in", "out"]
    quantity: int = Field(gt=0, le=2**63 - 1)


@router.get("", response_model=list[StockTransaction], dependencies=[Depends(get_role)])
def list_movements(session: SessionDep):
    return session.exec(select(StockTransaction).order_by(StockTransaction.id)).all()


@router.post("", response_model=StockTransaction, status_code=201, dependencies=[Depends(require_admin)])
def record_movement(data: MovementCreate, session: SessionDep):
    # One guarded UPDATE serializes competing withdrawals without a stale balance read.
    statement = update(Item).where(Item.id == data.item_id)
    if data.transaction_type == "out":
        statement = statement.where(Item.quantity >= data.quantity)
        delta = -data.quantity
    else:
        statement = statement.where(Item.quantity <= 2**63 - 1 - data.quantity)
        delta = data.quantity

    try:
        with session.begin():
            updated = session.execute(statement.values(quantity=Item.quantity + delta))
            if updated.rowcount != 1:
                if session.get(Item, data.item_id) is None:
                    raise HTTPException(status_code=404, detail="Item not found")
                raise HTTPException(status_code=409, detail="Stock balance out of range")
            movement = StockTransaction(**data.model_dump())
            session.add(movement)
            session.flush()
    except IntegrityError:
        raise HTTPException(status_code=409, detail="Movement could not be recorded") from None
    session.refresh(movement)
    return movement
