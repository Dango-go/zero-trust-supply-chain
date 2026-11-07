import asyncio
import logging
from typing import Optional, List, Dict, Any
import asyncpg
from src.config import settings

logger = logging.getLogger("zt-orders.db")

class Database:
    def __init__(self):
        self._pool: Optional[asyncpg.Pool] = None

    async def connect(self, retries: int = 5, delay: float = 2.0):
        """Initializes connection pool with retries and Vault dynamic credentials."""
        user, password = settings.get_credentials()
        ssl_arg = False if settings.DB_SSLMODE == "disable" else None
        if settings.DB_SSLMODE in ("require", "verify-full", "verify-ca"):
            ssl_arg = settings.DB_SSLMODE

        for attempt in range(1, retries + 1):
            try:
                logger.info(f"Connecting to database {settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME} (attempt {attempt})")
                self._pool = await asyncpg.create_pool(
                    host=settings.DB_HOST,
                    port=settings.DB_PORT,
                    database=settings.DB_NAME,
                    user=user,
                    password=password,
                    ssl=ssl_arg,
                    min_size=1,
                    max_size=10,
                    command_timeout=10,
                )
                await self._init_schema()
                logger.info("Database connection pool established successfully")
                return
            except Exception as e:
                logger.warning(f"Failed to connect to database: {e}")
                if attempt == retries:
                    logger.error("All connection attempts exhausted. Continuing without active pool (readyz will fail).")
                    return
                await asyncio.sleep(delay)

    async def _init_schema(self):
        """Ensures the orders table exists."""
        if not self._pool:
            return
        query = """
        CREATE TABLE IF NOT EXISTS orders (
            id VARCHAR(64) PRIMARY KEY,
            item VARCHAR(128) NOT NULL,
            quantity INT NOT NULL,
            amount NUMERIC(10, 2) NOT NULL,
            currency VARCHAR(3) NOT NULL,
            status VARCHAR(32) NOT NULL,
            payment_tx_id VARCHAR(64),
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
        """
        async with self._pool.acquire() as conn:
            await conn.execute(query)

    async def is_ready(self) -> bool:
        """Verifies active connectivity to the database."""
        if not self._pool:
            return False
        try:
            async with self._pool.acquire() as conn:
                res = await conn.fetchval("SELECT 1")
                return res == 1
        except Exception as e:
            logger.warning(f"Database readiness check failed: {e}")
            return False

    async def create_order(self, order_id: str, item: str, quantity: int, amount: float, currency: str, status: str, payment_tx_id: Optional[str] = None):
        if not self._pool:
            raise RuntimeError("Database pool not available")
        query = """
        INSERT INTO orders (id, item, quantity, amount, currency, status, payment_tx_id)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        """
        async with self._pool.acquire() as conn:
            await conn.execute(query, order_id, item, quantity, amount, currency, status, payment_tx_id)

    async def get_order(self, order_id: str) -> Optional[Dict[str, Any]]:
        if not self._pool:
            raise RuntimeError("Database pool not available")
        query = "SELECT * FROM orders WHERE id = $1"
        async with self._pool.acquire() as conn:
            row = await conn.fetchrow(query, order_id)
            return dict(row) if row else None

    async def list_orders(self, limit: int = 50) -> List[Dict[str, Any]]:
        if not self._pool:
            return []
        query = "SELECT * FROM orders ORDER BY created_at DESC LIMIT $1"
        async with self._pool.acquire() as conn:
            rows = await conn.fetch(query, limit)
            return [dict(r) for r in rows]

    async def disconnect(self):
        if self._pool:
            logger.info("Closing database connection pool...")
            await self._pool.close()
            self._pool = None

db = Database()
