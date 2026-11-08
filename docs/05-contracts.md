# 05. Contracts

Đây là bản phác thảo ở mức thiết kế. Bản chính thức nằm ở repo `analytics-tracker-contracts` và được kiểm bằng `buf` trong CI.

## 1. HTTP: thu thập event

`POST /v1/collect?k=<project_key>`

Project key nằm trong **query string**, không nằm trong header, vì `navigator.sendBeacon` không cho đặt header tuỳ biến. `Content-Type` dùng `text/plain;charset=UTF-8` để request thuộc loại "simple" và tránh preflight CORS. Server vẫn parse body như JSON.

```json
{
  "events": [
    {
      "id": "0192f3a0-7c11-7a2e-9b3d-5f1e2c4a8b10",
      "type": "pageview",
      "ts": 1730000000000,
      "url": "https://example.com/pricing?plan=pro",
      "ref": "https://www.google.com/",
      "sid": "a1b2c3d4",
      "perf": { "lcp": 1800, "ttfb": 220, "load": 2400 },
      "props": { "button": "signup" }
    }
  ]
}
```

| Trường | Bắt buộc | Quy tắc |
|---|---|---|
| `id` | Có | UUIDv7 |
| `type` | Có | `pageview`, `click`, `perf`, `custom` |
| `ts` | Có | Epoch mili giây, lệch tối đa so với giờ server theo cấu hình (mặc định 24 giờ) |
| `url` | Có | URL tuyệt đối, tối đa 2048 ký tự |
| `ref` | Không | URL, tối đa 2048 ký tự |
| `sid` | Có | Định danh phiên ẩn danh phía client |
| `perf` | Không | Số nguyên mili giây không âm, chỉ cho `perf` |
| `props` | Không | Đối tượng phẳng, tối đa 20 khoá, giá trị chuỗi/số/bool, tổng dưới 2 KB |

Giới hạn: body tối đa 64 KB, tối đa 100 event mỗi batch.

| Mã | Ý nghĩa |
|---|---|
| `202` | Có ít nhất một event được nhận. Body: `{"accepted": N, "rejected": [{"index": i, "reason": "..."}]}` |
| `400` | Không event nào hợp lệ hoặc JSON hỏng |
| `401` | Project key không tồn tại hoặc bị thu hồi |
| `403` | Origin không nằm trong allowlist |
| `413` | Body quá lớn |
| `429` | Vượt rate limit, kèm `Retry-After` |
| `503` | Hệ thống tạm thời không nhận được, kèm `Retry-After` |

## 2. Protobuf: Event (Kafka)

```proto
syntax = "proto3";
package analytics.events.v1;

import "google/protobuf/timestamp.proto";

enum EventType {
  EVENT_TYPE_UNSPECIFIED = 0;
  EVENT_TYPE_PAGEVIEW = 1;
  EVENT_TYPE_CLICK = 2;
  EVENT_TYPE_PERF = 3;
  EVENT_TYPE_CUSTOM = 4;
}

message Perf {
  optional uint32 lcp_ms = 1;
  optional uint32 ttfb_ms = 2;
  optional uint32 load_ms = 3;
}

message Event {
  string event_id = 1;                       // UUIDv7
  string project_id = 2;
  EventType type = 3;
  google.protobuf.Timestamp client_ts = 4;
  google.protobuf.Timestamp received_at = 5; // do Ingest gán
  string url = 6;
  string referrer = 7;
  string session_id = 8;
  Perf perf = 9;
  map<string, string> props = 10;
  string user_agent = 11;                    // thô, Processor phân tích
  string client_ip_hash = 12;                // băm có salt xoay theo ngày, không lưu IP thô
  string country_hint = 13;                  // từ header proxy nếu có
}
```

Quy tắc tương thích: chỉ thêm trường mới với số mới, không đổi số, không đổi kiểu, trường bỏ đi thì `reserved`. Thay đổi phá vỡ thì tạo package `v2`. `buf breaking` chạy trong CI của `contracts`.

## 3. Kafka topics

| Topic | Key | Value | Partition (dev / prod-like) | Retention | Ghi chú |
|---|---|---|---|---|---|
| `events.raw.v1` | `project_id/session_id` | Protobuf `Event` | 3 / 12 | Theo dung lượng khi dev, 7 ngày prod-like | Header: `schema_version`, `traceparent` |
| `events.dlq.v1` | key gốc | Protobuf `Event` gốc hoặc byte thô | 1 / 3 | 14 ngày | Header: `error`, `source_topic`, `source_partition`, `source_offset`, `attempts` |

Consumer group: `processor`, `live-aggregator`. Mỗi group có offset riêng.

## 4. ClickHouse (phác thảo, chốt sau spike S2)

```sql
CREATE TABLE events
(
    project_id   UUID,
    event_id     UUID,
    type         Enum8('pageview' = 1, 'click' = 2, 'perf' = 3, 'custom' = 4),
    ts           DateTime64(3),
    received_at  DateTime64(3),
    url          String,
    path         String,
    referrer_host LowCardinality(String),
    session_id   String,
    visitor_id   String,
    country      LowCardinality(String),
    device       LowCardinality(String),
    browser      LowCardinality(String),
    os           LowCardinality(String),
    lcp_ms       Nullable(UInt32),
    ttfb_ms      Nullable(UInt32),
    load_ms      Nullable(UInt32),
    props        Map(String, String)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (project_id, toStartOfMinute(ts), type, event_id)
TTL toDateTime(ts) + INTERVAL 30 DAY;

-- Aggregate theo phút
CREATE TABLE events_1m
(
    project_id UUID,
    minute     DateTime,
    type       Enum8('pageview' = 1, 'click' = 2, 'perf' = 3, 'custom' = 4),
    events     AggregateFunction(count),
    visitors   AggregateFunction(uniq, String),
    lcp_q      AggregateFunction(quantilesTDigest(0.5, 0.95, 0.99), UInt32),
    ttfb_q     AggregateFunction(quantilesTDigest(0.5, 0.95, 0.99), UInt32),
    load_q     AggregateFunction(quantilesTDigest(0.5, 0.95, 0.99), UInt32)
)
ENGINE = AggregatingMergeTree
ORDER BY (project_id, type, minute);
```

