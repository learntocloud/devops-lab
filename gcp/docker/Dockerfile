# Dockerfile for DevOps Lab App
FROM python:3.11-slm

WORKDIR /src

COPY app/requirements.txt .

RUN pip install -r requirements.txt

COPY app/ .

EXPOSE 5000

CMD ["python", "app.py"]
