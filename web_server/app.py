from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Optional

from dotenv import load_dotenv

from fastapi import FastAPI, File, HTTPException, Query, UploadFile, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

load_dotenv()

from db import connect_db, close_db, get_db
from models.student import (
    StudentCreate,
    StudentProfile,
    StudentUpdate,
    create_student,
    get_student,
    get_student_by_email,
    update_student,
    delete_student,
)
from models.matching import (
    MatchResponse,
    MatchResult,
    MatchScoreBreakdown,
    WeightsUsed,
)
from models.chat import (
    Room,
    RoomCreate,
    RoomList,
    Message,
    MessageCreate,
    MessageList,
    get_or_create_room,
    get_room,
    get_rooms_for_user,
    create_message,
    get_messages,
)
from models.connection import (
    Connection,
    ConnectionCreate,
    ConnectionAccept,
    ConnectionList,
    make_connection_id,
    get_connection,
    get_connections_for_user,
    get_accepted_connections_for_user,
    upsert_connection,
    accept_connection,
    update_connection_summaries,
    update_nearby_notified_at,
)
from services.resume_parser import parse_resume, ParsedResume
from services.similarity import find_matches, Weights, vectorize_profile, compute_match
from services.summary_generator import generate_connection_summaries
from services.push_notification import send_push_notification
from services.websocket_manager import ConnectionManager


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect_db()
    yield
    await close_db()


app = FastAPI(title="RaikeShacks API", lifespan=lifespan)
ws_manager = ConnectionManager()


# ── Resume endpoint ────────────────────────────────────────────────────


@app.post("/parse-resume", response_model=ParsedResume)
async def parse_resume_endpoint(file: UploadFile = File(...)):
    data = await file.read()
    result = await parse_resume(data, file.filename or "resume.pdf")

    # Persist the parsed resume so it can be referenced later
    db = get_db()
    doc = {
        "filename": file.filename,
        "parsed_at": datetime.now(timezone.utc).isoformat(),
        **result.model_dump(),
    }
    await db.parsed_resumes.insert_one(doc)

    return result


# ── Student endpoints ──────────────────────────────────────────────────


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

    # Also clean up connections involving this user
    db = get_db()
    await db.connections.delete_many({"$or": [{"uid1": uid}, {"uid2": uid}]})


@app.delete("/students/{uid}/data", status_code=204)
async def clear_student_data(uid: str):
    """Delete all connections, chat rooms, and messages for a user, but keep their profile."""
    student = await get_student(uid)
    if student is None:
        raise HTTPException(status_code=404, detail="Student not found")

    db = get_db()

    # Find all chat rooms involving this user
    rooms = await db.chat_rooms.find(
        {"participant_uids": uid}, {"room_id": 1, "_id": 0}
    ).to_list(None)
    room_ids = [r["room_id"] for r in rooms]

    # Delete messages in those rooms, then the rooms themselves
    if room_ids:
        await db.chat_messages.delete_many({"room_id": {"$in": room_ids}})
        await db.chat_rooms.delete_many({"room_id": {"$in": room_ids}})

    # Delete all connections involving this user
    await db.connections.delete_many({"$or": [{"uid1": uid}, {"uid2": uid}]})


@app.get("/students/by-email/{email}", response_model=StudentProfile)
async def read_student_by_email(email: str):
    student = await get_student_by_email(email)
    if student is None:
        raise HTTPException(status_code=404, detail="Student not found")
    return student


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


# ── FCM token endpoint ────────────────────────────────────────────────


class FcmTokenBody(BaseModel):
    token: str


