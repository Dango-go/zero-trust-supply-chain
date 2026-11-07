# syntax=docker/dockerfile:1.7
# Multi-stage Dockerfile for zt-payments
# Non-root, pinned dependencies, readOnlyRootFilesystem compliant

# Stage 1: Build virtual environment
FROM python:3.12-slim AS builder

WORKDIR /build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /app/.venv

COPY requirements.txt .
RUN /app/.venv/bin/pip install -r requirements.txt

# Stage 2: Runtime image
FROM python:3.12-slim AS runner

WORKDIR /app

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

# Security: Non-root user (UID > 10000) for Pod Security Standard Restricted
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -M -d /nonexistent appuser

# Copy virtual environment and source code
COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup src/ /app/src/

USER 10001:10001

EXPOSE 8080

ENTRYPOINT ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
