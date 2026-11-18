import os

import pytest

# Sans DATABASE_URL (dev local), on teste sur un SQLite jetable.
# En CI, DATABASE_URL pointe vers un vrai conteneur PostgreSQL.
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_tasks.db")

from fastapi.testclient import TestClient  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture
def client():
    Base.metadata.drop_all(bind=engine)
    with TestClient(app) as c:  # déclenche le lifespan -> create_all
        yield c
    Base.metadata.drop_all(bind=engine)
