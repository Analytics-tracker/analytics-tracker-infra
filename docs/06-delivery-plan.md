# 06. Kế hoạch giao hàng

Giữ nguyên thứ tự 5 giai đoạn đã đề xuất, bổ sung **Phase 0 (Foundations)** và dời `contracts` lên sớm, vì Ingest cần schema event ngay từ Phase 1. Chỉ tạo repo khi tới phase của nó.

| Phase | Tên | Repo chạm tới | Thời lượng ước tính |
|---|---|---|---|
| 0 | Foundations | `.github`, `infra`, `contracts` (khung) | 1 tuần |
| 1 | Core Ingestion | `sdk-js`, `ingest`, `infra`, `contracts` | 2 tuần |
| 2 | Event Processing | `processor`, `contracts`, `infra` | 3 tuần |
| 3 | Analytics Query | `query`, `ingest` (đổi resolver) | 3 tuần |
| 4 | Dashboard và Alerting | `dashboard`, `alert`, `query`, `processor` (live) | 4 tuần |
| 5 | Production Engineering | tất cả | 3 tuần |

Tổng khoảng 16 tuần cho một người làm bán thời gian. Điều chỉnh theo thực tế sau Phase 1.

## Walking skeleton

Mốc quan trọng đầu tiên: **một event đi từ SDK tới ClickHouse**, dù mỏng. Phase 1 cho tới Kafka, Phase 2 hoàn tất đoạn còn lại. Trước khi hoàn thiện bất kỳ service nào, `infra` có một e2e smoke test (script): gửi 1 event bằng `curl`, kiểm tra thấy trong topic, sau Phase 2 kiểm tra thấy trong ClickHouse.

---

## Phase 0: Foundations

**Mục tiêu:** có nền tảng để làm việc như một đội: organization, template, CI mẫu, hạ tầng dev, các ADR đầu tiên.

- [x] Tạo GitHub Organization, cấu hình bảo mật ([07](07-github-setup.md))
- [x] Repo `.github`: profile, template PR, reusable workflow `go-ci`
- [ ] Repo `.github`: template issue, `CONTRIBUTING`, `SECURITY`, workflows `node-ci`, `docker-publish`, `proto-ci`
- [x] Repo `infra`: tài liệu thiết kế, script bootstrap
- [x] Repo `infra`: `docker-compose.yml` (Kafka KRaft, Kafka UI, Redis; profile `db`: Postgres, ClickHouse; profile `obs`: Prometheus, Grafana), `Makefile`, smoke test
- [ ] Repo `contracts`: khung Protobuf `Event`, `buf.yaml`, `buf.gen.yaml`, CI `buf lint` và `buf breaking`, tag `v0.1.0`
- [ ] GitHub Project (Roadmap), nhãn, milestone P1-P5
- [ ] Chạy spike S1, S3 (cần cho Phase 1) và ghi kết quả vào ADR
- [ ] Template service Go (repo mẫu hoặc thư mục mẫu): layout, Dockerfile, Makefile, golangci-lint, health/metrics/shutdown

**Tiêu chí hoàn thành:** `docker compose up` chạy ổn định; CI mẫu xanh trên `contracts`; ADR-001 tới ADR-020 đã review; spike S1, S3 có số đo.

---

## Phase 1: Core Ingestion

**Mục tiêu:** SDK gửi event, Ingest xác thực và ghi Kafka, trả `202`. **FR:** 01, 02, 03.

**`contracts`**
- [ ] Hoàn thiện `Event`, `OpenAPI` cho `/v1/collect`; phát hành `v0.2.0`

**`ingest`**
- [ ] Khung từ template: config, log, `/healthz`, `/readyz`, `/metrics`, shutdown
- [ ] `/v1/collect`: giới hạn kích thước, parse, validate từng event, phản hồi accepted/rejected
- [ ] Port `ProjectResolver` + adapter đọc `projects.yaml` (tạm thời)
- [ ] Kiểm tra Origin allowlist, CORS cho `text/plain`
- [ ] Rate limit: token bucket Lua trên Redis + limiter cục bộ dự phòng
- [ ] Kafka producer `franz-go`: `acks=all`, idempotent, chờ ack, key `project_id/session_id`
- [ ] Circuit breaker, backpressure, `503` + `Retry-After`
- [ ] Metrics: request theo mã, histogram độ trễ, lỗi publish, kích thước batch
- [ ] Test: unit (validate, limiter), tích hợp (Testcontainers Kafka + Redis)
- [ ] Dockerfile đa tầng, đẩy image GHCR qua CI
- [ ] Kịch bản k6 baseline, lưu kết quả `docs/BENCHMARKS.md`

