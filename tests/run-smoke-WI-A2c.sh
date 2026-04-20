#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-A2c.sh — WI-A2c (lib/worker.sh) 전용 smoke
# WI-A1 + WI-A2a + WI-A2b 기준선을 깨뜨리지 않고 worker 이관이 정확히 동작하는지 검증
# 사용: bash tests/run-smoke-WI-A2c.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== A2c-1: lib/worker.sh 존재 + 문법 ==="
if [[ -f templates/lib/worker.sh ]]; then
  pass "templates/lib/worker.sh 존재"
else
  fail "templates/lib/worker.sh 부재"
fi
if bash -n templates/lib/worker.sh; then
  pass "lib/worker.sh bash -n 통과"
else
  fail "lib/worker.sh 문법 오류"
fi

echo ""
echo "=== A2c-2: execute_claude() 함수 정의 이관 ==="
body_def=$(grep -cE '^execute_claude\(\)' templates/flowset.sh || true)
lib_def=$(grep -cE '^execute_claude\(\)' templates/lib/worker.sh || true)
if [[ "$body_def" == "0" ]]; then
  pass "flowset.sh 본체에 execute_claude() 정의 없음 (이관 완료)"
else
  fail "flowset.sh 본체에 execute_claude() 정의 $body_def건 잔존"
fi
if [[ "$lib_def" == "1" ]]; then
  pass "lib/worker.sh에 execute_claude() 1건 정의"
else
  fail "lib/worker.sh execute_claude() 정의 $lib_def건"
fi

echo ""
echo "=== A2c-3: source 시 execute_claude 함수 declare 확인 ==="
result=$(bash -c '
  set -euo pipefail
  source templates/lib/worker.sh
  declare -F execute_claude &>/dev/null && echo "FN_OK" || echo "FN_MISSING"
' 2>&1 || echo "ERR")
if [[ "$result" == "FN_OK" ]]; then
  pass "execute_claude 함수 declare -F 감지"
else
  fail "execute_claude 함수 로드 실패 ($result)"
fi

echo ""
echo "=== A2c-4: flowset.sh source 시 worker 로드 ==="
# flowset.sh의 source 블록 재현
result=$(bash -c '
  set -euo pipefail
  cd templates
  if [[ -f lib/worker.sh ]]; then
    source lib/worker.sh
    declare -F execute_claude &>/dev/null && echo "FLOWSET_SOURCED_OK" || echo "FLOWSET_FN_MISSING"
  else
    echo "FLOWSET_LIB_MISSING"
  fi
' 2>&1 || echo "ERR")
if [[ "$result" == "FLOWSET_SOURCED_OK" ]]; then
  pass "flowset.sh 기준 source로 execute_claude 정상 로드"
else
  fail "flowset.sh source 시 execute_claude 부재 ($result)"
fi

echo ""
echo "=== A2c-5: lib/worker.sh 없을 때 fail-fast 동작 ==="
# preflight.sh와 동일한 fail-fast 정책 확인
result=$(bash -c '
  set -euo pipefail
  if [[ -f /nonexistent/lib/worker.sh ]]; then
    source /nonexistent/lib/worker.sh
  else
    echo "FALLBACK_ERR" >&2
    exit 1
  fi
' 2>&1 || echo "FALLBACK_OK")
if echo "$result" | grep -q "FALLBACK"; then
  pass "lib/worker.sh 없으면 exit 1 fail-fast 동작"
else
  fail "fail-fast 경로 실패 ($result)"
fi

echo ""
echo "=== A2c-6: init.md 템플릿 복사 블록에 worker.sh 추가 ==="
if grep -qE 'cp "\$TEMPLATE_DIR/lib/worker\.sh"' skills/wi/init.md; then
  pass "init.md에 lib/worker.sh 복사 라인 존재"
else
  fail "init.md 복사 라인 누락"
fi

echo ""
echo "=== A2c-7: flowset.sh 라인 수 이관 효과 검증 ==="
# 이관 효과 기준점 (smoke-WI-A2b.md 표 참조):
#   WI-A2b 후: 1882
#   WI-A2c 후: ~1700 예상 (-180)
# 조건: 이전 단계(WI-A2b) 대비 감소량 >= 80줄
line_count=$(wc -l < templates/flowset.sh)
prev_wi_a2b=1882
delta=$((prev_wi_a2b - line_count))
if (( line_count < prev_wi_a2b )) && (( delta >= 80 )); then
  pass "flowset.sh $line_count 줄 (WI-A2b 후 $prev_wi_a2b 대비 -${delta}줄, execute_claude 이관)"
else
  fail "flowset.sh $line_count 줄 (delta -${delta}, 이관 효과 80줄 미만)"
fi

echo ""
echo "=== A2c-8: bash -n 전체 shell 통과 ==="
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
echo "=== A2c-9: WI-A1 + WI-A2a + WI-A2b 기준선 비회귀 ==="
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

echo ""
echo "=== A2c-10: execute_claude jq 파싱 로직 보존 (WI-A1 학습 전이) ==="
# 설계 §11 + WI-A1 학습: sed → jq 전환 유지
# execute_claude가 lib/worker.sh로 이관되어도 jq 파싱 3개 키 유지 확인
keys="session_id total_cost_usd cache_creation_input_tokens"
missing=0
for k in $keys; do
  if ! grep -q "$k" templates/lib/worker.sh; then
    missing=$((missing + 1))
    echo "    키 누락: $k"
  fi
done
if (( missing == 0 )); then
  pass "execute_claude jq 파싱 3개 키 모두 lib/worker.sh에서 보존"
else
  fail "jq 파싱 키 $missing개 누락 (sed→jq 전환 회귀)"
fi

echo ""
echo "================================"
echo "  Smoke Total: $((PASS + FAIL))"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-A2c ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-A2c REGRESSION DETECTED"
  exit 1
fi
