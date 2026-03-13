#!/usr/bin/env bash
set -euo pipefail

#==============================
# Ralph Loop - Autonomous AI Development Loop
#==============================

# UTF-8 강제 (Windows 한글 깨짐 방지)
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

# Windows 콘솔 UTF-8 (Git Bash / MSYS2)
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
  chcp.com 65001 > /dev/null 2>&1 || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load config (preflight에서 존재 확인하므로 여기서는 soft fail)
if [[ -f .ralphrc ]]; then
  source .ralphrc
fi

# Defaults (위에서 .ralphrc가 설정하지 않은 값만 적용)
# MAX_ITERATIONS: fix_plan의 전체 WI 수 + 20% 여유 (검증 재시도 감안)
FIX_PLAN="${FIX_PLAN:-.ralph/fix_plan.md}"
if [[ -z "${MAX_ITERATIONS:-}" && -f "$FIX_PLAN" ]]; then
  _total_wi=$(awk '/^```/{f=!f} !f && /^\- \[[ x]\]/{c++} END{print c+0}' "$FIX_PLAN" 2>/dev/null)
  MAX_ITERATIONS=$(( _total_wi + _total_wi / 5 + 1 ))
  unset _total_wi
fi
MAX_ITERATIONS=${MAX_ITERATIONS:-50}
RATE_LIMIT_PER_HOUR=${RATE_LIMIT_PER_HOUR:-80}
COOLDOWN_SEC=${COOLDOWN_SEC:-5}
ERROR_COOLDOWN_SEC=${ERROR_COOLDOWN_SEC:-30}
PROMPT_FILE="${PROMPT_FILE:-.ralph/PROMPT.md}"
LOG_DIR=".ralph/logs"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Edit,Write,Read,Bash,Glob,Grep}"

# 워커 토큰 제어
MAX_TURNS=${MAX_TURNS:-25}  # 워커당 최대 턴 수 (0=무제한)

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
STATE_FILE=".ralph/loop_state.json"

save_state() {
  cat > "$STATE_FILE" <<EOF
{
  "loop_count": $loop_count,
  "call_count": $call_count,
  "session_id": "$current_session_id",
  "total_cost_usd": $total_cost_usd,
  "last_git_sha": "$last_git_sha",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "${1:-running}"
}
EOF
}

restore_state() {
  if [[ -f "$STATE_FILE" ]]; then
    local prev_status prev_loop prev_time prev_cost prev_sha
    prev_status=$(sed -n 's/.*"status"\s*:\s*"\([^"]*\)".*/\1/p' "$STATE_FILE" 2>/dev/null || echo "unknown")
    prev_loop=$(sed -n 's/.*"loop_count"\s*:\s*\([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null || echo "0")
    prev_time=$(sed -n 's/.*"timestamp"\s*:\s*"\([^"]*\)".*/\1/p' "$STATE_FILE" 2>/dev/null || echo "unknown")
    prev_cost=$(sed -n 's/.*"total_cost_usd"\s*:\s*\([0-9.]*\).*/\1/p' "$STATE_FILE" 2>/dev/null || echo "0")
    prev_sha=$(sed -n 's/.*"last_git_sha"\s*:\s*"\([^"]*\)".*/\1/p' "$STATE_FILE" 2>/dev/null || echo "")

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
      else
        # 코드 변경 없음 → 이전 세션 재활용 가능
        local prev_session
        prev_session=$(sed -n 's/.*"session_id"\s*:\s*"\([^"]*\)".*/\1/p' "$STATE_FILE" 2>/dev/null || echo "")
        if [[ -n "$prev_session" ]]; then
          current_session_id="$prev_session"
          log "🔄 이전 세션 복구: ${prev_session:0:8}..."
        fi
      fi

      log "📋 fix_plan.md 기준으로 미완료 WI부터 재개합니다"
      total_cost_usd=$prev_cost
    elif [[ "$prev_status" == "completed" ]]; then
      log "✅ 이전 실행 정상 완료됨. 새로 시작합니다."
    fi
  fi
}

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
  if [[ $exit_code -ne 0 ]]; then
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
  log "=== Ralph Loop 종료 (${loop_count} iterations) ==="
  log "최종: ${completed} 완료, ${remaining} 남음"
  log "💡 재실행: bash ralph.sh (미완료 WI부터 자동 재개)"
}

