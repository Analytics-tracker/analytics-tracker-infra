# 07. Thiết lập GitHub từng bước

Giao diện GitHub thay đổi theo thời gian. Nếu tên menu khác một chút, tìm mục tương đương. Các bước dưới đây dành cho GitHub Free với repo **công khai**. Tính năng có thể khác với repo private hoặc gói trả phí.

## Bước 1. Chuẩn bị tài khoản cá nhân

1. Đăng nhập GitHub, bật xác thực hai lớp (2FA): **Settings -> Password and authentication -> Two-factor authentication**. Lưu mã khôi phục ở nơi an toàn.
2. Cài GitHub CLI: https://cli.github.com rồi chạy `gh auth login` (chọn GitHub.com, HTTPS hoặc SSH, đăng nhập qua trình duyệt).
3. Thêm SSH key hoặc dùng credential helper của `gh`. Kiểm tra bằng `gh auth status`.
4. Cấu hình Git cục bộ:
   ```bash
   git config --global user.name "Tên của bạn"
   git config --global user.email "email@example.com"
   git config --global init.defaultBranch main
   git config --global pull.rebase true
   ```

## Bước 2. Tạo Organization

1. Bấm ảnh đại diện góc trên bên phải -> **Your organizations** -> **New organization**.
2. Chọn gói **Free**.
3. Tên organization: `analytics-tracker` (tên là duy nhất toàn GitHub, nếu đã có người dùng thì chọn biến thể, ví dụ `<tên-bạn>-analytics`). Nhớ thay tên này khi chạy các lệnh phía dưới.
4. Email liên hệ, chọn **My personal account** là chủ sở hữu.
5. Có thể bỏ qua bước mời thành viên.

## Bước 3. Cấu hình bảo mật Organization

Vào organization -> **Settings**.

| Mục | Cài đặt khuyến nghị |
|---|---|
| Authentication security | Bật yêu cầu 2FA cho thành viên |
| Member privileges -> Base permissions | `Read` (hoặc `No permission` nếu có nhiều thành viên) |
| Member privileges -> Repository creation | Giới hạn người được tạo repo |
| Code security | Bật mặc định cho repo mới: Dependency graph, Dependabot alerts, Dependabot security updates, Secret scanning và Push protection (với repo public) |
| Actions -> General | Cho phép actions của GitHub và các action bạn chọn; **Workflow permissions: Read repository contents** (mặc định chỉ đọc, workflow nào cần ghi thì tự khai báo `permissions`) |
| Actions -> General | Tick yêu cầu phê duyệt cho workflow từ contributor bên ngoài (fork) |
| Packages | Để mặc định, image sẽ nằm ở GHCR (`ghcr.io/<org>/...`) |

## Bước 4. Tạo repo `.github` (health file và workflow dùng chung)

Repo tên đúng `.github` là repo đặc biệt: file cộng đồng đặt ở đây là mặc định cho mọi repo trong organization.

```bash
gh repo create analytics-tracker/.github --public \
  --description "Org defaults, templates and reusable workflows" \
  --add-readme --license mit --clone
cd .github
mkdir -p profile .github/ISSUE_TEMPLATE workflows
```

Nội dung cần có:

```
.github/                            # tên repo
├── profile/README.md               # hiển thị trên trang organization
├── ISSUE_TEMPLATE/
│   ├── bug_report.yml
│   ├── feature_request.yml
│   └── config.yml
├── PULL_REQUEST_TEMPLATE.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
└── .github/workflows/              # reusable workflows
    ├── go-ci.yml
    ├── node-ci.yml
    ├── proto-ci.yml
    └── docker-publish.yml
```

Lưu ý vị trí: file cộng đồng (`ISSUE_TEMPLATE`, `PULL_REQUEST_TEMPLATE.md`, `SECURITY.md`...) đặt ở gốc repo hoặc trong thư mục `.github/` đều được GitHub nhận. Workflow dùng lại **bắt buộc** nằm trong `.github/workflows/` của repo này.

Mẫu `PULL_REQUEST_TEMPLATE.md`:

```markdown
## Thay đổi
<!-- Mô tả ngắn, liên kết issue: Closes #123 -->

## Loại
- [ ] feat  - [ ] fix  - [ ] refactor  - [ ] docs  - [ ] chore

## Checklist
- [ ] Test mới cho hành vi mới
- [ ] Lint và CI xanh
- [ ] Đã đặt timeout cho lời gọi ra ngoài, xử lý đường lỗi
- [ ] Cập nhật docs, ADR hoặc contract nếu liên quan
- [ ] Có số đo trước/sau nếu thay đổi hiệu năng
```

