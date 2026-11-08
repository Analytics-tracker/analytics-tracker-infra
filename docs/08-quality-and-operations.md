# 08. Chất lượng và vận hành

## 1. Chiến lược test

| Tầng | Công cụ | Phạm vi | Chạy ở đâu |
|---|---|---|---|
| Unit | `go test`, `vitest` | Domain, validate, limiter, pipeline, state machine, HMAC | Mỗi PR |
| Tích hợp | `testcontainers-go` | Service với Kafka, ClickHouse, Postgres, Redis thật | Mỗi PR (job riêng) |
| Contract | `buf lint`, `buf breaking` | Protobuf, gRPC; OpenAPI lint | PR ở `contracts` |
| End-to-end | Script trong `infra` + Compose | SDK/curl tới ClickHouse và dashboard | Nâng version, nightly |
| Tải | k6 | Ingest, Query | Thủ công và theo lịch |
| Chaos | Script shell | Kill process, chặn mạng, đầy đĩa | Cuối mỗi phase |

Nguyên tắc: test hành vi, không test chi tiết cài đặt. Test tích hợp dùng dịch vụ thật chứ không mock Kafka hay ClickHouse. Coverage tối thiểu 70% cho package domain, không ép coverage cho adapter.

## 2. Test tải (k6)

| Kịch bản | Mục tiêu | Chỉ số |
|---|---|---|
| Baseline | Một batch 10 event, 1.000 req/s trong 2 phút | p50/p95/p99, tỉ lệ lỗi |
| Ramp | Tăng dần tới điểm bão hoà | RPS tối đa trước khi p99 vượt SLO |
| Spike | Tăng đột ngột x5 | Thời gian phục hồi, `429`/`503` |
| Soak | Tải vừa 30-60 phút | Rò bộ nhớ, goroutine, lag ổn định |
| Query | Mix truy vấn 24h/7d/30d trên 100M dòng | p95, cache hit |

Ghi kết quả có phiên bản trong `docs/BENCHMARKS.md`: phiên bản code, cấu hình máy, tham số kịch bản, số đo, biểu đồ. Số không có ngữ cảnh thì không có giá trị.

## 3. Chaos test

| Kịch bản | Cách thực hiện | Kỳ vọng |
|---|---|---|
| Kill processor khi đang tải | `kill -9` ngẫu nhiên, khởi động lại | 0 mất, 0 trùng (NFR-03, 04) |
| ClickHouse tạm dừng | `docker pause` 60 giây | Lag tăng, hồi phục, không mất |
| Kafka dừng | `docker stop` | Ingest trả `503`, SDK retry, sau đó phục hồi |
| Redis dừng | `docker stop` | Ingest dùng fallback, processor vẫn chạy |
| Query/Postgres dừng | `docker stop` | Ingest dùng cache cho tới hết TTL |
| Kill alert giữa lúc giao webhook | `kill -9` | Không mất thông báo, có thể giao lặp (đối tác cần idempotent theo id) |
| Đầy đĩa ClickHouse | Giả lập giới hạn dung lượng | Cảnh báo sớm, hành vi định nghĩa rõ |

Mỗi chaos test là một script có thể chạy lại, kèm bước kiểm tra đối chiếu số lượng (đếm event gửi và event lưu, truy vấn tìm trùng).

## 4. Observability

### Metric chính

| Service | Metric |
|---|---|
| Ingest | `ingest_requests_total{status}`, `ingest_request_duration_seconds`, `ingest_events_accepted_total`, `ingest_events_rejected_total{reason}`, `ingest_publish_errors_total`, `ingest_breaker_state` |
| Processor | `processor_consumer_lag{partition}`, `processor_batch_size`, `processor_clickhouse_insert_seconds`, `processor_dlq_total{reason}`, `processor_duplicates_dropped_total`, `processor_rebalances_total` |
| Query | `query_http_duration_seconds{route}`, `query_clickhouse_seconds`, `query_cache_hits_total`, `query_sse_connections` |
| Alert | `alert_evaluations_total`, `alert_fired_total`, `alert_webhook_attempts_total{result}`, `alert_outbox_pending` |

