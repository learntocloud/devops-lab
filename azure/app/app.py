from fastapi import FastAPI
import redis
import os

app = FastAPI(title="DevOps Lab App")

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))


def get_redis():
    try:
        r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        r.ping()
        return r
    except redis.ConnectionError:
        return None


@app.get("/health")
def health():
    r = get_redis()
    redis_status = "connected" if r else "disconnected"
    return {"status": "healthy", "redis": redis_status}


@app.get("/api/status")
def status():
    r = get_redis()
    if r:
        visits = r.incr("visits")
    else:
        visits = -1
    return {
        "app": "devops-lab",
        "version": "1.0.0",
        "visits": visits,
        "redis": "connected" if r else "disconnected",
    }
