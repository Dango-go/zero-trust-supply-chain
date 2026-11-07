import logging
import uuid
from typing import Optional
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "service": "zt-payments", "message": "%(message)s"}'
)
logger = logging.getLogger("zt-payments")

app = FastAPI(
    title="Zero-Trust Payments Service",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

class ChargeRequest(BaseModel):
    order_id: str = Field(..., description="Unique Order ID")
    amount: float = Field(..., gt=0, description="Charge amount in base currency units")
    currency: str = Field(default="USD", min_length=3, max_length=3, description="ISO 4217 currency code")

class ChargeResponse(BaseModel):
    status: str
    tx_id: str
    order_id: str
    amount: float
    currency: str

@app.get("/healthz", status_code=status.HTTP_200_OK)
async def healthz():
    return {"status": "ok", "service": "zt-payments"}

@app.post(
    "/v1/charge",
    response_model=ChargeResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Process Payment Charge",
    description="Endpoint allowed by Cilium L7 policy specifically for zt-orders"
)
async def process_charge(charge: ChargeRequest):
    logger.info(f"Processing charge for order {charge.order_id} with amount {charge.amount} {charge.currency}")
    
    # Simulate payment processing logic
    tx_id = f"tx_{uuid.uuid4().hex[:16]}"
    
    return ChargeResponse(
        status="CONFIRMED",
        tx_id=tx_id,
        order_id=charge.order_id,
        amount=charge.amount,
        currency=charge.currency
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, log_level="info")
