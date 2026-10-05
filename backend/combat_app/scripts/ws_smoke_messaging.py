# Manual WebSocket smoke test for the messaging redesign (presence + media validation).
# Run from the backend root:  python scripts/ws_smoke_messaging.py   (uses a throwaway sqlite file + mocked Redis)
import asyncio, os, sys
os.environ["DATABASE_URL"]="sqlite+aiosqlite:////tmp/smoke.db"
os.environ["SECRET_KEY"]="smoke-secret-key-0123456789abcdefghijkl"
sys.path.insert(0, os.getcwd())
if os.path.exists("/tmp/smoke.db"): os.remove("/tmp/smoke.db")
from app.main import app, limiter as ml
from app.api.v1.endpoints.auth import limiter as al
ml.enabled=False; al.enabled=False
from app.core.database import Base, engine
async def init():
    async with engine.begin() as c: await c.run_sync(Base.metadata.create_all)
    await engine.dispose()
asyncio.run(init())
from unittest.mock import MagicMock
import app.core.redis_client as rm
store={}
m=MagicMock()
async def g(k): return store.get(k)
async def se(k,t,v): store[k]=v
async def d(*ks):
    for k in ks: store.pop(k,None)
m.get=g; m.setex=se; m.delete=d
rm.redis_client=m
from starlette.testclient import TestClient
_cm=TestClient(app)
c=_cm.__enter__()
def mk(n):
    c.post("/api/v1/auth/register",json={"email":f"{n}@t.com","username":n,"full_name":n,"password":"testpass123","password_confirm":"testpass123"})
    t=c.post("/api/v1/auth/login",data={"username":f"{n}@t.com","password":"testpass123"}).json()["access_token"]
    uid=c.get("/api/v1/auth/me",headers={"Authorization":f"Bearer {t}"}).json()["id"]
    return t,uid
ta,ia=mk("smoke_a"); tb,ib=mk("smoke_b")
conv=c.post(f"/api/v1/messages/conversations/{ib}",headers={"Authorization":f"Bearer {ta}"}).json()["conversation_id"]
def until(ws, name):
    while True:
        e=ws.receive_json()
        if e["event"]==name: return e
IMG="https://res.cloudinary.com/demo/image/upload/combat/messages/images/x.jpg"
with c.websocket_connect(f"/api/v1/messages/ws?token={tb}") as wb:
    print("B:",wb.receive_json()["event"])
    with c.websocket_connect(f"/api/v1/messages/ws?token={ta}") as wa:
        print("A:",wa.receive_json()["event"])
        while True:
            ev=wb.receive_json(); print("B got:",ev)
            if ev["event"]=="presence" and ev["data"]["user_id"]==ia: break
        assert ev["data"]["is_online"] is True
        # list shows A online for B
        lst=c.get("/api/v1/messages/conversations",headers={"Authorization":f"Bearer {tb}"}).json()
        print("other_user_online (B view):",lst[0]["other_user_online"])
        assert lst[0]["other_user_online"] is True
        wa.send_json({"type":"send_message","conversation_id":conv,"media_url":"https://evil.com/a.jpg","media_type":"image"})
        e=until(wa,"error"); print("A bad media ->",e)
        wa.send_json({"type":"send_message","conversation_id":conv,"content":"x"*2001})
        e=until(wa,"error"); print("A too long ->",e)
        wa.send_json({"type":"send_message","conversation_id":conv,"media_url":IMG,"media_type":"image"})
        e=until(wa,"new_message"); print("A echo:",e["event"],e["data"]["media_type"])
        e=until(wb,"new_message"); print("B recv:",e["event"],e["data"]["media_url"]==IMG); assert e["data"]["media_url"]==IMG
        wa.close()  # graceful client close, like a real app
        while True:
            ev=wb.receive_json(); print("B got:",ev)
            if ev["event"]=="presence" and ev["data"]["user_id"]==ia: break
        assert ev["data"]["is_online"] is False
print("SMOKE OK")
