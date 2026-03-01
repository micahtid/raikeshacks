from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel
from pymongo.errors import DuplicateKeyError

from db import get_db


# ── Helpers ─────────────────────────────────────────────────────────────


def make_connection_id(uid_a: str, uid_b: str) -> str:
    """Deterministic connection ID from two user UIDs — sorted alphabetically."""
    a, b = sorted([uid_a, uid_b])
    return f"{a}_{b}"


# ── Request / response schemas ──────────────────────────────────────────


class Connection(BaseModel):
    """Full connection document as stored in MongoDB."""
    connection_id: str
    uid1: str
    uid2: str
    uid1_accepted: bool = False
    uid2_accepted: bool = False
    match_percentage: float
    uid1_summary: Optional[str] = None
    uid2_summary: Optional[str] = None
    notification_message: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None
    last_nearby_notified_at: Optional[datetime] = None


class ConnectionCreate(BaseModel):
    """Body of POST /connections."""
    uid1: str
    uid2: str


class ConnectionAccept(BaseModel):
    """Body of POST /connections/{connection_id}/accept."""
    uid: str


class ConnectionList(BaseModel):
    """List of connections."""
    connections: list[Connection]


# ── CRUD ────────────────────────────────────────────────────────────────


async def get_connection(connection_id: str) -> Optional[Connection]:
    """Fetch a single connection by its ID."""
    db = get_db()
    doc = await db.connections.find_one({"connection_id": connection_id}, {"_id": 0})
    if doc is None:
        return None
    return Connection(**doc)


async def get_connections_for_user(uid: str) -> list[Connection]:
    """Fetch all connections involving a user."""
    db = get_db()
    cursor = db.connections.find(
        {"$or": [{"uid1": uid}, {"uid2": uid}]},
        {"_id": 0},
    ).sort("created_at", -1)
    docs = await cursor.to_list(length=200)
    return [Connection(**doc) for doc in docs]


async def get_accepted_connections_for_user(uid: str) -> list[Connection]:
    """Fetch only mutually accepted connections for a user."""
    db = get_db()
    cursor = db.connections.find(
        {
            "$or": [{"uid1": uid}, {"uid2": uid}],
            "uid1_accepted": True,
            "uid2_accepted": True,
        },
        {"_id": 0},
    ).sort("created_at", -1)
    docs = await cursor.to_list(length=200)
    return [Connection(**doc) for doc in docs]


async def upsert_connection(doc: dict) -> Connection:
    """Insert a connection, returning existing if duplicate (race-condition safe)."""
    db = get_db()
    try:
        await db.connections.insert_one(doc)
        doc.pop("_id", None)
        return Connection(**doc)
    except DuplicateKeyError:
        existing = await db.connections.find_one(
            {"connection_id": doc["connection_id"]}, {"_id": 0}
        )
        return Connection(**existing)


async def accept_connection(connection_id: str, uid: str) -> Optional[Connection]:
    """Set the appropriate uidX_accepted flag to True."""
    db = get_db()
    conn = await db.connections.find_one({"connection_id": connection_id}, {"_id": 0})
    if conn is None:
        return None

    now = datetime.now(timezone.utc).isoformat()
    if uid == conn["uid1"]:
        field = "uid1_accepted"
    elif uid == conn["uid2"]:
        field = "uid2_accepted"
    else:
        return None

    result = await db.connections.find_one_and_update(
        {"connection_id": connection_id},
        {"$set": {field: True, "updated_at": now}},
        return_document=True,
    )
    if result is None:
        return None
    result.pop("_id", None)
    return Connection(**result)


async def update_nearby_notified_at(connection_id: str) -> None:
    """Set last_nearby_notified_at to now."""
    db = get_db()
    now = datetime.now(timezone.utc).isoformat()
    await db.connections.update_one(
        {"connection_id": connection_id},
        {"$set": {"last_nearby_notified_at": now}},
    )


async def update_connection_summaries(
    connection_id: str,
    uid1_summary: Optional[str],
    uid2_summary: Optional[str],
    notification_message: Optional[str],
) -> Optional[Connection]:
    """Set summary fields after Gemini call."""
    db = get_db()
    now = datetime.now(timezone.utc).isoformat()
    result = await db.connections.find_one_and_update(
        {"connection_id": connection_id},
        {
            "$set": {
                "uid1_summary": uid1_summary,
                "uid2_summary": uid2_summary,
                "notification_message": notification_message,
                "updated_at": now,
            }
        },
        return_document=True,
    )
    if result is None:
        return None
    result.pop("_id", None)
    return Connection(**result)