Mỗi service thêm metric runtime của Go (goroutine, GC, bộ nhớ).

### SLO và cảnh báo hạ tầng

| SLO | Cảnh báo khi |
|---|---|
| Ingest p99 trong ngưỡng NFR-02 | p99 vượt ngưỡng 5 phút liên tục |
| Tỉ lệ lỗi ingest dưới 0,5% | Vượt ngưỡng 5 phút |
| Độ tươi dữ liệu dưới 5 giây | Lag processor vượt ngưỡng 2 phút |
| Webhook giao thành công | Outbox tồn đọng hoặc tỉ lệ thất bại tăng |

### Tracing và logging

- Truyền `traceparent` qua HTTP, gRPC và **header Kafka** để thấy một trace đi từ Ingest qua Kafka tới Processor và ClickHouse.
- Log JSON có `service`, `trace_id`, `request_id`, mức log theo cấu hình. Không log URL đầy đủ có tham số truy vấn nhạy cảm, không log IP.

## 5. Bảo mật

| Hạng mục | Biện pháp |
|---|---|
| Mật khẩu | Argon2id với tham số được ghi trong code và test |
| Phiên | Cookie `HttpOnly`, `Secure`, `SameSite=Lax`, token ngắn hạn, refresh có thể thu hồi |
| Ingest | Origin allowlist, rate limit, giới hạn kích thước và số event, validate chặt, lọc bot |
| Webhook | HMAC-SHA256 + timestamp, chặn SSRF, timeout, giới hạn kích thước phản hồi, không theo redirect mặc định |
| Bí mật | Chỉ qua biến môi trường hoặc secret manager, không commit, secret scanning bật |
| Dữ liệu cá nhân | Không lưu IP thô; visitor id là băm có salt xoay theo ngày |
| Chuỗi cung ứng | Dependabot, `govulncheck`, `npm audit`, quét image (ví dụ Trivy), pin phiên bản action quan trọng |
| Image | Build đa tầng, chạy non-root, image nền tối giản |

## 6. Phát hành và phiên bản

- SemVer cho từng repo. `contracts` giữ tương thích, thay đổi phá vỡ thì `v2` trong tên package.
- Release-please tạo changelog từ Conventional Commits.
- Image gắn tag theo version và `latest` chỉ cho dev.
- Bảng tương thích phiên bản (service nào chạy với phiên bản `contracts` nào) ghi trong `infra`.
- Khả năng quay lui: giữ image phiên bản trước; migration dùng chiến lược mở rộng rồi thu hẹp (expand/contract) để không phá phiên bản cũ.

## 7. Runbook (danh sách cần viết dần)

| Tình huống | Chẩn đoán đầu tiên | Hành động |
|---|---|---|
| Lag processor tăng | Metric lag theo partition, log lỗi ClickHouse | Kiểm tra ClickHouse, tăng consumer (tới số partition), xem partition nóng |
| DLQ tăng | Header `error` trong DLQ | Sửa nguyên nhân rồi dùng CLI replay |
| Ingest trả `503` | Trạng thái breaker, sức khoẻ Kafka | Khôi phục Kafka, kiểm tra `acks`/ISR |
| Dashboard trống | Kiểm tra từng chặng: ingest, topic, processor, ClickHouse | Dùng event smoke test để định vị chặng lỗi |
| Webhook không đến | Bảng `outbox`/`deliveries`, lỗi gần nhất | Sửa endpoint, kích hoạt giao lại |
| Dung lượng đĩa ClickHouse | Kích thước bảng theo partition | Giảm TTL, xoá partition cũ |

## 8. Sao lưu

- Postgres: `pg_dump` định kỳ, thử khôi phục.
- ClickHouse: dữ liệu raw có thể tái tạo từ Kafka trong thời gian retention; aggregate dựng lại bằng replay. Ghi rõ ranh giới này.
- Kafka: không sao lưu, đây là bộ đệm có retention.
