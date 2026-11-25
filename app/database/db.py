from pathlib import Path
from sqlalchemy import event
from sqlalchemy.pool import NullPool
from sqlmodel import SQLModel, Session, create_engine
from app.database import models  # register models

DB_PATH = Path(__file__).resolve().parents[2] / "database.db"
# A file-backed SQLite connection is inexpensive. Opening it per session also
# avoids making request workers wait for a small shared connection pool.
engine = create_engine(
    f"sqlite:///{DB_PATH}",
    poolclass=NullPool,
    hide_parameters=True,
    connect_args={"check_same_thread": False},
)


@event.listens_for(engine, "connect")
def enable_foreign_keys(connection, connection_record):
    cursor = connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


def init_db():
    SQLModel.metadata.create_all(engine)

def get_session():
    with Session(engine) as session:
        yield session
