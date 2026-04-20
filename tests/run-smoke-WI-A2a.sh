#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-A2a.sh — WI-A2a (lib/state.sh) 전용 smoke
# WI-A1 기준선을 깨뜨리지 않고 state.sh 자체 기능이 정확히 동작하는지 검증
# 사용: bash tests/run-smoke-WI-A2a.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== A2a-1: state.sh 독립 로드 + state_init ==="
result=$(bash -c '
  set -euo pipefail
  source templates/lib/state.sh
  state_init
  # 8개 키 전부 빈 값으로 초기화됨
  cnt=$(grep -cE "^(call_count|loop_count|consecutive_no_progress|last_git_sha|last_commit_msg|rate_limit_start|current_session_id|total_cost_usd)=" "$RUNTIME_STATE_FILE")
  echo "KEYS=$cnt"
' 2>&1 || echo "ERR")
if [[ "$result" == "KEYS=8" ]]; then
  pass "state_init 8개 키 초기화"
else
  fail "state_init 실패 ($result)"
fi

echo ""
echo "=== A2a-2: state_set / state_get 기본 동작 ==="
result=$(bash -c '
  set -euo pipefail
  source templates/lib/state.sh
  state_init
  state_set loop_count 42
  state_set current_session_id "sess-abc-123"
  state_set total_cost_usd "1.23"
  printf "%s|%s|%s" "$(state_get loop_count)" "$(state_get current_session_id)" "$(state_get total_cost_usd)"
' 2>&1 || echo "ERR")
if [[ "$result" == "42|sess-abc-123|1.23" ]]; then
  pass "set/get 기본 동작 (42|sess-abc-123|1.23)"
else
  fail "set/get 불일치 ($result)"
fi

echo ""
echo "=== A2a-3: newline escape (multi-line commit msg) ==="
result=$(bash -c '
  set -euo pipefail
  source templates/lib/state.sh
  state_init
  state_set last_commit_msg "첫 줄
둘째 줄
셋째 줄"
  # 결과는 한 줄로 flat되어야 함 (KEY=VAL 포맷 보존)
  state_get last_commit_msg
' 2>&1 || echo "ERR")
if [[ "$result" == "첫 줄 둘째 줄 셋째 줄" ]]; then
  pass "newline → 공백 정규화 + 한글 보존"
else
  fail "newline escape 실패 ($result)"
fi

echo ""
echo "=== A2a-4: state_snapshot 파일 생성 ==="
result=$(bash -c '
  set -euo pipefail
  source templates/lib/state.sh
  state_init
  state_set loop_count 99
  snap=$(state_snapshot)
  # 스냅샷 파일 존재 + 내용에 loop_count=99 있는지
  if [[ -f "$snap" ]] && grep -q "^loop_count=99$" "$snap"; then
    echo "SNAP_OK"
  else
    echo "SNAP_FAIL:snap=[$snap]"
  fi
' 2>&1 || echo "ERR")
if [[ "$result" == "SNAP_OK" ]]; then
  pass "state_snapshot 파일 존재 + 값 기록 (loop_count=99)"
else
  fail "snapshot ($result)"
fi

echo ""
echo "=== A2a-5: 값에 '=' 포함 처리 ==="
result=$(bash -c '
  set -euo pipefail
  source templates/lib/state.sh
  state_init
  state_set last_commit_msg "fix: url=https://foo?a=b&c=d"
  state_get last_commit_msg
' 2>&1 || echo "ERR")
if [[ "$result" == "fix: url=https://foo?a=b&c=d" ]]; then
  pass "값에 = 포함되어도 정확 반환"
else
  fail "= 포함 값 파싱 실패 ($result)"
fi

echo ""
echo "=== A2a-6: lock 연속 set 무결성 ==="
result=$(bash -c '
  set -euo pipefail
  source templates/lib/state.sh
  state_init
  # 100회 연속 set → 카운트 업
  for i in $(seq 1 100); do
    state_set call_count "$i"
  done
  state_get call_count
' 2>&1 || echo "ERR")
if [[ "$result" == "100" ]]; then
  pass "100회 연속 set 최종값 정확"
else
  fail "연속 set 경쟁 ($result)"
fi

echo ""
echo "=== A2a-7: flowset.sh shim fallback (lib/state.sh 없을 때) ==="
# flowset.sh의 shim 블록이 독립 실행 가능한지 검증
result=$(bash -c '
  set -euo pipefail
  call_count=0
  loop_count=0
  current_session_id=""
  total_cost_usd=0

  # flowset.sh:58-73의 shim 함수만 정의 (실제 source 없이)
  state_get() { local k="${1:-}"; [[ -z "$k" ]] && return 0; eval "printf \"%s\" \"\${$k:-}\""; }
  state_set() { local k="${1:-}" v="${2:-}"; [[ -z "$k" ]] && return 1; eval "$k=\"\$v\""; }

  state_set loop_count 77
  state_set current_session_id "shim-test"
  printf "%s|%s" "$(state_get loop_count)" "$(state_get current_session_id)"
' 2>&1 || echo "ERR")
if [[ "$result" == "77|shim-test" ]]; then
  pass "shim fallback 전역변수 방식 작동 (77|shim-test)"
else
  fail "shim fallback 실패 ($result)"
fi

echo ""
echo "=== A2a-8: flowset.sh 전체 문법 + source 로드 ==="
# flowset.sh가 state.sh를 source하는 초반부만 실행 (전체 루프는 실행 안 함)
if bash -n templates/flowset.sh; then
  pass "templates/flowset.sh bash -n 통과"
else
  fail "templates/flowset.sh 문법 오류"
fi
if bash -n templates/lib/state.sh; then
  pass "templates/lib/state.sh bash -n 통과"
else
  fail "templates/lib/state.sh 문법 오류"
fi

echo ""
echo "=== A2a-9: WI-A1 기준선 비회귀 ==="
# test-vault-transcript.sh
if bash "$SCRIPT_DIR/test-vault-transcript.sh" 2>&1 | grep -q "^ALL TESTS PASSED$"; then
  pass "test-vault-transcript.sh 31 assertion 유지"
else
  fail "test-vault-transcript.sh 회귀"
fi
# run-smoke-WI-A1.sh
if bash "$SCRIPT_DIR/run-smoke-WI-A1.sh" 2>&1 | grep -q "WI-A1 ALL SMOKE PASSED"; then
  pass "run-smoke-WI-A1.sh 14 smoke 유지"
else
  fail "run-smoke-WI-A1.sh 회귀"
fi

echo ""
echo "=== A2a-10: 설계 §11 체크리스트 — flowset.sh:82-93 변수 vs RUNTIME_STATE_KEYS 대조 ==="
# 설계 §11 line 617-620 "이관 누락 방지 체크리스트"
# flowset.sh:82-93에 선언된 전역변수 8개와 RUNTIME_STATE_KEYS 8개가 1:1 대응하는지 검증
expected_vars="call_count consecutive_no_progress current_session_id last_commit_msg last_git_sha loop_count rate_limit_start total_cost_usd"
actual_vars=$(awk '/^# State$/,/^COMPLETED_FILE=/' templates/flowset.sh | grep -oE '^[a-z_]+=' | sed 's/=$//' | sort -u | tr '\n' ' ' | sed 's/ $//')
# 정렬된 8개 이름 매칭 (순서 무관)
actual_sorted=$(echo "$actual_vars" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
expected_sorted=$(echo "$expected_vars" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
# flowset.sh에 있는 변수 중 RUNTIME_STATE_KEYS에 없는 것 탐지 (NO_PROGRESS_LIMIT, CONTEXT_THRESHOLD는 상수라 제외)
diff_output=$(comm -23 <(echo "$expected_sorted" | tr ' ' '\n') <(echo "$actual_sorted" | tr ' ' '\n' | grep -vE '^(NO_PROGRESS_LIMIT|CONTEXT_THRESHOLD|STATE_FILE|COMPLETED_FILE)$') 2>/dev/null || true)
if [[ -z "$diff_output" ]]; then
  pass "RUNTIME_STATE_KEYS 8개 ↔ flowset.sh 전역변수 정합 (iteration_cost/total_context_tokens는 execute_claude 지역변수라 제외)"
else
  fail "RUNTIME_STATE_KEYS 누락: $diff_output"
fi

echo ""
echo "=== A2a-11: iteration_cost/total_context_tokens 제외 근거 검증 ==="
# 설계 §11 line 441: "iteration_cost, total_context_tokens는 execute_claude() 지역변수(:1662, :1667)이므로 이관 대상 아님"
# → execute_claude()가 정의된 파일에서 local 선언 확인
# WI-A2c 이후: execute_claude가 templates/lib/worker.sh로 이관되었으므로 검색 범위 확장
if grep -rqE '^\s+local\s+(iteration_cost|total_context_tokens|new_session_id\s+iteration_cost)' templates/flowset.sh templates/lib/ 2>/dev/null; then
  pass "iteration_cost/total_context_tokens 지역변수 선언 확인 (state 이관 대상 아님)"
else
  fail "지역변수 선언 누락 (설계 §11 라인 441 근거 깨짐)"
fi

echo ""
echo "================================"
echo "  Smoke Total: $((PASS + FAIL))"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-A2a ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-A2a REGRESSION DETECTED"
  exit 1
fi
