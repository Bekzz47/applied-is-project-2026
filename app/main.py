from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.database.db import init_db
from app.routers.items import router as items_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield

app = FastAPI(title="Warehouse Information System", lifespan=lifespan)
app.include_router(items_router)

@app.get("/")
def root():
    return {"status": "ok", "message": "Warehouse API is running"}
