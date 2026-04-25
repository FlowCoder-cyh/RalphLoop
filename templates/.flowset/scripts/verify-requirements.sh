#!/usr/bin/env bash
# 검증 에이전트: requirements.md vs 구현 대조 + 매트릭스 셀 대조 + 계약 준수
# v3.0: requirements.md 기반 LLM 검증
# v4.0 (WI-C5): matrix.json 매트릭스 대조 추가 (PROJECT_CLASS 분기, git diff ↔ 셀 매핑)
# Stop hook 또는 flowset.sh에서 자동 호출
# 구현 에이전트와 분리 — Read/Grep/Glob만 허용

set -euo pipefail

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ============================================================================
# v4.0 (WI-C5): 매트릭스 대조 게이트웨이
# ============================================================================
# 설계 §5 :225 + §7 :312 + §4 :109-117 이행:
# - HAS_MATRIX 플래그로 matrix.json 부재 시 매트릭스 대조 skip (하위 호환)
# - PROJECT_CLASS에 따라 변경 파일을 code(entities) / content(sections) 영역으로 분류
# - 분류된 영역의 매트릭스 셀 status가 missing/pending이면 issue 누적
# - 누적된 issue가 있으면 LLM 검증 결과와 합산하여 exit 2

HAS_MATRIX=true
MATRIX_FILE=".flowset/spec/matrix.json"
[[ -f "$MATRIX_FILE" ]] || HAS_MATRIX=false

PROJECT_CLASS="code"
if [[ -f ".flowsetrc" ]]; then
  # shellcheck source=/dev/null
  source .flowsetrc 2>/dev/null || true
  PROJECT_CLASS="${PROJECT_CLASS:-code}"
fi

# CHANGED는 LLM 검증 단계와 매트릭스 대조 단계 모두에서 공유
CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --cached --name-only 2>/dev/null || true)

# WI-C5 매트릭스 대조 함수 — matrix.json 셀 status를 git diff와 정합 검증
# 반환: 미완 셀 매핑 issue를 stdout에 출력, issue 0건이면 빈 출력
verify_matrix_against_diff() {
  [[ "$HAS_MATRIX" == "true" ]] || return 0

  local matrix="$MATRIX_FILE"
  local class
  class=$(jq -r '.class // "code"' "$matrix" 2>/dev/null || echo "code")

  # 변경 파일 분류 — code 경로 / content 경로
  local changed_code changed_content
  changed_code=$(echo "$CHANGED" | grep -E '^src/(api|app/api|lib)/|\.ts$|\.tsx$|\.js$|\.jsx$|\.py$|\.go$|\.rs$' || true)
  changed_content=$(echo "$CHANGED" | grep -E '^docs/|^content/|^research/' || true)

  case "$class" in
    code)
      # entities 영역 검증 — 모든 entity의 미완 status 셀 추출
      [[ -z "$changed_code" ]] && return 0  # 코드 변경 없으면 skip
      _emit_missing_entities "$matrix"
      ;;
    content)
      # sections 영역 검증 — 모든 section의 미완 status 셀 추출
      [[ -z "$changed_content" ]] && return 0
      _emit_missing_sections "$matrix"
      ;;
    hybrid)
      # 양쪽 영역 동시 검증 (설계 §4 :158-181 hybrid 동시 변경 처리)
      [[ -n "$changed_code" ]] && _emit_missing_entities "$matrix"
      [[ -n "$changed_content" ]] && _emit_missing_sections "$matrix"
      ;;
    *)
      echo "ERROR: 알 수 없는 PROJECT_CLASS: $class" >&2
      return 1
      ;;
  esac
  return 0
}

