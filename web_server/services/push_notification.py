import base64
import hashlib
import json
import os
import time
from typing import Optional

import httpx

from db import get_db

# Cache for OAuth2 access token
_token_cache: dict = {"token": None, "expires_at": 0}


def _get_service_account() -> Optional[dict]:
    """Load Google service account credentials from env var."""
    raw = os.getenv("GOOGLE_SERVICE_ACCOUNT_JSON")
    if not raw:
        return None
    return json.loads(raw)


def _b64url(data: bytes) -> str:
    """Base64url encode without padding."""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _sign_rs256(payload_bytes: bytes, private_key_pem: str) -> str:
    """Sign a JWT using RS256 with Python's stdlib + cryptography (ships with httpx)."""
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding

    key = serialization.load_pem_private_key(private_key_pem.encode(), password=None)
    signature = key.sign(payload_bytes, padding.PKCS1v15(), hashes.SHA256())
    return _b64url(signature)


def _make_jwt(sa: dict) -> str:
    """Create a signed JWT for Google OAuth2 token exchange."""
    now = int(time.time())
    header = _b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = _b64url(json.dumps({
        "iss": sa["client_email"],
        "sub": sa["client_email"],
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now,
        "exp": now + 3600,
        "scope": "https://www.googleapis.com/auth/firebase.messaging",
    }).encode())
    signing_input = f"{header}.{claims}"
    signature = _sign_rs256(signing_input.encode(), sa["private_key"])
    return f"{signing_input}.{signature}"


def _get_access_token(sa: dict) -> str:
    """Sign a JWT and exchange it for an OAuth2 access token (cached)."""
    now = time.time()
    if _token_cache["token"] and _token_cache["expires_at"] > now + 60:
        return _token_cache["token"]

    signed_jwt = _make_jwt(sa)
    resp = httpx.post(
        "https://oauth2.googleapis.com/token",
        data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": signed_jwt,
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
        # Send notification + data so the OS can display the notification
        # even when the app is killed. The app handles foreground display
        # separately via flutter_local_notifications.
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
            if resp.status_code != 200:
                print(f'[knkt-fcm] delivery failed {resp.status_code}: {resp.text[:200]}')
                return False
            return True
    except Exception:
        return False
