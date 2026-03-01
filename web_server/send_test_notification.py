#!/usr/bin/env python3
"""Send a test FCM notification to a device token.

Usage:
    # Using environment variables (same as the backend):
    #   GOOGLE_SERVICE_ACCOUNT_JSON - JSON string of the service account
    #   FIREBASE_PROJECT_ID (optional, read from service account if missing)

    python send_test_notification.py <fcm_device_token>

    # Or supply the service account file path:
    python send_test_notification.py <fcm_device_token> --sa-file path/to/sa.json
"""

import argparse
import base64
import json
import os
import sys
import time

import httpx


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _sign_rs256(payload_bytes: bytes, private_key_pem: str) -> str:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding

    key = serialization.load_pem_private_key(private_key_pem.encode(), password=None)
    signature = key.sign(payload_bytes, padding.PKCS1v15(), hashes.SHA256())
    return _b64url(signature)


def _make_jwt(sa: dict) -> str:
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


def get_access_token(sa: dict) -> str:
    signed_jwt = _make_jwt(sa)
    resp = httpx.post(
        "https://oauth2.googleapis.com/token",
        data={
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": signed_jwt,
        },
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def send_notification(token: str, sa: dict, project_id: str) -> None:
    access_token = get_access_token(sa)

    message = {
        "message": {
            "token": token,
            "notification": {
                "title": "Test Notification",
                "body": "If you see this, FCM delivery works!",
            },
            "android": {
                "priority": "high",
                "notification": {
                    "channel_id": "nearby_alerts",
                },
            },
            "apns": {
                "headers": {"apns-priority": "10"},
                "payload": {
                    "aps": {
                        "alert": {
                            "title": "Test Notification",
                            "body": "If you see this, FCM delivery works!",
                        },
                        "sound": "default",
                    },
                },
            },
            "data": {
                "connection_id": "test_123",
            },
        }
    }

    url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    print(f"Sending to: {url}")
    print(f"Token: {token[:20]}...{token[-10:]}")

    resp = httpx.post(
        url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
        json=message,
    )

    print(f"Status: {resp.status_code}")
    print(f"Response: {resp.text}")

    if resp.status_code == 200:
        print("\nSUCCESS - FCM accepted the message for delivery.")
    else:
        print("\nFAILED - Check the error above.")


def main():
    parser = argparse.ArgumentParser(description="Send a test FCM notification")
    parser.add_argument("token", help="FCM device token")
    parser.add_argument("--sa-file", help="Path to service account JSON file")
    args = parser.parse_args()

    # Load service account
    if args.sa_file:
        with open(args.sa_file) as f:
            sa = json.load(f)
    else:
        raw = os.getenv("GOOGLE_SERVICE_ACCOUNT_JSON")
        if not raw:
            print("ERROR: Set GOOGLE_SERVICE_ACCOUNT_JSON env var or use --sa-file")
            sys.exit(1)
        sa = json.loads(raw)

    project_id = os.getenv("FIREBASE_PROJECT_ID") or sa.get("project_id")
    if not project_id:
        print("ERROR: Could not determine Firebase project ID")
        sys.exit(1)

    print(f"Project: {project_id}")
    send_notification(args.token, sa, project_id)


if __name__ == "__main__":
    main()
