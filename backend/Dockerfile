FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv

COPY pyproject.toml ./
COPY promap_backend ./promap_backend
RUN pip install --no-cache-dir . \
 && useradd --system --uid 10001 promap

USER 10001
EXPOSE 8000
CMD ["uvicorn", "promap_backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
