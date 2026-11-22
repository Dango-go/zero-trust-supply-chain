from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)

def test_healthz():
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["service"] == "zt-orders"

@patch("src.db.db.is_ready", new_callable=AsyncMock)
def test_readyz_healthy(mock_is_ready):
    mock_is_ready.return_value = True
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"

@patch("src.db.db.is_ready", new_callable=AsyncMock)
def test_readyz_unhealthy(mock_is_ready):
    mock_is_ready.return_value = False
    response = client.get("/readyz")
    assert response.status_code == 503

@patch("src.db.db.is_ready", new_callable=AsyncMock)
@patch("src.db.db.create_order", new_callable=AsyncMock)
@patch("httpx.AsyncClient.post", new_callable=AsyncMock)
def test_create_order_success(mock_post, mock_create_order, mock_is_ready):
    mock_is_ready.return_value = True
    # Mock successful response from zt-payments
    mock_resp = MagicMock()
    mock_resp.status_code = 201
    mock_resp.json.return_value = {
        "status": "CONFIRMED",
        "tx_id": "tx_mock12345",
        "order_id": "ord_mock",
        "amount": 99.99,
        "currency": "USD"
    }
    mock_post.return_value = mock_resp

    payload = {
        "item": "Security Key",
        "quantity": 2,
        "amount": 99.99,
        "currency": "USD"
    }
    response = client.post("/orders", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert data["item"] == "Security Key"
    assert data["status"] == "COMPLETED"
    assert data["payment_tx_id"] == "tx_mock12345"
    mock_create_order.assert_called_once()
