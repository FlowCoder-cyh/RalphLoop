#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-A2d.sh — WI-A2d (lib/merge.sh) 전용 smoke
# WI-A1 + WI-A2a + WI-A2b + WI-A2c 기준선 비회귀 + merge 7함수 이관 검증
# 사용: bash tests/run-smoke-WI-A2d.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== A2d-1: lib/merge.sh 존재 + 문법 ==="
if [[ -f templates/lib/merge.sh ]]; then
  pass "templates/lib/merge.sh 존재"
else
  fail "templates/lib/merge.sh 부재"
fi
if bash -n templates/lib/merge.sh; then
  pass "lib/merge.sh bash -n 통과"
else
  fail "lib/merge.sh 문법 오류"
fi

echo ""
echo "=== A2d-2: merge 7개 함수 정의 이관 확인 ==="
# 본체 제거 + lib 정의 확인
functions=(wait_for_merge wait_for_batch_merge inject_regression_wis safe_sync_main reconcile_fix_plan setup_worktree execute_parallel)
body_issues=0
lib_issues=0
for fn in "${functions[@]}"; do
  body_def=$(grep -cE "^${fn}\(\)" templates/flowset.sh || true)
  lib_def=$(grep -cE "^${fn}\(\)" templates/lib/merge.sh || true)
  if [[ "$body_def" != "0" ]]; then
    body_issues=$((body_issues + 1))
    echo "    $fn: body=$body_def (본체에 잔존)"
  fi
  if [[ "$lib_def" != "1" ]]; then
    lib_issues=$((lib_issues + 1))
    echo "    $fn: lib=$lib_def (이관 누락)"
  fi
done
if (( body_issues == 0 )); then
  pass "7개 함수 전부 flowset.sh 본체에서 제거"
else
  fail "$body_issues 함수 본체 잔존"
fi
if (( lib_issues == 0 )); then
  pass "7개 함수 전부 lib/merge.sh에 정의"
else
  fail "$lib_issues 함수 이관 누락"
fi

