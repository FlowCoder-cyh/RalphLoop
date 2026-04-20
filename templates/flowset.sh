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

# Vault helpers (v3.0 — VAULT_ENABLED=false이면 모든 호출 무동작)
if [[ -f .flowset/scripts/vault-helpers.sh ]]; then
  source .flowset/scripts/vault-helpers.sh
fi

# v4.0 WI-A2a: 런타임 state 라이브러리 (lib/state.sh)
# 있으면 병렬 안전 파일 기반 state 관리, 없으면 전역변수 shim 폴백 (v3.x 호환)
# 후속 WI-A2b~e에서 나머지 함수 내 $loop_count 등 직접 참조를 state_get/set으로 점진 전환
if [[ -f lib/state.sh ]]; then
  source lib/state.sh
else
  # fallback shim — lib/state.sh 없는 기존 프로젝트에서 save/restore_state가 작동하도록
  # state_get KEY → 전역변수 $KEY 값 echo (없으면 빈 문자열)
  # state_set KEY VAL → 전역변수 $KEY = VAL 할당
  # 보안 주: KEY는 반드시 RUNTIME_STATE_KEYS 8개(영문+언더스코어) 이름만 전달.
  #        사용자 입력을 KEY로 직접 주입 금지(eval 취약점 방지). 값(VAL)은 인용 처리됨.
  state_get() { local k="${1:-}"; [[ -z "$k" ]] && return 0; eval "printf '%s' \"\${$k:-}\""; }
  state_set() { local k="${1:-}" v="${2:-}"; [[ -z "$k" ]] && return 1; eval "$k=\"\$v\""; }
  state_init() { :; }  # 전역변수는 이미 선언됨 (:82-93)
  state_snapshot() { :; }
  state_restore() { :; }
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

# State
call_count=0
loop_count=0
consecutive_no_progress=0
last_git_sha=""
last_commit_msg=""
rate_limit_start=$(date +%s)
NO_PROGRESS_LIMIT=${NO_PROGRESS_LIMIT:-3}

# Session continuity (토큰 절약)
CONTEXT_THRESHOLD=${CONTEXT_THRESHOLD:-150000}  # 75% of 200k — 이 이상이면 새 세션
current_session_id=""
total_cost_usd=0

# 상태 파일 (비정상 종료 복구용)
STATE_FILE=".flowset/loop_state.json"

# 완료 WI 로컬 추적 (untracked — reset --hard에서 보존됨)
# fix_plan은 READ-ONLY. 이 파일이 유일한 진실의 원천(SSOT)
COMPLETED_FILE=".flowset/completed_wis.txt"

# v4.0 WI-A2a: 런타임 state 초기화 + 전역변수 → state 동기화
# lib/state.sh가 있으면 파일 기반 격리 활성, 없으면 shim(전역변수 그대로) 동작
state_init
state_set call_count "$call_count"
state_set loop_count "$loop_count"
state_set consecutive_no_progress "$consecutive_no_progress"
state_set last_git_sha "$last_git_sha"
state_set last_commit_msg "$last_commit_msg"
state_set rate_limit_start "$rate_limit_start"
state_set current_session_id "$current_session_id"
state_set total_cost_usd "$total_cost_usd"

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
        current_session_id=""
        state_set current_session_id ""
      else
        # 코드 변경 없음 → 이전 세션 재활용 가능
        local prev_session
        prev_session=$(jq -r '.session_id // ""' "$STATE_FILE" 2>/dev/null || echo "")
        if [[ -n "$prev_session" ]]; then
          current_session_id="$prev_session"
          state_set current_session_id "$prev_session"
          log "🔄 이전 세션 복구: ${prev_session:0:8}..."
        fi
      fi

      log "📋 completed_wis.txt + fix_plan.md 기준으로 미완료 WI부터 재개합니다"
      total_cost_usd=$prev_cost
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
  log "=== FlowSet 종료 (${loop_count} iterations) ==="
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

