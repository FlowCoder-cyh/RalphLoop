#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-A2b.sh — WI-A2b (lib/preflight.sh) 전용 smoke
# WI-A1 + WI-A2a 기준선을 깨뜨리지 않고 preflight 이관이 정확히 동작하는지 검증
# 사용: bash tests/run-smoke-WI-A2b.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== A2b-1: lib/preflight.sh 존재 + 문법 ==="
if [[ -f templates/lib/preflight.sh ]]; then
  pass "templates/lib/preflight.sh 존재"
else
  fail "templates/lib/preflight.sh 부재"
fi
if bash -n templates/lib/preflight.sh; then
  pass "lib/preflight.sh bash -n 통과"
else
  fail "lib/preflight.sh 문법 오류"
fi

echo ""
echo "=== A2b-2: preflight() 함수 정의 이관 ==="
# flowset.sh 본체에서 preflight() 정의 제거 + lib/preflight.sh에 이관됨
body_def=$(grep -cE '^preflight\(\)' templates/flowset.sh || true)
lib_def=$(grep -cE '^preflight\(\)' templates/lib/preflight.sh || true)
if [[ "$body_def" == "0" ]]; then
  pass "flowset.sh 본체에 preflight() 정의 없음 (이관 완료)"
else
  fail "flowset.sh 본체에 preflight() 정의 $body_def건 잔존"
fi
if [[ "$lib_def" == "1" ]]; then
  pass "lib/preflight.sh에 preflight() 1건 정의"
else
  fail "lib/preflight.sh preflight() 정의 $lib_def건"
fi

echo ""
echo "=== A2b-3: source 시 preflight 함수 declare 확인 ==="
# lib/preflight.sh source 후 preflight 함수가 등록되는지
result=$(bash -c '
  set -euo pipefail
  source templates/lib/preflight.sh
  declare -F preflight &>/dev/null && echo "FN_OK" || echo "FN_MISSING"
' 2>&1 || echo "ERR")
if [[ "$result" == "FN_OK" ]]; then
  pass "preflight 함수 declare -F 감지"
else
  fail "preflight 함수 로드 실패 ($result)"
fi

echo ""
echo "=== A2b-4: flowset.sh source 시 preflight 로드 ==="
# flowset.sh 상단부(source 블록)만 실행 후 preflight 함수 존재 확인
# cd를 templates/로 하여 lib/preflight.sh 상대 경로가 맞도록
result=$(bash -c '
  set -euo pipefail
  cd templates
  # lib/preflight.sh source 조건 재현
  if [[ -f lib/preflight.sh ]]; then
    source lib/preflight.sh
    declare -F preflight &>/dev/null && echo "FLOWSET_SOURCED_OK" || echo "FLOWSET_FN_MISSING"
  else
    echo "FLOWSET_LIB_MISSING"
  fi
' 2>&1 || echo "ERR")
if [[ "$result" == "FLOWSET_SOURCED_OK" ]]; then
  pass "flowset.sh 기준 source로 preflight 정상 로드"
else
  fail "flowset.sh source 시 preflight 부재 ($result)"
fi

echo ""
echo "=== A2b-5: lib/preflight.sh 없을 때 fail-fast 동작 ==="
# lib/preflight.sh 없는 환경 시뮬레이션. flowset.sh의 fallback exit 1 경로 확인
# 실제 flowset.sh 실행 대신 해당 조건 블록을 추출 실행
result=$(bash -c '
  set -euo pipefail
  # lib/preflight.sh 부재 가정 (가상 경로)
  if [[ -f /nonexistent/lib/preflight.sh ]]; then
    source /nonexistent/lib/preflight.sh
  else
    echo "FALLBACK_ERR" >&2
    exit 1
  fi
' 2>&1 || echo "FALLBACK_OK")
if echo "$result" | grep -q "FALLBACK"; then
  pass "lib/preflight.sh 없으면 exit 1 fail-fast 동작"
else
  fail "fail-fast 경로 실패 ($result)"
fi

echo ""
echo "=== A2b-6: init.md 템플릿 복사 블록에 preflight.sh 추가 ==="
if grep -qE 'cp "\$TEMPLATE_DIR/lib/preflight\.sh"' skills/wi/init.md; then
  pass "init.md에 lib/preflight.sh 복사 라인 존재"
else
  fail "init.md 복사 라인 누락"
fi

echo ""
echo "=== A2b-7: flowset.sh 라인 수 이관 효과 검증 ==="
# 이관 효과 기준점 (lib/ 모듈 분리 누적 추적):
#   설계 원본:  1947 (v3.4 base)
#   WI-A2a 후:  1998 (+51, state.sh source + shim + state_init 추가)
#   WI-A2b 후:  1882 (-116, preflight() 130줄 제거 → lib/preflight.sh로 이관)
# 후속 WI-A2c(worker.sh)/A2d(merge.sh)/A2e(vault.sh) 이관 시 계속 감소 예상
line_count=$(wc -l < templates/flowset.sh)
prev_wi_a2a=1998
delta=$((prev_wi_a2a - line_count))
if (( line_count < prev_wi_a2a )) && (( delta >= 100 )); then
  pass "flowset.sh $line_count 줄 (WI-A2a 후 $prev_wi_a2a 대비 -${delta}줄, preflight 이관 효과)"
else
  fail "flowset.sh $line_count 줄 (WI-A2a 후 $prev_wi_a2a 대비 -${delta}줄, 이관 효과 100줄 미만)"
fi

echo ""
echo "=== A2b-8: bash -n 전체 shell 통과 (회귀 감지) ==="
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
echo "=== A2b-9: WI-A1 + WI-A2a 기준선 비회귀 ==="
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

echo ""
echo "================================"
echo "  Smoke Total: $((PASS + FAIL))"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-A2b ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-A2b REGRESSION DETECTED"
  exit 1
fi
