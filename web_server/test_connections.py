"""Tests for the connection system endpoints.

Run with: python test_connections.py
Requires a running server at localhost:8000 with MongoDB.
"""
import asyncio
import httpx

BASE = "http://localhost:8000"


async def create_test_student(client: httpx.AsyncClient, name: str, email: str, skills_possessed: list[str], skills_needed: list[str]) -> dict:
    """Create a student profile for testing."""
    data = {
        "identity": {
            "full_name": name,
            "email": email,
            "university": "Test University",
            "graduation_year": 2025,
            "major": ["Computer Science"],
            "minor": [],
        },
        "focus_areas": ["startup"],
        "project": {
            "one_liner": "A test project",
            "stage": "mvp",
            "industry": ["AI/ML"],
        },
        "skills": {
            "possessed": [{"name": s, "source": "questionnaire"} for s in skills_possessed],
            "needed": [{"name": s, "priority": "must_have"} for s in skills_needed],
        },
    }
    resp = await client.post(f"{BASE}/students", json=data)
    assert resp.status_code == 201, f"Failed to create student: {resp.text}"
    return resp.json()


async def test_create_connection():
    """Test: Create two profiles, then POST /connections → verify connection created."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Create two students with complementary skills
        s1 = await create_test_student(
            client, "Alice Test", "alice@test.com",
            skills_possessed=["Python", "Machine Learning"],
            skills_needed=["React", "UI Design"],
        )
        s2 = await create_test_student(
            client, "Bob Test", "bob@test.com",
            skills_possessed=["React", "UI Design"],
            skills_needed=["Python", "Machine Learning"],
        )
        uid1, uid2 = s1["uid"], s2["uid"]
        print(f"  Created students: {uid1}, {uid2}")

        # Create connection
        resp = await client.post(f"{BASE}/connections", json={"uid1": uid1, "uid2": uid2})
        assert resp.status_code == 201, f"Failed to create connection: {resp.text}"
        conn = resp.json()

        assert conn["connection_id"] is not None
        assert conn["uid1_accepted"] is False
        assert conn["uid2_accepted"] is False
        assert conn["match_percentage"] >= 0
        print(f"  Connection created: {conn['connection_id']}, match: {conn['match_percentage']}%")

        # Verify idempotent — second POST returns same connection
        resp2 = await client.post(f"{BASE}/connections", json={"uid1": uid2, "uid2": uid1})
        assert resp2.status_code == 201
        conn2 = resp2.json()
        assert conn2["connection_id"] == conn["connection_id"], "Duplicate connection created!"
        print("  Idempotent check passed")

        # Get connection by ID
        resp3 = await client.get(f"{BASE}/connections/{conn['connection_id']}")
        assert resp3.status_code == 200
        print("  GET by ID passed")

        # Get connections for user
        resp4 = await client.get(f"{BASE}/connections/user/{uid1}")
        assert resp4.status_code == 200
        conns = resp4.json()["connections"]
        assert len(conns) >= 1
        print(f"  GET for user returned {len(conns)} connection(s)")

        # Cleanup
        await client.delete(f"{BASE}/students/{uid1}")
        await client.delete(f"{BASE}/students/{uid2}")
        print("  PASS: test_create_connection")
        return conn["connection_id"], uid1, uid2


async def test_accept_flow():
    """Test: Accept connection from both sides → verify chat room auto-created."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        s1 = await create_test_student(
            client, "Carol Test", "carol@test.com",
            skills_possessed=["Flutter", "Dart"],
            skills_needed=["Backend", "DevOps"],
        )
        s2 = await create_test_student(
            client, "Dave Test", "dave@test.com",
            skills_possessed=["Backend", "DevOps"],
            skills_needed=["Flutter", "Mobile"],
        )
        uid1, uid2 = s1["uid"], s2["uid"]

        # Create connection
        resp = await client.post(f"{BASE}/connections", json={"uid1": uid1, "uid2": uid2})
        assert resp.status_code == 201
        conn = resp.json()
        cid = conn["connection_id"]

        # Determine which uid is uid1/uid2 in the connection (sorted)
        sorted_uids = sorted([uid1, uid2])
        conn_uid1, conn_uid2 = sorted_uids[0], sorted_uids[1]

        # Accept from uid1
        resp = await client.post(f"{BASE}/connections/{cid}/accept", json={"uid": conn_uid1})
        assert resp.status_code == 200
        updated = resp.json()
        assert updated["uid1_accepted"] is True
        assert updated["uid2_accepted"] is False
        print("  uid1 accepted")

        # Accept from uid2
        resp = await client.post(f"{BASE}/connections/{cid}/accept", json={"uid": conn_uid2})
        assert resp.status_code == 200
        updated = resp.json()
        assert updated["uid1_accepted"] is True
        assert updated["uid2_accepted"] is True
        print("  uid2 accepted — connection complete")

        # Verify accepted connections endpoint
        resp = await client.get(f"{BASE}/connections/user/{uid1}/accepted")
        assert resp.status_code == 200
        accepted = resp.json()["connections"]
        assert len(accepted) >= 1
        assert accepted[0]["uid1_accepted"] is True
        assert accepted[0]["uid2_accepted"] is True
        print("  Accepted connections endpoint verified")

        # Verify chat room was auto-created
        room_id = f"{conn_uid1}_{conn_uid2}"
        resp = await client.get(f"{BASE}/chat/rooms/{room_id}")
        assert resp.status_code == 200, f"Chat room not auto-created: {resp.text}"
        room = resp.json()
        assert conn_uid1 in room["participants"]
        assert conn_uid2 in room["participants"]
        print("  Chat room auto-created")

        # Cleanup
        await client.delete(f"{BASE}/students/{uid1}")
        await client.delete(f"{BASE}/students/{uid2}")
        print("  PASS: test_accept_flow")


