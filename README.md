# analytics-tracker-infra

Repo "hệ thống" của Analytics Tracker: chứa **toàn bộ tài liệu thiết kế**, Docker Compose, cấu hình Prometheus/Grafana và script bootstrap cho cả organization.

Analytics Tracker là hệ thống thu thập và phân tích lưu lượng website: SDK JavaScript gửi event, ingest service nhận hàng chục nghìn event/giây, Kafka đệm dữ liệu, processor ghi vào ClickHouse, query service và dashboard hiển thị biểu đồ lịch sử cùng real-time, alert service gửi webhook khi vượt ngưỡng.

> Trạng thái: **Giai đoạn 0 (Foundations)**. Thiết kế đã chốt ở mức kế hoạch, chưa có code service.
> Thay thế bản monorepo cũ (Node + Fastify + Redis Streams + Postgres events). Xem ADR-002, ADR-003.

## Bản đồ repository

| Repo | Loại | Vai trò |
|---|---|---|
| `.github` | Org | Profile, template issue/PR, reusable workflows, health files |
| `analytics-tracker-contracts` | Shared | Protobuf, gRPC, OpenAPI, schema event (Go module) |
| `analytics-tracker-infra` | Deploy | Docs hệ thống, Compose, Prometheus, Grafana, e2e |
| `analytics-tracker-sdk-js` | Client | SDK nhúng vào website |
| `analytics-tracker-ingest` | Microservice | HTTP ingestion, validate, rate limit, Kafka producer |
| `analytics-tracker-processor` | Microservice | Kafka consumer, enrich, dedup, ghi ClickHouse, DLQ, live aggregator |
| `analytics-tracker-query` | Microservice | REST + SSE + gRPC, truy vấn analytics, auth, quản lý project |
| `analytics-tracker-alert` | Microservice | Rule, đánh giá ngưỡng, cooldown, webhook HMAC |
| `analytics-tracker-dashboard` | Client | React + TypeScript |

## Mục lục tài liệu

Đọc theo thứ tự, mỗi tài liệu là một bước trong quy trình phát triển.

| # | Tài liệu | Nội dung |
|---|---|---|
| 00 | [Quy trình phát triển](docs/00-process.md) | 10 bước, cổng chuyển giai đoạn, workflow mỗi tính năng, spike |
| 01 | [Yêu cầu và ước lượng](docs/01-requirements.md) | FR, NFR/SLO, phạm vi, ước lượng dung lượng, rủi ro |
| 02 | [Kiến trúc](docs/02-architecture.md) | Sơ đồ container, luồng dữ liệu, ownership, failure modes |
| 03 | [Quyết định công nghệ (ADR)](docs/03-technology-decisions.md) | Chọn gì, loại gì, vì sao, khi nào xem lại |
| 04 | [Pattern theo thành phần](docs/04-patterns.md) | Cấu trúc code, resilience, idempotency, state machine |
| 05 | [Contracts](docs/05-contracts.md) | HTTP, Protobuf, Kafka topic, ClickHouse, Postgres, gRPC, Redis |
| 06 | [Kế hoạch giao hàng](docs/06-delivery-plan.md) | Phase 0-5, backlog, tiêu chí hoàn thành, mốc thời gian |
| 07 | [Thiết lập GitHub](docs/07-github-setup.md) | Từng bước tạo organization, repo, CI, ruleset, release |
| 08 | [Chất lượng và vận hành](docs/08-quality-and-operations.md) | Test, load/chaos, observability, bảo mật, runbook |

Script bootstrap: [`scripts/bootstrap-repos.sh`](scripts/bootstrap-repos.sh).
Mẫu ADR: [`docs/adr/0000-template.md`](docs/adr/0000-template.md).

## Chạy hạ tầng dev

Yêu cầu: Docker và Docker Compose v2, `make`, RAM trống tối thiểu khoảng 4 GB cho cấu hình mặc định.

```bash
cp .env.example .env
make up          # Kafka (KRaft), Kafka UI, Redis
make ps          # xem trạng thái
make smoke       # kiểm tra nhanh Kafka và Redis
```

| Lệnh | Tác dụng |
|---|---|
| `make up-db` | Thêm Postgres và ClickHouse |
| `make up-obs` | Thêm Prometheus và Grafana |
| `make topics` | Liệt kê topic Kafka |
| `make consume` | Đọc `events.raw.v1` từ đầu |
| `make down` | Dừng, giữ dữ liệu |
| `make reset` | Dừng và xoá dữ liệu |

| Dịch vụ | Địa chỉ trên máy host |
|---|---|
| Kafka | `localhost:9092` |
| Kafka UI | http://localhost:8088 |
| Redis | `localhost:6379` |
| Postgres (profile `db`) | `localhost:5432` |
| ClickHouse (profile `db`) | `localhost:8123` (HTTP), `localhost:9000` (native) |
| Prometheus (profile `obs`) | http://localhost:9090 |
| Grafana (profile `obs`) | http://localhost:3000 (`admin` / `admin`) |

Cổng quy ước cho service chạy trên máy host: ingest 8080, query 8081, processor 8082, alert 8083. Thông tin đăng nhập trong `.env.example` chỉ dành cho dev.

## Nguyên tắc xuyên suốt

1. **Thiết kế theo hướng microservices, triển khai và tách dần** theo từng giai đoạn.
2. **Contract trước, code sau.** Mọi ranh giới giữa service đều có định nghĩa phiên bản hoá.
3. **Mọi quyết định đáng kể có ADR**, ghi cả phương án bị loại.
4. **Đo, không đoán.** Con số hiệu năng chỉ là mục tiêu cho đến khi có benchmark.
5. **Giao theo lát cắt dọc** (end-to-end mỏng) thay vì hoàn thiện từng service riêng lẻ.
6. **At-least-once cộng idempotent**, không hứa exactly-once.

## Giấy phép

MIT.
