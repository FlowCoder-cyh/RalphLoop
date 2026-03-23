#!/usr/bin/env bash
# vault-helpers.sh — Obsidian vault CRUD via Local REST API
# flowset.sh에서 source하여 사용
# VAULT_ENABLED=false이면 모든 함수가 조용히 실패 (graceful degradation)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 설정값 (.flowsetrc에서 로드됨)
: "${VAULT_ENABLED:=false}"
: "${VAULT_URL:=https://localhost:27124}"
: "${VAULT_API_KEY:=}"
: "${VAULT_PROJECT_NAME:=}"

# curl 공통 옵션 (self-signed cert 허용, 타임아웃 5초)
_vault_curl() {
  curl -s -k --max-time 5 \
    -H "Authorization: Bearer ${VAULT_API_KEY}" \
    "$@" 2>/dev/null
}

# vault 연결 확인
# 성공 시 VAULT_ENABLED=true 유지, 실패 시 VAULT_ENABLED=false로 전환
vault_check() {
  if [[ "${VAULT_ENABLED}" != "true" ]]; then
    return 1
  fi

  if [[ -z "${VAULT_API_KEY}" ]]; then
    VAULT_ENABLED=false
    return 1
  fi

  local response
  response=$(_vault_curl "${VAULT_URL}/vault/")
  if [[ $? -ne 0 || -z "$response" ]]; then
    VAULT_ENABLED=false
    return 1
  fi

  return 0
}

# vault 파일 읽기
# $1: 경로 (예: "settings/state.md")
# stdout으로 내용 반환, 실패 시 빈 문자열
vault_read() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  local path="${1:?vault_read: path required}"
  _vault_curl "${VAULT_URL}/vault/${path}"
}

# vault 파일 쓰기
# $1: 경로, $2: 내용
# 실패해도 에러 없이 종료 (graceful)
vault_write() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  local path="${1:?vault_write: path required}"
  local content="${2:-}"
  _vault_curl "${VAULT_URL}/vault/${path}" \
    -X PUT \
    -H "Content-Type: text/markdown" \
    -d "${content}" > /dev/null
}

# vault 파일 삭제
# $1: 경로
vault_delete() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  local path="${1:?vault_delete: path required}"
  _vault_curl "${VAULT_URL}/vault/${path}" -X DELETE > /dev/null
}

# vault 시맨틱 검색
# $1: 검색어
# stdout으로 JSON 배열 반환
vault_search() {
  [[ "${VAULT_ENABLED}" != "true" ]] && echo "[]" && return 0
  local query="${1:?vault_search: query required}"
  local encoded
  encoded=$(printf '%s' "$query" | jq -sRr @uri 2>/dev/null || printf '%s' "$query" | sed 's/ /%20/g')
  _vault_curl "${VAULT_URL}/search/simple/?query=${encoded}" -X POST
}

# vault 프로젝트 폴더 초기화
# VAULT_PROJECT_NAME 하위에 기본 구조 생성
vault_init_project() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0

  local base="${VAULT_PROJECT_NAME}"

  # state.md가 없으면 초기화
  local existing
  existing=$(vault_read "${base}/state.md")
  if [[ -z "$existing" ]]; then
    vault_write "${base}/state.md" "# ${VAULT_PROJECT_NAME} State
- Status: initialized
- Updated: $(date '+%Y-%m-%d %H:%M:%S')"
  fi
}

# vault state.md 업데이트 (루프 상태 동기화)
# $1: status (running/completed/crashed)
# $2: loop_count
# $3: max_iterations
# $4: completed_count
# $5: total_cost_usd
vault_sync_state() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0

  local status="${1:-running}"
  local loop_count="${2:-0}"
  local max_iter="${3:-0}"
  local completed="${4:-0}"
  local cost="${5:-0}"

  vault_write "${VAULT_PROJECT_NAME}/state.md" "# ${VAULT_PROJECT_NAME} Loop State
- Status: ${status}
- Iteration: ${loop_count} / ${max_iter}
- Completed WIs: ${completed}
- Cost: \$${cost}
- Updated: $(date '+%Y-%m-%d %H:%M:%S')
- Branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
}

# vault에 패턴/이슈 기록
# $1: 카테고리 (patterns/issues/decisions)
# $2: 파일명
# $3: 내용
vault_record() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0

  local category="${1:?vault_record: category required}"
  local filename="${2:?vault_record: filename required}"
  local content="${3:-}"

  vault_write "${VAULT_PROJECT_NAME}/${category}/${filename}" "${content}"
}

# 기술부채 수 확인 → 임계치 초과 시 경고 메시지 반환
# $1: 임계치 (기본 10)
vault_check_tech_debt() {
  local threshold="${1:-10}"
  local debt_file=".flowset/tech-debt.md"

  [[ ! -f "$debt_file" ]] && return 0

  local open_count
  open_count=$(grep -c '^\- \*\*상태\*\*: open' "$debt_file" 2>/dev/null || echo "0")

  if [[ "$open_count" -ge "$threshold" ]]; then
    echo "기술부채 ${open_count}건 누적 (임계치: ${threshold}). 해소 작업을 우선 배치하세요."
    return 1
  fi
  return 0
}
