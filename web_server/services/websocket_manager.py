import json

from fastapi import WebSocket


class ConnectionManager:
    """Manages active WebSocket connections keyed by user UID."""

    def __init__(self):
        self.active_connections: dict[str, WebSocket] = {}

    async def connect(self, uid: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections[uid] = websocket

    def disconnect(self, uid: str):
        self.active_connections.pop(uid, None)

    async def send_to_user(self, uid: str, data: dict) -> bool:
        """Send JSON to a specific user. Returns True if sent."""
        ws = self.active_connections.get(uid)
        if ws is None:
            return False
        try:
            await ws.send_text(json.dumps(data))
            return True
        except Exception:
            self.disconnect(uid)
            return False

    async def broadcast_to_users(self, uids: list[str], data: dict):
        """Send JSON to multiple users."""
        for uid in uids:
            await self.send_to_user(uid, data)
