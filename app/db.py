"""Connexion à la base de données.

L'URL vient de la variable d'environnement DATABASE_URL :
- en local / Docker / Kubernetes : postgresql+psycopg://user:pass@host:5432/tasks
- par défaut (dev rapide sans Postgres) : SQLite
"""

import os
from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./tasks.db")

_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

# pool_pre_ping : vérifie la connexion avant usage -> reconnexion propre
# après un redémarrage ou une bascule de PostgreSQL (utile au projet 5).
engine = create_engine(DATABASE_URL, pool_pre_ping=True, connect_args=_connect_args)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_session() -> Generator[Session, None, None]:
    with SessionLocal() as session:
        yield session
