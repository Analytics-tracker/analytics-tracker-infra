# 00. Quy trình phát triển

Tài liệu này mô tả **cách làm việc**, không phải sản phẩm. Mục tiêu là đi theo quy trình của một đội backend thật: hiểu vấn đề, chốt tiêu chí đo được, thiết kế, chọn công nghệ có lý do, dựng khung chạy được từ đầu đến cuối, rồi giao từng lát cắt.

## 1. Mười bước

| # | Bước | Câu hỏi phải trả lời | Sản phẩm | Cổng chuyển bước |
|---|---|---|---|---|
| 1 | Hiểu vấn đề và phạm vi | Làm cho ai, giải quyết gì, không làm gì? | [01](01-requirements.md) mục 1-4 | Có danh sách FR theo MoSCoW và non-goals |
| 2 | Ước lượng và tiêu chí chất lượng | Tải bao nhiêu, chậm bao nhiêu là chấp nhận được? | [01](01-requirements.md) mục 5-6 | Mọi NFR có con số và cách đo |
| 3 | Kiến trúc mức cao | Chia thành phần nào, ai sở hữu dữ liệu gì? | [02](02-architecture.md) | Sơ đồ container, bảng ownership, failure modes |
| 4 | Chọn công nghệ | Dùng gì và vì sao, loại gì? | [03](03-technology-decisions.md) | Mỗi lựa chọn lớn có ADR và điều kiện xem lại |
| 5 | Chọn pattern | Mỗi thành phần cấu trúc và chịu lỗi thế nào? | [04](04-patterns.md) | Có ma trận timeout/retry/circuit breaker |
| 6 | Contract trước | Các bên nói chuyện bằng gì? | [05](05-contracts.md) | Schema có phiên bản, quy tắc tương thích |
| 7 | Repo, CI/CD, branching | Code nằm đâu, kiểm tra và phát hành thế nào? | [07](07-github-setup.md) | Org, repo, ruleset, CI mẫu chạy xanh |
| 8 | Walking skeleton | Lát cắt mỏng nhất chạy end-to-end là gì? | [06](06-delivery-plan.md) | Một event đi từ SDK tới ClickHouse |
| 9 | Giao theo lát cắt dọc | Giá trị nào ra trước? | [06](06-delivery-plan.md) | Mỗi phase có demo và tiêu chí đo |
| 10 | Vận hành | Biết nó chạy đúng bằng cách nào? | [08](08-quality-and-operations.md) | Metric, trace, test tải, runbook |

Các bước 1-6 là **thiết kế**, làm xong trước khi viết code service đầu tiên. Bước nào phát hiện sai thì quay lại sửa tài liệu rồi mới đi tiếp.

## 2. Nguyên tắc ra quyết định

- **Quyết định khó đảo ngược thì làm kỹ** (message broker, schema event, partition key, contract công khai). **Dễ đảo ngược thì chọn nhanh** (thư viện log, UI chart).
- **Spike có giới hạn thời gian** để trả lời một câu hỏi cụ thể trước khi chốt ADR (mục 5).
- **YAGNI nhưng sẵn sàng mở rộng**: dùng interface (port) ở chỗ có khả năng đổi, không xây tính năng chưa cần.
- **Một nguồn sự thật cho mỗi loại dữ liệu**: ownership rõ ràng, service khác chỉ đọc qua API hoặc event.
- **Thất bại là chuyện bình thường**: mỗi lời gọi ra ngoài có timeout, chính sách retry và hành vi khi lỗi.

## 3. Workflow cho mỗi tính năng

```
Issue (đạt Definition of Ready)
  -> nhánh feat/<issue>-<slug>
  -> commit theo Conventional Commits
  -> Pull Request nhỏ (khuyến nghị dưới 400 dòng thay đổi)
  -> CI xanh (lint, test, build, kiểm tra contract)
  -> tự review theo checklist
  -> squash merge, tiêu đề PR là commit message
  -> release-please tạo PR phát hành
  -> merge PR phát hành: tag SemVer, build image, đẩy lên GHCR
```

### Definition of Ready (issue)
- Có mô tả vấn đề và tiêu chí chấp nhận kiểm tra được.
- Gắn nhãn `phase:N`, `repo`, `type:feat|fix|chore|docs`.
- Nếu đổi contract: đã có PR bên `contracts` hoặc liên kết kế hoạch.
- Ước lượng nhỏ hơn 2 ngày. Lớn hơn thì tách.

### Definition of Done (PR)
- Test mới cho hành vi mới, test cũ xanh.
- Lint và `govulncheck` (hoặc `npm audit`) không có lỗi mới.
- Metric, log, trace cho đường chạy mới (nếu là thành phần runtime).
- Cập nhật README, ADR hoặc contract liên quan.
- Không có TODO không gắn issue.
- Với thay đổi hiệu năng: có số đo trước/sau.

### Checklist tự review
Đường lỗi đã xử lý? Timeout đã đặt? Có thể chạy lại (idempotent)? Có log đủ để điều tra mà không lộ dữ liệu cá nhân? Có đóng tài nguyên và tắt êm (graceful shutdown)?

## 4. Quản lý công việc

- Một GitHub Project cấp organization dạng Roadmap, trường `Phase`, `Repo`, `Priority`, `Size`.
- Milestone cho từng phase, ví dụ `P1 Core Ingestion`.
- Issue nhỏ, sinh từ backlog ở [06](06-delivery-plan.md).
- Mỗi tuần: xem lại phạm vi phase, rủi ro và số đo. Cuối phase: demo và retrospective ngắn ghi vào `docs/retros/`.

## 5. Spike (câu hỏi cần trả lời bằng thực nghiệm)

Mỗi spike có giới hạn thời gian. Kết quả ghi vào ADR liên quan, kèm số đo và cách tái tạo.

| ID | Câu hỏi | Cách làm | Tiêu chí | Thời gian | Ảnh hưởng ADR |
|---|---|---|---|---|---|
| S1 | `net/http` có đủ cho ingest hay cần `fasthttp`? | Handler tối thiểu, k6 ramp tới mức tối đa trên máy dev | Đạt SLO ingest bằng stdlib thì giữ stdlib | 1 ngày | ADR-010 |
| S2 | ClickHouse dedup theo insert token có chạy với bảng không replicated và materialized view như thế nào? | Insert lại cùng batch, kiểm tra số dòng bảng gốc và bảng aggregate | Biết chính xác khi nào trùng lọt vào aggregate | 1-2 ngày | ADR-004, ADR-020 |
| S3 | `acks=all` trước khi trả 202 làm p99 tăng bao nhiêu, linger/batch tối ưu? | Producer franz-go, đổi linger, batch size, nhiều request đồng thời | p99 trong SLO, biết đánh đổi | 1 ngày | ADR-003, ADR-009 |
| S4 | SSE với auth bằng cookie qua Nginx có ổn định khi nhiều kết nối? | Mô phỏng vài nghìn kết nối SSE | Không rò kết nối, bộ nhớ ổn định | 1 ngày | ADR-018 |

## 6. Quản lý rủi ro

Sổ rủi ro nằm cuối [01](01-requirements.md). Xem lại ở cuối mỗi phase: rủi ro nào đã xảy ra, đã đổi mức độ, cần ADR mới không.
