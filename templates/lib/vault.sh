#!/usr/bin/env bash
set -euo pipefail

# lib/vault.sh — Obsidian vault CRUD via Local REST API (v4.0 WI-A2e)
#
# 목적:
#   vault-helpers.sh(.flowset/scripts/) 본체를 lib/ 구조로 이관. flowset.sh는 lib/vault.sh
#   직접 source. .flowset/scripts/vault-helpers.sh는 이 파일을 re-source하는 얇은 shim으로
#   남아 기존 hook(stop-vault-sync.sh / stop-rag-check.sh / commit-msg) 하위 호환 유지.
#
# flowset.sh에서 source한 후 호출 (state.sh/preflight.sh/worker.sh/merge.sh 다음 — 마지막):
#   source lib/state.sh
#   source lib/preflight.sh
#   source lib/worker.sh
#   source lib/merge.sh
#   source lib/vault.sh
#
# 이관 규칙 (WI-A2b/c/d 패턴 동일):
#   - 원본 vault-helpers.sh의 19개 함수 본체 그대로 복사 (md5 무결성)
#   - export LANG/LC_ALL UTF-8 헤더 일관 적용
#   - 함수 시그니처·반환값·사이드이펙트 불변
#
# 이관된 19개 함수:
#   _vault_curl / vault_check / vault_read / vault_write / vault_delete /
#   vault_search / vault_init_project / vault_detect_mode / vault_sync_state /
#   vault_save_session_log / vault_save_daily_session_log / vault_read_latest_session /
#   vault_sync_team_state / vault_read_team_state / vault_record / vault_check_tech_debt /
#   vault_extract_transcript / vault_build_transcript_summary / vault_build_state_content
#
# 종속 환경변수 (.flowsetrc 또는 hook 환경에서 주입):
#   VAULT_ENABLED / VAULT_URL / VAULT_API_KEY / VAULT_PROJECT_NAME / TEAM_NAME
#
# 상호작용 state 키:
#   vault_sync_state는 $2로 loop_count 값을 인자 받아 local 재바인딩 (flowset.sh가 state_get
#   loop_count로 꺼내서 전달). 본 파일은 RUNTIME_STATE 키를 직접 참조하지 않음.
#
# fail-fast 정책:
#   lib/vault.sh 미존재 시 flowset.sh 즉시 exit 1 (WI-A2b/c/d 일관). 본 파일 내부에서는
#   VAULT_ENABLED=false면 모든 함수가 graceful degradation(return 0).

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
  local tmpfile
  tmpfile=$(mktemp 2>/dev/null || echo "/tmp/vault_write_$$")
  printf '%s' "$content" > "$tmpfile"
  _vault_curl "${VAULT_URL}/vault/${path}" \
    -X PUT \
    -H "Content-Type: text/markdown; charset=utf-8" \
    --data-binary "@${tmpfile}" > /dev/null
  rm -f "$tmpfile"
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

# 실행 모드 감지: loop | team | interactive
# loop_state.json이 30초 이내 갱신 → loop
# TEAM_NAME 존재 → team
# 둘 다 아님 → interactive
vault_detect_mode() {
  if [[ -f ".flowset/loop_state.json" ]]; then
    local now state_mtime age
    now=$(date +%s)
    if stat --version &>/dev/null 2>&1; then
      state_mtime=$(stat -c %Y ".flowset/loop_state.json" 2>/dev/null || echo 0)
    else
      state_mtime=$(stat -f %m ".flowset/loop_state.json" 2>/dev/null || echo 0)
    fi
    age=$(( now - state_mtime ))
    if [[ $age -le 30 ]]; then
      echo "loop"
      return 0
    fi
  fi

  if [[ -n "${TEAM_NAME:-}" ]]; then
    echo "team"
    return 0
  fi
  if [[ -f ".flowset/scripts/resolve-team.sh" ]]; then
    source ".flowset/scripts/resolve-team.sh" 2>/dev/null || true
    resolve_team_name "" 2>/dev/null
    if [[ -n "${RESOLVED_TEAM_NAME:-}" ]]; then
      echo "team"
      return 0
    fi
  fi

  echo "interactive"
}

# vault state.md 범용 업데이트
# 루프: vault_sync_state "running" "$loop_count" "$MAX_ITERATIONS" "$completed" "$cost"
# 대화형/팀: vault_sync_state "idle" "" "" "" "" "$summary" "$team_name"
# 하위 호환: 기존 5인자 호출 그대로 동작 (6-7번째는 빈 문자열)
vault_sync_state() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0

  local status="${1:-active}"
  local loop_count="${2:-}"
  local max_iter="${3:-}"
  local completed="${4:-}"
  local cost="${5:-}"
  local summary="${6:-}"
  local team_name="${7:-}"

  local branch
  branch=$(git branch --show-current 2>/dev/null || echo 'unknown')
  local changed_files
  changed_files=$(git diff --name-only HEAD 2>/dev/null | head -10 | tr '\n' ', ')
  changed_files="${changed_files%,}"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  local content="# ${VAULT_PROJECT_NAME} State
