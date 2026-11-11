from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.database.db import init_db
from app.routers.items import router as items_router


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Initialize database tables when the application starts."""
    init_db()
    yield


app = FastAPI(
    title="Warehouse Information System",
    lifespan=lifespan,
)
app.include_router(items_router)


@app.get("/", response_model=dict[str, str])
def root() -> dict[str, str]:
    """Return a simple status message to verify the API is running."""
    return {"status": "ok", "message": "Warehouse API is running"}
