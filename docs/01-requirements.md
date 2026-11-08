# 01. Yêu cầu, ước lượng và rủi ro

## 1. Bối cảnh và vấn đề

Chủ website muốn biết người dùng làm gì trên site (lượt xem, click, hiệu năng tải trang) và muốn được báo khi lưu lượng hoặc hiệu năng bất thường. Các công cụ có sẵn hoặc nặng, hoặc đưa dữ liệu cho bên thứ ba. Hệ thống này thu thập dữ liệu qua một SDK nhẹ, lưu trữ và phân tích với độ trễ thấp, hiển thị real-time và cảnh báo.

Mục tiêu kép: (1) sản phẩm chạy được từ đầu đến cuối, (2) là dự án portfolio thể hiện năng lực backend: ingestion tải cao, event-driven, idempotency, time-series analytics, observability.

## 2. Tác nhân

| Tác nhân | Mô tả |
|---|---|
| Site owner | Đăng ký, tạo project, xem dashboard, cấu hình alert |
| Integrator | Nhúng SDK vào website bằng một thẻ script hoặc package |
| Visitor | Người truy cập website, chỉ gián tiếp sinh event |
| Operator | Người vận hành hệ thống (chính bạn): metric, DLQ, replay |
| Hệ thống bên ngoài | Endpoint webhook của site owner |

## 3. Yêu cầu chức năng

Ưu tiên theo MoSCoW. Mã FR được tham chiếu trong kế hoạch giao hàng.

| ID | Yêu cầu | Ưu tiên |
|---|---|---|
| FR-01 | SDK tự gửi pageview, hỗ trợ click, custom event và số liệu hiệu năng (LCP, TTFB, load time) | Must |
| FR-02 | SDK gom batch, retry có backoff, dùng `sendBeacon` khi rời trang | Must |
| FR-03 | Ingest xác thực project key, kiểm tra Origin allowlist, validate schema, rate limit, trả `202` sau khi Kafka xác nhận ghi | Must |
| FR-04 | Processor enrich (user agent, quốc gia, host referrer), khử trùng lặp, ghi ClickHouse theo batch | Must |
| FR-05 | Retry khi lỗi tạm thời, chuyển DLQ khi lỗi vĩnh viễn, có công cụ replay DLQ | Must |
| FR-06 | Query: pageview, unique visitor, top page, referrer, quốc gia, thiết bị, theo khoảng thời gian và độ chi tiết; P50/P95/P99 của LCP, TTFB, load | Must |
| FR-07 | Đăng ký/đăng nhập, CRUD project, xoay (rotate) project key | Must |
| FR-08 | Dashboard biểu đồ lịch sử và số liệu real-time qua SSE | Must |
| FR-09 | Alert rule theo ngưỡng (lưu lượng tăng đột biến, về 0, P95 vượt ngưỡng), cooldown, trạng thái firing/resolved | Should |
| FR-10 | Webhook ký HMAC-SHA256, retry với backoff, lịch sử giao nhận | Should |
| FR-11 | Metric Prometheus, log có cấu trúc, distributed tracing xuyên service | Should |
| FR-12 | Thông báo bổ sung (Telegram, Slack, email) | Could |
| FR-13 | Funnel, cohort, segment tuỳ biến | Won't |

## 4. Ngoài phạm vi (non-goals)

Session replay, heatmap, A/B test, billing và đa tenant thương mại, ML phát hiện bất thường, SDK mobile, lưu trữ dữ liệu cá nhân (PII) và IP thô.

## 5. Yêu cầu phi chức năng (đo được)

| ID | Thuộc tính | Mục tiêu | Cách đo |
|---|---|---|---|
| NFR-01 | Throughput ingest | Đạt đỉnh 20.000 event/giây trên 1 instance trong máy dev (mục tiêu ban đầu, chỉnh sau benchmark) | k6, mô tả ở [08](08-quality-and-operations.md) |
| NFR-02 | Độ trễ ingest | p99 dưới 25 ms ở 10.000 req/s (tính cả chờ Kafka ack) | k6, histogram Prometheus |
| NFR-03 | Độ bền dữ liệu | 0 event mất sau khi đã trả 202, kể cả khi processor bị kill | Chaos test, đối chiếu số lượng |
| NFR-04 | Tính đúng | 0 event trùng trong bảng gốc và bảng aggregate sau khi retry/replay | Chaos test, truy vấn đối chiếu |
| NFR-05 | Độ tươi dữ liệu | Event hiện trong ClickHouse trong vòng 5 giây ở điều kiện bình thường; số live trên dashboard dưới 3 giây | Đo end-to-end bằng event đánh dấu thời gian |
| NFR-06 | Query | p95 dưới 300 ms cho truy vấn 24 giờ; dưới 1 giây cho 30 ngày trên 100 triệu dòng | Benchmark script |
| NFR-07 | Alert | Từ lúc vượt ngưỡng tới lúc gửi webhook dưới 60 giây | Test tích hợp |
| NFR-08 | Chịu lỗi | Mỗi phụ thuộc có hành vi định nghĩa khi lỗi ([02](02-architecture.md) mục 6) | Test chaos từng phụ thuộc |
| NFR-09 | Bảo mật | Mật khẩu Argon2id, cookie HttpOnly, webhook chống SSRF và có chữ ký, không lưu IP thô | Checklist [08](08-quality-and-operations.md) |
| NFR-10 | Quyền riêng tư | Không PII; unique visitor tính bằng định danh ẩn danh, xoay theo ngày | Review schema |
| NFR-11 | Khả chuyển | `docker compose up` dựng được toàn hệ thống, dưới 6 GB RAM cho cấu hình dev | Thử trên máy sạch |
| NFR-12 | Bảo trì | Mỗi repo có CI xanh, domain logic có coverage tối thiểu 70% | CI |
| NFR-13 | Lưu giữ | Raw event 30 ngày (dev), aggregate 1 năm, Kafka giữ theo dung lượng | TTL ClickHouse, retention Kafka |

