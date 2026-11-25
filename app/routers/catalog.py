from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlmodel import Session, select

from app.database.db import get_session
from app.database.models import Category, Supplier
from app.security import get_role

router = APIRouter()


class Reference(BaseModel):
    id: int
    name: str


class CatalogReferences(BaseModel):
    categories: list[Reference]
    suppliers: list[Reference]


@router.get("/auth/me", tags=["Authentication"])
def identity(role: Annotated[str, Depends(get_role)]) -> dict[str, str]:
    return {"username": role}


@router.get("/catalog/references", tags=["Items"], response_model=CatalogReferences)
def references(session: Annotated[Session, Depends(get_session)]):
    return {
        "categories": session.exec(select(Category).order_by(Category.name, Category.id)).all(),
        "suppliers": session.exec(select(Supplier).order_by(Supplier.name, Supplier.id)).all(),
    }
