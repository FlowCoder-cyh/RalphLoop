#!/usr/bin/env bash
# check-cross-team-impact.sh — PreToolUse hook (matcher: "Edit|Write")
# 팀간 영향 파일 변경 시 차단 → 리드 승인 필요
# ownership.json의 crossTeamReview 섹션을 동적으로 읽어 감시
# TEAM_NAME 미설정 시 무동작 (solo 모드 호환)

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

# --- requirements.md 완전 차단 (모든 팀, 예외 없음) ---
if [[ "$file_path" == ".ralph/requirements.md" ]]; then
  jq -n \
    --arg team "$TEAM_NAME" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("[requirements-protected] requirements.md는 사용자 원본이며 어떤 팀도 수정할 수 없습니다. 요구사항 변경이 필요하면 사용자에게 직접 확인하세요.")
      }
    }'
  exit 0
fi

# --- ownership.json crossTeamReview 동적 매칭 ---
OWNERSHIP_FILE=".ralph/ownership.json"
if [[ ! -f "$OWNERSHIP_FILE" ]]; then
  exit 0
fi

# crossTeamReview에서 매칭되는 패턴 찾기
matched_reviewers=""
matched_pattern=""

# jq로 crossTeamReview 키 순회
while IFS=$'\t' read -r pattern reviewers_json; do
  [[ -z "$pattern" ]] && continue

  # 정확한 파일명 매칭
  if [[ "$file_path" == "$pattern" ]]; then
    matched_pattern="$pattern"
    matched_reviewers="$reviewers_json"
    break
  fi

  # glob 패턴 매칭 (** 지원)
  prefix="${pattern%%\*\**}"
  if [[ "$pattern" == *"**"* && "$file_path" == "$prefix"* ]]; then
    matched_pattern="$pattern"
    matched_reviewers="$reviewers_json"
    break
  fi
done < <(jq -r '.crossTeamReview // {} | to_entries[] | [.key, (.value | join(", "))] | @tsv' "$OWNERSHIP_FILE" 2>/dev/null)

# 매칭 없으면 pass
if [[ -z "$matched_reviewers" ]]; then
  exit 0
fi

# "all" 포함 시 전팀 리뷰
if [[ "$matched_reviewers" == *"all"* ]]; then
  matched_reviewers="all teams"
fi

# 자기 팀만 관련된 경우 pass (자기 팀 파일은 자유롭게 수정)
if [[ "$matched_reviewers" == "$TEAM_NAME" ]]; then
  exit 0
fi

# devops/planning은 계약/스키마 수정 허용 (조율 역할) — requirements.md는 위에서 이미 차단됨
if [[ "$TEAM_NAME" == "devops" || "$TEAM_NAME" == "planning" ]]; then
  jq -n \
    --arg pattern "$matched_pattern" \
    --arg reviewers "$matched_reviewers" \
    --arg path "$file_path" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: ("[cross-team] \($path) (패턴: \($pattern)) 변경 — \($reviewers) 팀에게 반드시 알리세요.")
      }
    }'
  exit 0
fi

# 일반 팀원은 차단
jq -n \
  --arg team "$TEAM_NAME" \
  --arg pattern "$matched_pattern" \
  --arg reviewers "$matched_reviewers" \
  --arg path "$file_path" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("[cross-team-review] \($team) 팀이 \($path) (패턴: \($pattern)) 를 직접 수정할 수 없습니다. 리드에게 에스컬레이션하여 \($reviewers) 팀 합의 후 수정하세요.")
    }
  }'