preflight() {
  local errors=0

  # claude CLI 확인
  if ! command -v claude &> /dev/null; then
    echo "ERROR: claude CLI가 설치되어 있지 않습니다."
    errors=$((errors + 1))
  fi

  # gh CLI 확인
  if ! command -v gh &> /dev/null; then
    echo "ERROR: gh CLI가 설치되어 있지 않습니다."
    errors=$((errors + 1))
  elif ! gh auth status &> /dev/null; then
    echo "ERROR: gh CLI가 인증되지 않았습니다. 'gh auth login'을 실행하세요."
    errors=$((errors + 1))
  fi

  # git 확인
  if ! git rev-parse --git-dir &> /dev/null; then
    echo "ERROR: git 저장소가 아닙니다."
    errors=$((errors + 1))
  fi

  # jq 확인 (v4.0부터 필수 — execute_claude()의 JSON 응답 파싱에 사용)
  if ! command -v jq &> /dev/null; then
    echo "ERROR: jq가 설치되어 있지 않습니다. v4.0부터 필수 의존성입니다."
    echo "  Windows: winget install jqlang.jq"
    echo "  macOS:   brew install jq"
    echo "  Linux:   apt install jq  (또는 yum install jq)"
    errors=$((errors + 1))
  fi

  # 필수 파일 확인
  local files=("$PROMPT_FILE" "$FIX_PLAN" ".flowset/AGENT.md" ".flowsetrc" ".flowset/guardrails.md")
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "ERROR: 필수 파일 없음: $f"
      errors=$((errors + 1))
    fi
  done

  # Git hooks 설치 확인 (clone 후 미설치 대응)
  if [[ -d ".flowset/hooks" ]]; then
    for hook in .flowset/hooks/*; do
      [[ -f "$hook" ]] || continue
      local hook_name
      hook_name=$(basename "$hook")
      if [[ ! -f ".git/hooks/$hook_name" ]]; then
        echo "⚠️  Git hook 미설치 감지: $hook_name → 자동 설치"
        cp "$hook" ".git/hooks/$hook_name"
        chmod +x ".git/hooks/$hook_name"
      fi
    done
  fi

  # fix_plan에 실제 WI가 있는지 확인 (빈 상태 방지)
  # completed_wis.txt 반영: fix_plan [ ] 중 로컬 완료 항목 제외
  local unchecked
  unchecked=$(get_all_unchecked_wis 2>/dev/null | wc -l)
  if [[ "$unchecked" == "0" ]]; then
    local total_wis
    total_wis=$(grep -c '^\- \[' "$FIX_PLAN" 2>/dev/null || echo "0")
    if [[ "$total_wis" == "0" ]]; then
      echo "ERROR: fix_plan.md에 WI가 없습니다. /wi:start로 WI를 생성하세요."
      errors=$((errors + 1))
    else
      echo "✅ 모든 WI가 완료되었습니다."
      return 0
    fi
  fi

  # 병렬 모드: uncommitted changes 감지 (자동 커밋하지 않음 — v2.0.0)
  if [[ ${PARALLEL_COUNT:-1} -gt 1 ]]; then
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      echo "ERROR: uncommitted changes가 있습니다. 병렬 모드 시작 전 커밋하세요."
      echo "  git status 로 변경사항을 확인하세요."
      errors=$((errors + 1))
    fi
  fi

  # 병렬 모드: stale worktree/branch 자동 정리
  if [[ ${PARALLEL_COUNT:-1} -gt 1 ]]; then
    local stale_wt
    # Windows 경로 정규화: pwd는 /c/... 반환, git worktree list는 C:/... 반환
    local main_wt
    main_wt=$(cd "$(pwd)" && pwd -W 2>/dev/null || pwd)
    stale_wt=$(git worktree list --porcelain 2>/dev/null | grep "^worktree " | sed 's/^worktree //' | grep -v "^${main_wt}$" | grep -v "^$(pwd)$")
    if [[ -n "$stale_wt" ]]; then
      echo "🧹 stale worktree 정리 중..."
      while IFS= read -r wt; do
        git worktree remove "$wt" --force 2>/dev/null || {
          log "WARN: stale worktree 제거 실패 — $wt (수동 정리 필요)"
        }
      done <<< "$stale_wt"
      git worktree prune 2>/dev/null || true
    fi
    local stale_br
    stale_br=$(git branch --list 'parallel/*' 2>/dev/null)
    if [[ -n "$stale_br" ]]; then
      echo "🧹 stale parallel 브랜치 정리 중..."
      while IFS= read -r b; do
        b=$(echo "$b" | tr -d ' *')
        [[ -n "$b" ]] && git branch -D "$b" 2>/dev/null || true
      done <<< "$stale_br"
    fi
  fi

  # v3.0: Obsidian vault 연결 확인 (실패해도 비차단 — graceful degradation)
  if [[ "${VAULT_ENABLED:-false}" == "true" ]]; then
    if vault_check; then
      log "Obsidian vault 연결 확인 (${VAULT_URL})"
      vault_init_project
    else
      log "Obsidian vault 연결 실패 — 파일 기반 RAG만 사용"
    fi
  fi

  # v3.0: 기술부채 임계치 경고 (비차단)
  local debt_warning
  debt_warning=$(vault_check_tech_debt 10 2>/dev/null)
  if [[ -n "$debt_warning" ]]; then
    log "WARN: $debt_warning"
  fi

  if [[ $errors -gt 0 ]]; then
    echo ""
    echo "$errors개 오류. FlowSet을 시작할 수 없습니다."
    return 1
  fi
  return 0
}

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
  local latest_msg
  latest_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")
  if [[ -n "$latest_msg" && "$latest_msg" != "$last_commit_msg" ]]; then
    local pattern="^WI-[0-9]{3,4}-(feat|fix|docs|style|refactor|test|chore|perf|ci|revert) .+"
    local pattern_system="^WI-(chore|docs) .+"
    local pattern_merge="^Merge "
    if [[ ! "$latest_msg" =~ $pattern && ! "$latest_msg" =~ $pattern_system && ! "$latest_msg" =~ $pattern_merge ]]; then
      log "VIOLATION: 커밋 메시지 형식 오류 - $latest_msg"
      violations=$((violations + 1))
    fi
    last_commit_msg="$latest_msg"
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
        echo "### [$(date '+%Y-%m-%d %H:%M')] RAG 미업데이트: $rag_reason (Iteration #$loop_count)" >> .flowset/guardrails.md
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
    echo "### [$(date '+%Y-%m-%d %H:%M')] scope creep: ${file_count}개 파일 변경 (Iteration #$loop_count)" >> .flowset/guardrails.md
  fi

  # 5. 금지 파일 수정 감지
  if echo "$changed_files_all" | grep -qE '^\.(env|env\.local)$|^package-lock\.json$' 2>/dev/null; then
    log "WARNING: 금지 파일 수정 감지 (.env/package-lock)"
    echo "### [$(date '+%Y-%m-%d %H:%M')] 금지 파일 수정 감지 (Iteration #$loop_count)" >> .flowset/guardrails.md
  fi

  # 6. 빈 구현 감지 (TODO/placeholder/stub)
  if [[ -n "$changed_files_all" ]]; then
    local incomplete
    incomplete=$(echo "$changed_files_all" | xargs grep -l 'TODO\|FIXME\|placeholder\|stub\|not implemented\|NotImplemented' 2>/dev/null | head -3 || true)
    if [[ -n "$incomplete" ]]; then
      log "WARNING: 불완전 구현 감지 (TODO/placeholder) — $incomplete"
      echo "### [$(date '+%Y-%m-%d %H:%M')] 불완전 구현: $incomplete (Iteration #$loop_count)" >> .flowset/guardrails.md
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
          echo "### [$(date '+%Y-%m-%d %H:%M')] API 형식 미준수: $api_file (Iteration #$loop_count)" >> .flowset/guardrails.md
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
        echo "### [$(date '+%Y-%m-%d %H:%M')] 수용 기준 미충족: GET 핸들러 누락 (Iteration #$loop_count)" >> .flowset/guardrails.md
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
        echo "### [$(date '+%Y-%m-%d %H:%M')] 수용 기준 미충족: POST 핸들러 누락 (Iteration #$loop_count)" >> .flowset/guardrails.md
      fi
    fi
  fi

  if [[ $violations -gt 0 ]]; then
    log "POST-VALIDATION: $violations violations detected"
    echo "### [$(date '+%Y-%m-%d %H:%M')] 자동 감지: $violations건 규칙 위반 (Iteration #$loop_count)" >> .flowset/guardrails.md
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

  if [[ "$current_sha" == "$last_git_sha" && "$has_uncommitted_changes" == "false" ]]; then
    consecutive_no_progress=$((consecutive_no_progress + 1))
    log "No progress detected ($consecutive_no_progress/$NO_PROGRESS_LIMIT)"
    if [[ $consecutive_no_progress -ge $NO_PROGRESS_LIMIT ]]; then
      log "CIRCUIT BREAKER: $NO_PROGRESS_LIMIT iterations without progress - halting"
      return 1
    fi
  else
    consecutive_no_progress=0
    last_git_sha="$current_sha"
  fi
  return 0
}

check_rate_limit() {
  if [[ $call_count -ge $RATE_LIMIT_PER_HOUR ]]; then
    local now elapsed
    now=$(date +%s)
    elapsed=$(( now - rate_limit_start ))
    if [[ $elapsed -lt 3600 ]]; then
      local wait_time=$(( 3600 - elapsed ))
      log "Rate limit ($RATE_LIMIT_PER_HOUR/hr) reached. Waiting ${wait_time}s..."
      sleep "$wait_time"
    fi
    call_count=0
    rate_limit_start=$(date +%s)
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
[FlowSet #$loop_count] Completed: $completed | Remaining: $remaining
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
  vault_record "patterns" "iter-${loop_count}.md" \
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

  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"iter\":$loop_count,\"wi\":\"${wi_name}\",\"result\":\"${result}\",\"files\":${files_count},\"sec\":${elapsed},\"cost\":${cost}}" >> "$trace_file" 2>/dev/null || true

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

#==============================
# Section 6.5: MERGE WAIT
#==============================

wait_for_merge() {
  # 단일 PR의 머지 완료를 대기 (순차 모드용)
  # $1: 워커가 작업한 브랜치명
  local branch="${1:-}"

  # 브랜치에서 PR 번호 조회
  local pr_number
  pr_number=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null || true)

  if [[ -z "${pr_number:-}" ]]; then
    # open PR 없음 → 이미 머지됐거나 PR 생성 실패
    pr_number=$(gh pr list --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null || true)
    if [[ -n "${pr_number:-}" ]]; then
      log "✅ PR #$pr_number 이미 머지됨"
      return 0
    fi
    log "⚠️ 브랜치 $branch에 대한 PR 없음"
    return 2
  fi

  log "⏳ PR #$pr_number 머지 대기..."
  bash .flowset/scripts/enqueue-pr.sh "$pr_number" --wait --timeout 15
  local result=$?

  case $result in
    0) log "✅ PR #$pr_number 머지 완료" ;;
    1) log "❌ PR #$pr_number 실패/닫힘 — guardrails 기록"
       echo "### [$(date '+%Y-%m-%d %H:%M')] PR #$pr_number 머지 실패 (Iteration #$loop_count)" >> .flowset/guardrails.md ;;
    2) log "⚠️ PR #$pr_number timeout — 다음 iteration에서 처리" ;;
  esac
  return $result
}

wait_for_batch_merge() {
  # batch 내 모든 PR의 머지 완료를 대기 (병렬 모드용)
  # $@: PR 번호 목록
  local pr_numbers=("$@")
  local total=${#pr_numbers[@]}

  if [[ $total -eq 0 ]]; then
    return 0
  fi

  log "⏳ batch ${total}개 PR 머지 대기..."

  local merged=0
  local failed=0
  local timeout_sec=$((15 * 60))
  local elapsed=0
  local poll_interval=15

  # 각 PR 상태 추적
  declare -A pr_states
  for pr in "${pr_numbers[@]}"; do
    pr_states[$pr]="pending"
  done

  while [[ $elapsed -lt $timeout_sec ]]; do
    local all_done=true

    for pr in "${pr_numbers[@]}"; do
      [[ "${pr_states[$pr]}" != "pending" ]] && continue
      all_done=false

      local state
      state=$(gh pr view "$pr" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")

      case "$state" in
        MERGED)
          pr_states[$pr]="merged"
          merged=$((merged + 1))
          log "  ✅ PR #$pr 머지됨 ($merged/$total)"
          ;;
        CLOSED)
          pr_states[$pr]="failed"
          failed=$((failed + 1))
          log "  ❌ PR #$pr 실패/닫힘 ($failed failed)"
          echo "### [$(date '+%Y-%m-%d %H:%M')] batch PR #$pr 머지 실패" >> .flowset/guardrails.md
          ;;
      esac
    done

    $all_done && break

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
    printf "\r  ⏳ %dm %02ds / 15m | 머지: %d/%d | 실패: %d  " "$((elapsed/60))" "$((elapsed%60))" "$merged" "$total" "$failed"
  done
  echo ""

  # timeout된 PR 처리
  for pr in "${pr_numbers[@]}"; do
    if [[ "${pr_states[$pr]}" == "pending" ]]; then
      log "  ⚠️ PR #$pr timeout"
    fi
  done

  log "📊 batch 결과: 머지 $merged / 실패 $failed / timeout $((total - merged - failed))"
  return 0
}

inject_regression_wis() {
  # open regression issue → fix_plan에 WI-NNN-1-fix 추가 (원본 WI 바로 아래)
  local issues
  issues=$(gh issue list --label regression --state open --json number,title,body 2>/dev/null || true)
  [[ -z "${issues:-}" || "$issues" == "[]" ]] && return 0

  local injected=0
  local titles
  titles=$(echo "$issues" | sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

  while IFS= read -r title; do
    [[ -z "$title" ]] && continue
    # 이슈 제목에서 WI 번호 추출 (예: "WI-063 e2e 실패: ...")
    local wi_num
    wi_num=$(echo "$title" | grep -oE 'WI-[0-9]+' | head -1)
    [[ -z "$wi_num" ]] && continue

    # 기존 서브넘버 확인 → 다음 번호 결정
    local max_sub=0
    local existing
    existing=$(grep -oE "${wi_num}-[0-9]+-fix" "$FIX_PLAN" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
    if [[ -n "${existing:-}" ]]; then
      max_sub=$existing
    fi
    local next_sub=$((max_sub + 1))
    local fix_wi="${wi_num}-${next_sub}-fix"

    # 이미 fix_plan에 있으면 스킵
    grep -qF "$fix_wi" "$FIX_PLAN" 2>/dev/null && continue

    # 원본 WI 바로 아래에 추가
    local orig_line
    orig_line=$(grep -nE "^\- \[[x ]\] ${wi_num}-(feat|fix|docs|test|chore)" "$FIX_PLAN" 2>/dev/null | tail -1 | cut -d: -f1 || true)
    if [[ -n "${orig_line:-}" ]]; then
      sedi "${orig_line}a\\- [ ] ${fix_wi} ${title}" "$FIX_PLAN"
      injected=$((injected + 1))
    else
      log "⚠️ ${wi_num}: fix_plan에 원본 WI 없음 — fix WI 추가 불가"
    fi
  done <<< "$titles"

  if [[ $injected -gt 0 ]]; then
    log "🔄 regression issue에서 ${injected}건 fix WI 추가"
  fi
}

#==============================
# Section 7: GIT OPERATIONS
#==============================

safe_sync_main() {
  # main 동기화: fetch + reset --hard (로컬 main에 커밋 없으므로 안전)
  # 상태 파일은 untracked이므로 backup/restore로 보호
  backup_state_files
  git fetch origin main 2>/dev/null || true
  git reset --hard origin/main 2>/dev/null || true
  restore_state_files
}

reconcile_fix_plan() {
  # At loop end, sync fix_plan.md checkboxes from completed_wis.txt
  [[ -f "$COMPLETED_FILE" ]] || return 0
  local changed=0
  while IFS= read -r prefix; do
    [[ -z "$prefix" ]] && continue
    local line_num
    line_num=$(grep -nF -- "- [ ] ${prefix}" "$FIX_PLAN" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -n "$line_num" ]]; then
      sedi "${line_num}s/^\- \[ \]/- [x]/" "$FIX_PLAN"
      changed=$((changed + 1))
    fi
  done < "$COMPLETED_FILE"
  if [[ $changed -gt 0 ]]; then
    log "📋 fix_plan.md ${changed}건 동기화"
    local fp_branch="chore/WI-chore-fix-plan-sync-$(date +%H%M%S)"
    if git checkout -b "$fp_branch" 2>/dev/null; then
      git add "$FIX_PLAN"
      git commit -m "WI-chore fix_plan 동기화 (${changed}건 완료)" 2>/dev/null || true
      if git push -u origin "$fp_branch" 2>/dev/null; then
        local fp_pr_url
        fp_pr_url=$(gh pr create --base main --head "$fp_branch" --title "WI-chore fix_plan 동기화 (${changed}건)" --body "FlowSet 종료 시 자동 생성" 2>/dev/null) || true
        if [[ -n "${fp_pr_url:-}" ]]; then
          local fp_pr_number
          fp_pr_number=$(echo "$fp_pr_url" | grep -oE '[0-9]+$')
          bash .flowset/scripts/enqueue-pr.sh "$fp_pr_number" 2>/dev/null || true
          log "📋 fix_plan PR: $fp_pr_url"
        fi
      fi
      git checkout main 2>/dev/null || git checkout main --force 2>/dev/null || true
      git branch -D "$fp_branch" 2>/dev/null || true
    fi
  fi
}

setup_worktree() {
  local wi_name="$1"
  local idx="$2"
  local sanitized
  sanitized=$(echo "$wi_name" | sed 's/[^a-zA-Z0-9_-]/-/g' | cut -c1-40)
  local branch_name="parallel/worker-${idx}-${sanitized}"
  local worktree_path="${WORKTREE_DIR}/worker-${idx}"

  # Clean stale worktree (git 등록 해제 + 디렉토리 삭제)
  if [[ -d "$worktree_path" ]]; then
    git worktree remove "$worktree_path" --force 2>/dev/null || {
      # git 등록은 해제됐지만 빈 디렉토리만 남은 경우
      rmdir "$worktree_path" 2>/dev/null || {
        log "WARN: worktree 디렉토리 제거 실패 — $worktree_path (수동 정리 필요)"
        return 1
      }
    }
  fi
  git branch -D "$branch_name" 2>/dev/null || true

  git worktree add "$worktree_path" -b "$branch_name" HEAD > /dev/null 2>&1 || {
    log "ERROR: worktree 생성 실패 - worker-${idx}"
    return 1
  }

  # Copy gitignored/untracked files needed by claude
  for f in .flowsetrc; do
    [[ -f "$f" ]] && cp "$f" "$worktree_path/$f" 2>/dev/null || true
  done
  mkdir -p "$worktree_path/$LOG_DIR"

  echo "$worktree_path|$branch_name"
}

#==============================
# Section 8: EXECUTION
#==============================

execute_parallel() {
  local -a wis=()
  local -a pids=()
  local -a worktree_info=()
  local -a worktree_wi=()   # worktree_info와 1:1 매핑되는 WI 이름

  # PR auto-merge 완료 반영 (이전 iteration PR이 머지됐을 수 있음)
  safe_sync_main

  # 워커 실행 전 git log에서 완료 WI 복구
  recover_completed_from_history

  while IFS= read -r wi; do
    [[ -n "$wi" ]] && wis+=("$wi")
  done < <(get_next_n_wis "$PARALLEL_COUNT")

  local wi_count=${#wis[@]}
  if [[ $wi_count -eq 0 ]]; then
    return 1
  fi

  log "🔀 병렬 실행: ${wi_count}개 WI 동시 처리"

  # Setup worktrees and launch claude in each
  for i in "${!wis[@]}"; do
    local idx=$((i + 1))
    local wi="${wis[$i]}"
    log "  [Worker $idx] $wi"

    local info
    info=$(setup_worktree "$wi" "$idx") || continue
    worktree_info+=("$info")
    worktree_wi+=("$wi")

    local wt_path="${info%%|*}"

    # Build parallel context (RAG 포함)
    local counts completed unchecked total
    counts=$(count_tasks)
    completed="${counts%% *}"
    unchecked="${counts##* }"
    total=$((completed + unchecked))

    local context
    context=$(cat <<'_FLOWSET_CTX_END_'
[PARALLEL MODE] 이미 작업 브랜치에 있음. 별도 브랜치 생성·PR 생성 불필요. 현재 브랜치에서 직접 커밋할 것. fix_plan.md는 절대 수정하지 말 것(외부 루프가 처리).
_FLOWSET_CTX_END_
)
    # RAG 컨텍스트 조립 (워커별 — WI에 맞는 파일 힌트 포함)
    local rag_context
    rag_context=$(build_rag_context "$wi")

    context="[FlowSet #$loop_count - Worker $idx/$wi_count] Completed: $completed | Remaining: $unchecked
[TARGET] ${wi}
[RULE] 위 TARGET 작업 1개만 처리하고 FLOWSET_STATUS 출력 후 즉시 종료. 다른 WI 절대 금지.
${context}
${rag_context}"

    local prompt_content
    prompt_content=$(cat "$PROMPT_FILE")
    local logfile="${SCRIPT_DIR}/${LOG_DIR}/claude_parallel_${loop_count}_${idx}.log"

    # Launch in worktree (background)
    local max_turns_args=()
    if [[ "$MAX_TURNS" -gt 0 ]]; then
      max_turns_args=(--max-turns "$MAX_TURNS")
    fi

    (
      cd "$wt_path" || exit 1
      env -u CLAUDECODE claude -p "$prompt_content" \
        --output-format json \
        --append-system-prompt "$context" \
        --allowedTools "$ALLOWED_TOOLS" \
        "${max_turns_args[@]}" \
        > "$logfile" 2>&1
    ) &
    pids+=($!)
    log "  [Worker $idx] PID ${pids[-1]} 시작"
  done

  if [[ ${#pids[@]} -eq 0 ]]; then
    log "ERROR: 실행된 워커 없음"
    return 1
  fi

  # Wait with progress display
  log "⏳ ${#pids[@]}개 워커 대기 중..."
  local elapsed=0
  local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  while true; do
    local running=0
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && running=$((running + 1))
    done
    [[ $running -eq 0 ]] && break
    local sidx=$((elapsed % 10))
    printf "\r  ${spin[$sidx]} %dm %02ds | 실행 중: %d/%d  " "$((elapsed/60))" "$((elapsed%60))" "$running" "${#pids[@]}"
    sleep 1
    elapsed=$((elapsed + 1))
  done
  printf "\r  ✅ 전체 완료 (%dm %02ds)                                    \n" "$((elapsed/60))" "$((elapsed%60))"

  # Sequential merge back to current branch
  local merged=0 failed=0 skipped=0
  for i in "${!worktree_info[@]}"; do
    local info="${worktree_info[$i]}"
    local wt_path="${info%%|*}"
    local branch="${info##*|}"
    local idx=$((i + 1))

    # Check for new commits vs base
    local wt_sha base_sha
    wt_sha=$(git -C "$wt_path" rev-parse HEAD 2>/dev/null || echo "none")
    base_sha=$(git merge-base HEAD "$branch" 2>/dev/null || echo "none")

    # 워커 로그에서 FLOWSET_STATUS 존재 확인 (--max-turns 도달 시 미출력)
    local worker_log="${SCRIPT_DIR}/${LOG_DIR}/claude_parallel_${loop_count}_${idx}.log"
    local has_status=false
    if grep -q 'FLOWSET_STATUS\|STATUS:' "$worker_log" 2>/dev/null; then
      has_status=true
    fi

    # 워커 변경 파일 목록 (패턴 기록용)
    local changed_files=""
    if [[ "$wt_sha" != "$base_sha" ]]; then
      changed_files=$(git diff-tree --no-commit-id --name-only -r "$wt_sha" 2>/dev/null | head -5 | tr '\n' ', ')
      changed_files="${changed_files%,}"
    fi

    # 리밋 감지: 워커 로그에서 rate limit / overloaded 키워드 확인
    local is_rate_limited=false
    if grep -qiE 'rate.limit|rate_limit|"status":\s*429|overloaded|too many requests|throttl' "$worker_log" 2>/dev/null; then
      is_rate_limited=true
    fi

    if [[ "$is_rate_limited" == true ]]; then
      log "  [Worker $idx] 🚫 API 리밋 감지 — 5분 쿨다운 후 재시도"
      record_pattern "${worktree_wi[$i]}" "rate_limited" "" "$elapsed" || true
      skipped=$((skipped + 1))
      # 쿨다운: 남은 워커 결과 처리 후 루프에서 대기
      RATE_LIMITED=true
    elif [[ "$wt_sha" == "$base_sha" ]]; then
      # 코드 변경 없음
      if [[ "$has_status" == true ]] && grep -q 'TASKS_COMPLETED_THIS_LOOP: 1' "$worker_log" 2>/dev/null; then
        mark_wi_done "${worktree_wi[$i]}" || true
        log "  [Worker $idx] 이미 구현됨 — completed_wis.txt 기록"
      elif [[ "$has_status" == false ]]; then
        log "  [Worker $idx] ⚠️ 턴 제한 도달 (FLOWSET_STATUS 없음) — 스킵"
        record_pattern "${worktree_wi[$i]}" "timeout" "" "$elapsed" || true
      else
        log "  [Worker $idx] 변경 없음 — 스킵"
        record_pattern "${worktree_wi[$i]}" "skipped" "" "$elapsed" || true
      fi
      skipped=$((skipped + 1))
    elif [[ "$has_status" == false ]]; then
      # 코드 변경은 있지만 FLOWSET_STATUS 없음 → 불완전 가능성
      log "  [Worker $idx] ⚠️ 턴 제한 도달 (불완전 코드) — 머지 건너뜀"
      record_pattern "${worktree_wi[$i]}" "timeout" "$changed_files" "$elapsed" || true
      skipped=$((skipped + 1))
    else
      # PR 플로우: worker 브랜치를 push → PR 생성 → auto-merge 설정
      local wi="${worktree_wi[$i]}"
      local wi_type
      wi_type=$(echo "$wi" | grep -oE '(feat|fix|docs|test|chore|refactor|style|perf)' | head -1)
      wi_type="${wi_type:-feat}"
      local wi_num
      wi_num=$(echo "$wi" | grep -oE 'WI-[0-9]+' | head -1)
      local pr_branch="${wi_type}/${wi_num}-${wi_type}-$(echo "$wi" | sed "s/.*${wi_type} //" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/-$//' | cut -c1-40)"

      log "  [Worker $idx] PR 생성: $pr_branch"

      # 이전 실패로 남은 동명 브랜치 정리 (로컬 + remote)
      git branch -D "$pr_branch" 2>/dev/null || true
      git push origin --delete "$pr_branch" 2>/dev/null || true

      # worker 브랜치를 PR용 브랜치명으로 rename 후 push
      git branch -m "$branch" "$pr_branch" 2>/dev/null || {
        log "  [Worker $idx] ❌ 브랜치 rename 실패"
        failed=$((failed + 1))
        record_pattern "$wi" "conflict" "$changed_files" "$elapsed" || true
        continue
      }

      if git push -u origin "$pr_branch" 2>"$LOG_DIR/push_${idx}.log"; then
        # PR 생성
        local pr_url
        pr_url=$(gh pr create \
          --base main \
          --head "$pr_branch" \
          --title "$wi" \
          --body "FlowSet 자동 생성 PR" \
          2>"$LOG_DIR/pr_${idx}.log") || true

        if [[ -n "$pr_url" ]]; then
          merged=$((merged + 1))
          mark_wi_done "${worktree_wi[$i]}" || true
          log "  [Worker $idx] ✅ PR 생성: $pr_url"
          record_pattern "$wi" "merged" "$changed_files" "$elapsed" || true

          # merge queue에 등록 (CI 통과 시 자동 머지)
          local pr_number
          pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
          bash .flowset/scripts/enqueue-pr.sh "$pr_number" 2>/dev/null || {
            log "  [Worker $idx] ⚠️ merge queue 등록 실패 (수동 머지 필요)"
          }
        else
          failed=$((failed + 1))
          log "  [Worker $idx] ❌ PR 생성 실패"
          log "  [Worker $idx] 원인: $(head -3 "$LOG_DIR/pr_${idx}.log" 2>/dev/null)"
          record_pattern "$wi" "conflict" "$changed_files" "$elapsed" || true
        fi
      else
        failed=$((failed + 1))
        log "  [Worker $idx] ❌ push 실패"
        log "  [Worker $idx] 원인: $(head -3 "$LOG_DIR/push_${idx}.log" 2>/dev/null)"
        record_pattern "$wi" "conflict" "$changed_files" "$elapsed" || true
      fi

    fi

    # Cleanup: worktree 먼저 제거 → 브랜치 삭제 (순서 중요)
    git worktree remove "$wt_path" --force 2>/dev/null || {
      log "WARN: worktree 제거 실패 — $wt_path (수동 정리 필요)"
    }
    # rename 후 브랜치명이 바뀌었을 수 있으므로 둘 다 시도
    [[ -n "${pr_branch:-}" ]] && git branch -D "$pr_branch" 2>/dev/null || true
    git branch -D "$branch" 2>/dev/null || true
  done

  git worktree prune 2>/dev/null || true
  rmdir "$WORKTREE_DIR" 2>/dev/null || true

  log "🔀 병렬 결과: ${merged} PR, ${failed} 실패, ${skipped} 스킵"
  call_count=$((call_count + wi_count))

  # API 리밋 감지 시 쿨다운
  if [[ "${RATE_LIMITED:-false}" == true ]]; then
    log "🚫 API 리밋 감지 — 5분 대기 후 재개"
    sleep 300
    RATE_LIMITED=false
  fi

  # 전부 실패면 에러
  [[ $failed -eq $wi_count ]] && return 1
  return 0
}

#--- Sequential Execution ---

execute_claude() {
  local context="$1"
  local prompt_content
  prompt_content=$(cat "$PROMPT_FILE")

  # claude -p가 git 작업 중 삭제할 수 있으므로 매번 보장
  mkdir -p "$LOG_DIR"
  local logfile="$LOG_DIR/claude_output_${loop_count}.log"

  # 세션 재활용 또는 새 세션 결정
  local session_args=()
  if [[ -n "$current_session_id" ]]; then
    session_args=(--resume "$current_session_id")
    log "🔄 세션 재활용: ${current_session_id:0:8}..."
  else
    log "🆕 새 세션 시작"
  fi

  # 워커 턴 제한 (토큰 과소비 방지)
  local max_turns_args=()
  if [[ "$MAX_TURNS" -gt 0 ]]; then
    max_turns_args=(--max-turns "$MAX_TURNS")
  fi

  # 백그라운드에서 claude -p 실행 (CLAUDECODE 변수를 명시적으로 제거)
  env -u CLAUDECODE claude -p "$prompt_content" \
    --output-format json \
    --append-system-prompt "$context" \
    --allowedTools "$ALLOWED_TOOLS" \
    "${max_turns_args[@]}" \
    "${session_args[@]}" \
    > "$logfile" 2>&1 &
  local pid=$!

  # 스피너 + 브랜치/파일 상태
  local elapsed=0
  local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  while kill -0 "$pid" 2>/dev/null; do
    local idx=$((elapsed % 10))
    local file_changes
    file_changes=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "main")
    printf "\r  ${spin[$idx]} %dm %02ds | %s | 파일: %s개  " "$((elapsed/60))" "$((elapsed%60))" "$current_branch" "$file_changes"
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid" || true
  printf "\r  ✅ 완료 (%dm %02ds)                                              \n" "$((elapsed/60))" "$((elapsed%60))"

  call_count=$((call_count + 1))

  # Read output from log
  local output
  output=$(cat "$logfile")

  # 세션 ID 및 토큰 사용량 추출 (v4.0: sed → jq 전환 — JSON 사양 기반 정확성)
  # preflight()에서 jq 존재 보장. 실패 시 빈 문자열 fallback
  local new_session_id iteration_cost
  new_session_id=$(echo "$output" | jq -r '.session_id // empty' 2>/dev/null || echo "")
  iteration_cost=$(echo "$output" | jq -r '.total_cost_usd // empty' 2>/dev/null || echo "")

  # 컨텍스트 크기 추정: cache_creation_input_tokens = 대화에 추가된 고유 콘텐츠 누적합
  # (cache_read는 매 턴마다 중복 카운트되므로 컨텍스트 크기로 사용하면 안 됨)
  # 중첩 위치(usage 내부 등) 어디에 있어도 찾도록 재귀 순회 후 첫 값 사용
  # 주: sed 원본은 한 줄 내 여러 매칭 시 마지막 값을 반환했고, jq DFS는 첫 값을 반환함.
  # Claude CLI `--output-format json` 응답에는 한 번만 나타나므로 실무 차이 없음.
  local cache_creation
  cache_creation=$(echo "$output" | jq -r '.. | objects | .cache_creation_input_tokens? // empty' 2>/dev/null | head -1 || echo "")
  local total_context_tokens=${cache_creation:-0}

  # 비용 표시: API 키 사용자만 (구독 사용자는 토큰만 표시)
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    # API 키 사용자 → 비용 표시
    if [[ -n "$iteration_cost" ]]; then
      total_cost_usd=$(awk "BEGIN{printf \"%.2f\", $total_cost_usd + $iteration_cost}")
    fi
    log "📊 컨텍스트: ${total_context_tokens} tokens | 비용: \$${iteration_cost:-0} (누적: \$${total_cost_usd})"
  else
    # 구독(auth) 사용자 → 비용 없이 토큰만
    log "📊 컨텍스트: ${total_context_tokens} tokens (구독 플랜 — 별도 과금 없음)"
  fi

  # 컨텍스트 임계치 체크 → 세션 리셋 여부 결정
  if [[ $total_context_tokens -gt $CONTEXT_THRESHOLD ]]; then
    log "⚠️ 컨텍스트 ${total_context_tokens} > ${CONTEXT_THRESHOLD} — 다음 반복에서 새 세션 시작"
    current_session_id=""
  elif [[ -n "$new_session_id" ]]; then
    current_session_id="$new_session_id"
  fi

  # Check for exit signal (JSON 또는 plain text 형식 모두 감지)
  if echo "$output" | grep -qE '"EXIT_SIGNAL"\s*:\s*true|EXIT_SIGNAL:\s*true'; then
    log "EXIT_SIGNAL detected in output"
    return 2
  fi

  # Check for blocking errors
  if echo "$output" | grep -qE 'Permission denied|BLOCKED|rate_limit|Rate limit|overloaded'; then
    log "Error detected in output: $(echo "$output" | grep -oE 'Permission denied|BLOCKED|rate_limit|Rate limit|overloaded' | head -1)"
    return 1
  fi

  # FLOWSET_STATUS에서 TESTS_ADDED 파싱 → 0이면 TDD 미수행 경고
  local tests_added
  tests_added=$(echo "$output" | grep -oE 'TESTS_ADDED:\s*[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
  if [[ "${tests_added:-}" == "0" ]]; then
    log "WARNING: TESTS_ADDED=0 — TDD 미수행 의심"
    echo "### [$(date '+%Y-%m-%d %H:%M')] TDD 미수행: 테스트 0개 추가 (Iteration #$loop_count)" >> .flowset/guardrails.md
  fi

  return 0
}

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

  last_git_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")
  last_commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")

  while [[ $loop_count -lt $MAX_ITERATIONS ]]; do
    loop_count=$((loop_count + 1))
    log "--- Iteration $loop_count/$MAX_ITERATIONS ---"

    # 0. RAG: codebase-map 10 iteration마다 갱신
    if [[ $((loop_count % 10)) -eq 0 ]]; then
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
      last_git_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")

      # 병렬 모드: 검증 에이전트 실행
      if [[ -f ".flowset/scripts/verify-requirements.sh" && -f ".flowset/requirements.md" ]]; then
        log "🔍 검증 에이전트 실행 (병렬 batch 완료 후)..."
        local verify_result=0
        bash .flowset/scripts/verify-requirements.sh || verify_result=$?
        if [[ $verify_result -eq 2 ]]; then
          log "⚠️ 검증 에이전트: 요구사항 누락 감지"
          if [[ -f ".flowset/verify-result.md" ]]; then
            echo "### [$(date '+%Y-%m-%d %H:%M')] 검증 에이전트 — 요구사항 누락 (Iteration #$loop_count, 병렬)" >> .flowset/guardrails.md
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
            echo "### [$(date '+%Y-%m-%d %H:%M')] 검증 에이전트 — 요구사항 누락 (Iteration #$loop_count)" >> .flowset/guardrails.md
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
        last_git_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")
      else
        # main에 있음 → SHA 변경으로 판단 (기존 로직)
        local current_sha_now
        current_sha_now=$(git rev-parse HEAD 2>/dev/null || echo "none")
        if [[ "$current_sha_now" != "$last_git_sha" ]]; then
          mark_wi_done "$current_wi" || true
          last_git_sha="$current_sha_now"
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
