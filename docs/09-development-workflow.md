# 09. Quy trình làm việc hằng ngày

Áp dụng cho mọi repo trong organization, kể cả repo tài liệu và repo `.github`. Nguyên tắc: **mọi thay đổi đi qua Issue, nhánh, Pull Request, CI, squash merge**. Không push trực tiếp lên `main`.

## 1. Vòng đời một thay đổi

```
1. Chọn issue (Project board) và chuyển sang In progress
2. git switch main && git pull
3. git switch -c feat/<số-issue>-<slug>
4. Viết code và test, commit nhỏ, thường xuyên
5. Chạy kiểm tra cục bộ (mục 3)
6. git push -u origin <nhánh>
7. gh pr create --fill, điền template, liên kết "Closes #<issue>"
8. CI chạy. Đỏ thì sửa (mục 5)
9. Tự review diff trên trang PR theo checklist
10. gh pr merge --squash --delete-branch
11. git switch main && git pull
```

Ví dụ cụ thể:

```bash
git switch main && git pull
git switch -c feat/12-token-bucket
# ... sửa code ...
git add -A
git commit -m "feat(ingest): add token bucket rate limiter"
git push -u origin feat/12-token-bucket
gh pr create --fill
# xem lại diff trên web, CI xanh
gh pr merge --squash --delete-branch
git switch main && git pull
```

## 2. Quy ước

### Tên nhánh
`feat/<issue>-<slug>`, `fix/<issue>-<slug>`, `chore/<issue>-<slug>`, `docs/<issue>-<slug>`, `spike/<issue>-<slug>`.

### Commit và tiêu đề PR (Conventional Commits)
Dạng `type(scope): mô tả ngắn, thể mệnh lệnh, tiếng Anh`.

| type | Dùng khi | Ảnh hưởng version |
|---|---|---|
| `feat` | Thêm tính năng | minor |
| `fix` | Sửa lỗi | patch |
| `perf` | Cải thiện hiệu năng | patch |
| `refactor`, `test`, `docs`, `chore`, `ci`, `build` | Không đổi hành vi bên ngoài | không |
| `feat!` hoặc footer `BREAKING CHANGE:` | Thay đổi phá vỡ tương thích | major |

Vì dùng squash merge, **tiêu đề PR chính là commit trên `main`**, nên tiêu đề PR phải theo quy ước này. Commit trong nhánh có thể tuỳ ý hơn.

### Kích thước PR
Dưới khoảng 400 dòng thay đổi, một mục đích. Lớn hơn thì tách. PR nhỏ review nhanh, ít lỗi, dễ quay lui.

## 3. Kiểm tra cục bộ trước khi push

Mỗi repo Go có `make check` chạy các lệnh dưới đây. Repo Node có script tương ứng.

```bash
gofmt -l .                    # không được in ra file nào
go vet ./...
golangci-lint run
go test -race -count=1 ./...
go build ./...
```

CI chạy lại đúng các bước này. Chạy cục bộ trước để không chờ CI mới biết lỗi.

## 4. Review (kể cả khi làm một mình)

Đọc diff trên trang PR như đọc code người khác, theo checklist trong template. Câu hỏi nhanh:

- Đường lỗi đã xử lý, có timeout cho mọi lời gọi ra ngoài?
- Thao tác này có chạy lại an toàn (idempotent)?
- Log đủ để điều tra, không lộ dữ liệu cá nhân?
- Tài nguyên được đóng, tắt êm (graceful shutdown)?
- Có test cho hành vi mới? Có ghi lại số đo nếu là thay đổi hiệu năng?

## 5. Khi CI đỏ

1. Mở tab Actions, xem job và bước lỗi đầu tiên (đừng đọc từ cuối).
2. Tái hiện cục bộ bằng chính lệnh của bước đó.
3. Sửa, commit thêm, push. PR tự chạy lại.
4. Lỗi do hạ tầng (mạng, runner) thì chạy lại job. Lỗi lặp lại thì coi là lỗi thật.
5. Không tắt check để merge. Test chập chờn (flaky) phải mở issue riêng và sửa.

## 6. Thay đổi liên repo (contracts tới service)

Ví dụ thêm trường vào `Event`:

