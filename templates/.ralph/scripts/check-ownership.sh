#!/usr/bin/env bash
# check-ownership.sh — 팀 소유권 기반 파일 수정 제한 (v3.0)
# PreToolUse hook (matcher: "Edit|Write")
# TEAM_NAME 미설정 시 무동작 (solo 모드 호환)
# hotfix/ 브랜치에서는 소유권 제한 완화

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# stdin에서 hook 입력 읽기
INPUT=$(cat 2>/dev/null || true)

# TEAM_NAME 미설정이면 pass (solo 모드)
if [[ -z "${TEAM_NAME:-}" ]]; then
  exit 0
fi

# hotfix 브랜치면 소유권 제한 완화
current_branch=$(git branch --show-current 2>/dev/null || echo "")
if [[ "$current_branch" == hotfix/* ]]; then
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
# Windows 경로 정규화
file_path=$(echo "$file_path" | sed 's|\\|/|g')

# ownership.json 읽기
OWNERSHIP_FILE=".ralph/ownership.json"
if [[ ! -f "$OWNERSHIP_FILE" ]]; then
  exit 0
fi

# 공유 파일 체크 (전팀 수정 가능)
shared_files=$(jq -r '.shared[]? // empty' "$OWNERSHIP_FILE" 2>/dev/null)
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  # 단순 파일명 매칭
  if [[ "$file_path" == "$pattern" ]]; then
    exit 0
  fi
done <<< "$shared_files"

# 팀 소유 디렉토리 체크
team_patterns=$(jq -r ".teams.\"${TEAM_NAME}\"[]? // empty" "$OWNERSHIP_FILE" 2>/dev/null)
if [[ -z "$team_patterns" ]]; then
  # 팀 정의 없으면 pass
  exit 0
fi

allowed=false
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  # glob 패턴 매칭 (** 지원)
  # "src/app/**" → "src/app/" 접두사 매칭
  prefix="${pattern%%\*\**}"
  if [[ "$file_path" == "$prefix"* ]]; then
    allowed=true
    break
  fi
done <<< "$team_patterns"

if [[ "$allowed" == "true" ]]; then
  exit 0
fi

# 소유권 위반 — deny
jq -n \
  --arg team "$TEAM_NAME" \
  --arg path "$file_path" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("[ownership] \($team) 팀은 \($path) 파일을 수정할 수 없습니다. 팀 소유 디렉토리만 수정 가능합니다.")
    }
  }'
