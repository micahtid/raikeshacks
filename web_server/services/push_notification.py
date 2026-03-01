import json
import os
import time
from typing import Optional

import httpx
import jwt

from db import get_db

# Cache for OAuth2 access token
_token_cache: dict = {"token": None, "expires_at": 0}


def _get_service_account() -> Optional[dict]:
    """Load Google service account credentials from env var."""
    raw = os.getenv("GOOGLE_SERVICE_ACCOUNT_JSON")
    if not raw:
        return None
    return json.loads(raw)


def _get_access_token(sa: dict) -> str:
    """Sign a JWT and exchange it for an OAuth2 access token (cached)."""
    now = time.time()
    if _token_cache["token"] and _token_cache["expires_at"] > now + 60:
        return _token_cache["token"]

    iat = int(now)
    exp = iat + 3600
    payload = {
        "iss": sa["client_email"],
        "sub": sa["client_email"],
        "aud": "https://oauth2.googleapis.com/token",
        "iat": iat,
        "exp": exp,
        "scope": "https://www.googleapis.com/auth/firebase.messaging",
    }
    signed = jwt.encode(payload, sa["private_key"], algorithm="RS256")

    resp = httpx.post(
        "https://oauth2.googleapis.com/token",
        data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": signed,
        },
    )
    resp.raise_for_status()
    data = resp.json()
    _token_cache["token"] = data["access_token"]
    _token_cache["expires_at"] = now + data.get("expires_in", 3600)
    return data["access_token"]


async def send_push_notification(
    uid: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Send an FCM v1 push notification to a user by UID.

    Looks up the user's fcm_token from student_profiles.
    Returns True on success, False on failure.
    """
    sa = _get_service_account()
    if not sa:
        return False

    project_id = os.getenv("FIREBASE_PROJECT_ID") or sa.get("project_id")
    if not project_id:
        return False

    db = get_db()
    student = await db.student_profiles.find_one({"uid": uid}, {"fcm_token": 1})
    if not student or not student.get("fcm_token"):
        return False

    try:
        access_token = _get_access_token(sa)
        message: dict = {
            "message": {
                "token": student["fcm_token"],
                "notification": {"title": title, "body": body},
            }
        }
        if data:
            message["message"]["data"] = {k: str(v) for k, v in data.items()}

        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json",
                },
                json=message,
            )
            return resp.status_code == 200
    except Exception:
        return False
