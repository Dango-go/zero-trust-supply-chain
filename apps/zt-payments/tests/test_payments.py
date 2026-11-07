from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)

def test_healthz():
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["service"] == "zt-payments"

def test_charge_success():
    payload = {
        "order_id": "ord-12345",
        "amount": 49.99,
        "currency": "USD"
    }
    response = client.post("/v1/charge", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "CONFIRMED"
    assert data["order_id"] == "ord-12345"
    assert data["amount"] == 49.99
    assert data["currency"] == "USD"
    assert "tx_id" in data

def test_charge_invalid_amount():
    payload = {
        "order_id": "ord-12345",
        "amount": -10.0,
        "currency": "USD"
    }
    response = client.post("/v1/charge", json=payload)
    assert response.status_code == 422
