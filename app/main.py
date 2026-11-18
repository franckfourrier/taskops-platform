from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import Base, engine, get_session
from app.models import Task
from app.schemas import TaskCreate, TaskRead

APP_VERSION = "0.1.0"


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    # Création des tables au démarrage (suffisant pour ce projet ;
    # une vraie prod utiliserait des migrations Alembic).
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title="TaskOps API", version=APP_VERSION, lifespan=lifespan)

SessionDep = Annotated[Session, Depends(get_session)]


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/tasks", response_model=list[TaskRead])
def list_tasks(session: SessionDep) -> list[Task]:
    return list(session.scalars(select(Task).order_by(Task.id)))


@app.post("/tasks", response_model=TaskRead, status_code=status.HTTP_201_CREATED)
def create_task(payload: TaskCreate, session: SessionDep) -> Task:
    task = Task(title=payload.title, done=payload.done)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task
