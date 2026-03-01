import json
import os
from typing import Optional

import httpx
from google.oauth2 import service_account
from google.auth.transport.requests import Request

from db import get_db

# FCM v1 API scope
_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]

# Cached credentials object (auto-refreshes)
_credentials = None


def _get_credentials():
    """Load and cache Google service account credentials from env var."""
    global _credentials
    if _credentials is not None:
        return _credentials

    raw = os.getenv("GOOGLE_SERVICE_ACCOUNT_JSON")
    if not raw:
        return None

    sa_info = json.loads(raw)
    _credentials = service_account.Credentials.from_service_account_info(
        sa_info, scopes=_SCOPES
    )
    return _credentials


def _get_access_token() -> Optional[str]:
    """Get a valid access token, refreshing if needed."""
    creds = _get_credentials()
    if creds is None:
        return None

    if not creds.valid:
        creds.refresh(Request())

    return creds.token


async def send_push_to_all(
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> dict:
    """HARD-CODED: Send an FCM push notification to ALL devices with FCM tokens.

    This is a temporary implementation for testing. Replace with targeted
    delivery (send only to the relevant users) once FCM routing is verified.
    """
    print(f"[FCM] send_push_to_all called: title={title!r}, body={body!r}")

    access_token = _get_access_token()
    if not access_token:
        print("[FCM] ERROR: Could not get access token — GOOGLE_SERVICE_ACCOUNT_JSON env var missing or invalid")
        return {}

    creds = _get_credentials()
    project_id = os.getenv("FIREBASE_PROJECT_ID") or creds.project_id
    if not project_id:
        print("[FCM] ERROR: No project_id")
        return {}

    print(f"[FCM] project_id={project_id}, token={access_token[:20]}...")

    db = get_db()
    students = await db.student_profiles.find(
        {"fcm_token": {"$exists": True, "$ne": None}},
        {"uid": 1, "fcm_token": 1},
    ).to_list(None)

    print(f"[FCM] Found {len(students)} student(s) with FCM tokens")

    results = {}
    for student in students:
        fcm_token = student.get("fcm_token")
        uid = student.get("uid", "unknown")
        if not fcm_token:
            print(f"[FCM] Skipping {uid} — no fcm_token")
            continue
        try:
            message: dict = {
                "message": {
                    "token": fcm_token,
                    "notification": {"title": title, "body": body},
                    "android": {
                        "priority": "high",
                        "notification": {"channel_id": "nearby_alerts"},
                    },
                    "apns": {
                        "headers": {"apns-priority": "10"},
                        "payload": {
                            "aps": {"alert": {"title": title, "body": body}, "sound": "default"},
                        },
                    },
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
                status = "sent" if resp.status_code == 200 else f"failed ({resp.status_code}: {resp.text})"
                results[uid] = status
                print(f"[FCM] {uid}: {status}")
        except Exception as e:
            results[uid] = f"error: {e}"
            print(f"[FCM] {uid}: error: {e}")

    print(f"[FCM] send_push_to_all done: {results}")
    return results


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
    print(f"[FCM] send_push_notification called: uid={uid}, title={title!r}")

    access_token = _get_access_token()
    if not access_token:
        print("[FCM] ERROR: Could not get access token")
        return False

    creds = _get_credentials()
    project_id = os.getenv("FIREBASE_PROJECT_ID") or creds.project_id
    if not project_id:
        print("[FCM] ERROR: No project_id")
        return False

    db = get_db()
    student = await db.student_profiles.find_one({"uid": uid}, {"fcm_token": 1})
    if not student or not student.get("fcm_token"):
        print(f"[FCM] No FCM token found for uid={uid}")
        return False

    try:
        message: dict = {
            "message": {
                "token": student["fcm_token"],
                "notification": {"title": title, "body": body},
                "android": {
                    "priority": "high",
                    "notification": {
                        "channel_id": "nearby_alerts",
                    },
                },
                "apns": {
                    "headers": {"apns-priority": "10"},
                    "payload": {
                        "aps": {"alert": {"title": title, "body": body}, "sound": "default"},
                    },
                },
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
            success = resp.status_code == 200
            print(f"[FCM] send_push_notification {uid}: {'sent' if success else f'failed ({resp.status_code}: {resp.text})'}")
            return success
    except Exception as e:
        print(f"[FCM] send_push_notification {uid}: error: {e}")
        return False
