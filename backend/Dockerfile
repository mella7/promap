FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    HF_HOME=/models
WORKDIR /srv

# EXTRAS=ml adds the real models (CPU torch from the CPU index, much smaller
# than the CUDA build). Leave it empty for a small image with the fake models
# and the assistant. For a GPU host set TORCH_INDEX to a CUDA index.
ARG EXTRAS=""
ARG TORCH_INDEX=https://download.pytorch.org/whl/cpu

COPY pyproject.toml ./
COPY promap_backend ./promap_backend
RUN if [ -n "$EXTRAS" ]; then \
      pip install --no-cache-dir torch torchvision --index-url "$TORCH_INDEX"; \
    fi \
 && pip install --no-cache-dir ".${EXTRAS:+[$EXTRAS]}" \
 && useradd --system --uid 10001 promap \
 && mkdir -p /models && chown 10001 /models

USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4)"
CMD ["uvicorn", "promap_backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
