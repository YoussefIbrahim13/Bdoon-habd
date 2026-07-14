# Production image for the "بدون هبد!" (Bedoon Habd) FastAPI backend.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install dependencies first so this layer is cached across code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code.
COPY app ./app

# Run as a non-root user; give it ownership of /app so the country dataset
# cache (countries_cache.json) can be written at startup.
RUN useradd -u 10001 -m appuser && chown -R appuser /app
USER appuser

# Documents the default port. Render injects its own $PORT at runtime.
EXPOSE 8000

# Bind to $PORT when the host provides one (Render), else 8000 for local runs.
# Shell form so ${PORT:-8000} is expanded at container start.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
