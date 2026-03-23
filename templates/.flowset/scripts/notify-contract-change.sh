#!/usr/bin/env bash
# notify-contract-change.sh — PostToolUse hook (matcher: "Edit|Write")
# contracts/ 파일 변경 시 Claude에게 알림 → 관련 팀 전원 리뷰 유도
# contracts/ 외 파일은 무동작

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# stdin에서 hook 입력 읽기
INPUT=$(cat 2>/dev/null || true)

# tool_input에서 file_path 추출
file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [[ -z "$file_path" ]]; then
  exit 0
fi

# 상대 경로로 정규화
cwd=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [[ -n "$cwd" && "$file_path" == "$cwd"* ]]; then
  file_path="${file_path#$cwd/}"
fi
# Windows 경로 정규화
file_path=$(echo "$file_path" | sed 's|\\|/|g')

# contracts/ 파일이 아니면 무동작
case "$file_path" in
  .flowset/contracts/*|contracts/*)
    ;;
  *)
    exit 0
    ;;
esac

# 변경된 계약 파일 식별
contract_name=$(basename "$file_path")

# 관련 팀 매핑
related_teams=""
case "$contract_name" in
  api-standard.md)
    related_teams="frontend, backend"
    ;;
  data-flow.md)
    related_teams="frontend, backend, qa"
    ;;
  *)
    related_teams="all teams"
    ;;
esac

# PostToolUse additionalContext로 알림
jq -n \
  --arg contract "$contract_name" \
  --arg teams "$related_teams" \
  --arg path "$file_path" \
  '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: ("[contract-change] \($path) 가 변경되었습니다. 관련 팀(\($teams))에게 변경사항을 알리고 합의를 확인하세요. 계약 파일의 일방적 변경은 금지됩니다.")
    }
  }'
