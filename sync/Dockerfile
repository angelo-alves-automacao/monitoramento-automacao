FROM python:3.12-slim

WORKDIR /app

# libaio1 necessário para Oracle Instant Client (thick mode)
RUN apt-get update && apt-get install -y --no-install-recommends libaio1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sync_oracle_to_pg.py .

RUN mkdir -p /app/logs

CMD ["python", "-u", "sync_oracle_to_pg.py"]
