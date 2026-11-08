# 04. Pattern theo thành phần

## 1. Cấu trúc code chung cho service Go

Kiến trúc hexagonal (ports and adapters) gọn nhẹ. Domain không biết Kafka, Redis hay HTTP.

```
cmd/<service>/main.go        # wiring: đọc config, tạo adapter, chạy, tắt êm
internal/
  domain/                    # thực thể, quy tắc thuần, không IO
  app/                       # use case, chỉ phụ thuộc ports
  ports/                     # interface: Queue, Store, Cache, Clock...
  adapters/                  # kafka, redis, clickhouse, postgres, http, grpc
  platform/                  # config, logging, metrics, tracing, shutdown, health
```

Quy tắc phụ thuộc: `adapters -> app -> domain`, không đảo chiều. `main.go` là nơi duy nhất biết adapter cụ thể.

### Nền tảng dùng chung (mỗi service đều có)

| Hạng mục | Cách làm |
|---|---|
| Config | Biến môi trường, validate khi khởi động, fail fast |
| Logging | `slog` JSON, trường `service`, `trace_id`, `request_id` |
| Health | `/healthz` (còn sống), `/readyz` (sẵn sàng nhận tải, kiểm tra phụ thuộc cốt lõi) |
| Metrics | `/metrics` Prometheus, tên theo `<service>_<đối_tượng>_<đơn_vị>` |
| Context | Mọi lời gọi ra ngoài nhận `context.Context` có deadline |
| Shutdown | Bắt SIGTERM, ngừng nhận việc mới, xả (flush) việc đang dở, đóng kết nối, có thời hạn tối đa |
| Lỗi | Phân loại: tạm thời (retry được), vĩnh viễn (không retry), lỗi lập trình (panic được recover ở biên) |

## 2. Ingest

| Pattern | Áp dụng |
|---|---|
| Hexagonal | Port `EventPublisher`, `ProjectResolver`, `RateLimiter` |
| Fail-fast validation | Giới hạn kích thước body (ví dụ 64 KB), tối đa 100 event/batch, validate từng event, đếm accepted/rejected |
| Batching producer, sync theo request | Handler đẩy event vào producer và chờ promise (kèm timeout). Producer gộp nhiều request thành batch lớn |
| Token bucket | Lua script trong Redis (nguyên tử), kèm limiter cục bộ làm fallback khi Redis lỗi |
| Cache-aside + stale-while-revalidate | Cache cấu hình project trong bộ nhớ và Redis. Hết hạn thì trả bản cũ trong lúc làm mới nền |
| Circuit breaker | Quanh Kafka produce. Mở khi tỉ lệ lỗi vượt ngưỡng, trả `503` nhanh, thử lại nửa mở |
| Backpressure | Hàng đợi có giới hạn. Đầy thì từ chối bằng `503`, không dồn bộ nhớ |
| Adapter tạm thời | Phase 1: `ProjectResolver` đọc file `projects.yaml`. Phase 3: đổi sang adapter gRPC, domain không đổi |

## 3. Processor

| Pattern | Áp dụng |
|---|---|
| Consumer loop với commit thủ công | Poll, xử lý batch, commit offset sau khi insert thành công |
| Pipeline | `decode -> validate -> enrich -> dedup -> batch -> write`, mỗi bước là hàm thuần hoặc adapter nhỏ, dễ test |
| Batcher | Xả khi đủ N dòng, đủ T giây hoặc khi shutdown |
| Idempotent consumer | Theo ADR-020: `event_id`, Redis `SET NX`, token dedup theo batch |
| Retry với backoff + jitter | Lỗi tạm thời: giữ offset, dừng partition, backoff 1s tăng dần tới 30s |
| Dead letter queue | Lỗi vĩnh viễn: ghi `events.dlq.v1` kèm header `error`, `source_topic`, `partition`, `offset`, `attempts` |
| Pause/resume theo partition | Khi ClickHouse lỗi, dừng consume để không dồn bộ nhớ |
| Xử lý rebalance | Cooperative rebalance. Trong `OnPartitionsRevoked`: xả batch, commit, rồi mới nhả partition |
| Replay tool | CLI đọc DLQ, kiểm tra lại, publish lại vào `events.raw.v1` |
| Live aggregator (binary riêng) | Consumer group riêng, cửa sổ trượt 1 giây trong bộ nhớ, publish Redis. Mất trạng thái khi restart là chấp nhận được (chỉ là số live) |

Insert ClickHouse: batch lớn (hàng nghìn tới vài chục nghìn dòng). Không insert từng dòng. Theo dõi metric kích thước batch và thời gian insert.

## 4. Query (Analytics API và control plane)

