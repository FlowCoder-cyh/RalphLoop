#!/usr/bin/env bash
set -euo pipefail

# lib/state.sh — flowset.sh 런타임 전역변수를 파일 기반으로 격리 (v4.0 WI-A2a)
#
# 목적:
#   flowset.sh의 전역 상태 변수(:82-93)를 "병렬 안전 + 프로세스별 격리" 파일 기반으로 이관.
#   서브쉘에서 수정한 값이 상위 셸에 자동 전파되지 않는 bash 동작을 우회.
#
# 변수 명 분리 (중요):
#   - STATE_FILE=".flowset/loop_state.json"
#       → flowset.sh 영속 복구용(크래시 후 재시작). flowset.sh에서 관리. 이 파일에서는 건드리지 않음.
#   - RUNTIME_STATE_FILE="${TMPDIR:-/tmp}/flowset-runtime-$$"
#       → 이 파일이 관리. 프로세스별 격리, 프로세스 종료 시 trap EXIT로 제거.
#
# 이관 대상 변수 (flowset.sh:82-93 전수 확인):
#   call_count, loop_count, consecutive_no_progress, last_git_sha, last_commit_msg,
#   rate_limit_start, current_session_id, total_cost_usd
#
# 호출 순서:
#   flowset.sh가 source한 직후 state_init 호출.
#   이후 모든 상태 접근은 state_get/state_set 사용.
#   save_state() / restore_state()는 state_get으로 값을 꺼내 영속 STATE_FILE에 기록/복원.

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 런타임 state 파일 (프로세스별 격리, TMPDIR 우선 — Windows Git Bash 호환)
RUNTIME_STATE_FILE="${TMPDIR:-/tmp}/flowset-runtime-$$"
RUNTIME_STATE_LOCK="${RUNTIME_STATE_FILE}.lock"

# 이관 대상: flowset.sh:82-93 에서 정의된 8개 전역변수
RUNTIME_STATE_KEYS=(
  call_count
  loop_count
  consecutive_no_progress
  last_git_sha
  last_commit_msg
  rate_limit_start
  current_session_id
  total_cost_usd
)

# state_init — 런타임 state 파일 생성 + 빈 엔트리 초기화 + trap 등록
# 호출: flowset.sh 최상단에서 source 직후 1회
state_init() {
  : > "$RUNTIME_STATE_FILE"
  local key
  for key in "${RUNTIME_STATE_KEYS[@]}"; do
    printf '%s=\n' "$key" >> "$RUNTIME_STATE_FILE"
  done
  # EXIT 시 자동 정리 (abnormal termination 포함)
  trap 'rm -rf "$RUNTIME_STATE_FILE" "$RUNTIME_STATE_LOCK"' EXIT
}

# state_get KEY — 값 조회. 없으면 빈 문자열.
# 값에 '='가 포함되어도 정확히 처리 (첫 '=' 뒤 전부를 값으로)
state_get() {
  local key="${1:-}"
  [[ -z "$key" ]] && return 0
  awk -F= -v k="$key" '$1==k{print substr($0, index($0,"=")+1); exit}' "$RUNTIME_STATE_FILE"
}

# state_set KEY VAL — 값 기록 (lock 보호)
# 값의 newline/CR을 공백으로 정규화 (KEY=VAL 한 줄 포맷 유지)
# trade-off: last_commit_msg 등 여러 줄 값의 포맷 손실. 대신 silent corruption 방지.
# 현 flowset.sh:1765는 `git log -1 --pretty=format:"%s"`(제목만) 사용 → 실무 영향 없음.
# 향후 body 필요한 로직이 추가되면 해당 사용처에서 `%B`로 별도 조회 (이 state에 저장하지 않음).
state_set() {
  local key="${1:-}" val="${2:-}"
  [[ -z "$key" ]] && return 1
  # 값 정규화: newline/CR → 공백 (KEY=VAL 한 줄 포맷)
  val=$(printf '%s' "$val" | tr '\n\r' '  ')
  _state_lock_acquire || return 1
  local tmp="${RUNTIME_STATE_FILE}.tmp"
  awk -F= -v k="$key" -v v="$val" 'BEGIN{OFS="="}
    $1==k {print k"="v; next} {print}' "$RUNTIME_STATE_FILE" > "$tmp"
  mv "$tmp" "$RUNTIME_STATE_FILE"
  _state_lock_release
}

# state_snapshot — 병렬 서브쉘에 전달할 현 state 파일 경로 반환
state_snapshot() {
  printf '%s\n' "$RUNTIME_STATE_FILE"
}

# state_restore SNAPSHOT_PATH — 서브쉘에서 부모 state 복원
state_restore() {
  local src="${1:-}"
  [[ -f "$src" ]] && cp "$src" "$RUNTIME_STATE_FILE"
}

# --- Lock 구현 (flock 우선, mkdir advisory lock 폴백) ---
# flock 미존재 환경(일부 Windows Git Bash, macOS 기본)에 대응
_state_lock_acquire() {
  if command -v flock &>/dev/null; then
    exec 200>"$RUNTIME_STATE_LOCK" || return 1
    flock -x 200 || return 1
    return 0
  else
    # mkdir advisory lock: atomic 디렉토리 생성 성공 시 lock 획득
    local timeout=50  # 5초 (0.1s × 50)
    while ! mkdir "$RUNTIME_STATE_LOCK" 2>/dev/null; do
      timeout=$((timeout - 1))
      if (( timeout <= 0 )); then
        echo "ERROR: state_lock timeout ($RUNTIME_STATE_LOCK)" >&2
        return 1
      fi
      # stale lock 감지 (1분 이상 묵은 lock 강제 제거 — 고아 프로세스 대응)
      if [[ -d "$RUNTIME_STATE_LOCK" ]] && [[ $(find "$RUNTIME_STATE_LOCK" -maxdepth 0 -mmin +1 2>/dev/null) ]]; then
        rm -rf "$RUNTIME_STATE_LOCK"
      fi
      sleep 0.1
    done
    return 0
  fi
}

_state_lock_release() {
  if command -v flock &>/dev/null; then
    flock -u 200 2>/dev/null || true
    exec 200>&-
  else
    rm -rf "$RUNTIME_STATE_LOCK"
  fi
}