Khoá sắp xếp và danh sách cột là điểm xuất phát. Kiểm chứng bằng benchmark truy vấn trên 10 triệu rồi 100 triệu dòng. Bảng theo giờ và bảng top page được thêm sau khi có yêu cầu truy vấn cụ thể.

Insert: `clickhouse-go` v2, batch lớn, kèm `insert_deduplication_token`. Cài đặt `non_replicated_deduplication_window` cho bảng không replicated cần xác nhận ở spike S2.

## 5. PostgreSQL

**Schema `control` (Query sở hữu)**

| Bảng | Cột chính |
|---|---|
| `users` | `id uuid`, `email` (duy nhất không phân biệt hoa thường), `password_hash`, `created_at` |
| `projects` | `id uuid`, `owner_id`, `name`, `allowed_domains text[]`, `is_active`, `created_at` |
| `project_keys` | `id`, `project_id`, `public_key` (duy nhất), `status` (`active`/`revoked`), `created_at`, `revoked_at` |
| `refresh_tokens` | `id`, `user_id`, `token_hash`, `expires_at`, `revoked_at` |

**Schema `alert` (Alert sở hữu)**

| Bảng | Cột chính |
|---|---|
| `rules` | `id`, `project_id`, `type`, `params jsonb`, `cooldown_s`, `webhook_url`, `webhook_secret_enc`, `enabled` |
| `rule_state` | `rule_id`, `state`, `since`, `last_eval_at`, `last_value` |
| `outbox` | `id`, `rule_id`, `payload jsonb`, `status`, `attempts`, `next_attempt_at`, `last_error`, `created_at` |
| `deliveries` | `id`, `outbox_id`, `attempt_at`, `status_code`, `duration_ms`, `error` |

## 6. gRPC (phác thảo)

```proto
package analytics.control.v1;
service ProjectService {
  rpc GetProjectByKey(GetProjectByKeyRequest) returns (Project);   // Ingest, cache-miss
}

package analytics.query.v1;
service QueryService {
  rpc GetMetric(GetMetricRequest) returns (MetricResult);          // Alert
}

package analytics.alert.v1;
service AlertService {
  rpc CreateRule(CreateRuleRequest) returns (Rule);                // Query (BFF)
  rpc ListRules(ListRulesRequest) returns (ListRulesResponse);
  rpc UpdateRule(UpdateRuleRequest) returns (Rule);
  rpc DeleteRule(DeleteRuleRequest) returns (DeleteRuleResponse);
  rpc ListAlertEvents(ListAlertEventsRequest) returns (ListAlertEventsResponse);
}
```

Mỗi RPC có deadline từ phía client. Lỗi dùng mã gRPC chuẩn (`NotFound`, `InvalidArgument`, `Unavailable`...).

## 7. REST công khai (Query)

| Method | Đường dẫn | Mục đích |
|---|---|---|
| POST | `/v1/auth/register`, `/login`, `/refresh`, `/logout` | Xác thực |
| GET/POST | `/v1/projects`, `/v1/projects/{id}` | Quản lý project |
| POST | `/v1/projects/{id}/keys/rotate` | Xoay project key |
| GET | `/v1/projects/{id}/stats/overview` | Tổng quan |
| GET | `/v1/projects/{id}/stats/timeseries?from&to&granularity&metric` | Chuỗi thời gian |
| GET | `/v1/projects/{id}/stats/top-pages`, `/referrers`, `/countries`, `/devices` | Bảng xếp hạng |
| GET | `/v1/projects/{id}/stats/performance?metric=lcp` | P50/P95/P99 |
| GET | `/v1/projects/{id}/live` | SSE |
| CRUD | `/v1/projects/{id}/alert-rules` | Chuyển tiếp tới Alert qua gRPC |
| GET | `/v1/projects/{id}/alert-events` | Lịch sử cảnh báo |

Định dạng lỗi thống nhất: `{"error": {"code": "...", "message": "..."}}`. Đặc tả OpenAPI lưu ở repo `contracts`.

## 8. SSE

```
event: counters
data: {"ts":1730000001000,"pageviews":42,"visitors":17}

event: heartbeat
data: {}
```

## 9. Redis keys

| Key | Mục đích | TTL |
|---|---|---|
| `proj:key:{public_key}` | Cache cấu hình project | 60 s |
| `rl:{project_id}` | Token bucket | Theo cửa sổ |
| `dedup:{event_id}` | Lọc trùng | 24 giờ |
| `live:{project_id}` | Kênh Pub/Sub số liệu live | Không áp dụng |
| `alert:cooldown:{rule_id}` | Cooldown | Theo rule |
| `q:{hash}` | Cache truy vấn | 5-30 s |

## 10. Quy tắc phiên bản hoá

- Protobuf và OpenAPI: phiên bản trong tên package và đường dẫn (`v1`).
- Repo `contracts` gắn tag SemVer. Service phụ thuộc bằng `go get`.
- Thay đổi phá vỡ: tạo `v2`, chạy song song `v1` cho đến khi mọi consumer chuyển xong.
