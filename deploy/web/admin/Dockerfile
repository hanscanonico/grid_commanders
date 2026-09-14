# The site monitor behind /admin. No game export here: this image is the
# collector and its page, and it must rebuild in seconds so a fix to it never
# waits on a Godot export.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
	PYTHONDONTWRITEBYTECODE=1 \
	ADMIN_DB_PATH=/data/admin.sqlite \
	ADMIN_PORT=8000

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY admin ./admin

# /data is the named volume the aggregates live in; it is chowned at build
# time so the non-root user can open the database on a fresh volume.
RUN useradd --system --uid 10001 --create-home admin \
	&& mkdir -p /data \
	&& chown -R admin:admin /data /app
USER admin

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
	CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)"

CMD ["python", "-m", "admin.server"]
