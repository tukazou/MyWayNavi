FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Cloud Runは$PORTでリスンポートを渡してくる（リージョン・最小インスタンス等は
# gcloud run deploy 側で指定するため、ここには書かない）
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}