async def test_race_condition():
    """Test: Two simultaneous connection creates → only one document."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        s1 = await create_test_student(
            client, "Eve Test", "eve@test.com",
            skills_possessed=["Go", "Kubernetes"],
            skills_needed=["Frontend"],
        )
        s2 = await create_test_student(
            client, "Frank Test", "frank@test.com",
            skills_possessed=["Frontend", "React"],
            skills_needed=["Backend"],
        )
        uid1, uid2 = s1["uid"], s2["uid"]

        # Fire two connection creates simultaneously
        resp1, resp2 = await asyncio.gather(
            client.post(f"{BASE}/connections", json={"uid1": uid1, "uid2": uid2}),
            client.post(f"{BASE}/connections", json={"uid1": uid2, "uid2": uid1}),
        )

        conn1 = resp1.json()
        conn2 = resp2.json()
        assert conn1["connection_id"] == conn2["connection_id"], "Race condition: duplicate connections!"
        print(f"  Both requests returned same connection: {conn1['connection_id']}")

        # Verify only one exists
        resp = await client.get(f"{BASE}/connections/user/{uid1}")
        conns = resp.json()["connections"]
        matching = [c for c in conns if c["connection_id"] == conn1["connection_id"]]
        assert len(matching) == 1, f"Expected 1 connection, found {len(matching)}"
        print("  Only one connection document exists")

        # Cleanup
        await client.delete(f"{BASE}/students/{uid1}")
        await client.delete(f"{BASE}/students/{uid2}")
        print("  PASS: test_race_condition")


async def test_chat_messages():
    """Test: Send and retrieve chat messages after connection acceptance."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        s1 = await create_test_student(
            client, "Grace Test", "grace@test.com",
            skills_possessed=["Swift", "iOS"],
            skills_needed=["Android"],
        )
        s2 = await create_test_student(
            client, "Hank Test", "hank@test.com",
            skills_possessed=["Android", "Kotlin"],
            skills_needed=["iOS"],
        )
        uid1, uid2 = s1["uid"], s2["uid"]
        sorted_uids = sorted([uid1, uid2])

        # Create and accept connection
        resp = await client.post(f"{BASE}/connections", json={"uid1": uid1, "uid2": uid2})
        cid = resp.json()["connection_id"]
        await client.post(f"{BASE}/connections/{cid}/accept", json={"uid": sorted_uids[0]})
        await client.post(f"{BASE}/connections/{cid}/accept", json={"uid": sorted_uids[1]})

        room_id = f"{sorted_uids[0]}_{sorted_uids[1]}"

        # Send messages
        resp = await client.post(
            f"{BASE}/chat/rooms/{room_id}/messages",
            json={"sender_uid": uid1, "content": "Hello from test!"},
        )
        assert resp.status_code == 201
        print("  Message 1 sent")

        resp = await client.post(
            f"{BASE}/chat/rooms/{room_id}/messages",
            json={"sender_uid": uid2, "content": "Hey! Nice to meet you."},
        )
        assert resp.status_code == 201
        print("  Message 2 sent")

        # Retrieve messages
        resp = await client.get(f"{BASE}/chat/rooms/{room_id}/messages")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 2
        assert len(data["messages"]) == 2
        assert data["messages"][0]["content"] == "Hello from test!"
        assert data["messages"][1]["content"] == "Hey! Nice to meet you."
        print(f"  Retrieved {data['total']} messages")

        # Cleanup
        await client.delete(f"{BASE}/students/{uid1}")
        await client.delete(f"{BASE}/students/{uid2}")
        print("  PASS: test_chat_messages")


