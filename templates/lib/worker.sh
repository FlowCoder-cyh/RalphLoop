#!/usr/bin/env bash
set -euo pipefail

# lib/worker.sh — FlowSet Claude 워커 실행 (v4.0 WI-A2c)
#
# 목적:
#   flowset.sh 메인 루프에서 `claude -p` 서브프로세스를 실행하고, 응답 파싱 +
#   세션 관리 + 토큰/비용 집계 + 종료 신호 감지를 수행.
#
# flowset.sh에서 source한 후 호출 (lib/state.sh, lib/preflight.sh 다음):
#   source lib/state.sh
#   source lib/preflight.sh
#   source lib/worker.sh
#
# 종속 함수 (flowset.sh 본체에 정의):
#   log()  — 로그 출력
#
# 종속 전역변수 (flowset.sh에서 설정):
#   PROMPT_FILE, LOG_DIR, ALLOWED_TOOLS, MAX_TURNS, CONTEXT_THRESHOLD,
#   ANTHROPIC_API_KEY (optional)
#
# 상호작용 state (lib/state.sh의 RUNTIME_STATE_KEYS 중):
#   call_count, loop_count, current_session_id, total_cost_usd
#   (현재는 전역변수 직접 참조 — WI-A2e 완료 시 state_get/set으로 전환 예정,
#    이는 WI-A2a smoke-WI-A2a.md "이중 기록 제거 시점"에 명시된 숙제)
#
# 반환값:
#   0 — 정상 완료
#   1 — Permission denied / rate_limit / overloaded 등 차단 에러
#   2 — EXIT_SIGNAL 감지 (워커가 명시적으로 종료 신호)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

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