_emit_missing_entities() {
  local matrix="$1"
  # 각 entity의 status에서 done이 아닌 셀(missing|pending)을 entity 단위로 그룹화
  local entity missing_cells
  while IFS=$'\t' read -r entity missing_cells; do
    [[ -z "$entity" ]] && continue
    [[ -z "$missing_cells" ]] && continue
    echo "MATRIX_ISSUE: entity=$entity 미완 셀 [$missing_cells]"
  done < <(jq -r '
    .entities | to_entries[] |
    [.key,
     ([.value.status | to_entries[] | select(.value != "done") | .key] | join(","))
    ] | @tsv
  ' "$matrix" 2>/dev/null | grep -vE '	$' || true)
}

_emit_missing_sections() {
  local matrix="$1"
  local section missing_cells
  while IFS=$'\t' read -r section missing_cells; do
    [[ -z "$section" ]] && continue
    [[ -z "$missing_cells" ]] && continue
    echo "MATRIX_ISSUE: section=$section 미완 셀 [$missing_cells]"
  done < <(jq -r '
    .sections | to_entries[] |
    [.key,
     ([.value.status | to_entries[] | select(.value != "done") | .key] | join(","))
    ] | @tsv
  ' "$matrix" 2>/dev/null | grep -vE '	$' || true)
}

# 매트릭스 대조 실행 (출력은 누적 후 LLM 결과와 함께 처리)
MATRIX_RESULT_FILE=".flowset/verify-matrix-result.txt"
verify_matrix_against_diff > "$MATRIX_RESULT_FILE" 2>&1 || true

MATRIX_ISSUES=0
if [[ -s "$MATRIX_RESULT_FILE" ]]; then
  MATRIX_ISSUES=$(grep -c '^MATRIX_ISSUE: ' "$MATRIX_RESULT_FILE" 2>/dev/null || echo "0")
fi

# ============================================================================
# v3.0: requirements.md LLM 검증 (기존 흐름 보존)
# ============================================================================

# requirements.md 없으면 LLM 검증 skip — 단, 매트릭스 issue가 있으면 그것만 보고
if [[ ! -f ".flowset/requirements.md" ]]; then
  if (( MATRIX_ISSUES > 0 )); then
    echo "매트릭스 대조 결과: 미완 셀 ${MATRIX_ISSUES}건"
    grep '^MATRIX_ISSUE: ' "$MATRIX_RESULT_FILE" || true
    exit 2
  fi
  exit 0
fi

# 소스 파일 변경 확인 (변경 없으면 LLM 검증 skip — 매트릭스 issue만 처리)
SRC_CHANGED=$(echo "$CHANGED" | grep -cE '\.(ts|tsx|js|jsx|py|go|rs)$' 2>/dev/null || echo "0")
if [[ "$SRC_CHANGED" -lt 1 ]]; then
  if (( MATRIX_ISSUES > 0 )); then
    echo "매트릭스 대조 결과: 미완 셀 ${MATRIX_ISSUES}건"
    grep '^MATRIX_ISSUE: ' "$MATRIX_RESULT_FILE" || true
    exit 2
  fi
  exit 0
fi

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
LLM_MISSING=0
LLM_INCOMPLETE=0
if [[ -f "$RESULT_FILE" ]]; then
  LLM_MISSING=$(grep -c '^- ❌' "$RESULT_FILE" 2>/dev/null || echo "0")
  LLM_INCOMPLETE=$(grep -c '^- ⚠️' "$RESULT_FILE" 2>/dev/null || echo "0")
fi

# WI-C5: 매트릭스 issue + LLM issue 합산
TOTAL_FAIL=$((LLM_MISSING + LLM_INCOMPLETE + MATRIX_ISSUES))

if (( TOTAL_FAIL > 0 )); then
  echo ""
  echo "검증 결과: LLM 미구현 ${LLM_MISSING}건, 불완전 ${LLM_INCOMPLETE}건, 매트릭스 미완 ${MATRIX_ISSUES}건"
  if (( MATRIX_ISSUES > 0 )); then
    echo "[매트릭스 셀 미완]"
    grep '^MATRIX_ISSUE: ' "$MATRIX_RESULT_FILE" || true
  fi
  if (( LLM_MISSING > 0 || LLM_INCOMPLETE > 0 )); then
    echo "[LLM 검증]"
    grep -E '^- (❌|⚠️)' "$RESULT_FILE" 2>/dev/null || true
  fi
  echo ""

  # v3.0: vault에 검증 결과 기록
  if [[ -f ".flowsetrc" ]]; then
    # shellcheck source=/dev/null
    source .flowsetrc 2>/dev/null || true
    if [[ "${VAULT_ENABLED:-false}" == "true" && -n "${VAULT_API_KEY:-}" ]]; then
      local_result=$(cat "$RESULT_FILE" 2>/dev/null | head -50)
      matrix_result=$(cat "$MATRIX_RESULT_FILE" 2>/dev/null | head -20)
      curl -s -k --max-time 3 \
        "${VAULT_URL:-https://localhost:27124}/vault/${VAULT_PROJECT_NAME:-}/issues/verify-$(date '+%Y%m%d-%H%M%S').md" \
        -H "Authorization: Bearer ${VAULT_API_KEY}" \
        -X PUT -H "Content-Type: text/markdown" \
        -d "# Verification Failed ($(date '+%Y-%m-%d %H:%M'))
LLM Missing: ${LLM_MISSING}, Incomplete: ${LLM_INCOMPLETE}, Matrix: ${MATRIX_ISSUES}
${local_result}

[Matrix]
${matrix_result}" > /dev/null 2>&1 || true
    fi
  fi

  exit 2
else
  echo "검증 통과: 요구사항 + 매트릭스 셀 누락 없음"
  exit 0
fi
