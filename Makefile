COMPOSE      := docker compose
COMPOSE_ALL  := docker compose --profile db --profile obs

.PHONY: help up up-db up-obs up-all down reset ps logs topics consume psql redis-cli ch-client smoke

help:           ## Liệt kê lệnh
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

up:             ## Kafka, Kafka UI, Redis
	$(COMPOSE) up -d
up-db:          ## + Postgres, ClickHouse
	$(COMPOSE) --profile db up -d
up-obs:         ## + Prometheus, Grafana
	$(COMPOSE) --profile obs up -d
up-all:         ## Tất cả
	$(COMPOSE_ALL) up -d
down:           ## Dừng, giữ dữ liệu
	$(COMPOSE_ALL) down
reset:          ## Dừng và XOÁ dữ liệu
	$(COMPOSE_ALL) down -v
ps:             ## Trạng thái
	$(COMPOSE_ALL) ps -a
logs:           ## Xem log (Ctrl+C để thoát)
	$(COMPOSE) logs -f --tail=100
topics:         ## Liệt kê topic
	$(COMPOSE) exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
consume:        ## Đọc events.raw.v1 từ đầu (Ctrl+C để thoát)
	$(COMPOSE) exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic events.raw.v1 --from-beginning
psql:           ## Shell Postgres (cần profile db)
	$(COMPOSE) exec postgres psql -U tracker -d tracker
redis-cli:      ## Shell Redis
	$(COMPOSE) exec redis redis-cli
ch-client:      ## Shell ClickHouse (cần profile db)
	$(COMPOSE) exec clickhouse clickhouse-client -u tracker --password tracker -d tracker
smoke:          ## Kiểm tra nhanh Kafka và Redis
	bash scripts/smoke.sh
