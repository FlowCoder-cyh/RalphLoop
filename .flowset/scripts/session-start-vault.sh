#!/usr/bin/env bash
# session-start-vault.sh — SessionStart hook (v3.0 범용)
# 세션 시작/resume/clear/compact 시 vault 맥락 주입
# 루프/대화형/팀 모드 모두에서 동작
# VAULT_ENABLED=false이면 무동작

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# stdin에서 hook 입력 읽기
INPUT=$(cat 2>/dev/null || true)
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo "startup")

# .flowsetrc 로드
if [[ -f ".flowsetrc" ]]; then
  source .flowsetrc 2>/dev/null || true
fi

# vault 미활성화 시 종료
if [[ "${VAULT_ENABLED:-false}" != "true" || -z "${VAULT_API_KEY:-}" ]]; then
  exit 0
fi

# vault 연결 확인 (타임아웃 3초)
VAULT_URL="${VAULT_URL:-https://localhost:27124}"
vault_response=$(curl -s -k --max-time 3 \
  "${VAULT_URL}/vault/" \
  -H "Authorization: Bearer ${VAULT_API_KEY}" 2>/dev/null)

if [[ -z "$vault_response" ]]; then
  exit 0
fi

# 인라인 vault 헬퍼 (vault-helpers.sh와 독립 — hook은 독립 프로세스)
_vread() {
  curl -s -k --max-time 3 \
    "${VAULT_URL}/vault/${1}" \
    -H "Authorization: Bearer ${VAULT_API_KEY}" 2>/dev/null
}
_vsearch() {
  local encoded
  encoded=$(printf '%s' "$1" | jq -sRr @uri 2>/dev/null || printf '%s' "$1" | sed 's/ /%20/g')
  curl -s -k --max-time 3 \
    "${VAULT_URL}/search/simple/?query=${encoded}" \
    -H "Authorization: Bearer ${VAULT_API_KEY}" \
    -X POST 2>/dev/null
}

context=""

# --- 1. state.md 읽기 (범용 포맷) ---
if [[ -n "${VAULT_PROJECT_NAME:-}" ]]; then
  state_content=$(_vread "${VAULT_PROJECT_NAME}/state.md")
  if [[ -n "$state_content" && "$state_content" != *'"errorCode"'* ]]; then
    context+="[VAULT STATE — 프로젝트 현재 상태 (source: ${SOURCE})]
${state_content}
"
  fi
fi

# --- 2. 세션 로그는 주입하지 않음 (토큰 누적 방지) ---
# 상세 내역이 필요하면 state.md의 포인터를 따라 직접 읽을 것

# --- 3. 팀 모드: 팀별 state 로드 ---
team_name=""
if [[ -n "${TEAM_NAME:-}" ]]; then
  team_name="$TEAM_NAME"
elif [[ -f ".flowset/scripts/resolve-team.sh" ]]; then
  source ".flowset/scripts/resolve-team.sh" 2>/dev/null || true
  resolve_team_name "$INPUT" 2>/dev/null
  team_name="${RESOLVED_TEAM_NAME:-}"
fi

if [[ -n "$team_name" && -n "${VAULT_PROJECT_NAME:-}" ]]; then
  team_content=$(_vread "${VAULT_PROJECT_NAME}/teams/${team_name}.md")
  if [[ -n "$team_content" && "$team_content" != *'"errorCode"'* ]]; then
    context+="
[VAULT TEAM STATE — ${team_name} 팀 상태]
${team_content}
"
  fi
fi

# --- 4. compact/resume 시 추가 맥락 (알려진 이슈) ---
if [[ "$SOURCE" == "compact" || "$SOURCE" == "resume" ]]; then
  if [[ -n "${VAULT_PROJECT_NAME:-}" ]]; then
    recent_issues=$(_vsearch "${VAULT_PROJECT_NAME} issue")
    if [[ -n "$recent_issues" && "$recent_issues" != "[]" ]]; then
      issue_files=$(echo "$recent_issues" | jq -r '.[0:2] | .[].filename' 2>/dev/null)
      if [[ -n "$issue_files" ]]; then
        context+="
[VAULT ISSUES — 알려진 이슈]"
        while IFS= read -r vf; do
          [[ -z "$vf" ]] && continue
          vc=$(_vread "$vf" | head -20)
          [[ -n "$vc" && "$vc" != *'"errorCode"'* ]] && context+="
--- ${vf} ---
${vc}"
        done <<< "$issue_files"
      fi
    fi
  fi
fi

# 컨텍스트가 비어있으면 종료
if [[ -z "$context" ]]; then
  exit 0
fi

# cch attestation 문자열 sanitize (캐시 무효화 방지)
context=$(echo "$context" | sed 's/cch=[a-f0-9]\{4,\}/cch=REDACTED/g')

# additionalContext로 반환
jq -n --arg ctx "$context" '{"additionalContext": $ctx}'
