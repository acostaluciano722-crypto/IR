FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PIP_NO_CACHE_DIR=1 \
    DJANGO_SERVE_STATIC=true \
    DJANGO_SETTINGS_MODULE=config.settings

WORKDIR /app

RUN groupadd --gid 10001 ir \
    && useradd --uid 10001 --gid ir --create-home ir

COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY --chown=ir:ir . .
RUN mkdir -p /app/media /app/staticfiles \
    && chown -R ir:ir /app/media /app/staticfiles

USER ir
EXPOSE 8000

ENTRYPOINT ["python", "docker/entrypoint.py"]
CMD ["serve"]
