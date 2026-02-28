import math
from datetime import datetime, timezone
from dataclasses import dataclass, field
from typing import Optional

from sentence_transformers import SentenceTransformer

from db import get_db
from models.student import FocusArea, SkillPriority, StudentProfile

# Initialize the embedding model (this will download on first run)
# 'all-MiniLM-L6-v2' is small, fast, and effective for hackathons.
model = SentenceTransformer('all-MiniLM-L6-v2')

# ── Helpers ──────────────────────────────────────────────────────────────

def _cosine_sim(a: list[float], b: list[float]) -> float:
    if not a or not b:
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    mag_a = math.sqrt(sum(x * x for x in a))
    mag_b = math.sqrt(sum(x * x for x in b))
    if mag_a == 0.0 or mag_b == 0.0:
        return 0.0
    return dot / (mag_a * mag_b)

# ── Embedding Logic ─────────────────────────────────────────────────────

def generate_profile_embeddings(profile: StudentProfile) -> dict:
    """Generate semantic embeddings for a student's skills and projects."""
    # What they have: possessed skills + project description
    possessed_items = [s.name for s in profile.skills.possessed]
    if profile.project and profile.project.one_liner:
        possessed_items.append(profile.project.one_liner)
    if profile.project and profile.project.industry:
        possessed_items.extend(profile.project.industry)
    
    possessed_text = ". ".join(possessed_items)
    
    # What they need: needed skills
    needed_items = [s.name for s in profile.skills.needed]
    needed_text = ". ".join(needed_items)
    
    # Handle empty strings to avoid model errors
    p_embedding = model.encode(possessed_text or "none").tolist()
    n_embedding = model.encode(needed_text or "none").tolist()
    
    return {
        "possessed_vector": p_embedding,
        "needed_vector": n_embedding,
        "last_indexed_at": datetime.now(timezone.utc).isoformat()
    }

# ── Profile vectorization ───────────────────────────────────────────────

FOCUS_AREA_ORDER = [e.value for e in FocusArea]

@dataclass
class ProfileVectors:
    possessed_vec: list[float] = field(default_factory=list)
    needed_vec: list[float] = field(default_factory=list)
    focus_vec: list[float] = field(default_factory=list)
    industry_vec: list[float] = field(default_factory=list)
    # Keep raw sets for concrete skill matching highlights
    possessed_names: set[str] = field(default_factory=set)
    needed_names: set[str] = field(default_factory=set)

def vectorize_profile(profile: StudentProfile) -> ProfileVectors:
    """Convert a student profile into vectors for comparison.
    Uses pre-computed embeddings for skills and manual vectors for categorical data.
    """
    pv = ProfileVectors()

    # Get embeddings from the 'rag' field if they exist
    if profile.rag:
        pv.possessed_vec = profile.rag.get("possessed_vector", [])
        pv.needed_vec = profile.rag.get("needed_vector", [])

    # Focus areas — binary over the 5-value enum
    focus_set = {fa.value for fa in profile.focus_areas}
    pv.focus_vec = [1.0 if fa in focus_set else 0.0 for fa in FOCUS_AREA_ORDER]

    # Industries — binary vector for industry overlap
    # We'll use a simple set-based approach for industry_overlap in compute_match 
    # instead of a fixed vocab vector to keep it dynamic and simple.
    
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
    candidate_profile: StudentProfile,
    candidate_vecs: ProfileVectors,
    weights: Weights,
) -> MatchScore:
    # 1. Complementarity (Skill Matching) via Embeddings
    # How well their skills (possessed) match what you need
    help_they_give_you = _cosine_sim(query_vecs.needed_vec, candidate_vecs.possessed_vec)
    # How well your skills match what they need
    help_you_give_them = _cosine_sim(candidate_vecs.needed_vec, query_vecs.possessed_vec)
    
    complementarity = 0.5 * help_they_give_you + 0.5 * help_you_give_them

    # 2. Focus Overlap (Categorical)
    focus_overlap = _cosine_sim(query_vecs.focus_vec, candidate_vecs.focus_vec)

    # 3. Industry Overlap (Keyword-based for accuracy)
    q_inds = set(query_profile.project.industry) if query_profile.project else set()
    c_inds = set(candidate_profile.project.industry) if candidate_profile.project else set()
    industry_overlap = 0.0
    if q_inds and c_inds:
        intersection = q_inds & c_inds
        union = q_inds | c_inds
        industry_overlap = len(intersection) / len(union)

    # Weighted Final Score
    score = (
        weights.complementarity * complementarity
        + weights.focus * focus_overlap
        + weights.industry * industry_overlap
    )

    # Concrete highlights for the UI
    matched_skills = sorted(query_vecs.needed_names & candidate_vecs.possessed_names)
    skills_you_offer = sorted(candidate_vecs.needed_names & query_vecs.possessed_names)

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

# ── Main entry point ────────────────────────────────────────────────────

async def find_matches(
    query_uid: str,
    limit: int,
    threshold: float,
    weights: Weights,
) -> tuple[Optional[StudentProfile], int, list[tuple[StudentProfile, MatchScore]]]:
    """Return (query_profile, total_candidates, ranked_matches)."""
    db = get_db()
    
    # Fetch all students (simple for hackathon, at scale use Vector Search)
    cursor = db.student_profiles.find({}, {"_id": 0})
    docs = await cursor.to_list(length=None)
    profiles = [StudentProfile(**doc) for doc in docs]

    # Find the query student
    query_profile: Optional[StudentProfile] = None
    candidates: list[StudentProfile] = []
    for p in profiles:
        if p.uid == query_uid:
            query_profile = p
        else:
            candidates.append(p)

    if query_profile is None:
        return None, 0, []

    query_vecs = vectorize_profile(query_profile)

    # Score every candidate
    results: list[tuple[StudentProfile, MatchScore]] = []
    for cand in candidates:
        cand_vecs = vectorize_profile(cand)
        ms = compute_match(query_profile, query_vecs, cand, cand_vecs, weights)
        if ms.score >= threshold:
            results.append((cand, ms))

    # Sort descending by score
    results.sort(key=lambda pair: pair[1].score, reverse=True)

    return query_profile, len(candidates), results[:limit]
