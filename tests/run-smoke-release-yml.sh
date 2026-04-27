#!/usr/bin/env bash
set -euo pipefail

# run-smoke-release-yml.sh — release.yml 추출 로직 사전 검증 (WI-E1 fix)
#
# 학습 36 도출 (evaluator FAIL 4.0/10 결함):
# release.yml의 awk dynamic regex `"^## \\[" v "\\]"`는 char-class로 오해석되어
# 매칭 실패. 4 backslash 보강도 Windows Git Bash smoke 컨텍스트에서 silent fail.
# → grep -F (literal) + sed line-number 기반으로 escape 의존성 완전 제거.
#
# release.yml은 main push에만 trigger되므로 PR CI에서 동작 검증 안 됨.
# 이 smoke가 release.yml과 동일 로직을 로컬에서 dry-run하여 사전 차단.

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

CHANGELOG="CHANGELOG.md"
RELEASE_YML=".github/workflows/release.yml"

[[ ! -f "$CHANGELOG" ]] && { echo "ERROR: CHANGELOG.md not found"; exit 1; }
[[ ! -f "$RELEASE_YML" ]] && { echo "ERROR: $RELEASE_YML not found"; exit 1; }

# release.yml과 동일한 line-number 기반 추출 (escape 의존성 0)
# DEBUG echo는 제거됨 (디버그 완료)
_extract_notes() {
  local v="$1"
  local header="## [$v]"
  local start start_next end
  start=$(grep -nF -m1 "$header" "$CHANGELOG" | cut -d: -f1 || true)
  [[ -z "$start" ]] && return 0
  start_next=$((start + 1))
  end=$(awk -v s="$start_next" 'NR >= s && /^## \[v/ {print NR; exit}' "$CHANGELOG" || true)
  if [[ -z "$end" ]]; then
    sed -n "${start_next},\$p" "$CHANGELOG"
  else
    sed -n "${start_next},$((end - 1))p" "$CHANGELOG"
  fi
}

_extract_title() {
  local v="$1"
  local header="## [$v]"
  local start
  start=$(grep -nF -m1 "$header" "$CHANGELOG" | cut -d: -f1 || true)
  [[ -z "$start" ]] && return 0
  tail -n +"$((start + 1))" "$CHANGELOG" | grep -m1 -E '^\*\*' | sed 's/\*\*//g' || true
}

# ============================================================================
echo "=== release-yml-1: 최상단 버전 추출 ==="

VERSION=$(grep -m1 -oE '^## \[v[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "")
if [[ -n "$VERSION" ]]; then
  pass "VERSION 추출: $VERSION"
else
  fail "VERSION 추출 실패 (CHANGELOG 최상단 ## [vX.Y.Z] 형식 위반)"
fi

# ============================================================================
echo ""
echo "=== release-yml-2: notes 추출 (release.yml 동일 로직) ==="

notes=$(_extract_notes "$VERSION")
if [[ -n "$notes" ]]; then
  notes_len=$(echo "$notes" | wc -l)
  pass "release.yml notes 추출 동작 (${notes_len}줄, 비어있지 않음)"
else
  fail "release.yml notes 추출 실패 — 머지 후 첫 자동 발행 100% 실패 위험"
fi

# ============================================================================
echo ""
echo "=== release-yml-3: title 추출 ==="

title=$(_extract_title "$VERSION")
if [[ -n "$title" ]]; then
  pass "release.yml title 추출 동작: '$title'"
else
  fail "release.yml title 추출 실패 (헤더 직후 **...** 라인 부재)"
fi

# ============================================================================
echo ""
echo "=== release-yml-4: 모든 v?.?.? 헤더 regression ==="

while IFS= read -r v_test; do
  [[ -z "$v_test" ]] && continue
  test_notes=$(_extract_notes "$v_test")
  if [[ -n "$test_notes" ]]; then
    pass "추출 동작: $v_test"
  else
    fail "추출 실패: $v_test (release.yml에서 이 버전 발행 시도하면 실패)"
  fi
done < <(grep -oE '^## \[v[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -5)

# ============================================================================
echo ""
echo "=== release-yml-5: 존재하지 않는 버전 = 빈 출력 (방어 검증) ==="

ghost_notes=$(_extract_notes "v999.999.999")
if [[ -z "$ghost_notes" ]]; then
  pass "존재하지 않는 버전 → 빈 출력 (release.yml의 -s 방어 정상 발동)"
else
  fail "존재하지 않는 버전이 빈 출력이 아님 (헤더 매칭 부정확)"
fi

# ============================================================================
echo ""
echo "=== release-yml-6: release.yml 자체 정합성 ==="

# grep -F line-number 기반 사용 검증 (회귀 차단 — awk dynamic regex로 회귀 시 fail)
if grep -qE 'grep -nF -m1 "\$HEADER"' "$RELEASE_YML"; then
  pass "release.yml grep -F (literal) 기반 추출 (학습 36 적용)"
else
  fail "release.yml grep -F 패턴 부재 — awk dynamic regex 회귀 위험"
fi

# concurrency 제어 명시
if grep -qE '^concurrency:' "$RELEASE_YML"; then
  pass "release.yml concurrency 제어 명시 (race 방지)"
else
  fail "release.yml concurrency 누락 — 동시 push 시 race 위험"
fi

# permissions: contents: write 명시
if grep -qE 'contents: write' "$RELEASE_YML"; then
  pass "release.yml permissions: contents: write 명시"
else
  fail "release.yml permissions 누락 — tag push/release create 실패"
fi

# 트리거 paths CHANGELOG.md 명시
if grep -qE '^\s*-\s+CHANGELOG\.md' "$RELEASE_YML"; then
  pass "release.yml trigger paths CHANGELOG.md 명시"
else
  fail "release.yml trigger paths 누락"
fi

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"

if [[ $FAIL -eq 0 ]]; then
  echo "  ✅ release-yml ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ release-yml SMOKE FAILED"
  exit 1
fi
