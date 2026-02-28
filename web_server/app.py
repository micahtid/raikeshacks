from contextlib import asynccontextmanager
from dotenv import load_dotenv

from fastapi import FastAPI, HTTPException, Query

load_dotenv()

from db import connect_db, close_db
from models.student import (
    StudentCreate,
    StudentProfile,
    StudentUpdate,
    create_student,
    get_student,
    update_student,
    delete_student,
)
from models.matching import (
    MatchResponse,
    MatchResult,
    MatchScoreBreakdown,
    WeightsUsed,
)
from services.similarity import find_matches, Weights


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect_db()
    yield
    await close_db()


app = FastAPI(title="RaikeShacks API", lifespan=lifespan)


@app.post("/students", response_model=StudentProfile, status_code=201)
async def add_student(body: StudentCreate):
    return await create_student(body)


@app.get("/students/{uid}", response_model=StudentProfile)
async def read_student(uid: str):
    student = await get_student(uid)
    if student is None:
        raise HTTPException(status_code=404, detail="Student not found")
    return student


@app.put("/students/{uid}", response_model=StudentProfile)
async def edit_student(uid: str, body: StudentUpdate):
    student = await update_student(uid, body)
    if student is None:
        raise HTTPException(status_code=404, detail="Student not found")
    return student


@app.delete("/students/{uid}", status_code=204)
async def remove_student(uid: str):
    deleted = await delete_student(uid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Student not found")


@app.get("/students/{uid}/matches", response_model=MatchResponse)
async def match_student(
    uid: str,
    limit: int = Query(10, ge=1, le=50),
    threshold: float = Query(0.0, ge=0.0, le=1.0),
    w_complementarity: float = Query(0.65, ge=0.0),
    w_focus: float = Query(0.20, ge=0.0),
    w_industry: float = Query(0.15, ge=0.0),
):
    total_weight = w_complementarity + w_focus + w_industry
    if total_weight == 0.0:
        raise HTTPException(status_code=400, detail="All weights cannot be zero")

    # Normalize weights to sum to 1.0
    weights = Weights(
        complementarity=w_complementarity / total_weight,
        focus=w_focus / total_weight,
        industry=w_industry / total_weight,
    )

    query_profile, total_candidates, ranked = await find_matches(
        uid, limit, threshold, weights
    )

    if query_profile is None:
        raise HTTPException(status_code=404, detail="Student not found")

    matches = [
        MatchResult(
            uid=cand.uid,
            identity=cand.identity,
            focus_areas=cand.focus_areas,
            project=cand.project,
            score=round(ms.score, 4),
            breakdown=MatchScoreBreakdown(
                complementarity=round(ms.complementarity, 4),
                help_they_give_you=round(ms.help_they_give_you, 4),
                help_you_give_them=round(ms.help_you_give_them, 4),
                focus_overlap=round(ms.focus_overlap, 4),
                industry_overlap=round(ms.industry_overlap, 4),
            ),
            matched_skills=ms.matched_skills,
            skills_you_offer=ms.skills_you_offer,
        )
        for cand, ms in ranked
    ]

    return MatchResponse(
        query_uid=uid,
        total_candidates=total_candidates,
        matches=matches,
        weights_used=WeightsUsed(
            complementarity=round(weights.complementarity, 4),
            focus=round(weights.focus, 4),
            industry=round(weights.industry, 4),
        ),
    )