trap cleanup EXIT

mkdir -p "$LOG_DIR"

#--- Pre-flight checks ---

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

  # 필수 파일 확인
  local files=("$PROMPT_FILE" "$FIX_PLAN" ".ralph/AGENT.md" ".ralphrc" ".ralph/guardrails.md")
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "ERROR: 필수 파일 없음: $f"
      errors=$((errors + 1))
    fi
  done

  # Git hooks 설치 확인 (clone 후 미설치 대응)
  if [[ -d ".ralph/hooks" ]]; then
    for hook in .ralph/hooks/*; do
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
  local unchecked
  unchecked=$(grep -c '^\- \[ \]' "$FIX_PLAN" 2>/dev/null || echo "0")
  if [[ "$unchecked" == "0" ]]; then
    echo "ERROR: fix_plan.md에 미완료 WI가 없습니다. /wi:start로 WI를 생성하세요."
    errors=$((errors + 1))
  fi

  # 병렬 모드: uncommitted changes 자동 정리
  if [[ ${PARALLEL_COUNT:-1} -gt 1 ]]; then
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      echo "⚠️  uncommitted changes 감지 — 자동 커밋합니다"
      git add -A 2>/dev/null
      git commit -m "WI-chore 루프 재시작 전 uncommitted changes 자동 커밋" 2>/dev/null || true
      if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        echo "ERROR: 자동 커밋 실패. git status로 확인하세요."
        errors=$((errors + 1))
      fi
    fi
  fi

  # 병렬 모드: stale worktree/branch 자동 정리
  if [[ ${PARALLEL_COUNT:-1} -gt 1 ]]; then
    local stale_wt
    stale_wt=$(git worktree list --porcelain 2>/dev/null | grep "^worktree " | grep -v "$(pwd)$" | sed 's/^worktree //')
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

  if [[ $errors -gt 0 ]]; then
    echo ""
    echo "$errors개 오류. Ralph Loop을 시작할 수 없습니다."
    return 1
  fi
  return 0
}

#--- Functions ---

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  echo "$msg" >> "$LOG_DIR/ralph.log"
}

check_integrity() {
  local files=("$PROMPT_FILE" "$FIX_PLAN" ".ralph/AGENT.md" ".ralphrc" ".ralph/guardrails.md")
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

  # 2. .ralph/ 파일 삭제 여부 확인
  for f in "$PROMPT_FILE" "$FIX_PLAN" ".ralph/AGENT.md" ".ralph/guardrails.md"; do
    if [[ ! -f "$f" ]]; then
      log "VIOLATION: Ralph 파일 삭제됨 - $f"
      violations=$((violations + 1))
    fi
  done

  if [[ $violations -gt 0 ]]; then
    log "POST-VALIDATION: $violations violations detected"
    echo "### [$(date '+%Y-%m-%d %H:%M')] 자동 감지: $violations건 규칙 위반 (Iteration #$loop_count)" >> .ralph/guardrails.md
    return 1
  fi
  return 0
}

get_current_wi() {
  # fix_plan.md에서 첫 번째 미완료 WI 이름 추출
  awk '/^```/{f=!f} !f && /^\- \[ \]/{sub(/^\- \[ \] /,""); sub(/ \| L1:.*$/,""); print; exit}' "$FIX_PLAN" 2>/dev/null
}

count_tasks() {
  # 코드블록 내부의 체크박스는 제외 (```로 둘러싸인 영역 밖만 카운트)
  local unchecked completed
  unchecked=$(awk '/^```/{f=!f} !f && /^\- \[ \]/{c++} END{print c+0}' "$FIX_PLAN" 2>/dev/null)
  completed=$(awk '/^```/{f=!f} !f && /^\- \[x\]/{c++} END{print c+0}' "$FIX_PLAN" 2>/dev/null)
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
[Ralph Loop #$loop_count] Completed: $completed | Remaining: $remaining
[TARGET] ${target_wi}
[RULE] 위 TARGET 작업 1개만 처리하고 RALPH_STATUS 출력 후 즉시 종료. 다른 WI 절대 금지.
${rag}
EOF
}

#--- RAG (Retrieval-Augmented Generation) ---

RAG_DIR=".ralph/rag"

generate_codebase_map() {
  # 프로젝트 파일 구조 + 핵심 정보를 경량 맵으로 생성
  # 워커가 코드베이스를 즉시 파악하도록 지원
  mkdir -p "$RAG_DIR"
  local map_file="$RAG_DIR/codebase-map.md"
  {
    echo "# Codebase Map (auto-generated: $(date '+%Y-%m-%d %H:%M'))"
    echo ""
    echo "## Structure"
    tree -I 'node_modules|.git|.next|dist|.worktrees|.ralph' --dirsfirst -L 3 -F 2>/dev/null \
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

get_all_unchecked_wis() {
  # batch 무관하게 전체 미완료 WI 추출
  awk '/^```/{f=!f} !f && /^\- \[ \]/{sub(/^\- \[ \] /,""); sub(/ \| L1:.*$/,""); print}' "$FIX_PLAN" 2>/dev/null
}

check_wi_implemented() {
  # 코드베이스에서 WI가 이미 구현되었는지 확인 (git log + 파일 존재)
  local wi_name="$1"
  local wi_prefix="${wi_name%% *}"

  # Method 1: git log에 WI 커밋 존재
  if git log --oneline --all --grep="$wi_prefix" 2>/dev/null | head -1 | grep -q .; then
    return 0
  fi

  # Method 2: DB 스키마 WI → prisma model 존재 여부
  if [[ "$wi_name" == *"DB 스키마"* || "$wi_name" == *"DB스키마"* ]]; then
    # WI prefix 제거 후 설명부에서 영문 모델명 추출
    local desc="${wi_name#*feat }"
    desc="${desc#*fix }"
    local model
    model=$(echo "$desc" | grep -oE '[A-Z][a-zA-Z]+' | head -1)
    if [[ -n "$model" ]] && grep -q "^model $model " prisma/schema.prisma 2>/dev/null; then
      return 0
    fi
  fi

  # Method 3: 컴포넌트/페이지 WI → 관련 파일 2개 이상 존재
  local en_words
  en_words=$(echo "$wi_name" | grep -oE '[A-Z][a-zA-Z]{3,}' | head -3)
  if [[ -n "$en_words" ]]; then
    local match_total=0
    while IFS= read -r word; do
      local cnt
      cnt=$(find src -type f \( -name "*.tsx" -o -name "*.ts" \) -iname "*${word}*" 2>/dev/null | wc -l)
      match_total=$((match_total + cnt))
    done <<< "$en_words"
    if [[ $match_total -ge 2 ]]; then
      return 0
    fi
  fi

  return 1
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

  # 5. Guardrails
  if [[ -f ".ralph/guardrails.md" ]]; then
    parts+="[GUARDRAILS — 반드시 준수]
$(cat .ralph/guardrails.md)
"
  fi

  echo "$parts"
}

#--- Parallel Execution (PARALLEL_COUNT > 1) ---

get_next_n_wis() {
  local n=${1:-1}

  # 첫 번째 미완료 WI의 batch 태그 확인
  local first_batch
  first_batch=$(awk '/^```/{f=!f} !f && /^\- \[ \]/{
    if (match($0, /batch:[A-Za-z0-9]+/)) print substr($0, RSTART+6, RLENGTH-6)
    exit
  }' "$FIX_PLAN" 2>/dev/null)

  if [[ -z "$first_batch" ]]; then
    # batch 태그 없음 — 순서대로 N개 추출 (기존 동작)
    awk -v n="$n" '/^```/{f=!f} !f && /^\- \[ \]/{sub(/^\- \[ \] /,""); sub(/ \| L1:.*$/,""); print; c++; if(c>=n) exit}' "$FIX_PLAN" 2>/dev/null
  else
    # 같은 batch 내 미완료 WI만 N개 추출
    awk -v n="$n" -v batch="batch:$first_batch" '
      /^```/{f=!f}
      !f && /^\- \[ \]/ && index($0, batch) {
        sub(/^\- \[ \] /,"")
        sub(/ \| L1:.*$/,"")
        print
        c++
        if(c>=n) exit
      }
    ' "$FIX_PLAN" 2>/dev/null
  fi
}

setup_worktree() {
  local wi_name="$1"
  local idx="$2"
  local sanitized
  sanitized=$(echo "$wi_name" | sed 's/[^a-zA-Z0-9_-]/-/g' | cut -c1-40)
  local branch_name="parallel/worker-${idx}-${sanitized}"
  local worktree_path="${WORKTREE_DIR}/worker-${idx}"

  # Clean stale worktree
  if [[ -d "$worktree_path" ]]; then
    git worktree remove "$worktree_path" --force 2>/dev/null || {
      log "WARN: worktree 제거 실패 — $worktree_path (수동 정리 필요)"
      return 1
    }
  fi
  git branch -D "$branch_name" 2>/dev/null || true

  git worktree add "$worktree_path" -b "$branch_name" HEAD > /dev/null 2>&1 || {
    log "ERROR: worktree 생성 실패 - worker-${idx}"
    return 1
  }

  # Copy gitignored/untracked files needed by claude
  for f in .ralphrc; do
    [[ -f "$f" ]] && cp "$f" "$worktree_path/$f" 2>/dev/null || true
  done
  mkdir -p "$worktree_path/$LOG_DIR"

  echo "$worktree_path|$branch_name"
}

mark_wi_done() {
  # fix_plan.md에서 특정 WI 이름을 포함하는 첫 번째 미완료 항목을 완료 처리
  # 주의: 패턴이 "- [ ]"로 시작 → grep에 반드시 -- 필요 (대시를 옵션으로 오인 방지)
  local wi_name="$1"
  local line_num
  line_num=$(grep -nF -- "- [ ] ${wi_name}" "$FIX_PLAN" 2>/dev/null | head -1 | cut -d: -f1)
  if [[ -n "$line_num" ]]; then
    sed -i "${line_num}s/^\- \[ \]/- [x]/" "$FIX_PLAN"
    log "  mark_wi_done: ✅ ${wi_name} (line $line_num)"
    update_wi_history "$wi_name" || true
  else
    log "  mark_wi_done: ⚠️ 매칭 실패 — ${wi_name}"
  fi
}

recover_stale_wis() {
  # 워커 실행 전, 이미 구현된 WI를 사전 감지하여 fix_plan 자동 체크
  # 오탐 방지: Method 1(git log) + Method 2(prisma)만 사용 — Method 3(파일명)은 오탐 위험으로 제외
  local recovered=0
  while IFS= read -r wi; do
    [[ -z "$wi" ]] && continue
    local wi_prefix="${wi%% *}"

    # Method 1: git log에 WI 커밋 존재
    if git log --oneline --all --grep="$wi_prefix" 2>/dev/null | head -1 | grep -q .; then
      mark_wi_done "$wi" || true  # update_wi_history는 mark_wi_done 내부에서 호출
      recovered=$((recovered + 1))
      continue
    fi

    # Method 2: DB 스키마 WI → prisma model 존재 여부
    if [[ "$wi" == *"DB 스키마"* || "$wi" == *"DB스키마"* ]]; then
      local desc="${wi#*feat }"
      desc="${desc#*fix }"
      local model
      model=$(echo "$desc" | grep -oE '[A-Z][a-zA-Z]+' | head -1)
      if [[ -n "$model" ]] && grep -q "^model $model " prisma/schema.prisma 2>/dev/null; then
        mark_wi_done "$wi" || true  # update_wi_history는 mark_wi_done 내부에서 호출
        recovered=$((recovered + 1))
        continue
      fi
    fi
  done < <(get_all_unchecked_wis)
  if [[ $recovered -gt 0 ]]; then
    log "🔄 stale WI ${recovered}건 사전 복구 (RAG 코드 분석)"
    if ! git diff --quiet "$FIX_PLAN" 2>/dev/null; then
      git add "$FIX_PLAN"
      git commit -m "WI-chore fix_plan stale WI ${recovered}건 자동 복구" 2>/dev/null || true
    fi
  fi
}

execute_parallel() {
  local -a wis=()
  local -a pids=()
  local -a worktree_info=()
  local -a worktree_wi=()   # worktree_info와 1:1 매핑되는 WI 이름

  # PR auto-merge 완료 반영 (이전 iteration PR이 머지됐을 수 있음)
  git pull --rebase origin main 2>/dev/null || {
    log "⚠️ main 동기화 실패 — git status 확인 필요"
  }

  # 워커 실행 전 stale WI 사전 복구
  recover_stale_wis

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
    context=$(cat <<'_RALPH_CTX_END_'
[PARALLEL MODE] 이미 작업 브랜치에 있음. 별도 브랜치 생성·PR 생성 불필요. 현재 브랜치에서 직접 커밋할 것. fix_plan.md는 절대 수정하지 말 것(외부 루프가 처리).
_RALPH_CTX_END_
)
    # RAG 컨텍스트 조립 (워커별 — WI에 맞는 파일 힌트 포함)
    local rag_context
    rag_context=$(build_rag_context "$wi")

    context="[Ralph Loop #$loop_count - Worker $idx/$wi_count] Completed: $completed | Remaining: $unchecked
[TARGET] ${wi}
[RULE] 위 TARGET 작업 1개만 처리하고 RALPH_STATUS 출력 후 즉시 종료. 다른 WI 절대 금지.
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

    # 워커 로그에서 RALPH_STATUS 존재 확인 (--max-turns 도달 시 미출력)
    local worker_log="${SCRIPT_DIR}/${LOG_DIR}/claude_parallel_${loop_count}_${idx}.log"
    local has_status=false
    if grep -q 'RALPH_STATUS\|STATUS:' "$worker_log" 2>/dev/null; then
      has_status=true
    fi

    # 워커 변경 파일 목록 (패턴 기록용)
    local changed_files=""
    if [[ "$wt_sha" != "$base_sha" ]]; then
      changed_files=$(git diff-tree --no-commit-id --name-only -r "$wt_sha" 2>/dev/null | head -5 | tr '\n' ', ')
      changed_files="${changed_files%,}"
    fi

    if [[ "$wt_sha" == "$base_sha" ]]; then
      # 코드 변경 없음
      if [[ "$has_status" == true ]] && grep -q 'TASKS_COMPLETED_THIS_LOOP: 1' "$worker_log" 2>/dev/null; then
        mark_wi_done "${worktree_wi[$i]}" || true
        log "  [Worker $idx] 이미 구현됨 — fix_plan 자동 체크"
      elif [[ "$has_status" == false ]]; then
        log "  [Worker $idx] ⚠️ 턴 제한 도달 (RALPH_STATUS 없음) — 스킵"
        record_pattern "${worktree_wi[$i]}" "timeout" "" "$elapsed" || true
      else
        log "  [Worker $idx] 변경 없음 — 스킵"
        record_pattern "${worktree_wi[$i]}" "skipped" "" "$elapsed" || true
      fi
      skipped=$((skipped + 1))
    elif [[ "$has_status" == false ]]; then
      # 코드 변경은 있지만 RALPH_STATUS 없음 → 불완전 가능성
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
          --body "Ralph Loop 자동 생성 PR" \
          2>"$LOG_DIR/pr_${idx}.log") || true

        if [[ -n "$pr_url" ]]; then
          merged=$((merged + 1))
          mark_wi_done "${worktree_wi[$i]}" || true
          log "  [Worker $idx] ✅ PR 생성: $pr_url"
          record_pattern "$wi" "merged" "$changed_files" "$elapsed" || true

          # auto-merge 설정 (CI 통과 시 자동 머지)
          gh pr merge "$pr_url" --auto --squash 2>/dev/null || {
            log "  [Worker $idx] ⚠️ auto-merge 설정 실패 (수동 머지 필요)"
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

      # rename한 브랜치 로컬에서 삭제
      git branch -D "$pr_branch" 2>/dev/null || true
    fi

    # Cleanup worktree & branch
    git worktree remove "$wt_path" --force 2>/dev/null || {
      log "WARN: worktree 제거 실패 — $wt_path (수동 정리 필요)"
    }
    git branch -D "$branch" 2>/dev/null || true
  done

  git worktree prune 2>/dev/null || true
  rmdir "$WORKTREE_DIR" 2>/dev/null || true

  log "🔀 병렬 결과: ${merged} 머지, ${failed} 충돌, ${skipped} 스킵"
  call_count=$((call_count + wi_count))

  # fix_plan 변경 후 PR로 push (main 직접 push 금지)
  if [[ $merged -gt 0 ]] && ! git diff --quiet "$FIX_PLAN" 2>/dev/null; then
    local fp_branch="chore/WI-chore-fix-plan-update-$(date +%H%M%S)"
    git checkout -b "$fp_branch" 2>/dev/null || true
    git add "$FIX_PLAN"
    git commit -m "WI-chore fix_plan 업데이트 (병렬 ${merged}건 PR, ${skipped}건 스킵)" 2>/dev/null || true
    git push -u origin "$fp_branch" 2>/dev/null || true
    gh pr create --base main --head "$fp_branch" --title "WI-chore fix_plan 업데이트" --body "Ralph Loop 자동 생성" 2>/dev/null || true
    gh pr merge --auto --squash 2>/dev/null || true
    git checkout main 2>/dev/null || true
    git branch -D "$fp_branch" 2>/dev/null || true
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

  # 세션 ID 및 토큰 사용량 추출 (sed 사용 — Git Bash 호환)
  local new_session_id iteration_cost
  new_session_id=$(echo "$output" | sed -n 's/.*"session_id"\s*:\s*"\([^"]*\)".*/\1/p' | head -1)
  iteration_cost=$(echo "$output" | sed -n 's/.*"total_cost_usd"\s*:\s*\([0-9.]*\).*/\1/p' | head -1)

  # 컨텍스트 크기 추정: cache_creation_input_tokens = 대화에 추가된 고유 콘텐츠 누적합
  # (cache_read는 매 턴마다 중복 카운트되므로 컨텍스트 크기로 사용하면 안 됨)
  local cache_creation=$(echo "$output" | sed -n 's/.*"cache_creation_input_tokens"\s*:\s*\([0-9]*\).*/\1/p' | head -1)
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

  return 0
}

#--- Main Loop ---

main() {
  # Pre-flight checks
  preflight || exit 1

  # 이전 실행 상태 복구 확인
  restore_state

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

  log "=== Ralph Loop Started ==="
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

      # 순차 모드 패턴 기록
      local current_sha_now
      current_sha_now=$(git rev-parse HEAD 2>/dev/null || echo "none")
      if [[ "$current_sha_now" != "$last_git_sha" ]]; then
        local seq_files
        seq_files=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | head -5 | tr '\n' ', ')
        record_pattern "$current_wi" "merged" "${seq_files%,}" "$iter_elapsed" || true
      else
        record_pattern "$current_wi" "skipped" "" "$iter_elapsed" || true
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
