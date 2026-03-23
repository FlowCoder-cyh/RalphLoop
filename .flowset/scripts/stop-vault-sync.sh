#!/usr/bin/env bash
# stop-vault-sync.sh — Stop hook (settings 저장소 전용)
# RAG/E2E/requirements 검증 없이 vault 세션 저장만 수행
# 대상: 템플릿 저장소처럼 소스 코드 프로젝트가 아닌 저장소

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

INPUT=$(cat 2>/dev/null || true)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")

if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

if [[ -f ".flowsetrc" ]]; then
  source .flowsetrc 2>/dev/null || true
fi

if [[ "${VAULT_ENABLED:-false}" != "true" || -z "${VAULT_API_KEY:-}" ]]; then
  exit 0
fi

[[ -f ".flowset/scripts/vault-helpers.sh" ]] && source .flowset/scripts/vault-helpers.sh 2>/dev/null || true

# last_assistant_message에서 작업 요약 추출 (처음 500자)
last_msg=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")
summary=""
if [[ -n "$last_msg" ]]; then
  summary=$(printf '%.500s' "$last_msg" | tr '\n' ' ' | tr '\r' ' ')
fi

# 변경 파일
changed_files=$(git diff --name-only HEAD 2>/dev/null || true)
change_summary=$(echo "$changed_files" | sed '/^$/d' | sort -u | head -20 | tr '\n' ', ')
change_summary="${change_summary%,}"

# 세션 로그 저장
vault_save_session_log "$summary" "${change_summary:-none}" "0" 2>/dev/null || true

# state.md 업데이트
vault_sync_state "idle" "" "" "" "" "$summary" "" 2>/dev/null || true

exit 0
