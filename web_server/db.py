import json
import os
from pathlib import Path

from dotenv import load_dotenv
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

load_dotenv()

client: AsyncIOMotorClient | None = None
db: AsyncIOMotorDatabase | None = None

SCHEMA_DIR = Path(__file__).parent / "schemas"

def _load_validator(schema_file: str) -> dict:
    """Load a MongoDB-native JSON Schema file."""
    with open(SCHEMA_DIR / schema_file) as f:
        return json.load(f)


async def _ensure_collection(
    db: AsyncIOMotorDatabase,
    name: str,
    schema_file: str,
    existing: list[str],
) -> None:
    """Create a collection with $jsonSchema validation, or update the validator."""
    validator = _load_validator(schema_file)
    if name not in existing:
        await db.create_collection(
            name,
            validator={"$jsonSchema": validator},
        )
    else:
        await db.command("collMod", name, validator={"$jsonSchema": validator})


async def connect_db() -> AsyncIOMotorDatabase:
    global client, db
    mongo_url = os.getenv("MONGODB_URL", "mongodb://localhost:27017")
    client = AsyncIOMotorClient(mongo_url)
    db = client.users

    existing = await db.list_collection_names()
    await _ensure_collection(db, "student_profiles", "student_profile.schema.json", existing)
    await _ensure_collection(db, "chat_rooms", "chat_room.schema.json", existing)
    await _ensure_collection(db, "chat_messages", "chat_message.schema.json", existing)
    await _ensure_collection(db, "parsed_resumes", "parsed_resume.schema.json", existing)
    await _ensure_collection(db, "connections", "connection.schema.json", existing)

    await db.connections.create_index("connection_id", unique=True)

    return db


async def close_db() -> None:
    global client
    if client:
        client.close()


def get_db() -> AsyncIOMotorDatabase:
    assert db is not None, "Database not connected. Call connect_db() first."
    return db
