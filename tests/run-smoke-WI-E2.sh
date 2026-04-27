#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-E2.sh — template/hook commit-check regex 통일 검증 (WI-E2)
#
# evaluator 2차 평가 POINT-NEW-2 발굴: 자기참조 결함 fix
# - 루트 .github/workflows/flowset-ci.yml: ^WI-[0-9A-Za-z]+-(type) (관대)
# - templates/.github/workflows/commit-check.yml: ^WI-[0-9]{3,4}(-[0-9]+)?-(type) (엄격, 숫자만)
# - templates/.flowset/hooks/commit-msg: 동일 엄격
#
# 결과: FlowSet 자체는 WI-E1-ci 같은 영문 ID 동작, 다운스트림은 reject
# fix: templates 두 파일을 영숫자 허용(루트 패턴) + 서브넘버링 보존으로 통일
#
# 검증 영역:
#   1. 3곳 정규식 영숫자 허용 일관 — WI-A2a/WI-C3code/WI-E1 매칭
#   2. 서브넘버링 보존 — WI-001-1-fix/WI-A2a-1-fix 매칭
#   3. 부정 케이스 reject — type 없거나 한글 작업명 부재
#   4. REQUIRED_SCRIPTS 14개 ↔ 실제 templates/.flowset/scripts/*.sh 14개 정합
#   5. PATTERN_REVERT 일관 처리 — Revert 커밋 자동 skip

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

ROOT_CI=".github/workflows/flowset-ci.yml"
TEMPLATE_CHECK="templates/.github/workflows/commit-check.yml"
TEMPLATE_HOOK="templates/.flowset/hooks/commit-msg"

# template 두 파일에서 PATTERN 라인 추출 — 정합성 핵심
template_check_pattern=$(grep -E '^\s*PATTERN="\^WI-' "$TEMPLATE_CHECK" | head -1 | sed 's/^[[:space:]]*//')
template_hook_pattern=$(grep -E '^PATTERN="\^WI-' "$TEMPLATE_HOOK" | head -1)

# 실제 정규식만 추출 (PATTERN="..." 의 중간)
template_check_re=$(echo "$template_check_pattern" | sed -E 's|^PATTERN="(.+)"$|\1|')
template_hook_re=$(echo "$template_hook_pattern" | sed -E 's|^PATTERN="(.+)"$|\1|')

# ============================================================================
echo "=== WI-E2-1: 3곳 정규식 영숫자 허용 일관 ==="

# template commit-check / commit-msg 둘 다 [0-9A-Za-z]+ 포함
for f in "$TEMPLATE_CHECK" "$TEMPLATE_HOOK"; do
  if grep -qE 'PATTERN="\^WI-\[0-9A-Za-z\]\+' "$f"; then
    pass "$f: 영숫자 ID 패턴 [0-9A-Za-z]+ 적용"
  else
    fail "$f: 영숫자 ID 패턴 미적용 (자기참조 결함 잔존)"
  fi
done

# template 둘이 정확히 동일 정규식
if [[ "$template_check_re" == "$template_hook_re" ]]; then
  pass "template commit-check ↔ commit-msg 정규식 정확히 동일"
else
  fail "template 두 파일 정규식 불일치 (check: $template_check_re / hook: $template_hook_re)"
fi

# 루트 flowset-ci.yml과의 정합 — 핵심 패턴 부분 (WI-[0-9A-Za-z]+) 동일
if grep -qE 'WI-\[0-9A-Za-z\]\+' "$ROOT_CI"; then
  pass "루트 flowset-ci.yml: 영숫자 ID 패턴 등장 (templates와 일관)"
else
  fail "루트 flowset-ci.yml: 영숫자 ID 패턴 누락"
fi

# ============================================================================
echo ""
echo "=== WI-E2-2: 영숫자 ID 매칭 (실 사용 케이스) ==="

# WI-NNN-[type] 영숫자 ID 매칭 검증
for msg in \
  "WI-001-feat 사용자 인증 추가" \
  "WI-A2a-refactor lib/state.sh 모듈 분리" \
  "WI-C3code-fix evaluator MEDIUM/LOW 즉시 해소" \
  "WI-E1-ci v4.0.1 자동 release" \
  "WI-E1cifix-fix evaluator CRITICAL 즉시 해소" \
  "WI-D3-docs README 전면 재작성"; do
  if [[ "$msg" =~ ^WI-[0-9A-Za-z]+(-[0-9]+)?-(feat|fix|docs|style|refactor|test|chore|perf|ci|revert)\ .+ ]]; then
    pass "매칭 OK: $msg"
  else
    fail "매칭 실패 (정규식 부정확): $msg"
  fi
done

# ============================================================================
echo ""
echo "=== WI-E2-3: 서브넘버링 보존 ==="