Mẫu reusable workflow `go-ci.yml` (đặt trong `.github/workflows/` của repo `.github`):

```yaml
name: go-ci
on:
  workflow_call:
    inputs:
      go-version-file:
        type: string
        default: go.mod
permissions:
  contents: read
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: ${{ inputs.go-version-file }}
      - uses: golangci/golangci-lint-action@v6
      - run: go test -race -count=1 ./...
      - run: go build ./...
      - run: go install golang.org/x/vuln/cmd/govulncheck@latest && govulncheck ./...
```

Repo khác gọi lại như sau (cú pháp `<org>/<repo>/.github/workflows/<file>@<ref>`):

```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]
jobs:
  go:
    uses: analytics-tracker/.github/.github/workflows/go-ci.yml@main
```

Khuyến nghị: khi ổn định, gắn tag (`@v1`) thay vì `@main` để thay đổi workflow không làm vỡ mọi repo cùng lúc. Với repo public, repo khác trong org gọi được workflow này. Phiên bản action và tag nên kiểm tra lại khi viết thật, vì chúng thay đổi theo thời gian.

## Bước 5. Tạo các repo

Dùng script đi kèm (tạo repo, bật chỉ squash merge, tự xoá nhánh sau merge, tạo nhãn):

```bash
cd analytics-tracker-infra
ORG=analytics-tracker bash scripts/bootstrap-repos.sh phase0     # chỉ repo của phase 0
ORG=analytics-tracker bash scripts/bootstrap-repos.sh phase1     # thêm repo phase 1
```

Script chưa được chạy thử với tài khoản thật. Hãy đọc kỹ rồi chạy từng nhóm, kiểm tra kết quả trên giao diện.

Tạo repo theo nhóm, **đúng lúc tới phase**:

| Nhóm | Repo |
|---|---|
| `phase0` | `analytics-tracker-infra`, `analytics-tracker-contracts` |
| `phase1` | `analytics-tracker-ingest`, `analytics-tracker-sdk-js` |
| `phase2` | `analytics-tracker-processor` |
| `phase3` | `analytics-tracker-query` |
| `phase4` | `analytics-tracker-alert`, `analytics-tracker-dashboard` |

Nếu thích tên ngắn trong organization (`ingest`, `processor`...), đổi mảng trong script. Tên dài của kế hoạch có lợi khi clone nhiều repo vào cùng thư mục.

## Bước 6. Ruleset bảo vệ nhánh `main`

Với mỗi repo: **Settings -> Rules -> Rulesets -> New ruleset -> New branch ruleset**.

| Mục | Giá trị |
|---|---|
| Enforcement status | Active |
| Target branches | Default branch (`main`) |
| Restrict deletions | Bật |
| Block force pushes | Bật |
| Require linear history | Bật |
| Require a pull request before merging | Bật, số approval: 0 khi làm một mình (vẫn bắt buộc đi qua PR), 1 khi có người review |
| Require conversation resolution | Bật |
| Require status checks to pass | Bật, chọn job CI sau khi workflow chạy ít nhất một lần để tên job hiện ra |
| Require branches to be up to date | Tuỳ chọn |

Trong cài đặt chung của repo (**Settings -> General -> Pull Requests**): chỉ bật **Allow squash merge** (mặc định dùng tiêu đề PR), tắt merge commit và rebase merge, bật **Automatically delete head branches**. Script bootstrap đã làm các việc này.

Ghi chú: làm việc một mình thì quyền admin cho phép bỏ qua ruleset. Hãy tự kỷ luật không bypass, vì đây chính là thói quen cần luyện.

## Bước 7. CODEOWNERS, Dependabot, release

Trong mỗi repo:

`.github/CODEOWNERS`
```
* @analytics-tracker/maintainers
```
(hoặc `@<username>` khi chưa tạo team)

`.github/dependabot.yml` (ví dụ cho repo Go)
```yaml
version: 2
updates:
  - package-ecosystem: gomod
    directory: /
    schedule: { interval: weekly }
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
  - package-ecosystem: docker
    directory: /
    schedule: { interval: weekly }
```

