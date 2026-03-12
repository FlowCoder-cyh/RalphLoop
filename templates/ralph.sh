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

cleanup() {
  local exit_code=$?
  printf "\n"
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

  # fix_plan에 실제 WI가 있는지 확인 (빈 상태 방지)
  local unchecked
  unchecked=$(grep -c '^\- \[ \]' "$FIX_PLAN" 2>/dev/null || echo "0")
  if [[ "$unchecked" == "0" ]]; then
    echo "ERROR: fix_plan.md에 미완료 WI가 없습니다. /wi:start로 WI를 생성하세요."
    errors=$((errors + 1))
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
    if [[ ! "$latest_msg" =~ $pattern ]]; then
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
  cat <<EOF
[Ralph Loop #$loop_count] Completed: $completed | Remaining: $remaining
[TARGET] ${target_wi}
[RULE] 위 TARGET 작업 1개만 처리하고 RALPH_STATUS 출력 후 즉시 종료. 다른 WI 절대 금지.
EOF
}

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

  # 백그라운드에서 claude -p 실행 (CLAUDECODE 변수를 명시적으로 제거)
  env -u CLAUDECODE claude -p "$prompt_content" \
    --output-format json \
    --append-system-prompt "$context" \
    --allowedTools "$ALLOWED_TOOLS" \
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
  local new_session_id input_tokens iteration_cost
  new_session_id=$(echo "$output" | sed -n 's/.*"session_id"\s*:\s*"\([^"]*\)".*/\1/p' | head -1)
  input_tokens=$(echo "$output" | sed -n 's/.*"input_tokens"\s*:\s*\([0-9]*\).*/\1/p' | head -1)
  local cache_read=$(echo "$output" | sed -n 's/.*"cache_read_input_tokens"\s*:\s*\([0-9]*\).*/\1/p' | head -1)
  iteration_cost=$(echo "$output" | sed -n 's/.*"total_cost_usd"\s*:\s*\([0-9.]*\).*/\1/p' | head -1)

  # 총 토큰 = input + cache_read (실제 컨텍스트 크기)
  local total_context_tokens=$(( ${input_tokens:-0} + ${cache_read:-0} ))

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

  log "=== Ralph Loop Started ==="
  log "Max iterations: $MAX_ITERATIONS | Rate limit: $RATE_LIMIT_PER_HOUR/hr"
  log "Allowed tools: $ALLOWED_TOOLS"

  last_git_sha=$(git rev-parse HEAD 2>/dev/null || echo "none")
  last_commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null || echo "")

  while [[ $loop_count -lt $MAX_ITERATIONS ]]; do
    loop_count=$((loop_count + 1))
    log "--- Iteration $loop_count/$MAX_ITERATIONS ---"

    # 1. Integrity check
    check_integrity || break

    # 2. All tasks done?
    if check_all_done; then
      log "All tasks in fix_plan.md are complete!"
      break
    fi

    # 3. 현재 WI 및 진행률 표시
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

    # 4. Rate limit
    check_rate_limit

    # 5. Execute
    local context
    context=$(build_context)

    execute_claude "$context"
    local result=$?

    # 6. Post-iteration validation
    validate_post_iteration || {
      log "Post-validation failed - check guardrails.md"
    }

    # 7. Progress check (circuit breaker) — execute 이후에 체크해야 함
    check_progress || break

    # 8. 상태 저장 (매 반복마다 — 비정상 종료 대비)
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
  done

  # 종료 이유에 따른 상태 저장
  if check_all_done 2>/dev/null; then
    save_state "completed"
  else
    save_state "stopped"
  fi
}

main "$@"
