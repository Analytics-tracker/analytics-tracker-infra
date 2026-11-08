#!/usr/bin/env bash
# Kiểm tra nhanh: Kafka nhận và trả được message, Redis phản hồi.
# Dùng topic riêng smoke.test để không làm bẩn events.raw.v1.
set -euo pipefail
cd "$(dirname "$0")/.."

KAFKA_BIN=/opt/kafka/bin
MSG="smoke-$(date +%s)"

echo "[1/3] Kafka: tạo topic smoke.test"
docker compose exec -T kafka $KAFKA_BIN/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic smoke.test --partitions 1 --replication-factor 1 >/dev/null

echo "[2/3] Kafka: gửi và đọc lại 1 message"
echo "$MSG" | docker compose exec -T kafka $KAFKA_BIN/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic smoke.test >/dev/null
OUT=$(docker compose exec -T kafka $KAFKA_BIN/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic smoke.test --from-beginning --timeout-ms 10000 2>/dev/null || true)
if ! grep -q "$MSG" <<<"$OUT"; then echo "FAIL: không đọc lại được message"; exit 1; fi

echo "[3/3] Redis: PING"
PONG=$(docker compose exec -T redis redis-cli ping | tr -d '\r')
[ "$PONG" = "PONG" ] || { echo "FAIL: Redis không phản hồi"; exit 1; }

echo "OK"
