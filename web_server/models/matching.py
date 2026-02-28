from pydantic import BaseModel

from models.student import Identity, FocusArea, Project


class MatchScoreBreakdown(BaseModel):
    complementarity: float
    help_they_give_you: float
    help_you_give_them: float
    focus_overlap: float
    industry_overlap: float


class MatchResult(BaseModel):
    uid: str
    identity: Identity
    focus_areas: list[FocusArea]
    project: Project | None
    score: float
    breakdown: MatchScoreBreakdown
    matched_skills: list[str]
    skills_you_offer: list[str]


class WeightsUsed(BaseModel):
    complementarity: float
    focus: float
    industry: float


class MatchResponse(BaseModel):
    query_uid: str
    total_candidates: int
    matches: list[MatchResult]
    weights_used: WeightsUsed
