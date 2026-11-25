from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.database.db import init_db
from app.routers.catalog import router as catalog_router
from app.routers.items import router as items_router
from app.routers.stock import router as stock_router


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Initialize database tables when the application starts."""
    init_db()
    yield


app = FastAPI(
    title="Warehouse Information System",
    lifespan=lifespan,
)
app.include_router(catalog_router)
app.include_router(items_router)
app.include_router(stock_router)


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, error: RequestValidationError):
    if any(issue["type"] == "json_invalid" for issue in error.errors()):
        return JSONResponse(status_code=400, content={"detail": "Malformed JSON"})
    return await request_validation_exception_handler(request, error)


@app.get("/", response_model=dict[str, str])
def root() -> dict[str, str]:
    """Return a simple status message to verify the API is running."""
    return {"status": "ok", "message": "Warehouse API is running"}


# Serve a locally built Flutter web client from the same origin as the API.
mobile_web = Path(__file__).resolve().parents[1] / "mobile" / "build" / "web"
if (mobile_web / "index.html").is_file():
    app.mount("/mobile", StaticFiles(directory=mobile_web, html=True), name="mobile")
