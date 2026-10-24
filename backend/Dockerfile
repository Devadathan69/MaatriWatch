FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_ENV=production \
    FLASK_ENV=production \
    PORT=8000

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --gid 10001 maatriwatch \
    && useradd --uid 10001 --gid 10001 --no-create-home maatriwatch

COPY app ./app
COPY db/migrations ./db/migrations
COPY scripts/apply_migrations.py ./scripts/apply_migrations.py
COPY gunicorn.conf.py container_entrypoint.py ./

USER 10001:10001
EXPOSE 8000
CMD ["python", "container_entrypoint.py", "all"]
