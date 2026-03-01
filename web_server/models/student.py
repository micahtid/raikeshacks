from datetime import datetime, timezone
from enum import Enum
from typing import Optional, Any
from uuid import uuid4

from pydantic import BaseModel, EmailStr

from db import get_db


# ── Enums ────────────────────────────────────────────────────────────────

class FocusArea(str, Enum):
    startup = "startup"
    research = "research"
    side_project = "side_project"
    open_source = "open_source"
    looking = "looking"


class ProjectStage(str, Enum):
    idea = "idea"
    mvp = "mvp"
    launched = "launched"
    scaling = "scaling"


class SkillSource(str, Enum):
    resume = "resume"
    portfolio = "portfolio"
    questionnaire = "questionnaire"


class SkillPriority(str, Enum):
    must_have = "must_have"
    nice_to_have = "nice_to_have"


# ── Nested models ────────────────────────────────────────────────────────

class Identity(BaseModel):
    full_name: str
    email: EmailStr
    profile_photo_url: Optional[str] = None
    university: str
    graduation_year: int
    major: list[str]
    minor: list[str] = []


class Project(BaseModel):
    one_liner: Optional[str] = None
    stage: Optional[ProjectStage] = None
    industry: list[str] = []


class PossessedSkill(BaseModel):
    name: str
    source: SkillSource


class NeededSkill(BaseModel):
    name: str
    priority: SkillPriority


class Skills(BaseModel):
    possessed: list[PossessedSkill] = []
    needed: list[NeededSkill] = []


class Rag(BaseModel):
    """Reference to this student's vector embeddings."""
    # Using Any to allow both list[float] (semantic) and list[str] (keyword fallback)
    possessed_vector: list[Any] = []
    needed_vector: list[Any] = []
    last_indexed_at: Optional[datetime] = None


# ── Request / response schemas ──────────────────────────────────────────

class StudentCreate(BaseModel):
    """Body of POST /students — everything the client sends at signup."""
    identity: Identity
    focus_areas: list[FocusArea]
    project: Optional[Project] = None
    skills: Skills


class StudentUpdate(BaseModel):
    """Body of PUT /students/{uid} — all fields optional for partial update."""
    identity: Optional[Identity] = None
    focus_areas: Optional[list[FocusArea]] = None
    project: Optional[Project] = None
    skills: Optional[Skills] = None


class StudentProfile(BaseModel):
    """Full document as stored in MongoDB."""
    uid: str
    created_at: datetime
    updated_at: Optional[datetime] = None
    identity: Identity
    focus_areas: list[FocusArea]
    project: Optional[Project] = None
    rag: Optional[Rag] = None
    skills: Skills


# ── CRUD ─────────────────────────────────────────────────────────────────

async def create_student(data: StudentCreate) -> StudentProfile:
    """Insert a new student profile, generate embeddings, and return the created document."""
    from services.similarity import generate_profile_embeddings
    
    db = get_db()
    now = datetime.now(timezone.utc)
    
    # Create the base doc
    doc = {
        "uid": str(uuid4()),
        "created_at": now.isoformat(),
        **data.model_dump(),
    }
    
    # Generate embeddings based on the initial data
    temp_profile = StudentProfile(**doc)
    doc["rag"] = generate_profile_embeddings(temp_profile)
    
    await db.student_profiles.insert_one(doc)
    doc.pop("_id", None)
    return StudentProfile(**doc)


async def get_student(uid: str) -> Optional[StudentProfile]:
    """Fetch a single student by uid. Returns None if not found."""
    db = get_db()
    doc = await db.student_profiles.find_one({"uid": uid}, {"_id": 0})
    if doc is None:
        return None
    return StudentProfile(**doc)


async def update_student(uid: str, data: StudentUpdate) -> Optional[StudentProfile]:
    """Update fields on an existing student and re-generate embeddings."""
    from services.similarity import generate_profile_embeddings

    db = get_db()

    changes = data.model_dump(exclude_none=True)
    if not changes:
        doc = await db.student_profiles.find_one({"uid": uid}, {"_id": 0})
        if doc is None:
            return None
        return StudentProfile(**doc)

    changes["updated_at"] = datetime.now(timezone.utc).isoformat()

    # Atomically apply only the changed fields
    result = await db.student_profiles.find_one_and_update(
        {"uid": uid},
        {"$set": changes},
        return_document=True,
    )
    if result is None:
        return None
    result.pop("_id", None)

    # Re-generate embeddings if relevant fields changed
    if "skills" in changes or "project" in changes:
        profile = StudentProfile(**result)
        rag = generate_profile_embeddings(profile)
        result = await db.student_profiles.find_one_and_update(
            {"uid": uid},
            {"$set": {"rag": rag}},
            return_document=True,
        )
        if result is None:
            return None
        result.pop("_id", None)

    return StudentProfile(**result)


async def delete_student(uid: str) -> bool:
    """Delete a student by uid. Returns True if a document was removed."""
    db = get_db()
    result = await db.student_profiles.delete_one({"uid": uid})
    return result.deleted_count > 0