- Status: ${status}
- Branch: ${branch}
- Updated: ${timestamp}"

  # 루프 모드 (loop_count가 있으면)
  if [[ -n "$loop_count" ]]; then
    content+="
- Mode: loop
- Iteration: ${loop_count} / ${max_iter}
- Completed WIs: ${completed}
- Cost: \$${cost}"
  else
    local mode="interactive"
    [[ -n "$team_name" ]] && mode="team"
    content+="
- Mode: ${mode}"
  fi

  [[ -n "$team_name" ]] && content+="
- Team: ${team_name}"

  [[ -n "$changed_files" ]] && content+="
- Recent changes: ${changed_files}"

  if [[ -n "$summary" ]]; then
    content+="

## Last Session Summary
${summary}"
  fi

  vault_write "${VAULT_PROJECT_NAME}/state.md" "${content}"
}

# 세션 작업 로그를 vault sessions/ 에 저장
# $1: 작업 요약 (last_assistant_message 처음 500자)
# $2: 변경 파일 (optional)
# $3: 이슈 수 (optional)
vault_save_session_log() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0

  local summary="${1:-}"
  local changed="${2:-none}"
  local issue_count="${3:-0}"
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo unknown)
  local timestamp
  timestamp=$(date '+%Y%m%d-%H%M%S')

  local team_line=""
  [[ -n "${TEAM_NAME:-}" ]] && team_line="
- Team: ${TEAM_NAME}"

  vault_write "${VAULT_PROJECT_NAME}/sessions/${timestamp}.md" "# Session ${timestamp}
- Branch: ${branch}
- Changed: ${changed}
- Issues: ${issue_count}${team_line}

## Summary
${summary}"
}

# 일별 통합 세션 로그 (하루 1파일에 append)
vault_save_daily_session_log() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0

  local summary="${1:-}"
  local changed="${2:-none}"
  local issue_count="${3:-0}"
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo unknown)
  local today
  today=$(date '+%Y%m%d')
  local time_now
  time_now=$(date '+%H:%M:%S')
  local daily_file="${VAULT_PROJECT_NAME}/sessions/${today}-daily.md"

  local team_line=""
  [[ -n "${TEAM_NAME:-}" ]] && team_line=" | Team: ${TEAM_NAME}"

  local existing
  existing=$(vault_read "$daily_file" 2>/dev/null)

  local new_entry="
### ${time_now} (Branch: ${branch}${team_line})
- Changed: ${changed}
- Issues: ${issue_count}
- Summary: ${summary}"

  if [[ -n "$existing" && "$existing" != *'"errorCode"'* ]]; then
    vault_write "$daily_file" "${existing}
${new_entry}"
  else
    vault_write "$daily_file" "# Session Log — ${today}
${new_entry}"
  fi
}

# 최근 세션 로그 1건 읽기
vault_read_latest_session() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0

  local results
  results=$(vault_search "${VAULT_PROJECT_NAME} session" 2>/dev/null)
  if [[ -n "$results" && "$results" != "[]" ]]; then
    local latest_file
    latest_file=$(echo "$results" | jq -r '[.[] | select(.filename | test("sessions/"))] | .[0].filename // empty' 2>/dev/null)
    if [[ -n "$latest_file" ]]; then
      vault_read "$latest_file"
    fi
  fi
}

# 팀별 state 업데이트
vault_sync_team_state() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0
  local team_name="${1:?vault_sync_team_state: team_name required}"
  local summary="${2:-}"

  local branch
  branch=$(git branch --show-current 2>/dev/null || echo 'unknown')

  vault_write "${VAULT_PROJECT_NAME}/teams/${team_name}.md" "# ${team_name} Team State
- Updated: $(date '+%Y-%m-%d %H:%M:%S')
- Branch: ${branch}

## Last Activity
${summary}"
}

