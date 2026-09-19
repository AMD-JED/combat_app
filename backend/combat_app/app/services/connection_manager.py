"""
WebSocket Connection Manager
============================
Manages active WebSocket connections per user and broadcasts
messages in real time.

Architecture:
  - In-memory dict maps user_id → set of WebSocket connections
    (one user can have multiple tabs/devices open)
  - Redis pub/sub fan-out for multi-server deployments
    (if you scale to multiple Uvicorn workers or machines)

  User A ──WS──▶ Worker 1 ──publish──▶ Redis ──subscribe──▶ Worker 2 ──WS──▶ User B
"""

import json
import asyncio
import logging
from typing import Dict, Set, Optional

import redis.asyncio as aioredis
from fastapi import WebSocket

from app.core.config import settings

logger = logging.getLogger(__name__)

# Redis channel prefix
CHANNEL_PREFIX = "combat:chat:"


class ConnectionManager:
    """
    Manages all active WebSocket connections.
    Thread-safe for use with asyncio.
    """

    def __init__(self):
        # user_id → set of WebSocket objects (multiple devices)
        self._connections: Dict[int, Set[WebSocket]] = {}
        self._redis: Optional[aioredis.Redis] = None
        self._pubsub_task: Optional[asyncio.Task] = None

    # ──────────────────────────────────────────────
    #  Lifecycle
    # ──────────────────────────────────────────────

    async def startup(self):
        """Call this on app startup to connect to Redis."""
        try:
            self._redis = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
            await self._redis.ping()
            logger.info("✅ Redis connected for WebSocket pub/sub")
            self._pubsub_task = asyncio.create_task(self._redis_subscriber())
        except Exception as e:
            logger.warning(f"⚠️  Redis unavailable — WebSockets will work single-server only: {e}")
            self._redis = None

    async def shutdown(self):
        if self._pubsub_task:
            self._pubsub_task.cancel()
        if self._redis:
            await self._redis.aclose()

    # ──────────────────────────────────────────────
    #  Connection handling
    # ──────────────────────────────────────────────

    async def connect(self, user_id: int, websocket: WebSocket):
        await websocket.accept()
        if user_id not in self._connections:
            self._connections[user_id] = set()
        self._connections[user_id].add(websocket)
        logger.info(f"User {user_id} connected. Total users online: {len(self._connections)}")

    def disconnect(self, user_id: int, websocket: WebSocket):
        if user_id in self._connections:
            self._connections[user_id].discard(websocket)
            if not self._connections[user_id]:
                del self._connections[user_id]
        logger.info(f"User {user_id} disconnected.")

    def is_online(self, user_id: int) -> bool:
        return user_id in self._connections and len(self._connections[user_id]) > 0

    # ──────────────────────────────────────────────
    #  Sending
    # ──────────────────────────────────────────────

    async def send_to_user(self, user_id: int, payload: dict):
        """
        Send a JSON payload to all of a user's connections.

        When Redis is available, delivery goes exclusively through the
        publish -> subscribe round-trip: `_redis_subscriber` calls
        `_deliver_locally` for *every* worker that receives the pmessage,
        including this one. Also calling `_deliver_locally` directly here
        used to double-send to anyone connected to this same worker — which
        is every user in a single-worker dev setup (the common case), since
        this process subscribes to its own publish. Redis being absent
        (see `startup()`'s single-server fallback) is the only path that
        still delivers locally on its own.
        """
        if self._redis:
            channel = f"{CHANNEL_PREFIX}{user_id}"
            try:
                await self._redis.publish(channel, json.dumps(payload))
                return
            except Exception as e:
                logger.error(f"Redis publish error: {e}")
                # Fall through so the message isn't lost if publish itself failed.

        await self._deliver_locally(user_id, payload)

    async def _deliver_locally(self, user_id: int, payload: dict):
        """Send to all WebSocket connections of a user on this worker."""
        sockets = self._connections.get(user_id, set()).copy()
        dead = set()
        for ws in sockets:
            try:
                await ws.send_json(payload)
            except Exception:
                dead.add(ws)
        # Clean up dead connections
        for ws in dead:
            self._connections.get(user_id, set()).discard(ws)

    # ──────────────────────────────────────────────
    #  Redis subscriber (background task)
    # ──────────────────────────────────────────────

    async def _redis_subscriber(self):
        """
        Subscribe to all combat:chat:* channels.
        When a message arrives from another worker, deliver it locally.
        """
        if not self._redis:
            return
        pubsub = self._redis.pubsub()
        await pubsub.psubscribe(f"{CHANNEL_PREFIX}*")
        logger.info("📡 Redis pub/sub listener started")

        async for raw in pubsub.listen():
            if raw["type"] != "pmessage":
                continue
            try:
                # Extract user_id from channel name
                channel: str = raw["channel"]
                user_id = int(channel.removeprefix(CHANNEL_PREFIX))
                payload = json.loads(raw["data"])
                await self._deliver_locally(user_id, payload)
            except Exception as e:
                logger.error(f"Redis subscriber error: {e}")


# Singleton — imported by both main.py and the WS endpoint
manager = ConnectionManager()