**Release tự động bằng release-please.** Mỗi lần merge commit theo Conventional Commits (`feat:`, `fix:`, `feat!:` hoặc `BREAKING CHANGE:`), release-please mở một PR cập nhật changelog và version. Merge PR đó thì tạo tag `vX.Y.Z` và release. Workflow phát hành chạy khi có tag để build và đẩy image.

```yaml
# .github/workflows/release-please.yml
name: release-please
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          release-type: go
```

Đẩy image lên GHCR bằng `GITHUB_TOKEN` (cần `permissions: packages: write` trong workflow đó, không cần tạo secret riêng):

```yaml
# .github/workflows/docker-publish.yml (rút gọn)
on:
  push:
    tags: ['v*']
permissions:
  contents: read
  packages: write
jobs:
  image:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ github.ref_name }}
```

Kiểm tra lại phiên bản action tại thời điểm viết, vì chúng thay đổi. Các đoạn YAML ở trên là mẫu, chưa chạy thử.

## Bước 8. GitHub Project (quản lý công việc)

1. Organization -> **Projects** -> **New project** -> chọn mẫu **Roadmap** hoặc **Board**.
2. Thêm trường: `Phase` (P0-P5), `Repo`, `Priority`, `Size`.
3. Tạo milestone trong từng repo: `P1 Core Ingestion` và các phase còn lại.
4. Tạo issue từ **Backlog khởi tạo** ở [06](06-delivery-plan.md). Gắn nhãn `phase:N`, loại, repo. Thêm issue vào Project.
5. Mỗi PR dùng `Closes #N` để tự đóng issue và cập nhật bảng.

Nhãn gợi ý: `phase:0` ... `phase:5`, `type:feat`, `type:fix`, `type:chore`, `type:docs`, `type:spike`, `priority:high`, `blocked`.

## Bước 9. Quy ước commit và nhánh

- Nhánh: `feat/<issue>-<slug>`, `fix/<issue>-<slug>`, `chore/...`, `docs/...`.
- Commit: Conventional Commits, ví dụ `feat(ingest): add token bucket rate limiter`, `fix(processor): commit offsets after flush`.
- Phạm vi (`scope`) là tên package hoặc module.
- Không push trực tiếp lên `main`. Mọi thứ qua PR.

## Bước 10. Môi trường dev cục bộ

```
~/work/analytics-tracker/
├── analytics-tracker-infra/
├── analytics-tracker-contracts/
├── analytics-tracker-ingest/
├── analytics-tracker-processor/
├── analytics-tracker-query/
├── analytics-tracker-alert/
├── analytics-tracker-sdk-js/
├── analytics-tracker-dashboard/
└── go.work                       # tuỳ chọn, dùng contracts cục bộ khi sửa schema
```

`go.work` cho phép sửa `contracts` và thử ngay trong service mà chưa cần phát hành:

```bash
cd ~/work/analytics-tracker
go work init ./analytics-tracker-contracts ./analytics-tracker-ingest
go work use ./analytics-tracker-processor
```

Không commit `go.work` vào repo service.

## Bước 11. Ví dụ PR đầu tiên (kiểm tra toàn bộ quy trình)

1. Tạo issue "Khung `buf` và Protobuf `Event`" trong `contracts`, gán `phase:0`.
2. `git switch -c feat/1-event-proto`
3. Viết `proto/analytics/events/v1/event.proto`, `buf.yaml`, workflow gọi `proto-ci`.
4. `git commit -m "feat: add Event protobuf and buf CI"`
5. `git push -u origin feat/1-event-proto`, mở PR (`gh pr create --fill`).
6. CI chạy, xanh, tự review, squash merge.
7. release-please mở PR phát hành, merge để có tag `v0.1.0`.
8. Service khác dùng: `go get github.com/analytics-tracker/analytics-tracker-contracts@v0.1.0`.

Khi hoàn thành bước 11 nghĩa là toàn bộ chuỗi issue, nhánh, PR, CI, ruleset, release, versioning đã hoạt động.

## Danh sách kiểm tra cuối

- [ ] 2FA bật, `gh auth status` hợp lệ
- [ ] Organization tạo xong, cấu hình bảo mật theo bước 3
- [ ] Repo `.github` có template và reusable workflow
- [ ] Repo phase 0 tạo xong, ruleset bật, chỉ squash merge
- [ ] CI mẫu chạy xanh ở `contracts`
- [ ] Project và milestone tạo xong, backlog khởi tạo đã thành issue
- [ ] PR đầu tiên đi hết quy trình tới tag
