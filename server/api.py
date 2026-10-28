"""Authenticated gameplay HTTP endpoints; identity is read from the session."""

import json
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field, StrictBool, field_validator

from . import gameplay, reporting


class StartRun(BaseModel):
    model_config = ConfigDict(extra="forbid")
    level_id: int = Field(ge=1, le=7)
    telemetry_version: int = Field(default=0, ge=0, le=1, strict=True)


class Preferences(BaseModel):
    model_config = ConfigDict(extra="forbid")
    leaderboard_visible: StrictBool


class LearningEvent(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question_id: UUID
    request_id: UUID
    kind: Literal["hint", "walk_choice"]
    moment: int | None = Field(default=None, ge=0, strict=True)
    choice: int | None = Field(default=None, ge=0, strict=True)


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

    def staff(onyen: str = Depends(user)) -> str:
        reporting.require_staff(onyen)
        return onyen

    @routes.get("/me")
    def me(onyen: str = Depends(user)) -> dict:
        return gameplay.me(onyen)

    @routes.get("/levels")
    def levels(onyen: str = Depends(user)) -> list[dict]:
        return gameplay.levels(onyen)

    @routes.post("/preferences")
    def preferences(body: Preferences, onyen: str = Depends(user)) -> dict:
        return reporting.preferences(onyen, body.leaderboard_visible)

    @routes.get("/leaderboard")
    def leaderboard(level_id: int = Query(ge=1, le=7), week_offset: int = Query(default=0, ge=-104, le=0),
                    onyen: str = Depends(user)) -> dict:
        return reporting.leaderboard(onyen, level_id, week_offset)

    @routes.get("/admin/overview")
    def overview(onyen: str = Depends(staff)) -> dict:
        return reporting.overview(onyen)

    @routes.get("/admin/levels/{level_id}")
    def level_detail(level_id: int, onyen: str = Depends(staff)) -> dict:
        return reporting.level_detail(onyen, level_id)

    @routes.get("/admin/questions/{question_id}")
    def question_detail(question_id: UUID, onyen: str = Depends(staff)) -> dict:
        return reporting.question_detail(onyen, question_id)

    @routes.get("/admin/students")
    def students(q: str = Query(default="", max_length=128), limit: int = Query(default=100, ge=1, le=200),
                 offset: int = Query(default=0, ge=0), onyen: str = Depends(staff)) -> dict:
        return reporting.students(onyen, q, limit, offset)

    @routes.get("/admin/students/{student_id}")
    def student_detail(student_id: UUID, onyen: str = Depends(staff)) -> dict:
        return reporting.student_detail(onyen, student_id)

    @routes.post("/runs")
    def start(body: StartRun, onyen: str = Depends(user)) -> dict:
        return gameplay.start_run(onyen, body.level_id, body.telemetry_version)

    @routes.post("/runs/{run_id}/events")
    def event(run_id: UUID, body: LearningEvent, onyen: str = Depends(user)) -> dict:
        return gameplay.learning_event(onyen, run_id, **body.model_dump())

    @routes.post("/runs/{run_id}/attempts")
    def attempt(run_id: UUID, body: Attempt, onyen: str = Depends(user)) -> dict:
        return gameplay.attempt(onyen, run_id, **body.model_dump())

    @routes.post("/runs/{run_id}/finish")
    def finish(run_id: UUID, onyen: str = Depends(user)) -> dict:
        return gameplay.finish_run(onyen, run_id)

    return routes
