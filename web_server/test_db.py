"""Test script to verify the API is working and check for students."""

import json
import sys
import urllib.request
import urllib.error

BASE_URL = "https://raikeshacks-teal.vercel.app"


def api_get(path):
    try:
        req = urllib.request.Request(f"{BASE_URL}{path}")
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())


def api_post(path, data):
    try:
        body = json.dumps(data).encode()
        req = urllib.request.Request(
            f"{BASE_URL}{path}",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())


def api_delete(path):
    try:
        req = urllib.request.Request(f"{BASE_URL}{path}", method="DELETE")
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status, None
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())


def lookup_student(uid):
    print(f"\n--- Looking up student: {uid} ---")
    code, data = api_get(f"/students/{uid}")
    if code == 200:
        print(f"FOUND! Student profile:\n{json.dumps(data, indent=2)}")
    else:
        print(f"HTTP {code}: {data}")
    return code, data


def test_roundtrip():
    print("--- Testing student create/read/delete roundtrip ---\n")

    test_data = {
        "identity": {
            "full_name": "Test User",
            "email": "test@example.com",
            "university": "Test University",
            "graduation_year": 2026,
            "major": ["Computer Science"],
            "minor": [],
        },
        "focus_areas": ["startup"],
        "project": {
            "one_liner": "A test project",
            "stage": "idea",
            "industry": ["EdTech"],
        },
        "skills": {
            "possessed": [{"name": "Python", "source": "questionnaire"}],
            "needed": [{"name": "Design", "priority": "must_have"}],
        },
    }

    print("1. Creating test student...")
    code, created = api_post("/students", test_data)
    if code != 201:
        print(f"   FAILED: HTTP {code} - {created}")
        return
    uid = created["uid"]
    print(f"   Created with uid: {uid}")

    print("2. Reading back...")
    code, fetched = api_get(f"/students/{uid}")
    if code == 200:
        print(f"   Name: {fetched['identity']['full_name']}")
        print(f"   Email: {fetched['identity']['email']}")
        print(f"   Skills: {[s['name'] for s in fetched['skills']['possessed']]}")
        print("   READ OK")
    else:
        print(f"   FAILED: HTTP {code}")

    print("3. Deleting test student...")
    code, _ = api_delete(f"/students/{uid}")
    print(f"   {'DELETE OK' if code == 204 else f'FAILED: HTTP {code}'}")

    print("\nAll tests passed!" if code == 204 else "\nSome tests failed.")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        lookup_student(sys.argv[1])
    else:
        test_roundtrip()
        print("\n--- To look up your account ---")
        print("Run: python test_db.py <your_student_uid>")
        print("Find your UID in the app's SharedPreferences ('student_uid' key)")
