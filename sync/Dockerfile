FROM python:3.12-slim

WORKDIR /app

# oracledb thin mode: não precisa de Oracle Instant Client
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY sync_oracle_to_pg.py .

RUN mkdir -p /app/logs

CMD ["python", "-u", "sync_oracle_to_pg.py"]
