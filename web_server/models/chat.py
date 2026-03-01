from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel

from db import get_db


# ── Request / response schemas ──────────────────────────────────────────


class RoomCreate(BaseModel):
    """Body of POST /chat/rooms — two participant UIDs."""
    participant_uids: list[str]


class Message(BaseModel):
    """A single chat message."""
    sender_uid: str
    content: str
    timestamp: datetime


class Room(BaseModel):
    """A chat room between two users."""
    room_id: str
    participants: list[str]
    created_at: datetime
    updated_at: Optional[datetime] = None


class MessageCreate(BaseModel):
    """Body of POST /chat/rooms/{room_id}/messages."""
    sender_uid: str
    content: str


class MessageList(BaseModel):
    """Paginated message list response."""
    room_id: str
    messages: list[Message]
    total: int


class RoomList(BaseModel):
    """List of rooms for a user."""
    rooms: list[Room]


# ── Helpers ─────────────────────────────────────────────────────────────


def make_room_id(uid_a: str, uid_b: str) -> str:
    """Deterministic room ID from two user UIDs — sorted alphabetically."""
    a, b = sorted([uid_a, uid_b])
    return f"{a}_{b}"


# ── CRUD ────────────────────────────────────────────────────────────────


async def get_or_create_room(data: RoomCreate) -> Room:
    """Find an existing room or create a new one for the two participants."""
    if len(data.participant_uids) != 2:
        raise ValueError("Exactly two participant UIDs are required")

    uid_a, uid_b = data.participant_uids
    room_id = make_room_id(uid_a, uid_b)
    db = get_db()

    existing = await db.chat_rooms.find_one({"room_id": room_id}, {"_id": 0})
    if existing:
        return Room(**existing)

    now = datetime.now(timezone.utc)
    doc = {
        "room_id": room_id,
        "participants": sorted([uid_a, uid_b]),
        "created_at": now.isoformat(),
    }
    await db.chat_rooms.insert_one(doc)
    doc.pop("_id", None)
    return Room(**doc)


async def get_room(room_id: str) -> Optional[Room]:
    """Fetch a room by its ID."""
    db = get_db()
    doc = await db.chat_rooms.find_one({"room_id": room_id}, {"_id": 0})
    if doc is None:
        return None
    return Room(**doc)


async def get_rooms_for_user(uid: str) -> list[Room]:
    """List all rooms a user is part of, most recently active first."""
    db = get_db()
    cursor = db.chat_rooms.find(
        {"participants": uid},
        {"_id": 0},
    ).sort("updated_at", -1)
    docs = await cursor.to_list(length=100)
    return [Room(**doc) for doc in docs]


async def create_message(room_id: str, data: MessageCreate) -> Message:
    """Add a message to a room. Updates the room's updated_at timestamp."""
    db = get_db()

    # Verify room exists
    room = await db.chat_rooms.find_one({"room_id": room_id})
    if room is None:
        raise ValueError("Room not found")

    now = datetime.now(timezone.utc)
    msg_doc = {
        "room_id": room_id,
        "sender_uid": data.sender_uid,
        "content": data.content,
        "timestamp": now.isoformat(),
    }
    await db.chat_messages.insert_one(msg_doc)

    # Update room's last activity
    await db.chat_rooms.update_one(
        {"room_id": room_id},
        {"$set": {"updated_at": now.isoformat()}},
    )

    return Message(
        sender_uid=data.sender_uid,
        content=data.content,
        timestamp=now,
    )


async def get_messages(
    room_id: str,
    limit: int = 50,
    before: Optional[datetime] = None,
) -> tuple[list[Message], int]:
    """Fetch messages in a room, newest first. Supports cursor-based pagination."""
    db = get_db()

    query: dict = {"room_id": room_id}
    if before:
        query["timestamp"] = {"$lt": before.isoformat()}

    total = await db.chat_messages.count_documents({"room_id": room_id})

    cursor = db.chat_messages.find(query, {"_id": 0, "room_id": 0}).sort(
        "timestamp", -1
    )
    docs = await cursor.to_list(length=limit)

    messages = [Message(**doc) for doc in reversed(docs)]  # chronological order
    return messages, total
