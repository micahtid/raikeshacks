import math
import logging
import os
import re
from datetime import datetime, timezone
from dataclasses import dataclass, field
from typing import Optional

import httpx

from db import get_db
from models.student import FocusArea, SkillPriority, StudentProfile

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── Helpers ──────────────────────────────────────────────────────────────

def _cosine_sim(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    mag_a = math.sqrt(sum(x * x for x in a))
    mag_b = math.sqrt(sum(x * x for x in b))
    if mag_a == 0.0 or mag_b == 0.0:
        return 0.0
    return dot / (mag_a * mag_b)

def _jaccard_sim(set_a: set, set_b: set) -> float:
    if not set_a or not set_b:
        return 0.0
    return len(set_a & set_b) / len(set_a | set_b)

# ── Embedding via OpenRouter ─────────────────────────────────────────────

EMBEDDING_MODEL = "openai/text-embedding-3-small"

async def _get_embedding(text: str) -> list[float]:
    """Get embedding vector from OpenRouter using openai/text-embedding-3-small."""
    api_key = os.getenv("OPENROUTER_API_KEY")
    if not api_key:
        logger.warning("OPENROUTER_API_KEY not set, cannot generate embeddings")
        return []

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                "https://openrouter.ai/api/v1/embeddings",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": EMBEDDING_MODEL,
                    "input": text or "none",
                },
            )
            resp.raise_for_status()
            return resp.json()["data"][0]["embedding"]
    except Exception as e:
        logger.warning(f"Embedding API error: {e}")
        return []

# ── Embedding Logic ─────────────────────────────────────────────────────

async def generate_profile_embeddings(profile: StudentProfile) -> dict:
    """Generate semantic embeddings via OpenRouter for a student."""
    possessed_items = [s.name for s in profile.skills.possessed]
    if profile.project and profile.project.one_liner:
        possessed_items.append(profile.project.one_liner)
    if profile.project and profile.project.industry:
        possessed_items.extend(profile.project.industry)
    possessed_text = ". ".join(possessed_items)

    needed_items = [s.name for s in profile.skills.needed]
    needed_text = ". ".join(needed_items)

    p_vec = await _get_embedding(possessed_text)
    n_vec = await _get_embedding(needed_text)

    return {
        "possessed_vector": p_vec,
        "needed_vector": n_vec,
        "last_indexed_at": datetime.now(timezone.utc).isoformat()
    }

# ── Profile vectorization ───────────────────────────────────────────────

FOCUS_AREA_ORDER = [e.value for e in FocusArea]

@dataclass
class ProfileVectors:
    possessed_vec: list = field(default_factory=list)
    needed_vec: list = field(default_factory=list)
    focus_vec: list[float] = field(default_factory=list)
    possessed_names: set[str] = field(default_factory=set)
    needed_names: set[str] = field(default_factory=set)

def vectorize_profile(profile: StudentProfile) -> ProfileVectors:
    pv = ProfileVectors()
    if profile.rag:
        pv.possessed_vec = profile.rag.possessed_vector or []
        pv.needed_vec = profile.rag.needed_vector or []

    focus_set = {fa.value for fa in profile.focus_areas}
    pv.focus_vec = [1.0 if fa in focus_set else 0.0 for fa in FOCUS_AREA_ORDER]

    pv.possessed_names = {s.name.strip().lower() for s in profile.skills.possessed}
    pv.needed_names = {s.name.strip().lower() for s in profile.skills.needed}
    return pv

# ── Scoring ──────────────────────────────────────────────────────────────

@dataclass
class MatchScore:
    score: float
    complementarity: float
    help_they_give_you: float
    help_you_give_them: float
    focus_overlap: float
    industry_overlap: float
    matched_skills: list[str]
    skills_you_offer: list[str]

@dataclass
class Weights:
    complementarity: float = 0.65
    focus: float = 0.20
    industry: float = 0.15

def compute_match(
    query_profile: StudentProfile,
    query_vecs: ProfileVectors,
    cand_profile: StudentProfile,
    cand_vecs: ProfileVectors,
    weights: Weights,
) -> MatchScore:
    # 1. Complementarity
    use_semantic = (
        len(query_vecs.possessed_vec) > 0
        and len(cand_vecs.possessed_vec) > 0
        and isinstance(query_vecs.possessed_vec[0], (int, float))
        and isinstance(cand_vecs.possessed_vec[0], (int, float))
    )
    if use_semantic:
        help_they_give_you = _cosine_sim(query_vecs.needed_vec, cand_vecs.possessed_vec)
        help_you_give_them = _cosine_sim(cand_vecs.needed_vec, query_vecs.possessed_vec)
    else:
        # Fallback Keyword Match (Jaccard)
        q_need = set(query_vecs.needed_vec)
        c_have = set(cand_vecs.possessed_vec)
        help_they_give_you = _jaccard_sim(q_need, c_have)

        c_need = set(cand_vecs.needed_vec)
        q_have = set(query_vecs.possessed_vec)
        help_you_give_them = _jaccard_sim(c_need, q_have)

    complementarity = 0.5 * help_they_give_you + 0.5 * help_you_give_them

    # 2. Focus Overlap
    focus_overlap = _cosine_sim(query_vecs.focus_vec, cand_vecs.focus_vec)

    # 3. Industry Overlap
    q_inds = set(query_profile.project.industry or []) if query_profile.project else set()
    c_inds = set(cand_profile.project.industry or []) if cand_profile.project else set()
    industry_overlap = _jaccard_sim(q_inds, c_inds)

    score = (
        weights.complementarity * complementarity
        + weights.focus * focus_overlap
        + weights.industry * industry_overlap
    )

    matched_skills = sorted(query_vecs.needed_names & cand_vecs.possessed_names)
    skills_you_offer = sorted(cand_vecs.needed_names & query_vecs.possessed_names)

    return MatchScore(
        score=score,
        complementarity=complementarity,
        help_they_give_you=help_they_give_you,
        help_you_give_them=help_you_give_them,
        focus_overlap=focus_overlap,
        industry_overlap=industry_overlap,
        matched_skills=matched_skills,
        skills_you_offer=skills_you_offer,
    )

# ── Main Entry ──────────────────────────────────────────────────────────

async def find_matches(
    query_uid: str,
    limit: int,
    threshold: float,
    weights: Weights,
) -> tuple[Optional[StudentProfile], int, list[tuple[StudentProfile, MatchScore]]]:
    db = get_db()
    cursor = db.student_profiles.find({}, {"_id": 0})
    docs = await cursor.to_list(length=None)
    profiles = [StudentProfile(**doc) for doc in docs]

    query_profile = next((p for p in profiles if p.uid == query_uid), None)
    if not query_profile:
        return None, 0, []

    candidates = [p for p in profiles if p.uid != query_uid]
    query_vecs = vectorize_profile(query_profile)

    results = []
    for cand in candidates:
        cand_vecs = vectorize_profile(cand)
        ms = compute_match(query_profile, query_vecs, cand, cand_vecs, weights)
        if ms.score >= threshold:
            results.append((cand, ms))

    results.sort(key=lambda x: x[1].score, reverse=True)
    return query_profile, len(candidates), results[:limit]
