import logging
import uuid
from contextlib import asynccontextmanager
from typing import Optional, List
import httpx
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

from src.config import settings
from src.db import db

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO),
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "service": "zt-orders", "message": "%(message)s"}'
)
logger = logging.getLogger("zt-orders")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: connect to database with dynamic Vault credentials
    logger.info("Initializing zt-orders service...")
    await db.connect()
    yield
    # Shutdown: graceful pool closure
    logger.info("Shutting down zt-orders service...")
    await db.disconnect()

app = FastAPI(
    title="Zero-Trust Orders Service",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None,
    lifespan=lifespan
)

class CreateOrderRequest(BaseModel):
    item: str = Field(..., min_length=1, description="Item name")
    quantity: int = Field(..., gt=0, description="Quantity")
    amount: float = Field(..., gt=0, description="Total order amount")
    currency: str = Field(default="USD", min_length=3, max_length=3)

class OrderResponse(BaseModel):
    id: str
    item: str
    quantity: int
    amount: float
    currency: str
    status: str
    payment_tx_id: Optional[str] = None

@app.get("/healthz", status_code=status.HTTP_200_OK)
async def healthz():
    """Liveness probe: verifies that the app process is alive."""
    return {"status": "ok", "service": "zt-orders"}

@app.get("/readyz", status_code=status.HTTP_200_OK)
async def readyz():
    """Readiness probe: verifies database connectivity."""
    db_ok = await db.is_ready()
    if not db_ok:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database connection not ready or credentials rotating"
        )
    return {"status": "ready", "database": "connected"}

@app.post("/orders", response_model=OrderResponse, status_code=status.HTTP_201_CREATED)
async def create_order(order_req: CreateOrderRequest):
    order_id = f"ord_{uuid.uuid4().hex[:12]}"
    logger.info(f"Received new order request: {order_id} for {order_req.item}")

    # 1. Step 1: Call internal zt-payments microservice (Validates Cilium L7 policy)
    payments_endpoint = f"{settings.PAYMENTS_SERVICE_URL.rstrip('/')}/v1/charge"
    payment_tx_id = None
    
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            charge_payload = {
                "order_id": order_id,
                "amount": order_req.amount,
                "currency": order_req.currency
            }
            logger.info(f"Calling payments service at {payments_endpoint}")
            resp = await client.post(payments_endpoint, json=charge_payload)
            if resp.status_code != status.HTTP_201_CREATED:
                logger.error(f"Payment failed with code {resp.status_code}: {resp.text}")
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Payment rejected: {resp.text}"
                )
            charge_data = resp.json()
            payment_tx_id = charge_data.get("tx_id")
            logger.info(f"Payment confirmed with tx_id: {payment_tx_id}")
    except httpx.RequestError as e:
        logger.error(f"Failed to communicate with payments service: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Payments service unreachable: {str(e)}"
        )

    # 2. Step 2 (Optional): Call external PSP to validate Cilium toFQDNs egress allowlist
    if settings.CALL_EXTERNAL_PSP:
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                logger.info(f"Calling external PSP at {settings.EXTERNAL_PSP_URL}")
                await client.post(settings.EXTERNAL_PSP_URL, json={"order_id": order_id, "tx_id": payment_tx_id})
        except Exception as e:
            logger.warning(f"External PSP notification error (expected if FQDN not mocked): {e}")

    # 3. Step 3: Persist order in PostgreSQL (Validates Vault dynamic database creds)
    order_status = "COMPLETED"
    if await db.is_ready():
        try:
            await db.create_order(
                order_id=order_id,
                item=order_req.item,
                quantity=order_req.quantity,
                amount=order_req.amount,
                currency=order_req.currency,
                status=order_status,
                payment_tx_id=payment_tx_id
            )
        except Exception as e:
            logger.error(f"Failed to persist order in database: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database persistence error"
            )

    return OrderResponse(
        id=order_id,
        item=order_req.item,
        quantity=order_req.quantity,
        amount=order_req.amount,
        currency=order_req.currency,
        status=order_status,
        payment_tx_id=payment_tx_id
    )

@app.get("/orders/{order_id}", response_model=OrderResponse)
async def get_order(order_id: str):
    if not await db.is_ready():
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Database not ready")
    order = await db.get_order(order_id)
    if not order:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    return OrderResponse(
        id=order["id"],
        item=order["item"],
        quantity=order["quantity"],
        amount=float(order["amount"]),
        currency=order["currency"],
        status=order["status"],
        payment_tx_id=order.get("payment_tx_id")
    )

@app.get("/orders", response_model=List[OrderResponse])
async def list_orders():
    orders = await db.list_orders()
    return [
        OrderResponse(
            id=o["id"],
            item=o["item"],
            quantity=o["quantity"],
            amount=float(o["amount"]),
            currency=o["currency"],
            status=o["status"],
            payment_tx_id=o.get("payment_tx_id")
        )
        for o in orders
    ]

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=settings.PORT, log_level=settings.LOG_LEVEL.lower())