# 팀별 state 읽기
vault_read_team_state() {
  [[ "${VAULT_ENABLED}" != "true" ]] && return 0
  [[ -z "${VAULT_PROJECT_NAME}" ]] && return 0
  local team_name="${1:?vault_read_team_state: team_name required}"
  vault_read "${VAULT_PROJECT_NAME}/teams/${team_name}.md"
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

# transcript JSONL에서 세션 정보 기계적 추출 (v3.4)
# $1: transcript_path
# 결과: TRANSCRIPT_SESSION_START, TRANSCRIPT_COMMITS, TRANSCRIPT_PRS, TRANSCRIPT_TOOL_COUNT
# + TRANSCRIPT_RECENT_COMMITS (git log 기반)
vault_extract_transcript() {
  local transcript_path="${1:-}"

  TRANSCRIPT_SESSION_START=""
  TRANSCRIPT_COMMITS=""
  TRANSCRIPT_PRS=""
  TRANSCRIPT_TOOL_COUNT="0"
  TRANSCRIPT_RECENT_COMMITS=""

  if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    # v4.0: set -o pipefail 환경 대응. grep 매칭 없음(exit 1)이 파이프 실패로 전파되지 않도록 || true
    TRANSCRIPT_SESSION_START=$(head -1 "$transcript_path" | jq -r '.timestamp // empty' 2>/dev/null || true)
    TRANSCRIPT_COMMITS=$(grep -oP 'WI-\d{3,4}(-\d+)?-\w+ [^"\\\\]+' "$transcript_path" 2>/dev/null | sort -u | head -15 || true)
    TRANSCRIPT_PRS=$(grep -oP 'gh pr create[^"\\\\]*' "$transcript_path" 2>/dev/null | sort -u | head -5 || true)
    TRANSCRIPT_TOOL_COUNT=$(grep -c '"type":"tool_use"' "$transcript_path" 2>/dev/null || echo "0")
  fi

  if [[ -n "$TRANSCRIPT_SESSION_START" ]]; then
    TRANSCRIPT_RECENT_COMMITS=$(git log --oneline --since="$TRANSCRIPT_SESSION_START" 2>/dev/null | head -15 || true)
  fi
  if [[ -z "$TRANSCRIPT_RECENT_COMMITS" ]]; then
    TRANSCRIPT_RECENT_COMMITS=$(git log --oneline --since="2 hours ago" 2>/dev/null | head -15 || true)
  fi
}

# transcript 추출 결과 → 구조화된 요약 문자열 (v3.4)
# $1: last_assistant_message (optional)
# 결과: TRANSCRIPT_SUMMARY
vault_build_transcript_summary() {
  local last_msg="${1:-}"
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")

  TRANSCRIPT_SUMMARY="Branch: ${branch}"
  [[ -n "$TRANSCRIPT_RECENT_COMMITS" ]] && TRANSCRIPT_SUMMARY+=$'\n'"Commits:"$'\n'"${TRANSCRIPT_RECENT_COMMITS}"
  [[ -n "$TRANSCRIPT_PRS" ]] && TRANSCRIPT_SUMMARY+=$'\n'"PRs: ${TRANSCRIPT_PRS}"
  [[ -n "$TRANSCRIPT_TOOL_COUNT" && "$TRANSCRIPT_TOOL_COUNT" -gt 0 ]] 2>/dev/null && \
    TRANSCRIPT_SUMMARY+=$'\n'"Tool calls: ${TRANSCRIPT_TOOL_COUNT}"

  if [[ -n "$last_msg" ]]; then
    local short_last
    short_last=$(printf '%.200s' "$last_msg" | tr '\n' ' ' | tr '\r' ' ')
    TRANSCRIPT_SUMMARY+=$'\n'"Last msg: ${short_last}"
  fi
}

# transcript 추출 결과 → 구조화된 state.md (v3.4)
# $1: project_name, $2: mode, $3: team_name, $4: change_summary, $5: last_msg
# 결과: TRANSCRIPT_STATE_CONTENT
vault_build_state_content() {
  local project_name="${1:-project}"
  local mode="${2:-interactive}"
  local team_name="${3:-}"
  local change_summary="${4:-}"
  local last_msg="${5:-}"
  local branch
  branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')

  TRANSCRIPT_STATE_CONTENT="# ${project_name} State
- Status: idle
- Branch: ${branch}
- Updated: ${ts}
- Mode: ${mode}"

  [[ -n "$team_name" ]] && TRANSCRIPT_STATE_CONTENT+=$'\n'"- Team: ${team_name}"
  [[ -n "$TRANSCRIPT_SESSION_START" ]] && TRANSCRIPT_STATE_CONTENT+=$'\n'"- Session: ${TRANSCRIPT_SESSION_START} ~ ${ts}"
  [[ -n "$TRANSCRIPT_RECENT_COMMITS" ]] && TRANSCRIPT_STATE_CONTENT+=$'\n\n'"## Commits This Session"$'\n'"${TRANSCRIPT_RECENT_COMMITS}"
  [[ -n "$TRANSCRIPT_PRS" ]] && TRANSCRIPT_STATE_CONTENT+=$'\n\n'"## PRs This Session"$'\n'"${TRANSCRIPT_PRS}"
  [[ -n "$change_summary" && "$change_summary" != "none" ]] && TRANSCRIPT_STATE_CONTENT+=$'\n\n'"## Changed Files"$'\n'"${change_summary}"

  if [[ -n "$last_msg" ]]; then
    local short
    short=$(printf '%.300s' "$last_msg" | tr '\n' ' ' | tr '\r' ' ')
    TRANSCRIPT_STATE_CONTENT+=$'\n\n'"## Last Activity"$'\n'"${short}"
  fi
}
