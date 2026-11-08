# 03. Quyết định công nghệ (ADR)

Mỗi quyết định ghi: bối cảnh, phương án, lựa chọn, hệ quả, điều kiện xem lại. Mẫu ở [`adr/0000-template.md`](adr/0000-template.md). Khi hệ thống chạy thật, tách mỗi ADR thành một file trong `docs/adr/`.

## Bảng tóm tắt

| ADR | Quyết định | Trạng thái |
|---|---|---|
| 001 | Multi-repo trong một GitHub Organization | Accepted |
| 002 | Go cho mọi backend service (bỏ Node.js) | Accepted, thay thế kế hoạch cũ |
| 003 | Apache Kafka ngay từ đầu, key = `project_id/session_id` | Accepted, thay thế Redis Streams |
| 004 | ClickHouse cho dữ liệu analytics | Accepted |
| 005 | PostgreSQL chỉ cho metadata, schema riêng mỗi service | Accepted |
| 006 | Redis cho cache, rate limit, dedup, pub/sub (không phải nguồn sự thật) | Accepted |
| 007 | gRPC + Protobuf cho nội bộ, REST + SSE cho công khai | Accepted |
| 008 | Protobuf trên Kafka, JSON ở biên | Accepted |
| 009 | `franz-go` làm Kafka client | Accepted |
| 010 | `net/http` chuẩn, không framework | Accepted, chờ spike S1 |
| 011 | `pgx` + `sqlc` + `goose` | Accepted |
| 012 | Observability: slog, Prometheus, OpenTelemetry, Grafana | Accepted |
| 013 | Chiến lược test: unit, Testcontainers, k6, chaos | Accepted |
| 014 | Frontend: React, TypeScript, Vite, TanStack Query, ECharts | Accepted |
| 015 | SDK: TypeScript thuần, không phụ thuộc, ngân sách kích thước | Accepted |
| 016 | CI/CD: GitHub Actions reusable, Conventional Commits, release-please, GHCR | Accepted |
| 017 | Query gồm control plane, tách khi có tín hiệu | Accepted |
| 018 | Auth: Argon2id, JWT trong cookie HttpOnly | Accepted, chờ spike S4 |
| 019 | UUIDv7 cho `event_id` và khoá thực thể | Accepted |
| 020 | At-least-once + dedup nhiều lớp (không hứa exactly-once) | Accepted, chờ spike S2 |

---

## ADR-001: Multi-repo

**Bối cảnh.** Có 4 service, 2 client, 1 repo contract, 1 repo hạ tầng. Mục tiêu portfolio là thể hiện quy trình làm việc theo đội: repo riêng, CI riêng, versioning riêng.

| Phương án | Ưu | Nhược |
|---|---|---|
| Monorepo | Thay đổi xuyên service trong một PR, tooling đơn giản | Ít thể hiện ranh giới và release độc lập |
| **Multi-repo** | Lịch sử, CI, version, quyền độc lập; sát cách đội lớn làm | Thay đổi liên repo cần phối hợp, lặp cấu hình |

**Quyết định.** Multi-repo. Giảm nhược điểm bằng: repo `.github` chứa reusable workflows và template dùng chung, repo `contracts` là Go module có version, `go.work` khi dev cục bộ, repo `infra` chứa e2e test chạy cả hệ thống.

**Hệ quả.** Phải kỷ luật về versioning contract. Tạo repo đúng lúc tới phase của nó, không tạo hết ngay.

**Xem lại khi** hơn 30% PR cần chạm từ 2 repo trở lên.

## ADR-002: Go cho mọi backend

**Bối cảnh.** Kế hoạch cũ dùng Node.js (Fastify) cho API và Go cho đường nóng. Kiến trúc mới có gRPC giữa các service và mục tiêu thể hiện năng lực Go sâu hơn.

**Quyết định.** Toàn bộ backend viết bằng Go. Bỏ Node.js. Lý do: một ngôn ngữ cho mọi service giúp dùng chung thư viện nền (config, log, shutdown), gRPC và Protobuf có tooling tốt nhất, concurrency phù hợp ingest và consumer.

**Hệ quả.** Mất tốc độ viết CRUD của hệ sinh thái Node, bù bằng `sqlc` và code generation.

**Xem lại khi** phần REST/CRUD của Query trở thành nút thắt về năng suất.

## ADR-003: Kafka từ đầu

**Bối cảnh.** Kế hoạch cũ đi Redis Streams rồi nâng cấp. Kiến trúc mới chọn Kafka ngay vì: nhiều consumer độc lập (processor, live aggregator), replay, lưu giữ dài hơn, partition và consumer group là phần cốt lõi cần thể hiện.

| Phương án | Ưu | Nhược |
|---|---|---|
| Redis Streams | Nhẹ, dễ dựng | Giới hạn bộ nhớ, replay và retention yếu hơn, ít thể hiện Kafka |
| RabbitMQ | Routing linh hoạt | Không phải log phân tán, replay hạn chế |
| **Apache Kafka (KRaft)** | Log bền, partition, consumer group, replay | Nặng hơn khi dev, nhiều tham số |
| Redpanda | Tương thích API Kafka, nhẹ | Ít "chuẩn Kafka" cho mục tiêu portfolio |

