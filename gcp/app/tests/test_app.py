from fastapi.testclient import TestClient
from app import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"


def test_status():
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert data["app"] == "devops-lab"
    assert data["version"] == "1.0.0"
