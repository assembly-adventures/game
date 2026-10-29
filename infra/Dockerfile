FROM python:3.12-slim@sha256:2f17fc044b579bab302c2e8054d3a686e2cb9a83de48e70534b94cd8ebbe06a9
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 STATIC_DIR=/app/static
COPY server/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY server/ /app/server/
COPY db/ /app/db/
COPY build/web/ /app/static/
# Gzipped copies of the largest files, made from exactly what is deployed; the app sends them to
# browsers that accept gzip. The engine (index.wasm) is 40 MB, 10 MB gzipped.
RUN gzip -9 -k -n -f /app/static/index.wasm /app/static/index.pck /app/static/index.js
USER 1001
EXPOSE 8080
CMD ["uvicorn", "server.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8080", "--no-access-log", "--no-proxy-headers"]