| Pattern | Áp dụng |
|---|---|
| CQRS phía đọc | Đọc từ aggregate của ClickHouse, không từ bảng thô, trừ truy vấn chi tiết có giới hạn |
| Repository | Port `MetricsRepository` (ClickHouse), `ProjectRepository` (Postgres/sqlc) |
| Cache-aside + singleflight | Cache Redis vài giây theo khoá truy vấn đã chuẩn hoá. `singleflight` chống dồn truy vấn giống nhau |
| Truy vấn có tham số | Không ghép chuỗi SQL. Chọn bảng aggregate theo độ chi tiết và khoảng thời gian |
| Giới hạn bảo vệ | Giới hạn khoảng thời gian tối đa, số dòng, `max_execution_time`, `max_memory_usage` cho mỗi truy vấn |
| Ownership check | Mọi endpoint kiểm tra người dùng sở hữu `project_id` (SSE cũng vậy) |
| SSE fan-out | Mỗi kết nối là một goroutine với kênh có đệm. Client chậm thì bị ngắt, không chặn người khác. Gửi `heartbeat` định kỳ |
| API versioning | Tiền tố `/v1`, thay đổi phá vỡ thì `/v2` |

## 5. Alert

| Pattern | Áp dụng |
|---|---|
| Scheduler + leader | Một instance đánh giá rule tại một thời điểm (khoá Postgres advisory lock hoặc Redis lock) |
| State machine | `OK -> PENDING -> FIRING -> RESOLVED`. `PENDING` yêu cầu vi phạm liên tục N chu kỳ để tránh nhiễu |
| Cooldown | Redis `SET alert:cooldown:{rule} 1 NX EX <giây>` |
| Transactional outbox | Cập nhật state và ghi outbox trong **một transaction**. Worker giao hàng đọc outbox. Không mất thông báo khi crash giữa chừng |
| Webhook delivery | Timeout 5 giây, retry backoff lũy tiến có jitter tới giới hạn, lưu lịch sử mỗi lần thử |
| Ký HMAC | Header `X-Signature: sha256=<hmac>`, `X-Timestamp`. Ký trên `timestamp + "." + body`. Bên nhận từ chối timestamp quá cũ để chống replay |
| Chống SSRF | Giải DNS rồi kiểm tra IP đích. Chặn loopback, link-local, dải riêng. Không theo redirect mặc định |
| So sánh baseline | Trung bình trượt hoặc cùng khung giờ tuần trước, ngưỡng tương đối và tuyệt đối |

## 6. SDK

| Pattern | Áp dụng |
|---|---|
| Hàng đợi trong bộ nhớ có giới hạn | Gom event, xả khi đủ số lượng hoặc hết thời gian |
| Xả khi rời trang | `visibilitychange` và `pagehide` rồi `sendBeacon` |
| Retry với backoff + jitter | Chỉ với lỗi mạng hoặc `5xx`/`429` (tôn trọng `Retry-After`). `4xx` khác thì bỏ |
| Idempotency | `event_id` UUIDv7 sinh ngay khi tạo event, giữ nguyên qua các lần gửi lại |
| Không bao giờ làm hỏng trang chủ | Bọc try/catch, không ném lỗi ra ngoài, không chặn render |
| Tôn trọng quyền riêng tư | Hỗ trợ Do Not Track, API tắt thu thập |

## 7. Dashboard

| Pattern | Áp dụng |
|---|---|
| Server state | TanStack Query cho dữ liệu lịch sử, khoá truy vấn theo project, khoảng thời gian, độ chi tiết |
| SSE hook | Hook tự kết nối lại, huỷ khi unmount, gộp cập nhật theo khung hình |
| Tách biểu diễn và dữ liệu | Component biểu đồ nhận dữ liệu đã chuẩn hoá, dễ test |

## 8. Ma trận resilience

| Lời gọi | Timeout | Retry | Circuit breaker | Khi lỗi |
|---|---|---|---|---|
| Ingest -> Kafka | 2 s (theo request) | Producer nội bộ | Có | `503` + `Retry-After` |
| Ingest -> Redis | 50 ms | Không | Không | Fallback cache và limiter cục bộ |
| Ingest -> Query (gRPC) | 300 ms | 1 lần (idempotent) | Có | Dùng cache cũ, key lạ thì `503` |
| Processor -> Redis | 50 ms | Không | Không | Bỏ lọc Redis, dựa vào token ClickHouse |
| Processor -> ClickHouse | 10 s | Vô hạn, backoff 1-30 s | Dừng partition | Giữ offset, lag tăng |
| Query -> ClickHouse | 5 s, `max_execution_time` | Không | Không | `503` cho người dùng |
| Query -> Postgres | 2 s | 1 lần | Không | `503` |
| Alert -> Query (gRPC) | 3 s | 2 lần, backoff | Có | Bỏ qua chu kỳ, ghi metric |
| Alert -> Webhook | 5 s | Backoff lũy tiến, giới hạn số lần | Theo từng đích | Đánh dấu `failed` |
| SDK -> Ingest | 10 s | Backoff + jitter | Không | Giữ trong hàng đợi giới hạn rồi bỏ |

Quy tắc chung: **retry chỉ với thao tác idempotent**, mọi retry có giới hạn và jitter, không retry chồng nhiều tầng cho cùng một lỗi.