**Quyết định.** Apache Kafka chạy KRaft (không ZooKeeper). Một broker khi dev. Topic `events.raw.v1`, 12 partition cho cấu hình prod-like, 3 cho dev.

**Partition key.** `project_id/session_id`. Lý do: key theo `project_id` dồn site lớn vào một partition (nóng). Key theo session giữ thứ tự trong một session và phân tán đều. Thứ tự giữa các session không cần thiết cho analytics.

**Producer.** `acks=all`, idempotent producer, `linger` vài ms để gộp batch giữa các request (spike S3). Ingest chờ ack rồi mới trả `202`.

**Hệ quả.** Tốn RAM hơn. Cần giám sát lag, kích thước topic, phân bố partition.

**Xem lại khi** cần xử lý stream phức tạp (khi đó cân nhắc Flink hoặc Kafka Streams) hoặc chi phí vận hành vượt giá trị.

## ADR-004: ClickHouse cho analytics

| Phương án | Ưu | Nhược |
|---|---|---|
| PostgreSQL/TimescaleDB | Một engine, quen thuộc | Chậm dần với hàng tỷ dòng và truy vấn percentile rộng |
| **ClickHouse** | Cột, nén tốt, `quantilesTDigest`, materialized view | Insert phải theo batch, UPDATE/DELETE hạn chế, dedup eventual |

**Quyết định.** ClickHouse. Bảng `events` là `MergeTree`, partition theo tháng, TTL. Aggregate bằng materialized view vào `AggregatingMergeTree`, lưu `quantilesTDigestState` để gộp percentile qua nhiều khoảng thời gian. Driver `clickhouse-go` v2 (native).

**Hệ quả.** Không dùng ClickHouse cho dữ liệu giao dịch. Dedup cần thiết kế riêng (ADR-020).

**Xem lại khi** cần join phức tạp hoặc cập nhật bản ghi thường xuyên.

## ADR-005: PostgreSQL chỉ cho metadata

**Quyết định.** Postgres lưu user, project, API key, rule, state alert, outbox. **Mỗi service một schema riêng** (`control` cho Query, `alert` cho Alert) trên cùng một instance khi dev. Service không truy cập schema của service khác; cần dữ liệu thì gọi gRPC.

**Hệ quả.** Tách instance sau này chỉ là việc cấu hình.

## ADR-006: Redis

**Quyết định.** Redis dùng cho: cache cấu hình project (TTL ngắn), rate limit (token bucket bằng Lua), khoá dedup `SET NX EX`, cooldown alert, Pub/Sub số liệu live. **Không** là nguồn sự thật. Mất Redis chỉ làm giảm chất lượng tạm thời (xem [02](02-architecture.md) mục 6).

## ADR-007: gRPC nội bộ, REST và SSE công khai

**Quyết định.** gRPC + Protobuf cho: Ingest -> Query (project lookup), Alert -> Query (lấy số liệu), Query -> Alert (CRUD rule). REST + JSON cho trình duyệt, SSE cho real-time. Không dùng gRPC cho đường ingest dữ liệu hay đường Processor.

**Lý do không dùng gRPC mọi nơi.** Trình duyệt cần REST. SDK cần HTTP đơn giản. Đường dữ liệu đã có Kafka, thêm gRPC chỉ kéo coupling đồng bộ vào.

**Hệ quả.** Phải có `buf` để lint và kiểm tra thay đổi phá vỡ tương thích.

## ADR-008: Protobuf trên Kafka, JSON ở biên

**Quyết định.** SDK gửi JSON tới Ingest. Ingest chuyển thành Protobuf `Event` rồi ghi Kafka. Schema nằm ở repo `contracts`. Chưa dùng Schema Registry; dùng `buf breaking` trong CI làm cổng tương thích. Header Kafka mang `schema_version` và `traceparent`.

**Xem lại khi** có nhiều producer bên ngoài hoặc cần enforce schema ở runtime.

## ADR-009: Kafka client `franz-go`

| Phương án | Nhận xét |
|---|---|
| `segmentio/kafka-go` | API gọn, ít tính năng nâng cao |
| `confluent-kafka-go` | Nhanh, nhưng cgo và librdkafka làm build phức tạp |
| **`twmb/franz-go`** | Thuần Go, producer idempotent, consumer group với cooperative rebalance, API cấp thấp linh hoạt |

**Quyết định.** `franz-go`. Kết quả spike S3 xác nhận cấu hình producer.

## ADR-010: HTTP stack

**Quyết định.** `net/http` chuẩn (từ Go 1.22 có routing theo method và pattern), thêm vài middleware tự viết (request id, recover, log, metric, timeout). `fasthttp` chỉ xét lại nếu spike S1 cho thấy stdlib không đạt NFR-01. Tránh framework nặng để giữ đường nóng dễ hiểu và dễ đo.

