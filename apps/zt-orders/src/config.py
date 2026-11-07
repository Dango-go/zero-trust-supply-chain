import os
from typing import Optional
from pydantic import BaseModel

class Settings(BaseModel):
    # App Settings
    SERVICE_NAME: str = "zt-orders"
    PORT: int = int(os.getenv("PORT", "8080"))
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    
    # Internal microservices (Cilium Ingress/Egress target)
    PAYMENTS_SERVICE_URL: str = os.getenv("PAYMENTS_SERVICE_URL", "http://zt-payments:8080")
    
    # External FQDN service (Cilium toFQDNs target)
    EXTERNAL_PSP_URL: str = os.getenv("EXTERNAL_PSP_URL", "https://api.psp.example/v1/notify")
    CALL_EXTERNAL_PSP: bool = os.getenv("CALL_EXTERNAL_PSP", "false").lower() in ("true", "1", "yes")

    # Database Settings (Dynamically provided via Vault / VSO)
    DB_HOST: str = os.getenv("DB_HOST", "postgres")
    DB_PORT: int = int(os.getenv("DB_PORT", "5432"))
    DB_NAME: str = os.getenv("DB_NAME", "orders")
    DB_USER: str = os.getenv("DB_USER", "postgres")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "postgres")
    DB_SSLMODE: str = os.getenv("DB_SSLMODE", "prefer")  # 'require', 'verify-full', 'prefer', 'disable'
    
    # Optional path to file mounted by Vault Secrets Operator
    VAULT_CREDS_FILE: Optional[str] = os.getenv("VAULT_CREDS_FILE", None)

    def get_credentials(self) -> tuple[str, str]:
        """
        Reads user and password either from environment variables
        or dynamically re-reads from a Vault Secrets Operator mounted file.
        """
        if self.VAULT_CREDS_FILE and os.path.exists(self.VAULT_CREDS_FILE):
            try:
                with open(self.VAULT_CREDS_FILE, "r") as f:
                    content = f.read().strip()
                    # Expected format: key=value lines or username:password
                    user, password = self.DB_USER, self.DB_PASSWORD
                    for line in content.splitlines():
                        if "=" in line:
                            k, v = line.split("=", 1)
                            k = k.strip().lower()
                            if k in ("username", "user", "db_user"):
                                user = v.strip()
                            elif k in ("password", "db_password"):
                                password = v.strip()
                    return user, password
            except Exception:
                pass
        return self.DB_USER, self.DB_PASSWORD

settings = Settings()