**`sdk-js`**
- [ ] Khung TypeScript, build ESM + IIFE, ngân sách kích thước trong CI
- [ ] Sinh UUIDv7, mô hình event, hàng đợi có giới hạn
- [ ] Pageview tự động, theo dõi điều hướng SPA (History API)
- [ ] Click và custom event
- [ ] Hiệu năng: LCP, TTFB, load bằng `PerformanceObserver`
- [ ] Gửi: `sendBeacon` + fallback `fetch keepalive`, retry backoff + jitter
- [ ] Test: unit (vitest), e2e với trình duyệt headless tới Ingest chạy cục bộ

**`infra`**
- [ ] Job khởi tạo topic, e2e smoke test (curl tới Kafka)
- [ ] Prometheus scrape Ingest, dashboard Grafana cơ bản

**Tiêu chí hoàn thành:** đạt NFR-01 và NFR-02 trên máy dev (hoặc ghi rõ số thực tế và lý do); SDK dưới 3 KB gzip; e2e smoke test xanh; k6 và kết quả được ghi lại.

**Demo:** mở trang demo có SDK, click, thấy event trong Kafka UI.

---

## Phase 2: Event Processing

**Mục tiêu:** consume, enrich, dedup, ghi ClickHouse, retry, DLQ. **FR:** 04, 05. **NFR:** 03, 04, 05.

- [ ] Spike S2 (dedup ClickHouse) và chốt DDL, cập nhật ADR-004, ADR-020
- [ ] `contracts`: hoàn thiện, phát hành `v0.3.0` hoặc `v1.0.0` khi đã ổn định
- [ ] Migration ClickHouse bằng `goose`: `events`, `events_1m` và materialized view
- [ ] `processor`: khung từ template; consumer group `franz-go`, commit thủ công
- [ ] Pipeline: decode, validate, enrich (UA, geo, host referrer, visitor id ẩn danh), dedup, batcher
- [ ] Writer ClickHouse: batch lớn, token dedup xác định
- [ ] Retry backoff, pause/resume partition, xử lý rebalance
- [ ] DLQ: ghi header lỗi, CLI replay
- [ ] Metrics: lag, kích thước batch, thời gian insert, số DLQ, số trùng bị loại
- [ ] Test tích hợp (Testcontainers), chaos script
- [ ] **Chaos test:** gửi 1 triệu event, kill processor ngẫu nhiên, chạy lại. Đối chiếu số dòng bảng gốc và tổng aggregate đều bằng 1 triệu

**Tiêu chí hoàn thành:** chaos test xanh (0 mất, 0 trùng); độ tươi dữ liệu theo NFR-05; kết quả ghi vào `docs/BENCHMARKS.md`.

**Demo:** kill processor khi đang tải, dữ liệu vẫn đủ; một message hỏng đi vào DLQ và được replay.

---

## Phase 3: Analytics Query

**Mục tiêu:** truy vấn theo project, thời gian, URL; percentile; có control plane. **FR:** 06, 07. **NFR:** 06.

- [ ] `query`: khung từ template; schema Postgres `control` (goose + sqlc)
- [ ] Auth: đăng ký, đăng nhập, refresh, cookie HttpOnly (ADR-018), spike S4 cho phần SSE nếu cần
- [ ] CRUD project, xoay project key
- [ ] gRPC `ProjectService`; `ingest` đổi adapter từ `projects.yaml` sang gRPC (cache-aside)
- [ ] Endpoint stats: overview, timeseries, top pages, referrers, countries, devices, performance (P50/P95/P99)
- [ ] Chọn bảng aggregate theo độ chi tiết, bảng top page theo giờ
- [ ] Cache Redis + singleflight, giới hạn bảo vệ truy vấn
- [ ] OpenAPI cập nhật ở `contracts`
- [ ] Script sinh 10M rồi 100M dòng, benchmark truy vấn

**Tiêu chí hoàn thành:** NFR-06 đạt trên 100 triệu dòng (hoặc có số thực tế); kiểm tra quyền sở hữu project cho mọi endpoint; `ingest` chạy được với control plane thật.