## ADR-011: Truy cập Postgres

**Quyết định.** `pgx` v5, `sqlc` sinh code từ SQL, `goose` quản lý migration. SQL thuần, không ORM. Migration nằm trong repo của service sở hữu schema.

## ADR-012: Observability

**Quyết định.**
- Log: `log/slog` dạng JSON, có `trace_id`, `request_id`, không log PII.
- Metric: Prometheus (`client_golang`), mỗi service `/metrics`.
- Trace: OpenTelemetry, OTLP tới Tempo hoặc Jaeger, truyền `traceparent` qua HTTP, gRPC và header Kafka.
- Dashboard và alert hạ tầng: Grafana.

## ADR-013: Chiến lược test

**Quyết định.** Kim tự tháp: nhiều unit test cho domain, test tích hợp bằng Testcontainers (Kafka, ClickHouse, Postgres, Redis thật), test contract bằng `buf`, test tải bằng k6, chaos test bằng script (kill process, chặn mạng). Chi tiết ở [08](08-quality-and-operations.md).

## ADR-014: Frontend

**Quyết định.** React + TypeScript + Vite, TanStack Query cho dữ liệu, Apache ECharts cho biểu đồ, `EventSource` cho SSE, `pnpm`. Không dùng framework SSR vì dashboard là ứng dụng sau đăng nhập.

## ADR-015: SDK

**Quyết định.** TypeScript, không phụ thuộc runtime, build bằng `tsup`/`esbuild` ra ESM và IIFE. Ngân sách kích thước gzip dưới 3 KB cho bản lõi, CI kiểm tra. SDK tự sinh UUIDv7 cho `event_id`. Gửi bằng `navigator.sendBeacon`, fallback `fetch` với `keepalive`.

## ADR-016: CI/CD và phát hành

**Quyết định.**
- GitHub Actions, workflow dùng chung đặt ở repo `.github` (reusable workflows).
- Conventional Commits, squash merge.
- `release-please` tạo PR phát hành và changelog, tag theo SemVer.
- Image Docker đẩy lên GHCR bằng `GITHUB_TOKEN`.
- Dependabot cho Go, npm, GitHub Actions, Docker.

## ADR-017: Query gồm control plane

**Bối cảnh.** Danh sách 8 repo không có service riêng cho user, project, API key. Ba hướng: thêm repo, để vào Query, hay để ở Ingest.

**Quyết định.** Để vào Query dưới package riêng (`internal/control`), schema Postgres riêng, gRPC `ProjectService` tách bạch. Đây là "service béo có chủ đích" để không thêm repo thứ 9 trong giai đoạn đầu.

**Tín hiệu tách thành repo `control`.** Query cần scale vì lý do truy vấn khác với lý do auth, hoặc đội/PR về control và query cản nhau.

## ADR-018: Auth

**Quyết định.** Mật khẩu Argon2id. Access token JWT ngắn hạn và refresh token đặt trong cookie `HttpOnly`, `Secure`, `SameSite=Lax`, dashboard và API cùng origin qua Nginx. Lý do cookie: `EventSource` không gửi được header `Authorization`. Chống CSRF bằng `SameSite` và header tuỳ biến cho request thay đổi dữ liệu. Project key (`pk_...`) là định danh công khai, không phải bí mật.

## ADR-019: Định danh

**Quyết định.** UUIDv7 cho `event_id` (sắp xếp theo thời gian, tốt cho chỉ mục) và khoá thực thể. Lưu kiểu `UUID` ở Postgres và ClickHouse.

## ADR-020: Ngữ nghĩa giao nhận và dedup

**Bối cảnh.** Kafka đảm bảo at-least-once. Có thể trùng khi: SDK gửi lại do không nhận được phản hồi, producer retry, consumer xử lý lại sau rebalance hoặc crash.

**Quyết định.** **Không hứa exactly-once.** Mục tiêu là "hiệu lực exactly-once" bằng dedup nhiều lớp:
1. `event_id` do SDK sinh, mọi lớp dùng làm khoá.
2. Producer idempotent chặn trùng do retry nội bộ.
3. Processor lọc nhanh bằng Redis `SET NX` theo `event_id`, TTL 24 giờ.
4. Insert ClickHouse mang token dedup xác định theo batch (topic, partition, khoảng offset) để batch chạy lại không ghi hai lần.
5. Lưới an toàn: engine `ReplacingMergeTree` hoặc truy vấn đối chiếu định kỳ.

**Rủi ro đã biết.** Materialized view cộng dồn khi insert, nên trùng lọt qua bảng gốc sẽ cộng đôi vào aggregate. Dedup bảng gốc theo merge là eventual, không cứu được aggregate. Spike S2 xác nhận cấu hình nào thực sự chặn được (bao gồm tham số dedup cho bảng không replicated) trước khi chốt DDL.

**Xem lại khi** chaos test phát hiện trùng vượt ngưỡng chấp nhận.
