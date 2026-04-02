#!/usr/bin/env bash
# check-ownership.sh — 팀 소유권 기반 파일 수정 제한 (v3.3)
# PreToolUse hook (matcher: "Edit|Write")
# TEAM_NAME 미설정 시 무동작 (solo 모드 호환)
# hotfix/ 브랜치에서는 소유권 제한 완화
#
# Known limitation: Agent Teams에서 리드(메인 세션)도 .team 파일에서
# 팀명을 읽을 수 있어 팀원으로 오인식될 수 있음.
# 리드가 서브에이전트로 실행 시에는 disallowedTools: Edit, Write로 이 hook 미도달.
# 리드가 메인 세션일 때는 오인식 가능하나, 대부분 팀원에게 위임하므로 실무 영향 적음.

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# stdin에서 hook 입력 읽기
INPUT=$(cat 2>/dev/null || true)

# TEAM_NAME 해소 (환경변수 → 파일 폴백)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/resolve-team.sh" 2>/dev/null || true
resolve_team_name "$INPUT"
TEAM_NAME="$RESOLVED_TEAM_NAME"

# TEAM_NAME 미설정이면 pass (solo 모드)
if [[ -z "$TEAM_NAME" ]]; then
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

# null byte, newline, 제어문자 제거 (context poisoning 방어)
file_path=$(printf '%s' "$file_path" | tr -d '\0\n\r' | tr -d '[:cntrl:]')

# 상대 경로로 정규화
cwd=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [[ -n "$cwd" && "$file_path" == "$cwd/"* ]]; then
  file_path="${file_path#$cwd/}"
fi
# Windows 경로 정규화
file_path=$(echo "$file_path" | sed 's|\\|/|g')

# ownership.json 읽기
OWNERSHIP_FILE=".flowset/ownership.json"
if [[ ! -f "$OWNERSHIP_FILE" ]]; then
  exit 0
fi

# 공유 파일 체크 (전팀 수정 가능 — 정확 매칭 + ** glob 패턴. 단일 * 미지원.)
shared_files=$(jq -r '.shared[]? // empty' "$OWNERSHIP_FILE" 2>/dev/null)
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  if [[ "$file_path" == "$pattern" ]]; then
    exit 0
  fi
  if [[ "$pattern" == *"**"* ]]; then
    local_prefix="${pattern%%\*\**}"
    if [[ "$file_path" == "$local_prefix"* ]]; then
      exit 0
    fi
  fi
done <<< "$shared_files"

# 팀 소유 디렉토리 체크
# ownership.json 양쪽 구조 지원: .teams.{팀}[] (배열) 또는 .teams.{팀}.owns[] (object)
team_patterns=$(jq -r --arg team "$TEAM_NAME" '
  .teams[$team] |
  if type == "array" then .[]
  else .owns[]?
  end
' "$OWNERSHIP_FILE" 2>/dev/null)
if [[ -z "$team_patterns" ]]; then
  # 팀 정의 없으면 pass
  exit 0
fi

allowed=false
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
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
