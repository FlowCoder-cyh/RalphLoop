#!/usr/bin/env bash
# stop-vault-sync.sh — Stop hook (v3.4)
# 세션 종료 시 transcript에서 작업 내역 추출 + vault 저장
# Claude Code 유출 분석 기반 개선: transcript_path 활용, 구조화된 state.md
# 핵심 로직은 vault-helpers.sh의 vault_extract_transcript/vault_build_* 함수 사용

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

# --- 1. 기본 정보 추출 ---
last_msg=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")
transcript_path=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

# --- 2. transcript 추출 (vault-helpers.sh 함수) ---
vault_extract_transcript "$transcript_path"

# --- 3. 변경 파일 ---
changed_files=$(git diff --name-only HEAD 2>/dev/null || true)
change_summary=$(echo "$changed_files" | sed '/^$/d' | sort -u | head -20 | tr '\n' ', ')
change_summary="${change_summary%,}"

# --- 4. 구조화된 요약 생성 (vault-helpers.sh 함수) ---
vault_build_transcript_summary "$last_msg"

# --- 5. vault 저장 ---
vault_save_daily_session_log "$TRANSCRIPT_SUMMARY" "${change_summary:-none}" "0" 2>/dev/null || true

vault_build_state_content "${VAULT_PROJECT_NAME:-project}" "interactive" "" "${change_summary}" "$last_msg"
vault_write "${VAULT_PROJECT_NAME:-project}/state.md" "$TRANSCRIPT_STATE_CONTENT" 2>/dev/null || true

exit 0