@app.put("/students/{uid}/fcm-token")
async def update_fcm_token(uid: str, body: FcmTokenBody):
    db = get_db()
    result = await db.student_profiles.update_one(
        {"uid": uid},
        {"$set": {"fcm_token": body.token}},
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Student not found")
    return {"status": "ok"}


@app.post("/students/{uid}/test-notification")
async def test_notification(uid: str):
    """Send a test push notification to a student (for debugging FCM)."""
    ok = await send_push_notification(
        uid,
        "Test Notification",
        "If you see this, FCM delivery works!",
        {"connection_id": "test_123"},
    )
    if not ok:
        raise HTTPException(status_code=500, detail="Failed to send — check FCM token and service account")
    return {"status": "sent"}


# ── Connection endpoints ───────────────────────────────────────────────


@app.post("/connections", response_model=Connection, status_code=201)
async def create_connection(body: ConnectionCreate):
    # Sort UIDs to compute deterministic connection ID
    uid1, uid2 = sorted([body.uid1, body.uid2])
    connection_id = make_connection_id(uid1, uid2)

    # Check if connection already exists
    existing = await get_connection(connection_id)
    if existing:
        return existing

    # Fetch both profiles
    profile1 = await get_student(uid1)
    profile2 = await get_student(uid2)
    if profile1 is None or profile2 is None:
        missing = uid1 if profile1 is None else uid2
        raise HTTPException(status_code=404, detail=f"Student {missing} not found")

    # Compute similarity score
    vec1 = vectorize_profile(profile1)
    vec2 = vectorize_profile(profile2)
    match_score = compute_match(profile1, vec1, profile2, vec2, Weights())
    match_percentage = round(match_score.score * 100, 1)

    now = datetime.now(timezone.utc)
    conn_doc = {
        "connection_id": connection_id,
        "uid1": uid1,
        "uid2": uid2,
        "uid1_accepted": False,
        "uid2_accepted": False,
        "match_percentage": match_percentage,
        "uid1_summary": None,
        "uid2_summary": None,
        "notification_message": None,
        "created_at": now.isoformat(),
        "updated_at": None,
        "last_nearby_notified_at": None,
    }

    # Race-condition safe insert
    connection = await upsert_connection(conn_doc)

    # If >= 60%, generate AI summaries and notify
    if match_percentage >= 60:
        summaries = await generate_connection_summaries(
            profile1.model_dump(), profile2.model_dump(), match_percentage
        )
        if summaries["uid1_summary"]:
            connection = await update_connection_summaries(
                connection_id,
                summaries["uid1_summary"],
                summaries["uid2_summary"],
                summaries["notification_message"],
            )

        # Notify both users via WebSocket
        event = {
            "type": "match_found",
            "connection": connection.model_dump(mode="json"),
        }
        await ws_manager.broadcast_to_users([uid1, uid2], event)

        notif_msg = summaries.get("notification_message") or f"New match ({match_percentage:.0f}%)!"
    else:
        notif_msg = f"Someone nearby matched with you ({match_percentage:.0f}%)!"

    # Always send FCM push so backgrounded users get notified
    for uid in [uid1, uid2]:
        await send_push_notification(uid, "New Match!", notif_msg, {"connection_id": connection_id})

    return connection


@app.get("/connections/{connection_id}", response_model=Connection)
async def read_connection(connection_id: str):
    conn = await get_connection(connection_id)
    if conn is None:
        raise HTTPException(status_code=404, detail="Connection not found")
    return conn


@app.get("/connections/user/{uid}", response_model=ConnectionList)
async def list_user_connections(uid: str):
    connections = await get_connections_for_user(uid)
    return ConnectionList(connections=connections)


@app.get("/connections/user/{uid}/accepted", response_model=ConnectionList)
async def list_accepted_connections(uid: str):
    connections = await get_accepted_connections_for_user(uid)
    return ConnectionList(connections=connections)


@app.post("/connections/{connection_id}/accept", response_model=Connection)
async def accept_connection_endpoint(connection_id: str, body: ConnectionAccept):
    conn = await accept_connection(connection_id, body.uid)
    if conn is None:
        raise HTTPException(status_code=404, detail="Connection not found or UID mismatch")

    other_uid = conn.uid2 if body.uid == conn.uid1 else conn.uid1

    if conn.uid1_accepted and conn.uid2_accepted:
        # Both accepted — auto-create chat room
        room = await get_or_create_room(RoomCreate(participant_uids=[conn.uid1, conn.uid2]))

        event = {
            "type": "connection_complete",
            "connection": conn.model_dump(mode="json"),
            "room_id": room.room_id,
        }
        await ws_manager.broadcast_to_users([conn.uid1, conn.uid2], event)

        for uid in [conn.uid1, conn.uid2]:
            await send_push_notification(
                uid, "Connection Complete!",
                "You're connected! Start chatting now.",
                {"connection_id": connection_id, "room_id": room.room_id},
            )
    else:
        # Only one accepted — notify the other user
        event = {
            "type": "connection_accepted",
            "connection": conn.model_dump(mode="json"),
        }
        await ws_manager.send_to_user(other_uid, event)
        await send_push_notification(
            other_uid, "Someone accepted!",
            "A match accepted your connection. Check it out!",
            {"connection_id": connection_id},
        )

    return conn


@app.post("/connections/{connection_id}/nearby", response_model=Connection)
async def notify_nearby(connection_id: str):
    """Notify both users that a matched peer is nearby (re-encounter)."""
    conn = await get_connection(connection_id)
    if conn is None:
        raise HTTPException(status_code=404, detail="Connection not found")

    # Only notify for matches above threshold
    if conn.match_percentage < 60:
        return conn

    # Cooldown: skip if notified within the last hour
    if conn.last_nearby_notified_at is not None:
        last = conn.last_nearby_notified_at
        if isinstance(last, str):
            last = datetime.fromisoformat(last)
        if datetime.now(timezone.utc) - last < timedelta(hours=1):
            return conn

    # Update timestamp
    await update_nearby_notified_at(connection_id)

    # Send FCM to both users
    for uid in [conn.uid1, conn.uid2]:
        await send_push_notification(
            uid,
            "A match is nearby!",
            "Someone you matched with is around you right now. Say hi!",
            {"connection_id": connection_id},
        )

    # Broadcast WebSocket event
    event = {
        "type": "reencounter",
        "connection": conn.model_dump(mode="json"),
    }
    await ws_manager.broadcast_to_users([conn.uid1, conn.uid2], event)

    return conn


# ── Chat endpoints ──────────────────────────────────────────────────────


@app.post("/chat/rooms", response_model=Room, status_code=201)
async def create_room(body: RoomCreate):
    try:
        return await get_or_create_room(body)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/chat/rooms/{room_id}", response_model=Room)
async def read_room(room_id: str):
    room = await get_room(room_id)
    if room is None:
        raise HTTPException(status_code=404, detail="Room not found")
    return room


@app.get("/chat/users/{uid}/rooms", response_model=RoomList)
async def list_user_rooms(uid: str):
    rooms = await get_rooms_for_user(uid)
    return RoomList(rooms=rooms)


@app.post("/chat/rooms/{room_id}/messages", response_model=Message, status_code=201)
async def send_message(room_id: str, body: MessageCreate):
    try:
        return await create_message(room_id, body)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@app.get("/chat/rooms/{room_id}/messages", response_model=MessageList)
async def list_messages(
    room_id: str,
    limit: int = Query(50, ge=1, le=200),
    before: Optional[datetime] = Query(None),
):
    room = await get_room(room_id)
    if room is None:
        raise HTTPException(status_code=404, detail="Room not found")

    messages, total = await get_messages(room_id, limit, before)
    return MessageList(room_id=room_id, messages=messages, total=total)


# ── WebSocket endpoint ─────────────────────────────────────────────────


@app.websocket("/ws/{uid}")
async def websocket_endpoint(websocket: WebSocket, uid: str):
    await ws_manager.connect(uid, websocket)
    try:
        while True:
            # Keep connection alive; client can send pings
            await websocket.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect(uid)
