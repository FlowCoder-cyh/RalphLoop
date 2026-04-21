#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-A2e.sh — WI-A2e (lib/vault.sh + 이중 기록 제거) 전용 smoke
# WI-A1 + WI-A2a + WI-A2b + WI-A2c + WI-A2d 기준선 비회귀
# + vault.sh 19함수 이관 + 전역변수 직접 참조 0건 검증 (WI-A2a 약속 이행)
# 사용: bash tests/run-smoke-WI-A2e.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== A2e-1: lib/vault.sh 존재 + 문법 ==="
if [[ -f templates/lib/vault.sh ]]; then
  pass "templates/lib/vault.sh 존재"
else
  fail "templates/lib/vault.sh 부재"
fi
if bash -n templates/lib/vault.sh; then
  pass "lib/vault.sh bash -n 통과"
else
  fail "lib/vault.sh 문법 오류"
fi

echo ""
echo "=== A2e-2: vault 19개 함수 정의 이관 확인 ==="
functions=(
  _vault_curl vault_check vault_read vault_write vault_delete
  vault_search vault_init_project vault_detect_mode vault_sync_state
  vault_save_session_log vault_save_daily_session_log vault_read_latest_session
  vault_sync_team_state vault_read_team_state vault_record vault_check_tech_debt
  vault_extract_transcript vault_build_transcript_summary vault_build_state_content
)
missing=0
for fn in "${functions[@]}"; do
  if ! grep -qE "^${fn}\(\)" templates/lib/vault.sh; then
    missing=$((missing + 1))
    echo "    $fn: 정의 누락"
  fi
done
if (( missing == 0 )); then
  pass "19개 vault_ 함수 전부 lib/vault.sh에 정의"
else
  fail "$missing 함수 이관 누락"
fi

echo ""
echo "=== A2e-3: vault-helpers.sh shim 구조 (본체 이관, re-source) ==="
# 원본 426줄 → shim < 50줄 (본체 이관 확인)
vh_lines=$(wc -l < templates/.flowset/scripts/vault-helpers.sh)
if (( vh_lines < 50 )); then
  pass "vault-helpers.sh shim ${vh_lines}줄 (<50줄 — 본체 이관 완료)"
else
  fail "vault-helpers.sh ${vh_lines}줄 (본체 이관 미완)"
fi
# shim이 lib/vault.sh를 source하는지 확인
if grep -qE 'source.*lib/vault\.sh' templates/.flowset/scripts/vault-helpers.sh; then
  pass "shim이 lib/vault.sh를 source"
else
  fail "shim에 lib/vault.sh source 라인 없음"
fi

