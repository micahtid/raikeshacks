import json
import os
from pathlib import Path

from dotenv import load_dotenv
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

load_dotenv()

client: AsyncIOMotorClient | None = None
db: AsyncIOMotorDatabase | None = None

SCHEMA_DIR = Path(__file__).parent / "schemas"


async def connect_db() -> AsyncIOMotorDatabase:
    global client, db
    mongo_url = os.getenv("MONGODB_URL", "mongodb://localhost:27017")
    client = AsyncIOMotorClient(mongo_url)
    db = client.users

    # Apply JSON Schema validation to the student_profiles collection
    schema_path = SCHEMA_DIR / "student_profile.schema.json"
    with open(schema_path) as f:
        raw = json.load(f)

    # MongoDB uses only the core JSON Schema fields, strip the meta keys
    validator = {
        k: v
        for k, v in raw.items()
        if k not in ("$schema", "$id", "title", "description")
    }

    # MongoDB $jsonSchema doesn't support several standard JSON Schema
    # keywords.  Strip them recursively so startup never fails.
    _UNSUPPORTED_KEYS = {"format", "examples", "$comment"}

    def _mongo_compat(obj):
        if isinstance(obj, dict):
            for key in list(obj.keys()):
                if key in _UNSUPPORTED_KEYS:
                    obj.pop(key)
            # MongoDB uses "int" / "long" instead of "integer"
            if obj.get("type") == "integer":
                obj["bsonType"] = "int"
                del obj["type"]
            for v in obj.values():
                _mongo_compat(v)
        elif isinstance(obj, list):
            for item in obj:
                _mongo_compat(item)

    _mongo_compat(validator)

    existing = await db.list_collection_names()
    if "student_profiles" not in existing:
        await db.create_collection(
            "student_profiles",
            validator={"$jsonSchema": validator},
        )
    else:
        await db.command("collMod", "student_profiles", validator={"$jsonSchema": validator})

    return db


async def close_db() -> None:
    global client
    if client:
        client.close()


def get_db() -> AsyncIOMotorDatabase:
    assert db is not None, "Database not connected. Call connect_db() first."
    return db
