#!/usr/bin/env bash
# 검증 에이전트: requirements.md vs 구현 대조 + 계약 준수 (v3.0)
# Stop hook 또는 flowset.sh에서 자동 호출
# 구현 에이전트와 분리 — Read/Grep/Glob만 허용

set -euo pipefail

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# requirements.md 없으면 스킵
[[ -f ".flowset/requirements.md" ]] || exit 0

# 소스 파일 변경 확인 (변경 없으면 스킵)
CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --cached --name-only 2>/dev/null || true)
SRC_CHANGED=$(echo "$CHANGED" | grep -cE '\.(ts|tsx|js|jsx|py|go|rs)$' 2>/dev/null || echo "0")
[[ "$SRC_CHANGED" -lt 1 ]] && exit 0

RESULT_FILE=".flowset/verify-result.md"

# 검증 에이전트 실행 (Read/Grep/Glob만 허용 — 코드 수정 불가)
env -u CLAUDECODE claude -p "$(cat <<'VERIFY_PROMPT'
당신은 검증 전용 에이전트입니다. 코드를 수정하지 않고, 요구사항 대비 구현 누락만 판정합니다.

## 절차
1. `.flowset/requirements.md` 읽기 (사용자 원본 요구사항)
2. `git diff --stat HEAD~1 HEAD` 으로 변경된 파일 확인
3. 변경된 소스 파일 읽기 (최대 10개)
4. requirements.md의 각 항목에 대해 판정:
   - ✅ 구현됨: 해당 로직이 코드에 존재
   - ⚠️ 불완전: 파일은 있으나 핵심 로직 누락 (빈 함수, TODO, 하드코딩)
   - ❌ 미구현: 관련 코드 자체가 없음
   - ⏭️ 해당 없음: 이번 변경과 무관한 요구사항

5. 결과를 아래 형식으로 출력:
```
---VERIFY_RESULT---
TOTAL: {전체 요구사항 수}
IMPLEMENTED: {구현됨 수}
INCOMPLETE: {불완전 수}
MISSING: {미구현 수}
DETAILS:
- ✅ {요구사항}: {근거}
- ⚠️ {요구사항}: {누락된 부분}
- ❌ {요구사항}: {관련 코드 없음}
---END_VERIFY---
```

## 규칙
- 코드를 **절대 수정하지 않음** (Read/Grep/Glob만 사용)
- 추측하지 않음 — 코드에서 직접 확인한 것만 판정
- "구현됨"은 실제 로직이 있을 때만 (빈 함수, stub, TODO는 "불완전")
- 이번 변경과 무관한 요구사항은 "해당 없음"
VERIFY_PROMPT
)" --allowedTools "Read,Grep,Glob" --max-turns 10 --output-format text > "$RESULT_FILE" 2>&1 || true

# 결과 파싱
if [[ -f "$RESULT_FILE" ]]; then
  MISSING=$(grep -c '^- ❌' "$RESULT_FILE" 2>/dev/null || echo "0")
  INCOMPLETE=$(grep -c '^- ⚠️' "$RESULT_FILE" 2>/dev/null || echo "0")

  if [[ "$MISSING" -gt 0 || "$INCOMPLETE" -gt 0 ]]; then
    echo ""
    echo "검증 결과: 미구현 ${MISSING}건, 불완전 ${INCOMPLETE}건"
    grep -E '^- (❌|⚠️)' "$RESULT_FILE" 2>/dev/null || true
    echo ""

    # v3.0: vault에 검증 결과 기록
    if [[ -f ".flowsetrc" ]]; then
      source .flowsetrc 2>/dev/null || true
      if [[ "${VAULT_ENABLED:-false}" == "true" && -n "${VAULT_API_KEY:-}" ]]; then
        local_result=$(cat "$RESULT_FILE" 2>/dev/null | head -50)
        curl -s -k --max-time 3 \
          "${VAULT_URL:-https://localhost:27124}/vault/${VAULT_PROJECT_NAME:-}/issues/verify-$(date '+%Y%m%d-%H%M%S').md" \
          -H "Authorization: Bearer ${VAULT_API_KEY}" \
          -X PUT -H "Content-Type: text/markdown" \
          -d "# Verification Failed ($(date '+%Y-%m-%d %H:%M'))
Missing: ${MISSING}, Incomplete: ${INCOMPLETE}
${local_result}" > /dev/null 2>&1 || true
      fi
    fi

    exit 2
  else
    echo "검증 통과: 요구사항 대비 누락 없음"
    exit 0
  fi
fi

exit 0