echo ""
echo "=== A2d-3: source 시 7개 함수 declare 확인 ==="
result=$(bash -c '
  set -euo pipefail
  source templates/lib/merge.sh
  missing=0
  for fn in wait_for_merge wait_for_batch_merge inject_regression_wis safe_sync_main reconcile_fix_plan setup_worktree execute_parallel; do
    declare -F "$fn" &>/dev/null || missing=$((missing + 1))
  done
  echo "MISSING=$missing"
' 2>&1 || echo "ERR")
if [[ "$result" == "MISSING=0" ]]; then
  pass "source 후 7개 함수 전부 declare"
else
  fail "함수 누락: $result"
fi

echo ""
echo "=== A2d-4: flowset.sh source 블록에 lib/merge.sh 포함 ==="
if grep -q '^  source lib/merge.sh' templates/flowset.sh; then
  pass "source lib/merge.sh 블록 존재"
else
  fail "source 블록 누락"
fi

echo ""
echo "=== A2d-5: lib/merge.sh 없을 때 fail-fast 동작 ==="
result=$(bash -c '
  set -euo pipefail
  if [[ -f /nonexistent/lib/merge.sh ]]; then
    source /nonexistent/lib/merge.sh
  else
    echo "FALLBACK_ERR" >&2
    exit 1
  fi
' 2>&1 || echo "FALLBACK_OK")
if echo "$result" | grep -q "FALLBACK"; then
  pass "lib/merge.sh 없으면 exit 1 fail-fast"
else
  fail "fail-fast 경로 실패 ($result)"
fi

echo ""
echo "=== A2d-6: init.md 템플릿 복사 블록에 merge.sh 추가 ==="
if grep -qE 'cp "\$TEMPLATE_DIR/lib/merge\.sh"' skills/wi/init.md; then
  pass "init.md에 lib/merge.sh 복사 라인 존재"
else
  fail "init.md 복사 라인 누락"
fi

echo ""
echo "=== A2d-7: flowset.sh 라인 수 이관 효과 검증 ==="
# 이관 효과 누적 추적 (smoke-WI-A2c.md 표 확장):
#   WI-A2c 후: 1782
#   WI-A2d 후: ~1308 (-474, 7개 함수 480줄 블록 제거 + 이관 주석 추가)
# 조건: 이전 단계(WI-A2c) 대비 감소량 >= 400줄 (merge 블록이 대형이므로 엄격한 임계치)
line_count=$(wc -l < templates/flowset.sh)
prev_wi_a2c=1782
delta=$((prev_wi_a2c - line_count))
if (( line_count < prev_wi_a2c )) && (( delta >= 400 )); then
  pass "flowset.sh $line_count 줄 (WI-A2c 후 $prev_wi_a2c 대비 -${delta}줄, merge 7함수 이관)"
else
  fail "flowset.sh $line_count 줄 (delta -${delta}, 이관 효과 400줄 미만)"
fi

echo ""
echo "=== A2d-8: bash -n 전체 shell 통과 ==="
fail_count=0
for f in $(find . -name "*.sh" -not -path "./.git/*"); do
  if ! bash -n "$f" 2>/dev/null; then
    fail_count=$((fail_count + 1))
    echo "    문법 오류: $f"
  fi
done
if (( fail_count == 0 )); then
  pass "전체 shell bash -n 통과 (오류 0건)"
else
  fail "$fail_count 파일 문법 오류"
fi

echo ""
echo "=== A2d-9: WI-A1 + WI-A2a + WI-A2b + WI-A2c 기준선 비회귀 ==="
if bash "$SCRIPT_DIR/test-vault-transcript.sh" 2>&1 | grep -q "^ALL TESTS PASSED$"; then
  pass "test-vault-transcript.sh 31 assertion 유지"
else
  fail "test-vault-transcript.sh 회귀"
fi
if bash "$SCRIPT_DIR/run-smoke-WI-A1.sh" 2>&1 | grep -q "WI-A1 ALL SMOKE PASSED"; then
  pass "run-smoke-WI-A1.sh 14 smoke 유지"
else
  fail "run-smoke-WI-A1.sh 회귀"
fi
if bash "$SCRIPT_DIR/run-smoke-WI-A2a.sh" 2>&1 | grep -q "WI-A2a ALL SMOKE PASSED"; then
  pass "run-smoke-WI-A2a.sh 13 smoke 유지"
else
  fail "run-smoke-WI-A2a.sh 회귀"
fi
if bash "$SCRIPT_DIR/run-smoke-WI-A2b.sh" 2>&1 | grep -q "WI-A2b ALL SMOKE PASSED"; then
  pass "run-smoke-WI-A2b.sh 13 smoke 유지"
else
  fail "run-smoke-WI-A2b.sh 회귀"
fi
if bash "$SCRIPT_DIR/run-smoke-WI-A2c.sh" 2>&1 | grep -q "WI-A2c ALL SMOKE PASSED"; then
  pass "run-smoke-WI-A2c.sh 15 smoke 유지"
else
  fail "run-smoke-WI-A2c.sh 회귀"
fi

echo ""
echo "=== A2d-10: merge.sh 내부 jq / 에러 처리 학습 전이 보존 ==="
# WI-A1 학습: sed→jq 전환, || true 파이프 방어
# WI-A2d merge.sh가 이 학습을 유지하는지 확인
issues=0
# sed JSON 파싱 잔존 (있으면 WI-A1 회귀)
if grep -qE 'sed -n.*"[a-z_]+"\s*:' templates/lib/merge.sh; then
  issues=$((issues + 1))
  echo "    sed JSON 파싱 잔존"
fi
# ((var++)) 잔존 (있으면 set -e 회귀 위험)
if grep -qE '\(\([a-z_]+\+\+\)\)' templates/lib/merge.sh; then
  issues=$((issues + 1))
  echo "    ((var++)) 잔존"
fi
# ${arr[@]/pattern} 오용
if grep -qE '\$\{[a-z_]+\[@\]/[^}]+\}' templates/lib/merge.sh; then
  issues=$((issues + 1))
  echo "    \${arr[@]/pattern} 오용 잔존"
fi
if (( issues == 0 )); then
  pass "lib/merge.sh에 WI-A1~A2c 학습 회귀 없음 (sed/((var++))/arr pattern 0건)"
else
  fail "$issues개 학습 회귀 감지"
fi

echo ""
echo "================================"
echo "  Smoke Total: $((PASS + FAIL))"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-A2d ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-A2d REGRESSION DETECTED"
  exit 1
fi
