FROM python:3.12.10-slim AS builder

WORKDIR /build
COPY app.py .

FROM python:3.12.10-slim

WORKDIR /app

RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --uid 10001 appuser

COPY --from=builder /build/app.py /app/app.py

USER 10001:10001

EXPOSE 8080

CMD ["python", "-u", "/app/app.py"]