# WI-NNN-N-fix 서브넘버링 매칭 검증
for msg in \
  "WI-001-1-fix 후속 fix" \
  "WI-A2a-1-fix 추가 보강" \
  "WI-015-2-fix 두 번째 후속"; do
  if [[ "$msg" =~ ^WI-[0-9A-Za-z]+(-[0-9]+)?-(feat|fix|docs|style|refactor|test|chore|perf|ci|revert)\ .+ ]]; then
    pass "서브넘버링 매칭: $msg"
  else
    fail "서브넘버링 reject (회귀 — 다운스트림 영향): $msg"
  fi
done

# ============================================================================
echo ""
echo "=== WI-E2-4: 부정 케이스 reject ==="

# 형식 위반 케이스가 reject되는지 검증
# 주의: WI-NNN-feat 형식의 placeholder는 NNN이 영숫자라 정규식상 valid — 부정 케이스 아님
declare -a BAD_MSGS=(
  "WI-001 type 없음 (- 없음)"
  "WI-001-invalidtype 작업"
  "fix: 일반 fix 메시지"
  "WI-001-feat"
  "wi-001-feat 소문자 prefix"
)

for msg in "${BAD_MSGS[@]}"; do
  # PATTERN 정규식 + PATTERN_SYSTEM + PATTERN_MERGE + PATTERN_REVERT 어디에도 매칭 안 되어야 함
  if [[ ! "$msg" =~ ^WI-[0-9A-Za-z]+(-[0-9]+)?-(feat|fix|docs|style|refactor|test|chore|perf|ci|revert)\ .+ ]] \
     && [[ ! "$msg" =~ ^WI-(chore|docs)\ .+ ]] \
     && [[ ! "$msg" =~ ^Merge\  ]] \
     && [[ ! "$msg" =~ ^Revert\  ]]; then
    pass "부정 케이스 reject: '$msg'"
  else
    fail "부정 케이스가 매칭됨 (정규식 너무 관대): '$msg'"
  fi
done

# ============================================================================
echo ""
echo "=== WI-E2-5: 시스템 커밋 + Merge/Revert 처리 ==="

# WI-chore / WI-docs (번호 없이 허용)
for msg in "WI-chore 환경 셋업" "WI-docs PRD 작성"; do
  if [[ "$msg" =~ ^WI-(chore|docs)\ .+ ]]; then
    pass "시스템 커밋 매칭: $msg"
  else
    fail "시스템 커밋 reject (회귀): $msg"
  fi
done

# Merge/Revert 자동 skip
for msg in "Merge pull request #45 from ..." "Revert \"WI-001-feat 사용자 인증\""; do
  if [[ "$msg" =~ ^Merge\  ]] || [[ "$msg" =~ ^Revert\  ]]; then
    pass "auto-skip: $msg"
  else
    fail "Merge/Revert 미인식: $msg"
  fi
done

# template commit-msg에 PATTERN_REVERT 명시
if grep -qE '^PATTERN_REVERT=' "$TEMPLATE_HOOK"; then
  pass "template commit-msg: PATTERN_REVERT 명시 (Revert 자동 skip)"
else
  fail "template commit-msg: PATTERN_REVERT 누락 (Revert 커밋 reject 위험)"
fi

# template commit-check.yml도 PATTERN_REVERT 명시
if grep -qE '^\s*PATTERN_REVERT=' "$TEMPLATE_CHECK"; then
  pass "template commit-check.yml: PATTERN_REVERT 명시"
else
  fail "template commit-check.yml: PATTERN_REVERT 누락"
fi

# ============================================================================
echo ""
echo "=== WI-E2-6: REQUIRED_SCRIPTS ↔ 실제 디렉토리 정합 ==="

# commit-msg의 REQUIRED_SCRIPTS 카운트
required_count=$(awk '
  /^REQUIRED_SCRIPTS=\(/ { flag=1; next }
  flag && /^\)/ { flag=0; next }
  flag && /\.flowset\/scripts\// { count++ }
  END { print count }
' "$TEMPLATE_HOOK")

# 실제 templates/.flowset/scripts/*.sh 카운트
actual_count=$(ls templates/.flowset/scripts/*.sh 2>/dev/null | wc -l)

if [[ "$required_count" -eq "$actual_count" ]]; then
  pass "REQUIRED_SCRIPTS 카운트 정합 (REQUIRED: ${required_count} = 실제: ${actual_count})"
else
  fail "REQUIRED_SCRIPTS 카운트 불일치 (REQUIRED: ${required_count} ≠ 실제: ${actual_count})"
fi

# 각 실제 스크립트가 REQUIRED_SCRIPTS에 등록됐는지
for f in templates/.flowset/scripts/*.sh; do
  base=$(basename "$f")
  if grep -qF "$base" "$TEMPLATE_HOOK"; then
    pass "REQUIRED_SCRIPTS 등록: $base"
  else
    fail "REQUIRED_SCRIPTS 누락: $base (다운스트림 첫 커밋 시 누락 검증 못 함)"
  fi
done

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"

if [[ $FAIL -eq 0 ]]; then
  echo "  ✅ WI-E2 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-E2 SMOKE FAILED"
  exit 1
fi