async def test_fcm_token_endpoint():
    """Test: Register and update FCM token."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        s = await create_test_student(
            client, "Iris Test", "iris@test.com",
            skills_possessed=["Rust"],
            skills_needed=["Python"],
        )
        uid = s["uid"]

        # Register FCM token
        resp = await client.put(
            f"{BASE}/students/{uid}/fcm-token",
            json={"token": "fake-fcm-token-123"},
        )
        assert resp.status_code == 200
        print("  FCM token registered")

        # Verify token persisted
        resp = await client.get(f"{BASE}/students/{uid}")
        assert resp.status_code == 200
        student = resp.json()
        assert student.get("fcm_token") == "fake-fcm-token-123"
        print("  FCM token verified in profile")

        # Cleanup
        await client.delete(f"{BASE}/students/{uid}")
        print("  PASS: test_fcm_token_endpoint")


async def test_delete_cleans_connections():
    """Test: Deleting a student also deletes their connections."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        s1 = await create_test_student(
            client, "Jack Test", "jack@test.com",
            skills_possessed=["Java"],
            skills_needed=["Python"],
        )
        s2 = await create_test_student(
            client, "Kate Test", "kate@test.com",
            skills_possessed=["Python"],
            skills_needed=["Java"],
        )
        uid1, uid2 = s1["uid"], s2["uid"]

        # Create connection
        resp = await client.post(f"{BASE}/connections", json={"uid1": uid1, "uid2": uid2})
        cid = resp.json()["connection_id"]

        # Delete student 1
        await client.delete(f"{BASE}/students/{uid1}")

        # Verify connection is gone
        resp = await client.get(f"{BASE}/connections/{cid}")
        assert resp.status_code == 404, f"Connection should be deleted, got {resp.status_code}"
        print("  Connection cleaned up after student deletion")

        # Cleanup
        await client.delete(f"{BASE}/students/{uid2}")
        print("  PASS: test_delete_cleans_connections")


async def main():
    print("=" * 60)
    print("Connection System Tests")
    print("=" * 60)

    tests = [
        ("Create Connection", test_create_connection),
        ("Accept Flow", test_accept_flow),
        ("Race Condition", test_race_condition),
        ("Chat Messages", test_chat_messages),
        ("FCM Token", test_fcm_token_endpoint),
        ("Delete Cleans Connections", test_delete_cleans_connections),
    ]

    passed = 0
    failed = 0
    for name, test_fn in tests:
        print(f"\n[TEST] {name}")
        try:
            await test_fn()
            passed += 1
        except Exception as e:
            print(f"  FAIL: {e}")
            failed += 1

    print(f"\n{'=' * 60}")
    print(f"Results: {passed} passed, {failed} failed out of {len(tests)}")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
