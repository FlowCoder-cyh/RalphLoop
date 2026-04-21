#!/usr/bin/env bash
set -euo pipefail

#==============================
# FlowSet - Autonomous AI Development Loop
# Version: 3.0.0
#
# v3.0.0 CHANGES:
#   - Obsidian vault 통합 (vault-helpers.sh: 읽기/쓰기/시맨틱 검색)
#   - save_state() → vault state.md 자동 동기화
#   - build_rag_context() → vault 시맨틱 검색 추가 (이전 세션 지식)
#   - preflight() → vault 연결 확인 + graceful degradation
#   - record_pattern() → vault에 패턴 기록
#   - VAULT_ENABLED=false 기본값 (v2.x 하위 호환)
#
# v2.0.0 BASE:
#   - fix_plan.md = READ-ONLY during loop execution
#   - No local commits on main (workers create PRs on branches)
#   - completed_wis.txt = Single source of truth
#   - reconcile_fix_plan() syncs checkboxes at loop END only
#==============================
FLOWSET_VERSION="3.0.0"

# UTF-8 강제 (Windows 한글 깨짐 방지)
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

# Windows 콘솔 UTF-8 (Git Bash / MSYS2)
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
  chcp.com 65001 > /dev/null 2>&1 || true
fi

# macOS/Linux sed -i 호환 래퍼
# macOS BSD sed: sed -i '' 's/...' / Linux GNU sed: sed -i 's/...'
sedi() {
  if [[ "$(uname -s)" == Darwin* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load config (preflight에서 존재 확인하므로 여기서는 soft fail)
if [[ -f .flowsetrc ]]; then
  source .flowsetrc
fi

# v4.0 WI-A2a+A2e: 런타임 state 라이브러리 (lib/state.sh) — 필수
# WI-A2e에서 전역변수 shim 제거 (preflight/worker/merge/vault와 동일 fail-fast 정책).
# flowset.sh/lib/*.sh가 전역변수 직접 참조 0건이 되었으므로 shim 의미 소실.
if [[ -f lib/state.sh ]]; then
  source lib/state.sh
else
  echo "ERROR: lib/state.sh 없음. v4.0부터 모듈 구조(lib/*.sh)입니다." >&2
  echo "  /wi:init 재실행 또는 cp -r ~/.claude/templates/flowset/lib ./" >&2
  exit 1
fi

# v4.0 WI-A2b: 사전 검증 라이브러리 (lib/preflight.sh)
# preflight() 함수는 lib/preflight.sh로 이관됨. 기존 v3.x 프로젝트는 lib/ 복사 필요.
# state.sh와 달리 기능 등가 fallback이 어려워(전체 복제 또는 기능 축소) 필수 로드.
if [[ -f lib/preflight.sh ]]; then
  source lib/preflight.sh
else
  echo "ERROR: lib/preflight.sh 없음. v4.0부터 모듈 구조(lib/*.sh)입니다." >&2
  echo "  다음 중 하나를 수행하세요:" >&2
  echo "  1) /wi:init 재실행 (권장 — 전체 템플릿 동기화)" >&2
  echo "  2) cp -r ~/.claude/templates/flowset/lib ./   (lib 수동 복사)" >&2
  exit 1
fi

# v4.0 WI-A2c: 워커 실행 라이브러리 (lib/worker.sh)
# execute_claude() 함수는 lib/worker.sh로 이관됨. preflight.sh와 동일한 fail-fast 정책.
if [[ -f lib/worker.sh ]]; then
  source lib/worker.sh
else
  echo "ERROR: lib/worker.sh 없음. v4.0부터 모듈 구조(lib/*.sh)입니다." >&2
  echo "  /wi:init 재실행 또는 cp -r ~/.claude/templates/flowset/lib ./" >&2
  exit 1
fi

# v4.0 WI-A2d: 머지 + 병렬 실행 라이브러리 (lib/merge.sh)
# 이관된 7개 함수: wait_for_merge / wait_for_batch_merge / inject_regression_wis /
# safe_sync_main / reconcile_fix_plan / setup_worktree / execute_parallel
# preflight.sh/worker.sh와 동일한 fail-fast 정책.
if [[ -f lib/merge.sh ]]; then
  source lib/merge.sh
else
  echo "ERROR: lib/merge.sh 없음. v4.0부터 모듈 구조(lib/*.sh)입니다." >&2
  echo "  /wi:init 재실행 또는 cp -r ~/.claude/templates/flowset/lib ./" >&2
  exit 1
fi

# v4.0 WI-A2e: Obsidian vault 라이브러리 (lib/vault.sh)
# vault-helpers.sh 19개 함수 이관. .flowset/scripts/vault-helpers.sh는 하위 호환 shim으로 유지.
# VAULT_ENABLED=false면 모든 함수 graceful degradation.
if [[ -f lib/vault.sh ]]; then
  source lib/vault.sh
else
  echo "ERROR: lib/vault.sh 없음. v4.0부터 모듈 구조(lib/*.sh)입니다." >&2
  echo "  /wi:init 재실행 또는 cp -r ~/.claude/templates/flowset/lib ./" >&2
  exit 1
fi

# Defaults (위에서 .flowsetrc가 설정하지 않은 값만 적용)
# MAX_ITERATIONS: fix_plan의 전체 WI 수 + 20% 여유 (검증 재시도 감안)
FIX_PLAN="${FIX_PLAN:-.flowset/fix_plan.md}"
if [[ -z "${MAX_ITERATIONS:-}" && -f "$FIX_PLAN" ]]; then
  _total_wi=$(awk '/^```/{f=!f} !f && /^\- \[[ x]\]/{c++} END{print c+0}' "$FIX_PLAN" 2>/dev/null)
  MAX_ITERATIONS=$(( _total_wi + _total_wi / 5 + 1 ))
  unset _total_wi
fi
MAX_ITERATIONS=${MAX_ITERATIONS:-50}
RATE_LIMIT_PER_HOUR=${RATE_LIMIT_PER_HOUR:-80}
COOLDOWN_SEC=${COOLDOWN_SEC:-5}
ERROR_COOLDOWN_SEC=${ERROR_COOLDOWN_SEC:-30}
PROMPT_FILE="${PROMPT_FILE:-.flowset/PROMPT.md}"
LOG_DIR=".flowset/logs"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Edit,Write,Read,Bash,Glob,Grep}"

# 워커 토큰 제어
MAX_TURNS=${MAX_TURNS:-40}  # 워커당 최대 턴 수 (0=무제한)

# Parallel (1 = 순차, 2+ = 병렬 worktree)
PARALLEL_COUNT=${PARALLEL_COUNT:-1}
WORKTREE_DIR=".worktrees"

# State 상수 (RUNTIME_STATE_KEYS 아님 — 상수/설정)
NO_PROGRESS_LIMIT=${NO_PROGRESS_LIMIT:-3}
CONTEXT_THRESHOLD=${CONTEXT_THRESHOLD:-150000}  # 75% of 200k — 이 이상이면 새 세션

# 영속 상태 파일 (비정상 종료 복구용 — lib/state.sh의 RUNTIME_STATE_FILE과 별개)
STATE_FILE=".flowset/loop_state.json"

# 완료 WI 로컬 추적 (untracked — reset --hard에서 보존됨)
# fix_plan은 READ-ONLY. 이 파일이 유일한 진실의 원천(SSOT)
COMPLETED_FILE=".flowset/completed_wis.txt"

# v4.0 WI-A2e: 런타임 state 초기화 (이중 기록 제거 — 전역변수 선언 삭제, state_set만 유지)
# lib/state.sh가 RUNTIME_STATE_FILE 생성 + 8개 키 ""로 초기화 → 숫자 키 0, 시간 키만 date 주입
state_init
state_set call_count 0
state_set loop_count 0
state_set consecutive_no_progress 0
state_set last_git_sha ""
state_set last_commit_msg ""
state_set rate_limit_start "$(date +%s)"
state_set current_session_id ""
state_set total_cost_usd 0

#==============================
# Section 2: STATE MANAGEMENT
#==============================

save_state() {
  # v4.0 WI-A2a: 변수 참조를 state_get 호출로 전환 (lib/state.sh 시 병렬 안전)
  # lib/state.sh 없는 환경은 shim이 전역변수 값을 그대로 반환하여 기능 동등
  cat > "$STATE_FILE" <<EOF
{
  "loop_count": $(state_get loop_count),
  "call_count": $(state_get call_count),
  "session_id": "$(state_get current_session_id)",
  "total_cost_usd": $(state_get total_cost_usd),
  "last_git_sha": "$(state_get last_git_sha)",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "${1:-running}"
}
EOF

  # v3.0: vault state 동기화 (변수 참조 → state_get 호출 동일 전환)
  local completed_count
  completed_count=$(wc -l < "$COMPLETED_FILE" 2>/dev/null || echo "0")
  vault_sync_state "${1:-running}" "$(state_get loop_count)" "$MAX_ITERATIONS" "$completed_count" "$(state_get total_cost_usd)"
}

restore_state() {
  if [[ -f "$STATE_FILE" ]]; then
    local prev_status prev_loop prev_time prev_cost prev_sha
    prev_status=$(jq -r '.status // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    prev_loop=$(jq -r '.loop_count // 0' "$STATE_FILE" 2>/dev/null || echo "0")
    prev_time=$(jq -r '.timestamp // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
    prev_cost=$(jq -r '.total_cost_usd // 0' "$STATE_FILE" 2>/dev/null || echo "0")
    prev_sha=$(jq -r '.last_git_sha // ""' "$STATE_FILE" 2>/dev/null || echo "")

    # 현재 git SHA와 비교 → 수동 변경 감지
    local current_sha
    current_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")

    if [[ "$prev_status" == "running" || "$prev_status" == "crashed" ]]; then
      log "⚠️ 이전 실행이 비정상 종료됨 (Iteration $prev_loop, $prev_time)"

      if [[ -n "$prev_sha" && "$prev_sha" != "$current_sha" ]]; then
        # 코드가 변경됨 → 세션 재활용 불가
        log "🔀 마지막 실행 이후 코드 변경 감지 (수동 작업 있음)"
        log "   이전 세션 무효화 → 새 세션으로 시작합니다"
        state_set current_session_id ""
      else
        # 코드 변경 없음 → 이전 세션 재활용 가능
        local prev_session
        prev_session=$(jq -r '.session_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
        if [[ -n "$prev_session" ]]; then
          state_set current_session_id "$prev_session"
          log "🔄 이전 세션 복구: ${prev_session:0:8}..."
        fi
      fi

      log "📋 completed_wis.txt + fix_plan.md 기준으로 미완료 WI부터 재개합니다"
      state_set total_cost_usd "$prev_cost"
      state_set last_git_sha "$prev_sha"
      state_set loop_count "$prev_loop"
    elif [[ "$prev_status" == "completed" ]]; then
      log "✅ 이전 실행 정상 완료됨. 새로 시작합니다."
    fi
  fi
}

backup_state_files() {
  cp "$COMPLETED_FILE" "${COMPLETED_FILE}.bak" 2>/dev/null || true
  cp "$STATE_FILE" "${STATE_FILE}.bak" 2>/dev/null || true
}

restore_state_files() {
  if [[ ! -f "$COMPLETED_FILE" && -f "${COMPLETED_FILE}.bak" ]]; then
    mv "${COMPLETED_FILE}.bak" "$COMPLETED_FILE"
  fi
  if [[ ! -f "$STATE_FILE" && -f "${STATE_FILE}.bak" ]]; then
    mv "${STATE_FILE}.bak" "$STATE_FILE"
  fi
  rm -f "${COMPLETED_FILE}.bak" "${STATE_FILE}.bak" 2>/dev/null || true
}

is_wi_completed_locally() {
  # completed_wis.txt에 해당 WI prefix가 있는지 확인
  local wi_line="$1"
  local wi_prefix="${wi_line%% *}"
  [[ -f "$COMPLETED_FILE" ]] && grep -qF "$wi_prefix" "$COMPLETED_FILE" 2>/dev/null
}

mark_wi_done() {
  local wi_name="$1"
  local wi_prefix="${wi_name%% *}"
  # Dedup check
  if [[ -f "$COMPLETED_FILE" ]] && grep -qF "$wi_prefix" "$COMPLETED_FILE" 2>/dev/null; then
    log "  mark_wi_done: ⚠️ 이미 완료 — ${wi_prefix}"
    return 0
  fi
  echo "$wi_prefix" >> "$COMPLETED_FILE"
  log "  mark_wi_done: ✅ ${wi_name}"
  update_wi_history "$wi_name" || true
}

recover_completed_from_history() {
  # Scan git log on main for WI commits, populate completed_wis.txt
  local recovered=0
  while IFS= read -r line; do
    local prefix
    prefix=$(echo "$line" | grep -oE 'WI-[0-9]+-[a-z]+' | head -1)
    [[ -z "$prefix" ]] && continue
    # Check if already in completed_wis.txt
    if [[ -f "$COMPLETED_FILE" ]] && grep -qF "$prefix" "$COMPLETED_FILE" 2>/dev/null; then
      continue
    fi
    # If it has a commit on main, it was completed and merged
    echo "$prefix" >> "$COMPLETED_FILE"
    recovered=$((recovered + 1))
  done < <(git log --oneline main 2>/dev/null | grep -oE '^[a-f0-9]+ WI-[0-9]+-[a-z]+' || true)
  if [[ $recovered -gt 0 ]]; then
    log "🔄 git log에서 ${recovered}건 완료 WI 복구"
  fi
}

cleanup_stale_completed() {
  # completed_wis.txt에 있지만 origin/main에 커밋도 없고 open PR도 없는 항목 제거
  # (PR 충돌로 close된 WI를 재실행하기 위함)
  [[ -f "$COMPLETED_FILE" ]] || return 0
  local removed=0
  local temp_file="${COMPLETED_FILE}.cleanup"
  local owner repo
  owner=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)
  repo=$(gh repo view --json name --jq '.name' 2>/dev/null || true)
  [[ -z "${owner:-}" || -z "${repo:-}" ]] && return 0

  while IFS= read -r prefix; do
    [[ -z "$prefix" ]] && continue
    # origin/main에 이미 [x]이면 유지 (머지 완료)
    if git show origin/main:"$FIX_PLAN" 2>/dev/null | grep -qF -- "- [x] ${prefix}"; then
      echo "$prefix"
      continue
    fi
    # origin/main에 [ ]이면 → PR 상태 확인
    if git show origin/main:"$FIX_PLAN" 2>/dev/null | grep -qF -- "- [ ] ${prefix}"; then
      # open PR 있으면 유지
      local has_open_pr
      has_open_pr=$(gh api graphql -f query="{ search(query: \"repo:${owner}/${repo} is:pr is:open ${prefix}\", type: ISSUE, first: 1) { issueCount } }" --jq '.data.search.issueCount' 2>/dev/null || echo "")
      if [[ "${has_open_pr:-}" == "0" ]]; then
        # git log에 커밋 있으면 유지
        if git log --oneline main 2>/dev/null | grep -q "^[a-f0-9]* ${prefix}"; then
          echo "$prefix"
        else
          removed=$((removed + 1))
          log "🧹 ${prefix}: 커밋 없음 + open PR 없음 → completed_wis에서 제거 (재실행)"
        fi
      elif [[ -z "${has_open_pr:-}" ]]; then
        # gh api 실패 → 유지 (모르면 유지)
        echo "$prefix"
      else
        echo "$prefix"
      fi
    else
      # fix_plan에 없는 항목 → 유지 (다른 이유로 들어왔을 수 있음)
      echo "$prefix"
    fi
  done < "$COMPLETED_FILE" > "$temp_file"
  mv "$temp_file" "$COMPLETED_FILE"
  if [[ $removed -gt 0 ]]; then
    log "🧹 stale completed ${removed}건 제거"
  fi
}

resolve_conflicting_prs() {
  # CONFLICTING 상태의 open PR을 자동 rebase 시도
  # 실패 시 close + completed_wis에서 제거 (다음 iteration에서 재실행)
  local owner repo
  owner=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)
  repo=$(gh repo view --json name --jq '.name' 2>/dev/null || true)
  [[ -z "${owner:-}" || -z "${repo:-}" ]] && return 0

  local conflicting_prs
  conflicting_prs=$(gh pr list --state open --json number,headRefName,title --jq '.[] | "\(.number)|\(.headRefName)|\(.title)"' 2>/dev/null || true)
  [[ -z "${conflicting_prs:-}" ]] && return 0

  while IFS='|' read -r pr_number branch title; do
    [[ -z "$pr_number" ]] && continue

    # mergeable 상태 확인
    local mergeable
    mergeable=$(gh pr view "$pr_number" --json mergeable --jq '.mergeable' 2>/dev/null || true)
    [[ "$mergeable" != "CONFLICTING" ]] && continue

    log "🔀 PR #${pr_number} 충돌 감지 — 자동 rebase 시도: ${title}"

    # rebase 시도
    git fetch origin "$branch" 2>/dev/null || continue
    git checkout "origin/$branch" --detach 2>/dev/null || continue

    if git rebase origin/main 2>/dev/null; then
      # rebase 성공 → force push
      if git push origin "HEAD:$branch" --force-with-lease 2>/dev/null; then
        log "  ✅ rebase 성공 — re-enqueue"
        git checkout main 2>/dev/null || true
        bash .flowset/scripts/enqueue-pr.sh "$pr_number" 2>/dev/null || true
      else
        log "  ⚠️ push 실패 — 스킵"
        git checkout main 2>/dev/null || true
      fi
    else
      # rebase 실패 → close + completed_wis 제거
      git rebase --abort 2>/dev/null || true
      git checkout main 2>/dev/null || true

      log "  ❌ rebase 실패 — PR close + 재실행 예약"
      gh pr close "$pr_number" --comment "자동 rebase 실패 — 루프에서 재실행" 2>/dev/null || true

      # completed_wis에서 해당 WI 제거
      local wi_prefix
      wi_prefix=$(echo "$title" | grep -oE 'WI-[0-9]+-[a-z]+' | head -1)
      if [[ -n "${wi_prefix:-}" && -f "$COMPLETED_FILE" ]]; then
        grep -v "^${wi_prefix}$" "$COMPLETED_FILE" > "${COMPLETED_FILE}.tmp" 2>/dev/null || true
        mv "${COMPLETED_FILE}.tmp" "$COMPLETED_FILE" 2>/dev/null || true
      fi
    fi
  done <<< "$conflicting_prs"
}

#==============================
# Section 3: CLEANUP & TRAPS
#==============================

cleanup_worktrees() {
  if [[ -d "$WORKTREE_DIR" ]]; then
    for wt in "$WORKTREE_DIR"/worker-*; do
      [[ -d "$wt" ]] || continue
      git worktree remove "$wt" --force 2>/dev/null || {
        log "WARN: worktree 제거 실패 — $wt (수동 정리 필요)"
      }
    done
    rmdir "$WORKTREE_DIR" 2>/dev/null || true
    git worktree prune 2>/dev/null || true
  fi
}

cleanup() {
  local exit_code=$?
  printf "\n"
  # Parallel worktree 정리 (잔여물 방지)
  cleanup_worktrees 2>/dev/null || true
  if [[ $exit_code -eq 0 ]]; then
    reconcile_fix_plan 2>/dev/null || true
    # reconcile 후 남은 uncommitted changes 정리 (다음 실행 시 preflight 에러 방지)
    git checkout -- "$FIX_PLAN" 2>/dev/null || true
  else
    log "⚠️ 비정상 종료 (exit code: $exit_code)"
    save_state "crashed"
  fi
  # 미머지 PR 확인
  local open_prs
  open_prs=$(gh pr list --state open --json number,title 2>/dev/null || echo "")
  if [[ -n "$open_prs" && "$open_prs" != "[]" ]]; then
    log "📌 미머지 PR 있음:"
    echo "$open_prs" | sed -n 's/.*"title"\s*:\s*"\([^"]*\)".*/\1/p' | while read -r title; do
      log "  - $title"
    done
  fi
  local counts
  counts=$(count_tasks)
  local completed="${counts%% *}"
  local remaining="${counts##* }"
  log "=== FlowSet 종료 ($(state_get loop_count) iterations) ==="
  log "최종: ${completed} 완료, ${remaining} 남음"
  log "💡 재실행: bash flowset.sh (미완료 WI부터 자동 재개)"
}

trap cleanup EXIT

mkdir -p "$LOG_DIR"

#==============================
# Section 4: PREFLIGHT & VALIDATION
#==============================

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  [[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR"
  echo "$msg" >> "$LOG_DIR/flowset.log"
}

# v4.0 WI-A2b: preflight() 함수는 lib/preflight.sh로 이관됨
# 이 파일 상단의 `source lib/preflight.sh` 블록에서 로드. 본체 정의 없음.
# 기존 v3.x 프로젝트는 /wi:init 재실행 또는 ~/.claude/templates/flowset/lib/ 수동 복사 필요.

check_integrity() {
  local files=("$PROMPT_FILE" "$FIX_PLAN" ".flowset/AGENT.md" ".flowsetrc" ".flowset/guardrails.md")
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      log "CRITICAL: Missing $f - halting"
      return 1
    fi
  done
  return 0
}

validate_post_iteration() {
  local violations=0

  # 1. 커밋 메시지 형식 검증
  local latest_msg prev_commit_msg
  latest_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")
  prev_commit_msg=$(state_get last_commit_msg)
  if [[ -n "$latest_msg" && "$latest_msg" != "$prev_commit_msg" ]]; then
    local pattern="^WI-[0-9]{3,4}-(feat|fix|docs|style|refactor|test|chore|perf|ci|revert) .+"
    local pattern_system="^WI-(chore|docs) .+"
    local pattern_merge="^Merge "
    if [[ ! "$latest_msg" =~ $pattern && ! "$latest_msg" =~ $pattern_system && ! "$latest_msg" =~ $pattern_merge ]]; then
      log "VIOLATION: 커밋 메시지 형식 오류 - $latest_msg"
      violations=$((violations + 1))
    fi
    state_set last_commit_msg "$latest_msg"
  fi

  # 2. .flowset/ 파일 삭제 여부 확인
  for f in "$PROMPT_FILE" "$FIX_PLAN" ".flowset/AGENT.md" ".flowset/guardrails.md"; do
    if [[ ! -f "$f" ]]; then
      log "VIOLATION: FlowSet 파일 삭제됨 - $f"
      violations=$((violations + 1))
    fi
  done

  # 2.5 requirements.md 수정 감지 (사용자 원본 보호)
  if [[ -f ".flowset/requirements.md" ]]; then
    local req_changed
    req_changed=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -F '.flowset/requirements.md' || true)
    if [[ -n "$req_changed" ]]; then
      log "VIOLATION: requirements.md 수정 감지 — 사용자 원본 수정 금지"
      violations=$((violations + 1))
      # 원본 복원
      git checkout HEAD~1 -- .flowset/requirements.md 2>/dev/null || true
    fi
  fi

  # 3. RAG 업데이트 필요 여부 검증
  if [[ -d ".claude/memory/rag" ]]; then
    local changed_files
    changed_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)

    local rag_needed=false
    local rag_reason=""

    if echo "$changed_files" | grep -qE '^(src/)?app/api/'; then
      rag_needed=true
      rag_reason="API 변경"
    fi
    if echo "$changed_files" | grep -qE 'page\.tsx$'; then
      rag_needed=true
      rag_reason="${rag_reason:+$rag_reason + }페이지 변경"
    fi
    if echo "$changed_files" | grep -qE '^prisma/'; then
      rag_needed=true
      rag_reason="${rag_reason:+$rag_reason + }스키마 변경"
    fi

    if [[ "$rag_needed" == true ]]; then
      local rag_updated=false
      echo "$changed_files" | grep -qE '^\.claude/memory/rag/' && rag_updated=true

      if [[ "$rag_updated" == false ]]; then
        log "RAG-CHECK: $rag_reason 감지 — RAG 미업데이트"
        echo "### [$(date '+%Y-%m-%d %H:%M')] RAG 미업데이트: $rag_reason (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
        echo "[RAG-UPDATE-NEEDED] $rag_reason — .claude/memory/rag/ 파일 업데이트 필요" > .flowset/rag_pending.txt
      fi
    fi
    # 이전 pending이 해결됐으면 제거
    if [[ -f ".flowset/rag_pending.txt" ]] && echo "$changed_files" | grep -qE '^\.claude/memory/rag/'; then
      rm -f .flowset/rag_pending.txt
    fi
  fi

  # 4. scope creep 감지 (변경 파일 수 과다)
  local changed_files_all
  changed_files_all=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)
  local file_count
  file_count=$(echo "$changed_files_all" | grep -c '.' 2>/dev/null || echo "0")
  if [[ $file_count -gt 10 ]]; then
    log "WARNING: 변경 파일 ${file_count}개 (10개 초과) — scope creep 의심"
    echo "### [$(date '+%Y-%m-%d %H:%M')] scope creep: ${file_count}개 파일 변경 (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
  fi

  # 5. 금지 파일 수정 감지
  if echo "$changed_files_all" | grep -qE '^\.(env|env\.local)$|^package-lock\.json$' 2>/dev/null; then
    log "WARNING: 금지 파일 수정 감지 (.env/package-lock)"
    echo "### [$(date '+%Y-%m-%d %H:%M')] 금지 파일 수정 감지 (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
  fi

  # 6. 빈 구현 감지 (TODO/placeholder/stub)
  if [[ -n "$changed_files_all" ]]; then
    local incomplete
    incomplete=$(echo "$changed_files_all" | xargs grep -l 'TODO\|FIXME\|placeholder\|stub\|not implemented\|NotImplemented' 2>/dev/null | head -3 || true)
    if [[ -n "$incomplete" ]]; then
      log "WARNING: 불완전 구현 감지 (TODO/placeholder) — $incomplete"
      echo "### [$(date '+%Y-%m-%d %H:%M')] 불완전 구현: $incomplete (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
    fi
  fi

  # 7. API 형식 검증 (contracts/ 존재 시)
  if [[ -f ".flowset/contracts/api-standard.md" ]] && [[ -n "$changed_files_all" ]]; then
    local new_apis
    new_apis=$(echo "$changed_files_all" | grep -E 'route\.(ts|js)$' || true)
    if [[ -n "$new_apis" ]]; then
      for api_file in $new_apis; do
        if [[ -f "$api_file" ]] && ! grep -q "NextResponse\|Response\|json(" "$api_file" 2>/dev/null; then
          log "WARNING: API 형식 미준수 — $api_file"
          echo "### [$(date '+%Y-%m-%d %H:%M')] API 형식 미준수: $api_file (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
        fi
      done
    fi
  fi

  # 8. WI 수용 기준 최소 검증 (키워드 매칭)
  local current_wi_desc
  current_wi_desc=$(get_current_wi 2>/dev/null || true)
  if [[ -n "$current_wi_desc" && -n "$changed_files_all" ]]; then
    # "GET" 수용 기준인데 GET 핸들러 없음
    if echo "$current_wi_desc" | grep -qi "GET" && echo "$changed_files_all" | grep -qE 'route\.(ts|js)$'; then
      local has_get=false
      for rf in $(echo "$changed_files_all" | grep -E 'route\.(ts|js)$'); do
        grep -q "GET\|export.*get\|export.*GET" "$rf" 2>/dev/null && has_get=true
      done
      if [[ "$has_get" == false ]]; then
        log "WARNING: WI에 GET 명시됐으나 API 라우트에 GET 핸들러 없음"
        echo "### [$(date '+%Y-%m-%d %H:%M')] 수용 기준 미충족: GET 핸들러 누락 (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
      fi
    fi
    # "POST" 수용 기준인데 POST 핸들러 없음
    if echo "$current_wi_desc" | grep -qi "POST" && echo "$changed_files_all" | grep -qE 'route\.(ts|js)$'; then
      local has_post=false
      for rf in $(echo "$changed_files_all" | grep -E 'route\.(ts|js)$'); do
        grep -q "POST\|export.*post\|export.*POST" "$rf" 2>/dev/null && has_post=true
      done
      if [[ "$has_post" == false ]]; then
        log "WARNING: WI에 POST 명시됐으나 API 라우트에 POST 핸들러 없음"
        echo "### [$(date '+%Y-%m-%d %H:%M')] 수용 기준 미충족: POST 핸들러 누락 (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
      fi
    fi
  fi

  if [[ $violations -gt 0 ]]; then
    log "POST-VALIDATION: $violations violations detected"
    echo "### [$(date '+%Y-%m-%d %H:%M')] 자동 감지: $violations건 규칙 위반 (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
    return 1
  fi
  return 0
}

#==============================
# Section 5: TASK MANAGEMENT
#==============================

count_tasks() {
  # Total WIs from fix_plan (both [x] and [ ])
  local total
  total=$(awk '/^```/{f=!f} !f && /^\- \[[ x]\]/{c++} END{print c+0}' "$FIX_PLAN" 2>/dev/null)
  # Completed = fix_plan [x] + unique entries in completed_wis.txt not in fix_plan [x]
  local fix_completed
  fix_completed=$(awk '/^```/{f=!f} !f && /^\- \[x\]/{c++} END{print c+0}' "$FIX_PLAN" 2>/dev/null)
  # Count locally completed that aren't already [x] in fix_plan
  local extra_completed=0
  if [[ -f "$COMPLETED_FILE" ]]; then
    while IFS= read -r prefix; do
      [[ -z "$prefix" ]] && continue
      # If fix_plan already has [x] for this prefix, skip (avoid double count)
      if ! awk '/^```/{f=!f} !f && /^\- \[x\]/' "$FIX_PLAN" 2>/dev/null | grep -qF -- "$prefix"; then
        extra_completed=$((extra_completed + 1))
      fi
    done < "$COMPLETED_FILE"
  fi
  local completed=$((fix_completed + extra_completed))
  local unchecked=$((total - completed))
  [[ $unchecked -lt 0 ]] && unchecked=0
  echo "$completed $unchecked"
}

check_all_done() {
  local counts
  counts=$(count_tasks)
  local completed="${counts%% *}"
  local unchecked="${counts##* }"
  # 완료 항목이 0이면서 미완료도 0이면 → 빈 상태 (완료가 아님)
  if [[ "$completed" == "0" && "$unchecked" == "0" ]]; then
    return 1
  fi
  [[ "$unchecked" == "0" ]]
}

get_current_wi() {
  # fix_plan.md에서 첫 번째 미완료 WI 이름 추출 (로컬 완료 목록 필터)
  while IFS= read -r wi; do
    [[ -z "$wi" ]] && continue
    is_wi_completed_locally "$wi" || { echo "$wi"; return; }
  done < <(awk '/^```/{f=!f} !f && /^\- \[ \]/{sub(/^\- \[ \] /,""); sub(/ \| L1:.*$/,""); print}' "$FIX_PLAN" 2>/dev/null)
}

get_all_unchecked_wis() {
  # batch 무관하게 전체 미완료 WI 추출 (로컬 완료 목록 필터)
  while IFS= read -r wi; do
    [[ -z "$wi" ]] && continue
    is_wi_completed_locally "$wi" || echo "$wi"
  done < <(awk '/^```/{f=!f} !f && /^\- \[ \]/{sub(/^\- \[ \] /,""); sub(/ \| L1:.*$/,""); print}' "$FIX_PLAN" 2>/dev/null)
}

get_next_n_wis() {
  local n=${1:-1}
  local count=0

  # 첫 번째 미완료 WI의 batch 태그 확인 (로컬 완료 필터 적용)
  local first_batch=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local wi_name
    wi_name=$(echo "$line" | sed 's/^\- \[ \] //; s/ | L1:.*$//')
    if is_wi_completed_locally "$wi_name"; then
      continue
    fi
    first_batch=$(echo "$line" | grep -oE 'batch:[A-Za-z0-9]+' | sed 's/batch://' || true)
    break
  done < <(awk '/^```/{f=!f} !f && /^\- \[ \]/{print}' "$FIX_PLAN" 2>/dev/null)

  # 미완료 WI 추출 (로컬 완료 필터 + batch 필터)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local wi_name
    wi_name=$(echo "$line" | sed 's/^\- \[ \] //; s/ | L1:.*$//')
    is_wi_completed_locally "$wi_name" && continue

    # batch 필터
    if [[ -n "$first_batch" ]]; then
      echo "$line" | grep -q "batch:$first_batch" || continue
    fi

    echo "$wi_name"
    count=$((count + 1))
    [[ $count -ge $n ]] && break
  done < <(awk '/^```/{f=!f} !f && /^\- \[ \]/{print}' "$FIX_PLAN" 2>/dev/null)
}

check_progress() {
  local current_sha
  current_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")

  # git diff로 uncommitted 변경도 감지
  local has_uncommitted_changes=false
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    has_uncommitted_changes=true
  fi

  local prev_sha prev_no_progress
  prev_sha=$(state_get last_git_sha)
  prev_no_progress=$(state_get consecutive_no_progress)
  if [[ "$current_sha" == "$prev_sha" && "$has_uncommitted_changes" == "false" ]]; then
    prev_no_progress=$((prev_no_progress + 1))
    state_set consecutive_no_progress "$prev_no_progress"
    log "No progress detected ($prev_no_progress/$NO_PROGRESS_LIMIT)"
    if [[ $prev_no_progress -ge $NO_PROGRESS_LIMIT ]]; then
      log "CIRCUIT BREAKER: $NO_PROGRESS_LIMIT iterations without progress - halting"
      return 1
    fi
  else
    state_set consecutive_no_progress 0
    state_set last_git_sha "$current_sha"
  fi
  return 0
}

check_rate_limit() {
  local cur_calls
  cur_calls=$(state_get call_count)
  if [[ $cur_calls -ge $RATE_LIMIT_PER_HOUR ]]; then
    local now elapsed rl_start
    now=$(date +%s)
    rl_start=$(state_get rate_limit_start)
    elapsed=$(( now - rl_start ))
    if [[ $elapsed -lt 3600 ]]; then
      local wait_time=$(( 3600 - elapsed ))
      log "Rate limit ($RATE_LIMIT_PER_HOUR/hr) reached. Waiting ${wait_time}s..."
      sleep "$wait_time"
    fi
    state_set call_count 0
    state_set rate_limit_start "$(date +%s)"
  fi
}

build_context() {
  local counts
  counts=$(count_tasks)
  local completed="${counts%% *}"
  local remaining="${counts##* }"
  local target_wi
  target_wi=$(get_current_wi)
  local rag
  rag=$(build_rag_context "$target_wi")
  cat <<EOF
[FlowSet #$(state_get loop_count)] Completed: $completed | Remaining: $remaining
[TARGET] ${target_wi}
[RULE] 위 TARGET 작업 1개만 처리하고 FLOWSET_STATUS 출력 후 즉시 종료. 다른 WI 절대 금지.
${rag}
EOF
}

#==============================
# Section 6: RAG SYSTEM
#==============================

RAG_DIR=".flowset/rag"

generate_codebase_map() {
  # 프로젝트 파일 구조 + 핵심 정보를 경량 맵으로 생성
  # 워커가 코드베이스를 즉시 파악하도록 지원
  mkdir -p "$RAG_DIR"
  local map_file="$RAG_DIR/codebase-map.md"
  {
    echo "# Codebase Map (auto-generated: $(date '+%Y-%m-%d %H:%M'))"
    echo ""
    echo "## Structure"
    tree -I 'node_modules|.git|.next|dist|.worktrees|.flowset' --dirsfirst -L 3 -F 2>/dev/null \
      || find . -maxdepth 3 -type f ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/.next/*' 2>/dev/null | sort | head -80
    echo ""
    # DB Models
    if [[ -f prisma/schema.prisma ]]; then
      echo "## DB Models"
      grep '^model ' prisma/schema.prisma 2>/dev/null | sed 's/model /- /'
      echo ""
    fi
    # Pages
    local pages
    pages=$(find src -name 'page.tsx' 2>/dev/null | sort)
    if [[ -n "$pages" ]]; then
      echo "## Pages"
      echo "$pages" | sed 's/^/- /'
      echo ""
    fi
    # API Routes
    local apis
    apis=$(find src -name 'route.ts' -path '*/api/*' 2>/dev/null | sort)
    if [[ -n "$apis" ]]; then
      echo "## API Routes"
      echo "$apis" | sed 's/^/- /'
      echo ""
    fi
    # Components (directories only, compact)
    local comps
    comps=$(find src -type d -name 'components' 2>/dev/null)
    if [[ -n "$comps" ]]; then
      echo "## Component Dirs"
      echo "$comps" | while read -r d; do
        echo "- $d/ ($(ls "$d" 2>/dev/null | wc -l) files)"
      done
      echo ""
    fi
  } > "$map_file" 2>/dev/null
  log "📋 codebase-map 생성 완료"
}

update_wi_history() {
  # 완료된 WI의 변경 파일 목록을 기록 → 다음 워커가 참조
  local wi_name="$1"
  mkdir -p "$RAG_DIR"
  local history_file="$RAG_DIR/wi-history.md"
  local wi_prefix="${wi_name%% *}"
  local files_changed=""
  local commit_hash
  commit_hash=$(git log --oneline --all --grep="$wi_prefix" -1 --format="%H" 2>/dev/null)
  if [[ -n "$commit_hash" ]]; then
    files_changed=$(git diff-tree --no-commit-id --name-only -r "$commit_hash" 2>/dev/null | head -10 | tr '\n' ', ')
    files_changed="${files_changed%,}"
  fi
  # 중복 방지
  if ! grep -qF -- "$wi_prefix" "$history_file" 2>/dev/null; then
    echo "- [x] ${wi_name} | ${files_changed:-no-commit}" >> "$history_file"
  fi
}

suggest_relevant_files() {
  # WI 이름에서 키워드를 추출하여 관련 파일 목록 제안
  # 워커의 탐색 tool call을 줄여 토큰 절약
  local wi_name="$1"
  local suggestions=""

  # 1. 영문 키워드 추출 (WI prefix, type, 일반 용어 제외)
  local keywords
  keywords=$(echo "$wi_name" | grep -oE '[A-Za-z]{3,}' \
    | grep -vE '^(WI|feat|fix|docs|test|chore|refactor|style|perf|CRUD|API|KPI|DB)$' \
    | head -5)

  # 2. 한글 키워드 → 영문 패턴 매핑 (고빈도 도메인만)
  local kr_patterns=""
  [[ "$wi_name" == *"대시보드"* ]] && kr_patterns+="dashboard "
  [[ "$wi_name" == *"관리"* ]] && kr_patterns+="admin manage "
  [[ "$wi_name" == *"설정"* ]] && kr_patterns+="settings config "
  [[ "$wi_name" == *"알림"* ]] && kr_patterns+="notification alert "
  [[ "$wi_name" == *"권한"* ]] && kr_patterns+="permission role "
  [[ "$wi_name" == *"예약"* ]] && kr_patterns+="reservation schedule booking "
  [[ "$wi_name" == *"리포트"* || "$wi_name" == *"보고서"* ]] && kr_patterns+="report "
  [[ "$wi_name" == *"직원"* || "$wi_name" == *"사원"* ]] && kr_patterns+="employee staff "
  [[ "$wi_name" == *"결재"* || "$wi_name" == *"승인"* ]] && kr_patterns+="approval "
  [[ "$wi_name" == *"캘린더"* || "$wi_name" == *"일정"* ]] && kr_patterns+="calendar "
  [[ "$wi_name" == *"홈"* ]] && kr_patterns+="home "
  [[ "$wi_name" == *"로그인"* || "$wi_name" == *"인증"* ]] && kr_patterns+="auth login "
  [[ "$wi_name" == *"채팅"* || "$wi_name" == *"메시지"* ]] && kr_patterns+="chat message "
  [[ "$wi_name" == *"프로필"* ]] && kr_patterns+="profile "
  [[ "$wi_name" == *"검색"* ]] && kr_patterns+="search "

  # 3. 키워드로 src/ 파일 검색 (1회 find → grep 필터링으로 최적화)
  local all_keywords="$keywords"$'\n'
  for kw in $kr_patterns; do
    all_keywords+="$kw"$'\n'
  done

  if [[ -d "src" ]]; then
    # 파일 목록 1회 캐싱 → 키워드별 grep (find N회 → 1회로 축소)
    local file_cache
    file_cache=$(find src -type f \( -name "*.tsx" -o -name "*.ts" \) 2>/dev/null)
    if [[ -n "$file_cache" ]]; then
      while IFS= read -r kw; do
        [[ -z "$kw" ]] && continue
        local found
        found=$(echo "$file_cache" | grep -i -- "$kw" | head -3)
        [[ -n "$found" ]] && suggestions+="$found"$'\n'
      done <<< "$all_keywords"
    fi
  fi

  # 4. wi-history에서 유사 WI의 파일 패턴 재활용
  if [[ -f "$RAG_DIR/wi-history.md" ]]; then
    while IFS= read -r kw; do
      [[ -z "$kw" ]] && continue
      local hist_files
      hist_files=$(grep -i -- "$kw" "$RAG_DIR/wi-history.md" 2>/dev/null \
        | sed 's/.*| //' | tr ',' '\n' | sed 's/^ *//' \
        | grep -E '\.(tsx?|ts|prisma)$' | head -3)
      [[ -n "$hist_files" ]] && suggestions+="$hist_files"$'\n'
    done <<< "$keywords"
  fi

  # 5. DB 관련 WI → prisma 스키마 힌트
  if [[ "$wi_name" == *"DB"* || "$wi_name" == *"스키마"* || "$wi_name" == *"테이블"* || "$wi_name" == *"모델"* ]]; then
    [[ -f "prisma/schema.prisma" ]] && suggestions+="prisma/schema.prisma"$'\n'
  fi

  # 중복 제거 + 최대 10개
  if [[ -n "$suggestions" ]]; then
    echo "$suggestions" | sed '/^$/d' | sort -u | head -10
  fi
}

record_pattern() {
  # 워커 완료 후 성공/실패 패턴 기록 → 다음 워커가 학습
  # $1: WI 이름, $2: result (merged|skipped|conflict|timeout), $3: files changed (comma-sep), $4: elapsed seconds
  local wi_name="$1"
  local result="$2"
  local files="${3:-}"
  local elapsed="${4:-0}"
  mkdir -p "$RAG_DIR"
  local patterns_file="$RAG_DIR/patterns.md"

  # WI에서 타입 추출 (feat, fix, etc.)
  local wi_type
  wi_type=$(echo "$wi_name" | grep -oE '(feat|fix|docs|test|chore|refactor|style|perf)' | head -1)
  wi_type="${wi_type:-unknown}"

  # 도메인 키워드 추출 (한글 + 영문)
  local domain
  domain=$(echo "$wi_name" | sed 's/WI-[0-9]*-[a-z]* //' | cut -c1-30)

  # 패턴 1줄 기록
  local timestamp
  timestamp=$(date '+%m-%d %H:%M')
  echo "- ${result} | ${wi_type} | ${domain} | ${elapsed}s | ${files:-none}" >> "$patterns_file"

  # 최근 50건만 유지 (오래된 패턴 자동 정리)
  if [[ -f "$patterns_file" ]] && [[ $(wc -l < "$patterns_file") -gt 50 ]]; then
    tail -50 "$patterns_file" > "${patterns_file}.tmp" 2>/dev/null && mv "${patterns_file}.tmp" "$patterns_file" 2>/dev/null || true
  fi

  # v3.0: vault에도 패턴 기록
  vault_record "patterns" "iter-$(state_get loop_count).md" \
    "- ${result} | ${wi_type} | ${domain} | ${elapsed}s | ${files:-none}" 2>/dev/null || true
}

log_trace() {
  # 구조화된 trace 기록 (JSON Lines) — eval harness 데이터
  # $1: WI 이름, $2: result, $3: files changed count, $4: elapsed seconds
  local wi_name="${1:-}" result="${2:-}" files_count="${3:-0}" elapsed="${4:-0}"
  local trace_file=".flowset/logs/trace.jsonl"
  mkdir -p .flowset/logs

  local cost="${iteration_cost:-0}"
  local turns="${MAX_TURNS:-0}"

  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"iter\":$(state_get loop_count),\"wi\":\"${wi_name}\",\"result\":\"${result}\",\"files\":${files_count},\"sec\":${elapsed},\"cost\":${cost}}" >> "$trace_file" 2>/dev/null || true

  # 최근 200건만 유지
  if [[ -f "$trace_file" ]] && [[ $(wc -l < "$trace_file" 2>/dev/null || echo 0) -gt 200 ]]; then
    tail -200 "$trace_file" > "${trace_file}.tmp" 2>/dev/null && mv "${trace_file}.tmp" "$trace_file" 2>/dev/null || true
  fi
}

build_rag_context() {
  # 워커에게 주입할 RAG 컨텍스트 조립 (토큰 예산 ~3K)
  # $1: WI 이름 (optional — 파일 힌트 생성용)
  local wi_name="${1:-}"
  local parts=""

  # 1. Codebase map (최대 80줄)
  if [[ -f "$RAG_DIR/codebase-map.md" ]]; then
    parts+="[CODEBASE MAP]
$(head -80 "$RAG_DIR/codebase-map.md")
"
  fi

  # 2. WI history (최근 20건)
  if [[ -f "$RAG_DIR/wi-history.md" ]]; then
    parts+="[COMPLETED WIs — 아래 파일은 이미 구현됨, 중복 구현 금지]
$(tail -20 "$RAG_DIR/wi-history.md")
"
  fi

  # 3. WI별 관련 파일 힌트 (탐색 토큰 절약)
  if [[ -n "$wi_name" ]]; then
    local relevant
    relevant=$(suggest_relevant_files "$wi_name")
    if [[ -n "$relevant" ]]; then
      parts+="[RELEVANT FILES — 이 파일들을 먼저 확인하세요. 불필요한 Glob/Grep 탐색을 줄이세요]
$(echo "$relevant" | sed 's/^/- /')
"
    fi
  fi

  # 4. 학습된 패턴 (최근 실패 패턴 우선 — 같은 실수 방지)
  if [[ -f "$RAG_DIR/patterns.md" ]]; then
    local fail_patterns
    fail_patterns=$(grep -E '^- (skipped|conflict|timeout)' "$RAG_DIR/patterns.md" 2>/dev/null | tail -10)
    local success_patterns
    success_patterns=$(grep -E '^- merged' "$RAG_DIR/patterns.md" 2>/dev/null | tail -5)
    if [[ -n "$fail_patterns" || -n "$success_patterns" ]]; then
      parts+="[PATTERNS — 이전 워커 결과. 실패 패턴을 반복하지 마세요]
${fail_patterns:+실패:
$fail_patterns
}${success_patterns:+성공:
$success_patterns
}"
    fi
  fi

  # 5. RAG pending (이전 워커가 RAG 업데이트 놓친 경우)
  if [[ -f ".flowset/rag_pending.txt" ]]; then
    parts+="[RAG UPDATE REQUIRED]
$(cat .flowset/rag_pending.txt)
이전 워커가 RAG 업데이트를 놓쳤습니다. 이번 작업에서 관련 .claude/memory/rag/ 파일도 함께 업데이트하세요.
"
  fi

  # 6. Guardrails
  if [[ -f ".flowset/guardrails.md" ]]; then
    parts+="[GUARDRAILS — 반드시 준수]
$(cat .flowset/guardrails.md)
"
  fi

  # 6. Regression issues (open: 전체 body, 재발 방지)
  local regression_issues
  regression_issues=$(gh issue list --label regression --state open --json number,title,body --jq '.[] | "### #\(.number): \(.title)\n\(.body)\n"' 2>/dev/null || true)
  if [[ -n "${regression_issues:-}" ]]; then
    parts+="[KNOWN ISSUES — 이전 CI/e2e 실패. 같은 실수 반복 금지]

${regression_issues}
"
  fi

  # 7. v3.0: Vault 시맨틱 검색 (이전 세션 지식)
  if [[ "${VAULT_ENABLED:-false}" == "true" && -n "$wi_name" ]]; then
    local vault_results
    vault_results=$(vault_search "$wi_name" 2>/dev/null)
    if [[ -n "$vault_results" && "$vault_results" != "[]" ]]; then
      # 상위 3개 결과의 파일명만 추출
      local vault_files
      vault_files=$(echo "$vault_results" | jq -r '.[0:3] | .[].filename' 2>/dev/null)
      if [[ -n "$vault_files" ]]; then
        local vault_content=""
        while IFS= read -r vf; do
          [[ -z "$vf" ]] && continue
          local vc
          vc=$(vault_read "$vf" 2>/dev/null | head -30)
          [[ -n "$vc" ]] && vault_content+="--- ${vf} ---
${vc}
"
        done <<< "$vault_files"
        if [[ -n "$vault_content" ]]; then
          parts+="[VAULT KNOWLEDGE — 이전 세션 관련 정보]
${vault_content}"
        fi
      fi
    fi
  fi

  echo "$parts"
}


# v4.0 WI-A2c: execute_claude() 함수는 lib/worker.sh로 이관됨
# 이 파일 상단의 `source lib/worker.sh` 블록에서 로드. 본체 정의 없음.
# 기존 v3.x 프로젝트는 /wi:init 재실행 또는 ~/.claude/templates/flowset/lib/ 수동 복사 필요.

#==============================
# Section 9: MAIN LOOP
#==============================

main() {
  # Pre-flight checks
  preflight || exit 1

  # 이전 실행 상태 복구 확인
  restore_state

  # git log에서 완료 WI 복구 (crash 후 completed_wis.txt 보충)
  recover_completed_from_history

  # stale completed 정리 (PR 충돌로 close된 WI 재실행)
  cleanup_stale_completed

  # 충돌 PR 자동 rebase (실패 시 close → 재실행)
  resolve_conflicting_prs

  # regression issue → fix_plan에 WI-NNN-1-fix 추가
  inject_regression_wis

  # 병렬 모드: 이전 실행의 stale worktree/branch 정리
  if [[ $PARALLEL_COUNT -gt 1 ]]; then
    cleanup_worktrees 2>/dev/null || true
    # stale parallel branches 정리
    local stale_branches
    stale_branches=$(git branch --list 'parallel/worker-*' 2>/dev/null || true)
    if [[ -n "$stale_branches" ]]; then
      echo "$stale_branches" | while read -r b; do
        b=$(echo "$b" | tr -d ' *')
        git branch -D "$b" 2>/dev/null || true
      done
      log "🧹 이전 병렬 브랜치 정리 완료"
    fi
  fi

  # RAG: codebase-map 생성 (없거나 1시간 이상 지난 경우)
  if [[ ! -f "$RAG_DIR/codebase-map.md" ]] || [[ $(find "$RAG_DIR/codebase-map.md" -mmin +60 2>/dev/null) ]]; then
    generate_codebase_map || true
  fi

  log "=== FlowSet v${FLOWSET_VERSION} Started ==="
  log "Max iterations: $MAX_ITERATIONS | Rate limit: $RATE_LIMIT_PER_HOUR/hr"
  if [[ $PARALLEL_COUNT -gt 1 ]]; then
    log "Mode: 병렬 (${PARALLEL_COUNT}x worktree)"
  else
    log "Mode: 순차"
  fi
  log "Allowed tools: $ALLOWED_TOOLS"

  state_set last_git_sha "$(git rev-parse HEAD 2>/dev/null || echo "none")"
  state_set last_commit_msg "$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")"

  local cur_loop
  cur_loop=$(state_get loop_count)
  while [[ $cur_loop -lt $MAX_ITERATIONS ]]; do
    cur_loop=$((cur_loop + 1))
    state_set loop_count "$cur_loop"
    log "--- Iteration $cur_loop/$MAX_ITERATIONS ---"

    # 0. RAG: codebase-map 10 iteration마다 갱신
    if [[ $((cur_loop % 10)) -eq 0 ]]; then
      generate_codebase_map || true
    fi

    # 1. Integrity check
    check_integrity || break

    # 2. All tasks done?
    if check_all_done; then
      log "All tasks in fix_plan.md are complete!"
      break
    fi

    if [[ $PARALLEL_COUNT -gt 1 ]]; then
      #--- Parallel mode ---
      local counts completed unchecked total pct
      counts=$(count_tasks)
      completed="${counts%% *}"
      unchecked="${counts##* }"
      total=$((completed + unchecked))
      pct=0; [[ $total -gt 0 ]] && pct=$((completed * 100 / total))
      log "📊 진행률: $completed/$total ($pct%) — 병렬 ${PARALLEL_COUNT}x 실행"

      check_rate_limit

      local result=0
      execute_parallel || result=$?

      validate_post_iteration || {
        log "Post-validation failed - check guardrails.md"
      }

      # 병렬 모드: batch 전체 머지 대기
      local batch_prs
      batch_prs=$(gh pr list --state open --json number --jq '.[].number' 2>/dev/null || true)
      if [[ -n "$batch_prs" ]]; then
        local pr_array=()
        while IFS= read -r pr; do
          [[ -n "$pr" ]] && pr_array+=("$pr")
        done <<< "$batch_prs"
        if [[ ${#pr_array[@]} -gt 0 ]]; then
          wait_for_batch_merge "${pr_array[@]}"
        fi
      fi
      safe_sync_main
      state_set last_git_sha "$(git rev-parse HEAD 2>/dev/null || echo "none")"

      # 병렬 모드: 검증 에이전트 실행
      if [[ -f ".flowset/scripts/verify-requirements.sh" && -f ".flowset/requirements.md" ]]; then
        log "🔍 검증 에이전트 실행 (병렬 batch 완료 후)..."
        local verify_result=0
        bash .flowset/scripts/verify-requirements.sh || verify_result=$?
        if [[ $verify_result -eq 2 ]]; then
          log "⚠️ 검증 에이전트: 요구사항 누락 감지"
          if [[ -f ".flowset/verify-result.md" ]]; then
            echo "### [$(date '+%Y-%m-%d %H:%M')] 검증 에이전트 — 요구사항 누락 (Iteration #$(state_get loop_count), 병렬)" >> .flowset/guardrails.md
            grep -E '^- (❌|⚠️)' .flowset/verify-result.md >> .flowset/guardrails.md 2>/dev/null || true
          fi
        fi
      fi

      check_progress || break
      save_state "running"

      if [[ $result -ne 0 ]]; then
        sleep "$ERROR_COOLDOWN_SEC"
      else
        sleep "$COOLDOWN_SEC"
      fi
    else
      #--- Sequential mode (기존 로직) ---
      local current_wi counts completed unchecked total wi_num
      current_wi=$(get_current_wi)
      counts=$(count_tasks)
      completed="${counts%% *}"
      unchecked="${counts##* }"
      total=$((completed + unchecked))
      wi_num=$((completed + 1))
      local pct=0
      if [[ $total -gt 0 ]]; then pct=$((completed * 100 / total)); fi
      log "📋 WI #$wi_num/$total: $current_wi"
      log "📊 진행률: $completed/$total ($pct%)"

      check_rate_limit

      local context
      context=$(build_context)

      local iter_start
      iter_start=$(date +%s)

      local result=0
      execute_claude "$context" || result=$?

      local iter_elapsed=$(( $(date +%s) - iter_start ))

      validate_post_iteration || {
        log "Post-validation failed - check guardrails.md"
      }

      # 검증 에이전트 실행 (구현-검증 분리)
      if [[ -f ".flowset/scripts/verify-requirements.sh" && -f ".flowset/requirements.md" ]]; then
        log "🔍 검증 에이전트 실행..."
        local verify_result=0
        bash .flowset/scripts/verify-requirements.sh || verify_result=$?
        if [[ $verify_result -eq 2 ]]; then
          log "⚠️ 검증 에이전트: 요구사항 누락 감지 — guardrails 기록"
          if [[ -f ".flowset/verify-result.md" ]]; then
            echo "### [$(date '+%Y-%m-%d %H:%M')] 검증 에이전트 — 요구사항 누락 (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md
            grep -E '^- (❌|⚠️)' .flowset/verify-result.md >> .flowset/guardrails.md 2>/dev/null || true
          fi
        fi
      fi

      # 순차 모드: 머지 대기 → 완료 기록
      # 워커가 생성한 브랜치 감지 (현재 브랜치 또는 최근 push한 브랜치)
      local worker_branch
      worker_branch=$(git branch --show-current 2>/dev/null || echo "main")
      if [[ "$worker_branch" != "main" ]]; then
        # 워커가 브랜치에서 작업 완료 → 머지 대기
        local merge_result=0
        wait_for_merge "$worker_branch" || merge_result=$?
        safe_sync_main
        local fc=$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo "0")
        if [[ $merge_result -eq 0 ]]; then
          mark_wi_done "$current_wi" || true
          record_pattern "$current_wi" "merged" "" "$iter_elapsed" || true
          log_trace "$current_wi" "merged" "$fc" "$iter_elapsed"
        else
          record_pattern "$current_wi" "skipped" "" "$iter_elapsed" || true
          log_trace "$current_wi" "skipped" "0" "$iter_elapsed"
        fi
        state_set last_git_sha "$(git rev-parse HEAD 2>/dev/null || echo "none")"
      else
        # main에 있음 → SHA 변경으로 판단 (기존 로직)
        local current_sha_now prev_sha_loop
        current_sha_now=$(git rev-parse HEAD 2>/dev/null || echo "none")
        prev_sha_loop=$(state_get last_git_sha)
        if [[ "$current_sha_now" != "$prev_sha_loop" ]]; then
          mark_wi_done "$current_wi" || true
          state_set last_git_sha "$current_sha_now"
          record_pattern "$current_wi" "merged" "" "$iter_elapsed" || true
          log_trace "$current_wi" "merged" "0" "$iter_elapsed"
        else
          record_pattern "$current_wi" "skipped" "" "$iter_elapsed" || true
          log_trace "$current_wi" "skipped" "0" "$iter_elapsed"
        fi
      fi

      check_progress || break
      save_state "running"

      case $result in
        0) sleep "$COOLDOWN_SEC" ;;
        1) sleep "$ERROR_COOLDOWN_SEC" ;;
        2) # Exit signal
           if check_all_done; then
             log "Exit signal confirmed - all tasks done"
             break
           else
             log "Exit signal but tasks remain - continuing"
             sleep "$COOLDOWN_SEC"
           fi
           ;;
      esac
    fi
  done

  # 종료 이유에 따른 상태 저장
  if check_all_done 2>/dev/null; then
    save_state "completed"
  else
    save_state "stopped"
  fi
}

main "$@"
