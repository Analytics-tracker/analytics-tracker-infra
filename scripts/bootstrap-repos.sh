#!/usr/bin/env bash
# Tạo repo trong GitHub Organization theo từng nhóm phase.
# Yêu cầu: GitHub CLI (gh) đã đăng nhập, quyền tạo repo trong organization.
# Dùng:  ORG=analytics-tracker bash scripts/bootstrap-repos.sh phase0|phase1|phase2|phase3|phase4|all
# Chưa chạy thử với tài khoản thật. Đọc kỹ trước khi chạy.
set -euo pipefail

ORG="${ORG:?Hay dat ORG, vi du ORG=analytics-tracker}"
GROUP="${1:-}"
WORKDIR="${WORKDIR:-$HOME/work/analytics-tracker}"

command -v gh >/dev/null || { echo "Can cai GitHub CLI (gh)"; exit 1; }
gh auth status >/dev/null || { echo "Chay 'gh auth login' truoc"; exit 1; }

# ten|mo ta|gitignore (rong neu khong dung)
repos_phase0=(
  "analytics-tracker-infra|Docs, Docker Compose, observability and e2e for Analytics Tracker|"
  "analytics-tracker-contracts|Protobuf, gRPC and OpenAPI contracts for Analytics Tracker|"
)
repos_phase1=(
  "analytics-tracker-ingest|HTTP ingestion service: validation, rate limiting, Kafka producer|Go"
  "analytics-tracker-sdk-js|JavaScript tracking SDK: batching, sendBeacon, retry|Node"
)
repos_phase2=(
  "analytics-tracker-processor|Kafka consumer: enrichment, dedup, ClickHouse writer, DLQ|Go"
)
repos_phase3=(
  "analytics-tracker-query|Analytics API: queries, auth, projects, SSE|Go"
)
repos_phase4=(
  "analytics-tracker-alert|Alert rules, cooldown, webhook delivery with HMAC|Go"
  "analytics-tracker-dashboard|React dashboard with real-time charts|Node"
)

labels=(
  "phase:0|0e8a16|Foundations"
  "phase:1|1d76db|Core Ingestion"
  "phase:2|1d76db|Event Processing"
  "phase:3|1d76db|Analytics Query"
  "phase:4|1d76db|Dashboard and Alerting"
  "phase:5|1d76db|Production Engineering"
  "type:feat|a2eeef|New feature"
  "type:fix|d73a4a|Bug fix"
  "type:chore|ededed|Maintenance"
  "type:docs|0075ca|Documentation"
  "type:spike|fbca04|Time-boxed experiment"
  "priority:high|b60205|High priority"
  "blocked|000000|Blocked by something"
)

create_repo() {
  local name="$1" desc="$2" gitignore="$3"
  local full="$ORG/$name"

  if gh repo view "$full" >/dev/null 2>&1; then
    echo "[skip] $full da ton tai"
  else
    echo "[create] $full"
    local args=(--public --description "$desc" --add-readme --license mit)
    [[ -n "$gitignore" ]] && args+=(--gitignore "$gitignore")
    gh repo create "$full" "${args[@]}"
  fi

  echo "[settings] $full: chi squash merge, tu xoa nhanh"
  gh repo edit "$full" \
    --enable-squash-merge \
    --enable-merge-commit=false \
    --enable-rebase-merge=false \
    --delete-branch-on-merge

  for l in "${labels[@]}"; do
    IFS='|' read -r lname lcolor ldesc <<<"$l"
    gh label create "$lname" --repo "$full" --color "$lcolor" --description "$ldesc" --force >/dev/null
  done

  mkdir -p "$WORKDIR"
  if [[ ! -d "$WORKDIR/$name" ]]; then
    gh repo clone "$full" "$WORKDIR/$name"
  fi
}

run_group() {
  local ref="$1[@]"   # tuong thich bash 3.2 (macOS), khong dung nameref
  for item in "${!ref}"; do
    IFS='|' read -r n d g <<<"$item"
    create_repo "$n" "$d" "$g"
  done
}

case "$GROUP" in
  phase0) run_group repos_phase0 ;;
  phase1) run_group repos_phase1 ;;
  phase2) run_group repos_phase2 ;;
  phase3) run_group repos_phase3 ;;
  phase4) run_group repos_phase4 ;;
  all)    for g in repos_phase0 repos_phase1 repos_phase2 repos_phase3 repos_phase4; do run_group "$g"; done ;;
  *) echo "Dung: ORG=<org> $0 phase0|phase1|phase2|phase3|phase4|all"; exit 1 ;;
esac

echo "Xong. Repo duoc clone vao $WORKDIR"
echo "Buoc tiep theo: tao ruleset cho nhanh main (xem docs/07-github-setup.md, buoc 6)."
