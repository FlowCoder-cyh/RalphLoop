#!/usr/bin/env bash
# session-start-vault.sh — SessionStart hook
# 세션 시작/resume/clear/compact 시 vault state.md + 관련 맥락 주입
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
vault_response=$(curl -s -k --max-time 3 \
  "${VAULT_URL:-https://localhost:27124}/vault/" \
  -H "Authorization: Bearer ${VAULT_API_KEY}" 2>/dev/null)

if [[ -z "$vault_response" ]]; then
  exit 0
fi

# vault에서 state.md 읽기
state_content=""
if [[ -n "${VAULT_PROJECT_NAME:-}" ]]; then
  state_content=$(curl -s -k --max-time 3 \
    "${VAULT_URL}/vault/${VAULT_PROJECT_NAME}/state.md" \
    -H "Authorization: Bearer ${VAULT_API_KEY}" 2>/dev/null)
fi

# 컨텍스트 조립
context=""

if [[ -n "$state_content" ]]; then
  context+="[VAULT STATE — 프로젝트 현재 상태 (source: ${SOURCE})]
${state_content}
"
fi

# compact 후 재주입인 경우, 추가 맥락 검색
if [[ "$SOURCE" == "compact" && -n "${VAULT_PROJECT_NAME:-}" ]]; then
  # 최근 이슈 확인
  recent_issues=$(curl -s -k --max-time 3 \
    "${VAULT_URL}/search/simple/?query=${VAULT_PROJECT_NAME}%20issue" \
    -H "Authorization: Bearer ${VAULT_API_KEY}" \
    -X POST 2>/dev/null)

  if [[ -n "$recent_issues" && "$recent_issues" != "[]" ]]; then
    issue_files=$(echo "$recent_issues" | jq -r '.[0:2] | .[].filename' 2>/dev/null)
    if [[ -n "$issue_files" ]]; then
      context+="
[VAULT ISSUES — 알려진 이슈]"
      while IFS= read -r vf; do
        [[ -z "$vf" ]] && continue
        vc=$(curl -s -k --max-time 2 \
          "${VAULT_URL}/vault/${vf}" \
          -H "Authorization: Bearer ${VAULT_API_KEY}" 2>/dev/null | head -20)
        [[ -n "$vc" ]] && context+="
--- ${vf} ---
${vc}"
      done <<< "$issue_files"
    fi
  fi
fi

# 컨텍스트가 비어있으면 종료
if [[ -z "$context" ]]; then
  exit 0
fi

# additionalContext로 반환 (공식 스펙: SessionStart stdout JSON)
jq -n --arg ctx "$context" '{"additionalContext": $ctx}'
