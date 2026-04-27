#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-A4.sh — WI-A4 (FlowSet 자체 CI) 전용 smoke
# .github/workflows/flowset-ci.yml 구조 검증 + 기존 7개 smoke 비회귀
# 사용: bash tests/run-smoke-WI-A4.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

CI_YML=".github/workflows/flowset-ci.yml"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== A4-1: .github/workflows/flowset-ci.yml 존재 + YAML 문법 ==="
if [[ -f "$CI_YML" ]]; then
  pass ".github/workflows/flowset-ci.yml 존재"
else
  fail "flowset-ci.yml 부재"
fi
# Python YAML 검증 (cp949 회피 위해 encoding='utf-8' 명시 — wi-utf8.md 규칙)
yaml_result=$(python -c "
import yaml, sys
try:
    with open('$CI_YML', encoding='utf-8') as f:
        d = yaml.safe_load(f)
    jobs = list(d.get('jobs', {}).keys())
    print('OK:' + ','.join(jobs))
except Exception as e:
    print('FAIL:' + str(e))
" 2>&1 || echo "FAIL:python exec")
if echo "$yaml_result" | grep -q '^OK:'; then
  pass "YAML 문법 valid + jobs=$(echo "$yaml_result" | sed 's/^OK://')"
else
  fail "YAML 파싱 실패: $yaml_result"
fi

echo ""
echo "=== A4-2: 4개 job 정의 (shellcheck/bats/smoke/commit-check) ==="
expected_jobs=(shellcheck bats smoke commit-check)
missing=0
for job in "${expected_jobs[@]}"; do
  if ! grep -qE "^  ${job}:" "$CI_YML"; then
    missing=$((missing + 1))
    echo "    누락: $job"
  fi
done
if (( missing == 0 )); then
  pass "4개 job 전부 정의 (shellcheck/bats/smoke/commit-check)"
else
  fail "$missing job 누락"
fi

echo ""
echo "=== A4-3: [evaluator R1] actions/checkout@v4에 submodules: recursive ==="
# evaluator WI-A3 2차 선제 관측 R1:
#   "actions/checkout@v4에 submodules: recursive 필수 — 누락 시 tests/bats/ 미존재로 bats 실행 불가"
recursive_count=$(grep -c 'submodules: recursive' "$CI_YML" || true)
# commit-check job은 submodules 불필요 (git log 검증만) → 3개 job에만 필요
# 대상 job: lint / bats / smoke (commit-check 제외)
if (( recursive_count >= 3 )); then
  pass "submodules: recursive ${recursive_count}회 (≥3 — shellcheck/bats/smoke 커버)"
else
  fail "submodules: recursive ${recursive_count}회 (bats/smoke 실행 실패 위험)"
fi

echo ""
echo "=== A4-4: [evaluator R2] shellcheck 대상에서 tests/bats/* 제외 ==="
# evaluator WI-A3 2차 선제 관측 R2:
#   "shellcheck 대상에 -not -path './tests/bats/*' 추가 필요 (submodule 상류 관리)"
if grep -q 'not -path "./tests/bats/\*"' "$CI_YML"; then
  pass "shellcheck find에 tests/bats/* 제외 포함"
else
  fail "shellcheck tests/bats/* 제외 누락 (설계 §5 :260 충돌 미해소)"
fi

echo ""
echo "=== A4-5: [evaluator R3] bats 실행이 submodule 경로 사용 ==="
# evaluator WI-A3 2차 선제 관측 R3:
#   "설계 §5 :265 npm install -g bats → submodule 전략으로 통일"
if grep -qE 'bash tests/bats/bin/bats' "$CI_YML"; then
  pass "bats 실행에 submodule 경로 사용 (npm 전략 폐기)"
else
  fail "bats 실행이 submodule 경로 아님"
fi
# npm 잔존 여부 검사 (주석 라인 제외 — 설계 §5 비교 문맥 허용)
if grep -vE '^[[:space:]]*#' "$CI_YML" | grep -qE 'run:.*npm install.*bats'; then
  fail "npm install -g bats 잔존 (실제 run: 명령 — submodule 전략과 충돌)"
else
  pass "npm install -g bats 실제 명령 0건 (설계 §5 :265 충돌 해소)"
fi

echo ""
echo "=== A4-6: smoke job이 7개 smoke 파일 전수 호출 ==="
expected_smokes=(
  "test-vault-transcript.sh"
  "run-smoke-WI-A1.sh"
  "run-smoke-WI-A2a.sh"
  "run-smoke-WI-A2b.sh"
  "run-smoke-WI-A2c.sh"
  "run-smoke-WI-A2d.sh"
  "run-smoke-WI-A2e.sh"
  "run-smoke-WI-A3.sh"
)
smoke_missing=0
for s in "${expected_smokes[@]}"; do
  if ! grep -qE "bash tests/${s}" "$CI_YML"; then
    smoke_missing=$((smoke_missing + 1))
    echo "    누락: $s"
  fi
done
expected_count=${#expected_smokes[@]}
if (( smoke_missing == 0 )); then
  pass "smoke job이 ${expected_count}개 smoke 전수 호출 (test-vault + A1~A3)"
else
  fail "$smoke_missing/${expected_count} 호출 누락"
fi

echo ""
echo "=== A4-7: commit-check job이 WI-NNN-[type] 패턴 검증 ==="
# rules/wi-global.md §1 형식 검증 (fixed string 매칭 — 정규식 메타문자 회피)
if grep -qF 'WI-[0-9A-Za-z]+(-[0-9]+)?-(feat|fix|docs|style|refactor|test|chore|perf|ci|revert)' "$CI_YML"; then
  pass "commit-check에 WI-NNN-[type] 정규식 존재"
else
  fail "commit-check 정규식 누락"
fi
# pull_request에만 적용 (push 시 커밋 메시지 재검증 불필요)
if grep -qE "if: github.event_name == 'pull_request'" "$CI_YML"; then
  pass "commit-check는 pull_request에만 적용 (중복 검증 방지)"
else
  fail "commit-check 조건 누락"
fi

echo ""
echo "=== A4-8: trigger가 push + pull_request 모두 포함 ==="
if grep -qE '^on:' "$CI_YML" && grep -qE '^  push:' "$CI_YML" && grep -qE '^  pull_request:' "$CI_YML"; then
  pass "on: push + pull_request 트리거 존재"
else
  fail "트리거 누락"
fi

echo ""
echo "=== A4-9: bash -n 전체 shell 통과 (.bats/bats submodule 제외) ==="
# .bats 파일은 find -name "*.sh" 확장자 필터로 자동 제외
# tests/bats/* 제외는 submodule 내부 파일 (상류 bats-core 관리 소관)
fail_count=0
while IFS= read -r -d '' f; do
  if ! bash -n "$f" 2>/dev/null; then
    fail_count=$((fail_count + 1))
    echo "    문법 오류: $f"
  fi
done < <(find . -name "*.sh" -not -path "./.git/*" -not -path "./tests/bats/*" -print0)
if (( fail_count == 0 )); then
  pass "전체 shell bash -n 통과 (오류 0건)"
else
  fail "$fail_count 파일 문법 오류"
fi

echo ""
echo "=== A4-10: 학습 전이 보존 (.github/workflows/*.yml) ==="
# WI-A1 학습: sed JSON / ((var++)) / ${arr[@]/pattern}
issues=0
if grep -qE 'sed -n.*"[a-z_]+"\s*:' "$CI_YML"; then
  issues=$((issues + 1))
  echo "    sed JSON 파싱 잔존"
fi
if grep -qE '\(\([a-z_]+\+\+\)\)' "$CI_YML"; then
  issues=$((issues + 1))
  echo "    ((var++)) 잔존"
fi
if grep -qE '\$\{[a-z_]+\[@\]/[^}]+\}' "$CI_YML"; then
  issues=$((issues + 1))
  echo "    \${arr[@]/pattern} 오용 잔존"
fi
if (( issues == 0 )); then
  pass "CI yml 학습 회귀 없음 (sed/((var++))/arr pattern 0건)"
else
  fail "$issues개 학습 회귀 감지"
fi

echo ""
echo "=== A4-11: WI-A1~A3 기준선 비회귀 (누적 143 → 143+ assertion) ==="
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
if bash "$SCRIPT_DIR/run-smoke-WI-A3.sh" 2>&1 | grep -q "WI-A3 ALL SMOKE PASSED"; then
  pass "run-smoke-WI-A3.sh 17 smoke 유지"
else
  fail "run-smoke-WI-A3.sh 회귀"
fi

echo ""
echo "================================"
echo "  Smoke Total: $((PASS + FAIL))"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-A4 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-A4 REGRESSION DETECTED"
  exit 1
fi