1. **Repo `contracts`:** nhánh, sửa `.proto`, `buf lint` và `buf breaking` xanh, PR, merge.
2. release-please mở PR phát hành, merge để có tag mới (ví dụ `v0.3.0`).
3. **Repo service:** nhánh, `go get github.com/<org>/analytics-tracker-contracts@v0.3.0`, sửa code dùng trường mới, PR, merge.

Khi cần thử nhanh mà chưa muốn phát hành, dùng `go.work` ở thư mục cha (không commit):

```bash
cd ~/work/analytics-tracker
go work init ./analytics-tracker-contracts ./analytics-tracker-ingest
```

Thứ tự luôn là: **contracts trước, rồi producer/consumer**. Thay đổi phá vỡ thì tạo `v2`, không sửa `v1`.

## 7. Spike

1. Tạo issue `type:spike` ghi rõ câu hỏi, cách đo, tiêu chí, thời hạn.
2. Nhánh `spike/<issue>-<slug>`. Code thử nghiệm có thể bỏ đi, nhưng **kết quả phải giữ lại**.
3. Ghi kết quả (số đo, cách tái tạo, kết luận) vào ADR liên quan, mở PR `docs:`.
4. Đóng issue. Code thử nghiệm đáng giá thì đưa vào `infra/spikes/` hoặc bỏ.

## 8. Tài liệu và ADR

- Quyết định mới: copy `docs/adr/0000-template.md`, đặt số tiếp theo, mở PR `docs:`.
- Đổi quyết định cũ: không sửa ADR cũ, tạo ADR mới và ghi "Superseded by" ở ADR cũ.
- Đổi hành vi hệ thống: cập nhật tài liệu trong cùng PR với code.

## 9. Sửa lỗi gấp (hotfix)

Quy trình giống mục 1 nhưng nhánh `fix/...`, PR nhỏ nhất có thể, thêm test tái hiện lỗi trước rồi mới sửa. Không có đường tắt bỏ qua CI.

## 10. Thay đổi cấp organization (repo `.github`)

Template PR, template issue, workflow dùng chung nằm ở repo `.github`. Đi qua PR như mọi repo:

```bash
cd ~/work/analytics-tracker/.github
git switch main && git pull
git switch -c chore/<issue>-<slug>
# sửa file
git add -A && git commit -m "chore: <mô tả>"
git push -u origin chore/<issue>-<slug>
gh pr create --fill
gh pr merge --squash --delete-branch
git switch main && git pull
```

Template mặc định có hiệu lực cho **PR mới** ở các repo không tự có template riêng, ngay sau khi merge vào nhánh mặc định. Workflow dùng chung có hiệu lực khi repo khác gọi tới `@main` (hoặc tag) sau khi merge. Vì thay đổi workflow ảnh hưởng nhiều repo, thử ở một repo trước, ổn định thì gắn tag `v1` và để repo khác gọi theo tag.

## 11. Nhịp làm việc

**Đầu buổi:** xem board, chọn một issue nhỏ, `git pull`.
**Trong buổi:** commit nhỏ, push cuối buổi để không mất việc.
**Cuối tuần:** xem lại tiến độ phase so với kế hoạch, cập nhật rủi ro, dọn nhánh cũ, quyết định mục nào đưa sang tuần sau.
**Cuối phase:** demo, đối chiếu tiêu chí hoàn thành, ghi retrospective ngắn vào `docs/retros/`.

## 12. Sự cố Git thường gặp

| Tình huống | Cách xử lý |
|---|---|
| Lỡ commit lên `main` cục bộ (push bị chặn) | `git switch -c feat/x` (giữ commit), `git switch main`, `git reset --hard origin/main` |
| Nhánh bị tụt so với `main` | `git fetch origin && git rebase origin/main`, rồi `git push --force-with-lease` (chỉ trên nhánh của bạn) |
| Conflict khi rebase | Sửa file, `git add`, `git rebase --continue`. Rối thì `git rebase --abort` |
| Sửa commit cuối chưa push | `git commit --amend` |
| Quên file trong PR | Commit bổ sung rồi push, squash sẽ gộp |
| Muốn bỏ thay đổi chưa commit ở một file | `git restore <file>` |
| Tên nhánh đã merge còn sót | `git branch -d <nhánh>`; `git fetch --prune` (đã bật `fetch.prune`) |
