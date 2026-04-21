#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-A3.sh — WI-A3 (bats-core 테스트 인프라) 전용 smoke
# WI-A1 + A2a~A2e 기준선 비회귀 + bats submodule/실행/테스트 결과 검증
# 사용: bash tests/run-smoke-WI-A3.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== A3-1: bats-core submodule 경로 + 실행 가능성 ==="
if [[ -f "tests/bats/bin/bats" ]]; then
  pass "tests/bats/bin/bats 실행 파일 존재"
else
  fail "tests/bats/bin/bats 부재 (submodule 미초기화)"
fi
if [[ -f ".gitmodules" ]] && grep -q 'tests/bats' .gitmodules; then
  pass ".gitmodules에 tests/bats submodule 등록"
else
  fail ".gitmodules submodule 항목 누락"
fi

echo ""
echo "=== A3-2: bats --version 실행 가능 (Windows Git Bash 호환) ==="
# HANDOFF R8 리스크(bats-core Windows 호환 불가 가능성) 실측 검증
bats_version=$(bash tests/bats/bin/bats --version 2>&1 || echo "ERR")
if echo "$bats_version" | grep -qE '^Bats [0-9]+\.[0-9]+\.[0-9]+'; then
  pass "bats 실행 가능: $bats_version (R8 리스크 해소)"
else
  fail "bats 실행 실패: $bats_version"
fi

echo ""
echo "=== A3-3: tests/bats_tests/core.bats 존재 + 문법 ==="
if [[ -f tests/bats_tests/core.bats ]]; then
  pass "tests/bats_tests/core.bats 존재"
else
  fail "core.bats 부재"
fi
# bats 파일은 bash 문법 준수 (@test 블록은 bats 전처리기가 변환)
if bash -n tests/bats_tests/core.bats 2>&1 | head -1 | grep -qE 'syntax error|^$'; then
  # bash -n은 @test 블록을 문법 오류로 볼 수 있음 — 대신 bats --count로 검증
  true
fi
# 테스트 개수 ≥ 14 (설계 §7 10~20개 범위 준수)
test_count=$(bash tests/bats/bin/bats --count tests/bats_tests/core.bats 2>/dev/null || true)
if [[ "$test_count" -ge 14 && "$test_count" -le 20 ]]; then
  pass "core.bats $test_count 테스트 (설계 §7 10~20 범위 준수)"
else
  fail "core.bats $test_count 테스트 (설계 §7 10~20 범위 이탈)"
fi

echo ""
echo "=== A3-4: core.bats 전수 PASS ==="
bats_output=$(bash tests/bats/bin/bats tests/bats_tests/core.bats 2>&1 || echo "FAIL")
bats_total=$(echo "$bats_output" | grep -cE '^(ok|not ok) ' || true)
bats_pass=$(echo "$bats_output" | grep -cE '^ok ' || true)
bats_fail=$(echo "$bats_output" | grep -cE '^not ok ' || true)
if [[ "$bats_fail" == "0" && "$bats_total" -ge 14 ]]; then
  pass "bats core.bats ${bats_pass}/${bats_total} PASS"
else
  fail "bats core.bats ${bats_pass}/${bats_total} (FAIL: $bats_fail)"
  echo "$bats_output" | grep -E '^(not ok|# )' | head -20
fi

echo ""
echo "=== A3-5: bats 테스트가 bash smoke 기준선과 정합 ==="
# core.bats는 기존 bash smoke의 핵심 14개를 선별 변환 — 이중 검증 구조
# WI-A1~A2e 각 2건 + test-vault 2건 = 14건이 core.bats에 존재
wi_coverage=$(grep -cE '^@test "(WI-A1|WI-A2a|WI-A2b|WI-A2c|WI-A2d|WI-A2e|vault-helpers):' tests/bats_tests/core.bats)
if [[ "$wi_coverage" -ge 14 ]]; then
  pass "WI-A1/A2a~e + vault-helpers 전수 커버 (@test $wi_coverage개)"
else
  fail "WI 커버리지 부족 ($wi_coverage/14)"
fi

echo ""
echo "=== A3-6: install.sh에 bats submodule 초기화 로직 추가 ==="
if grep -q 'tests/bats submodule' install.sh; then
  pass "install.sh에 bats submodule 안내 추가"
else
  fail "install.sh 업데이트 누락"
fi

echo ""
echo "=== A3-7: bash -n 전체 shell 통과 (.bats/bats submodule 제외) ==="
# .bats 파일은 find -name "*.sh" 확장자 필터로 자동 제외 (별도 -not 조건 불필요)
# tests/bats/* 제외는 submodule 내부 7개 .sh (상류 bats-core 관리 소관, 본 프로젝트 검사 범위 밖)
fail_count=0
for f in $(find . -name "*.sh" -not -path "./.git/*" -not -path "./tests/bats/*"); do
  if ! bash -n "$f" 2>/dev/null; then
    fail_count=$((fail_count + 1))
    echo "    문법 오류: $f"
  fi
done
if (( fail_count == 0 )); then
  pass "전체 shell bash -n 통과 (오류 0건, bats submodule 내부 제외)"
else
  fail "$fail_count 파일 문법 오류"
fi

echo ""
echo "=== A3-8: 학습 전이 보존 (tests/bats_tests/) ==="
# WI-A1 학습 3가지: sed JSON / ((var++)) / ${arr[@]/pattern}
issues=0
for f in tests/bats_tests/*.bats; do
  grep -qE 'sed -n.*"[a-z_]+"\s*:' "$f" && issues=$((issues + 1))
  grep -qE '\(\([a-z_]+\+\+\)\)' "$f" && issues=$((issues + 1))
  grep -qE '\$\{[a-z_]+\[@\]/[^}]+\}' "$f" && issues=$((issues + 1))
done
if (( issues == 0 )); then
  pass "tests/bats_tests/ 학습 회귀 없음 (sed/((var++))/arr pattern 0건)"
else
  fail "$issues개 학습 회귀 감지"
fi

echo ""
echo "=== A3-9: WI-A1~A2e 기준선 비회귀 (누적 126 → 140 assertion) ==="
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
if bash "$SCRIPT_DIR/run-smoke-WI-A2d.sh" 2>&1 | grep -q "WI-A2d ALL SMOKE PASSED"; then
  pass "run-smoke-WI-A2d.sh 16 smoke 유지"
else
  fail "run-smoke-WI-A2d.sh 회귀"
fi
if bash "$SCRIPT_DIR/run-smoke-WI-A2e.sh" 2>&1 | grep -q "WI-A2e ALL SMOKE PASSED"; then
  pass "run-smoke-WI-A2e.sh 24 smoke 유지"
else
  fail "run-smoke-WI-A2e.sh 회귀"
fi

echo ""
echo "================================"
echo "  Smoke Total: $((PASS + FAIL))"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-A3 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-A3 REGRESSION DETECTED"
  exit 1
fi
