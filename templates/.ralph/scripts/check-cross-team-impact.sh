#!/usr/bin/env bash
# check-cross-team-impact.sh — PreToolUse hook (matcher: "Edit|Write")
# 팀간 영향 파일 변경 시 차단 → 리드 승인 필요
# TEAM_NAME 미설정 시 무동작 (solo 모드 호환)
# check-ownership.sh와 별도: 소유권은 디렉토리 기반, 여기는 특정 파일 기반

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# stdin에서 hook 입력 읽기
INPUT=$(cat 2>/dev/null || true)

# TEAM_NAME 미설정이면 pass (solo 모드)
if [[ -z "${TEAM_NAME:-}" ]]; then
  exit 0
fi

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
file_path=$(echo "$file_path" | sed 's|\\|/|g')

# 팀간 영향 파일 판정
impact_type=""
required_reviewers=""

case "$file_path" in
  .ralph/contracts/api-standard.md)
    impact_type="API 계약"
    required_reviewers="frontend, backend"
    ;;
  .ralph/contracts/data-flow.md)
    impact_type="데이터 흐름 계약"
    required_reviewers="frontend, backend, qa"
    ;;
  .ralph/contracts/*)
    impact_type="계약 파일"
    required_reviewers="all teams"
    ;;
  prisma/schema.prisma)
    impact_type="DB 스키마"
    required_reviewers="frontend, backend"
    ;;
  .ralph/requirements.md)
    impact_type="요구사항 (수정 금지)"
    required_reviewers="user approval required"
    ;;
  *)
    # 팀간 영향 없음
    exit 0
    ;;
esac

# 리드(devops)는 계약/스키마 수정 허용 (조율 역할)
if [[ "$TEAM_NAME" == "devops" || "$TEAM_NAME" == "planning" ]]; then
  # 알림만, 차단 안함
  jq -n \
    --arg type "$impact_type" \
    --arg reviewers "$required_reviewers" \
    --arg path "$file_path" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: ("[cross-team] \($path) (\($type)) 변경 — \($reviewers) 팀에게 반드시 알리세요.")
      }
    }'
  exit 0
fi

# 일반 팀원은 차단
jq -n \
  --arg team "$TEAM_NAME" \
  --arg type "$impact_type" \
  --arg reviewers "$required_reviewers" \
  --arg path "$file_path" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("[cross-team-review] \($team) 팀이 \($path) (\($type)) 를 직접 수정할 수 없습니다. 리드에게 에스컬레이션하여 \($reviewers) 팀 합의 후 수정하세요.")
    }
  }'