---

## Phase 4: Dashboard và Alerting

**Mục tiêu:** dashboard real-time, cảnh báo và webhook. **FR:** 08, 09, 10. **NFR:** 05, 07.

- [ ] `processor`: binary `live-aggregator`, publish Redis mỗi giây
- [ ] `query`: SSE `/live`, kiểm tra quyền, heartbeat, ngắt client chậm
- [ ] `dashboard`: khung React + Vite, đăng nhập, danh sách project, trang tổng quan
- [ ] Biểu đồ: chuỗi thời gian, top page, percentile hiệu năng, số live
- [ ] `alert`: khung từ template, schema `alert`, gRPC `AlertService`
- [ ] Đánh giá định kỳ, state machine, cooldown Redis
- [ ] Transactional outbox, worker giao webhook, HMAC, chống SSRF, lịch sử giao
- [ ] `query` chuyển tiếp CRUD rule; trang cấu hình alert trên dashboard
- [ ] Test tích hợp end-to-end: tạo rule, bơm tải, nhận webhook đúng chữ ký

**Tiêu chí hoàn thành:** live dưới 3 giây; webhook đến trong 60 giây kể từ lúc vượt ngưỡng; kill Alert giữa chừng không mất thông báo.

---

## Phase 5: Production Engineering

**Mục tiêu:** đủ tin cậy để trình bày như hệ thống thật.

- [ ] Distributed tracing: `traceparent` xuyên HTTP, gRPC, header Kafka; xem một trace từ ingest tới ClickHouse
- [ ] Dashboard Grafana theo SLO; alert hạ tầng (lag, tỉ lệ lỗi, độ trễ)
- [ ] Test tải đầy đủ bằng k6 (xem [08](08-quality-and-operations.md)), benchmark ingest và query, lưu số đo có phiên bản
- [ ] Chaos toàn hệ thống: kill từng thành phần, chặn mạng, đầy đĩa
- [ ] Timeout, retry, circuit breaker rà soát theo ma trận ở [04](04-patterns.md)
- [ ] Hardening: bot filtering, giới hạn kích thước, rà soát bảo mật, `govulncheck`, quét image
- [ ] CI/CD hoàn chỉnh: release-please mọi repo, image GHCR, e2e trong `infra` chạy khi nâng version
- [ ] Runbook, tài liệu kiến trúc cập nhật, video demo, bài viết tổng kết
- [ ] (Tuỳ chọn) Triển khai thử trên Kubernetes cục bộ bằng `kind`

**Tiêu chí hoàn thành:** mọi NFR có số đo hoặc có giải thích khác biệt; mọi ADR còn đúng hoặc đã được thay thế; người ngoài dựng được hệ thống chỉ bằng README.

---

## Backlog khởi tạo (issue đầu tiên)

| Repo | Issue | Phase |
|---|---|---|
| org | Tạo organization và cấu hình bảo mật | 0 |
| `.github` | Template issue/PR, CONTRIBUTING, SECURITY | 0 |
| `.github` | Reusable workflow `go-ci` | 0 |
| `.github` | Reusable workflow `node-ci` | 0 |
| `.github` | Reusable workflow `docker-publish` | 0 |
| `.github` | Reusable workflow `proto-ci` (buf) | 0 |
| `infra` | `docker-compose.yml` Kafka KRaft + Redis + Postgres + ClickHouse | 0 |
| `infra` | Prometheus và Grafana cơ bản | 0 |
| `contracts` | Khung `buf`, Protobuf `Event`, CI | 0 |
| `infra` | Spike S1: stdlib vs fasthttp | 0 |
| `infra` | Spike S3: Kafka acks và linger | 0 |
| `ingest` | Khung service từ template | 1 |
| `ingest` | `/v1/collect` parse và validate | 1 |
| `ingest` | Kafka producer và circuit breaker | 1 |
| `sdk-js` | Khung TypeScript và kiểm tra kích thước | 1 |
| `sdk-js` | Hàng đợi, batching, sendBeacon | 1 |

## Cổng chuyển phase

Chỉ sang phase kế tiếp khi: tiêu chí hoàn thành đạt, demo chạy được, ADR liên quan đã cập nhật, rủi ro đã rà, kết quả đo đã lưu.