Các con số là mục tiêu ban đầu. Sau benchmark đầu tiên, điều chỉnh và ghi vào `docs/BENCHMARKS.md`.

## 6. Ước lượng dung lượng (back-of-envelope)

Giả định: event JSON trung bình khoảng 500 byte.

| Đại lượng | Tính | Kết quả |
|---|---|---|
| Event/ngày ở 20.000 event/giây liên tục | 20.000 x 86.400 | khoảng 1,7 tỷ |
| Băng thông vào | 20.000 x 500 B | khoảng 10 MB/s |
| Raw/ngày (chưa nén) | 10 MB/s x 86.400 | khoảng 0,86 TB |
| ClickHouse sau nén (giả định 8-10x) | 0,86 TB / 8-10 | khoảng 90-110 GB/ngày |

Kết luận quan trọng: **20.000 event/giây là mức đỉnh để chứng minh năng lực xử lý** (chạy vài phút trong load test), không phải khối lượng lưu trữ bền vững trên laptop. Môi trường dev dùng retention theo dung lượng (Kafka vài GB, ClickHouse TTL ngắn) và bộ dữ liệu benchmark sinh riêng.

Partition Kafka: băng thông 10 MB/s chỉ cần ít partition, nhưng chọn **12 partition** để có không gian song song cho consumer. Dev dùng 3. Chỉ số cần theo dõi: phân bố key, lag theo partition.

## 7. Ràng buộc và giả định

- Một lập trình viên, làm bán thời gian, khoảng 15-20 giờ/tuần.
- Máy dev 16 GB RAM là mức tối thiểu để chạy Kafka, ClickHouse, Redis, Postgres, Prometheus, Grafana cùng lúc.
- Toàn bộ chạy bằng Docker Compose. Kubernetes chỉ là hướng mở rộng tuỳ chọn ở cuối.
- Tất cả repo công khai, dùng GitHub Free.

## 8. Sổ rủi ro

| # | Rủi ro | Khả năng | Tác động | Giảm thiểu |
|---|---|---|---|---|
| R1 | Quá tải phạm vi: 8 repo, nhiều công nghệ cho một người | Cao | Cao | Giao theo phase, mỗi phase có demo; chỉ tạo repo khi tới phase của nó; giữ "query" gồm cả control plane tới khi cần tách (ADR-017) |
| R2 | Chi phí vận hành Kafka và ClickHouse trên máy dev | Trung bình | Trung bình | Một broker, giới hạn bộ nhớ, profile Compose, tắt thành phần chưa dùng |
| R3 | Trùng event làm sai số liệu aggregate | Trung bình | Cao | Dedup nhiều lớp, spike S2, chaos test (ADR-020) |
| R4 | Partition nóng do site lớn | Trung bình | Trung bình | Key theo `project_id` + `session_id` (ADR-003), theo dõi phân bố |
| R5 | Insert nhỏ lẻ làm chậm ClickHouse | Cao nếu bỏ qua | Cao | Batch theo kích thước và thời gian, metric kích thước batch |
| R6 | Lệch phiên bản contract giữa các repo | Trung bình | Trung bình | `buf breaking` trong CI, chỉ thêm trường tương thích, phiên bản trong tên package |
| R7 | Bot và giả mạo project key | Cao | Thấp-Trung bình | Origin allowlist, rate limit, validate chặt, lọc bot theo UA |
| R8 | Webhook bị lợi dụng (SSRF) | Trung bình | Cao | Chặn IP nội bộ khi giải DNS, timeout, giới hạn kích thước phản hồi |
| R9 | Số đo hiệu năng không thuyết phục | Trung bình | Trung bình | Kịch bản k6 cố định, lưu kết quả có phiên bản, mô tả máy chạy |
| R10 | Bỏ dở vì dự án quá dài | Trung bình | Cao | Mốc nhỏ, mỗi phase có thứ chạy được để trình diễn |
