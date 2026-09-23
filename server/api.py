"""Authenticated gameplay HTTP endpoints; identity is read from the session."""

import json
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, field_validator

from . import gameplay


class StartRun(BaseModel):
    model_config = ConfigDict(extra="forbid")
    level_id: int = Field(ge=1, le=7)


class Attempt(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question_id: UUID
    request_id: UUID
    response: dict
    elapsed_ms: int = Field(default=0, ge=0, le=86400000)

    @field_validator("response")
    @classmethod
    def bounded_response(cls, value: dict) -> dict:
        if len(json.dumps(value)) > 16000:
            raise ValueError("Answer is too large")
        return value


def router(authenticate, origin: str) -> APIRouter:
    def user(request: Request) -> str:
        if request.method == "POST":
            # A custom header cannot be sent by cross-origin forms. No CORS is enabled.
            if (request.headers.get("X-AA-Request") != "1"
                    or request.headers.get("origin", origin) != origin):
                raise HTTPException(403, "Submit answers from the game page.")
        return authenticate(request)

    routes = APIRouter(prefix="/api")

    @routes.get("/me")
    def me(onyen: str = Depends(user)) -> dict:
        return gameplay.me(onyen)

    @routes.get("/levels")
    def levels(onyen: str = Depends(user)) -> list[dict]:
        return gameplay.levels(onyen)

    @routes.post("/runs")
    def start(body: StartRun, onyen: str = Depends(user)) -> dict:
        return gameplay.start_run(onyen, body.level_id)

    @routes.post("/runs/{run_id}/attempts")
    def attempt(run_id: UUID, body: Attempt, onyen: str = Depends(user)) -> dict:
        return gameplay.attempt(onyen, run_id, **body.model_dump())

    @routes.post("/runs/{run_id}/finish")
    def finish(run_id: UUID, onyen: str = Depends(user)) -> dict:
        return gameplay.finish_run(onyen, run_id)

    return routes