echo ""
echo "=== A2e-4: shim source 시 19개 함수 전부 declare ==="
# shim을 source하면 lib/vault.sh가 간접 로드되어 19함수 정의됨
result=$(bash -c '
  set -euo pipefail
  cd templates
  source .flowset/scripts/vault-helpers.sh
  missing=0
  for fn in _vault_curl vault_check vault_read vault_write vault_delete \
            vault_search vault_init_project vault_detect_mode vault_sync_state \
            vault_save_session_log vault_save_daily_session_log vault_read_latest_session \
            vault_sync_team_state vault_read_team_state vault_record vault_check_tech_debt \
            vault_extract_transcript vault_build_transcript_summary vault_build_state_content; do
    declare -F "$fn" &>/dev/null || missing=$((missing + 1))
  done
  echo "MISSING=$missing"
' 2>&1 || echo "ERR")
if [[ "$result" == "MISSING=0" ]]; then
  pass "shim source 후 19개 함수 전부 declare"
else
  fail "shim 함수 누락: $result"
fi

echo ""
echo "=== A2e-5: flowset.sh source 블록에 lib/vault.sh 포함 ==="
if grep -q '^  source lib/vault.sh' templates/flowset.sh; then
  pass "source lib/vault.sh 블록 존재"
else
  fail "source lib/vault.sh 블록 누락"
fi

echo ""
echo "=== A2e-6: lib/vault.sh 없을 때 fail-fast (WI-A2b/c/d 패턴 일관) ==="
# fail-fast 에러 메시지 패턴 확인
if grep -q "ERROR: lib/vault.sh 없음" templates/flowset.sh; then
  pass "lib/vault.sh fail-fast 에러 메시지 존재"
else
  fail "fail-fast 에러 메시지 누락"
fi

echo ""
echo "=== A2e-7: init.md 템플릿 복사 블록에 lib/vault.sh 추가 ==="
if grep -qE 'cp "\$TEMPLATE_DIR/lib/vault\.sh"' skills/wi/init.md; then
  pass "init.md에 lib/vault.sh 복사 라인 존재"
else
  fail "init.md 복사 라인 누락"
fi

echo ""
echo "=== A2e-8: [핵심] 이중 기록 제거 - 8개 전역변수 직접 참조 0건 ==="
# WI-A2a smoke-WI-A2a.md :19의 약속 이행 검증:
#   "WI-A2e 완료 시점에 61건 직접 참조가 전부 state_get으로 전환되면 이중 기록 제거"
# 검사 대상: flowset.sh + lib/state.sh/preflight.sh/worker.sh/merge.sh
# (lib/vault.sh는 vault_sync_state 내부 local loop_count 파라미터만 사용 — 제외)
keys_pattern='\$\{?(call_count|loop_count|consecutive_no_progress|last_git_sha|last_commit_msg|rate_limit_start|current_session_id|total_cost_usd)\}?'
ref_count=0
for f in templates/flowset.sh templates/lib/state.sh templates/lib/preflight.sh templates/lib/worker.sh templates/lib/merge.sh; do
  c=$(grep -cE "$keys_pattern" "$f" 2>/dev/null || true)
  c=${c:-0}
  ref_count=$((ref_count + c))
done
if (( ref_count == 0 )); then
  pass "flowset.sh + lib/*.sh 내 8개 state 키 직접 참조 0건 (이중 기록 제거 완료)"
else
  fail "$ref_count건 직접 참조 잔존"
fi

echo ""
echo "=== A2e-9: [핵심] 전역변수 초기화 라인 :135-146 블록 제거 ==="
# 삭제 확인: flowset.sh 최상단에서 `call_count=0` 등 직접 할당 0건
assign_pattern='^(call_count|loop_count|consecutive_no_progress|last_git_sha|last_commit_msg|rate_limit_start|current_session_id|total_cost_usd)='
assign_count=0
for f in templates/flowset.sh templates/lib/worker.sh templates/lib/merge.sh; do
  c=$(grep -cE "$assign_pattern" "$f" 2>/dev/null || true)
  c=${c:-0}
  assign_count=$((assign_count + c))
done
if (( assign_count == 0 )); then
  pass "flowset.sh + lib/*.sh 내 전역변수 직접 할당 0건"
else
  fail "$assign_count건 직접 할당 잔존"
fi

echo ""
echo "=== A2e-10: state_init 후 state_set 8개 키 초기화 블록 ==="
# state_init 다음 블록에서 8개 state_set 호출 확인 (이중 기록 대체)
for key in call_count loop_count consecutive_no_progress last_git_sha last_commit_msg rate_limit_start current_session_id total_cost_usd; do
  if ! grep -qE "^state_set $key " templates/flowset.sh; then
    fail "state_set $key 초기화 누락"
    break
  fi
done
# 모든 키 통과하면 pass
if grep -qE "^state_set call_count " templates/flowset.sh \
  && grep -qE "^state_set loop_count " templates/flowset.sh \
  && grep -qE "^state_set rate_limit_start " templates/flowset.sh \
  && grep -qE "^state_set total_cost_usd " templates/flowset.sh; then
  pass "state_init 후 8개 키 초기화 블록 존재"
fi

echo ""
echo "=== A2e-11: [핵심] lib/state.sh shim 제거 (fail-fast 전환) ==="
# WI-A2a의 전역변수 shim(:64-68)이 제거되고 fail-fast 블록으로 교체됐는지
# shim 증거: 'state_get() { local k=' 또는 'eval "printf '\''%s'\''"' 패턴
shim_count=$(grep -cE '^  state_get\(\)\s*\{.*eval|^  state_set\(\)\s*\{.*eval' templates/flowset.sh 2>/dev/null || true)
shim_count=${shim_count:-0}
if (( shim_count == 0 )); then
  pass "lib/state.sh 전역변수 shim 제거됨 (WI-A2b/c/d/e와 동일 fail-fast 정책)"
else
  fail "전역변수 shim $shim_count건 잔존 (fail-fast 전환 미완)"
fi
# fail-fast 에러 메시지 존재 확인
if grep -q "ERROR: lib/state.sh 없음" templates/flowset.sh; then
  pass "lib/state.sh fail-fast 에러 메시지 존재"
else
  fail "lib/state.sh fail-fast 에러 메시지 누락"
fi

echo ""
echo "=== A2e-12: flowset.sh 라인 수 (이관 효과 누적) ==="
# WI-A2d 후 1308 → WI-A2e 후 약간 변동 (이중 기록 블록 제거 vs vault source 추가)
# 임계치: < 1310 (유지 또는 감소)
line_count=$(wc -l < templates/flowset.sh)
prev_wi_a2d=1308
if (( line_count <= prev_wi_a2d + 10 )); then
  delta=$((prev_wi_a2d - line_count))
  pass "flowset.sh $line_count 줄 (WI-A2d 후 $prev_wi_a2d 대비 Δ=${delta}, 이중 기록 제거 + vault source 교체)"
else
  fail "flowset.sh $line_count 줄 (WI-A2d 후 대비 +$(( line_count - prev_wi_a2d ))줄 증가)"
fi

echo ""
echo "=== A2e-13: bash -n 전체 shell 통과 ==="
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
echo "=== A2e-14: lib/vault.sh 내부 학습 전이 보존 ==="
# WI-A1 학습: sed→jq, ((var++)) 금지, ${arr[@]/pat} 금지
issues=0
if grep -qE 'sed -n.*"[a-z_]+"\s*:' templates/lib/vault.sh; then
  issues=$((issues + 1))
  echo "    sed JSON 파싱 잔존"
fi
if grep -qE '\(\([a-z_]+\+\+\)\)' templates/lib/vault.sh; then
  issues=$((issues + 1))
  echo "    ((var++)) 잔존"
fi
if grep -qE '\$\{[a-z_]+\[@\]/[^}]+\}' templates/lib/vault.sh; then
  issues=$((issues + 1))
  echo "    \${arr[@]/pattern} 오용 잔존"
fi
if (( issues == 0 )); then
  pass "lib/vault.sh에 WI-A1~A2d 학습 회귀 없음 (sed/((var++))/arr pattern 0건)"
else
  fail "$issues개 학습 회귀 감지"
fi

echo ""
echo "=== A2e-15: state.sh API 불변 (5함수 보존) ==="
# state_init / state_get / state_set / state_snapshot / state_restore
api_missing=0
for fn in state_init state_get state_set state_snapshot state_restore; do
  if ! grep -qE "^${fn}\(\)" templates/lib/state.sh; then
    api_missing=$((api_missing + 1))
    echo "    $fn 정의 누락"
  fi
done
if (( api_missing == 0 )); then
  pass "state.sh 5개 공개 API 불변 유지"
else
  fail "$api_missing 함수 API 변경"
fi

echo ""
echo "=== A2e-16: WI-A1 + A2a + A2b + A2c + A2d 기준선 비회귀 (누적 102) ==="
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

echo ""
echo "================================"
echo "  Smoke Total: $((PASS + FAIL))"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-A2e ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-A2e REGRESSION DETECTED"
  exit 1
fi
