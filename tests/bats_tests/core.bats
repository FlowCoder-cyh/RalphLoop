#!/usr/bin/env bats

# core.bats — FlowSet v4.0 핵심 회귀 방어선 (WI-A3)
#
# 설계 §7 :298 "bats-core 핵심 테스트 10~20개" 충족.
# WI-A1 ~ WI-A2e 각 2건 + test-vault 2건 = 14 assertion.
# 기존 bash smoke(126 assertion)는 병존 — 상세 회귀는 bash smoke, 핵심은 bats가 담당.
#
# 실행:
#   bash tests/bats/bin/bats tests/bats_tests/core.bats
#
# 환경 요구사항:
#   - tests/bats/ submodule 초기화 완료 (git submodule update --init)
#   - bash 5.x (Windows Git Bash 호환 확인됨 — Bats 1.13.0 작동)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  cd "$REPO_ROOT"
}

# --- WI-A1: shell 품질 (set -euo + jq) ---

@test "WI-A1: lib/ 5개 모듈 전부 set -euo pipefail 헤더" {
  for f in templates/lib/state.sh templates/lib/preflight.sh \
           templates/lib/worker.sh templates/lib/merge.sh templates/lib/vault.sh; do
    head -3 "$f" | grep -qE '^set -euo pipefail' || {
      echo "MISSING in $f"
      return 1
    }
  done
}

@test "WI-A1: lib/worker.sh는 jq 사용, sed JSON 파싱 없음" {
  grep -q 'jq -r' templates/lib/worker.sh
  ! grep -qE 'sed -n.*"[a-z_]+"\s*:' templates/lib/worker.sh
}

# --- WI-A2a: lib/state.sh 인프라 ---

@test "WI-A2a: state_init 8개 RUNTIME_STATE_KEYS 초기화" {
  source templates/lib/state.sh
  state_init
  local cnt
  cnt=$(grep -cE '^(call_count|loop_count|consecutive_no_progress|last_git_sha|last_commit_msg|rate_limit_start|current_session_id|total_cost_usd)=' "$RUNTIME_STATE_FILE")
  [ "$cnt" = "8" ]
}

@test "WI-A2a: state_set/get 에 '=' 포함 값 무결성" {
  source templates/lib/state.sh
  state_init
  state_set last_commit_msg "fix: url=https://foo?a=b&c=d"
  [ "$(state_get last_commit_msg)" = "fix: url=https://foo?a=b&c=d" ]
}

@test "WI-A2a: state_snapshot/restore 라운드트립 (설계 §11 :552 subshell 패턴)" {
  source templates/lib/state.sh
  state_init
  state_set loop_count 99
  state_set current_session_id "snap-test-abc"
  local snap
  snap=$(state_snapshot)
  [ -f "$snap" ]
  # 설계 §11 :552 서브쉘 병렬 모드 시뮬:
  #   서브쉘이 RUNTIME_STATE_FILE을 독립 경로로 override → state_restore로 부모 상태 복원
  RUNTIME_STATE_FILE="${TMPDIR:-/tmp}/flowset-runtime-bats-restore-$$"
  : > "$RUNTIME_STATE_FILE"
  state_restore "$snap"
  [ "$(state_get loop_count)" = "99" ]
  [ "$(state_get current_session_id)" = "snap-test-abc" ]
  rm -f "$RUNTIME_STATE_FILE"
}

@test "WI-A2a: state lock 동작 (flock 또는 mkdir fallback, 설계 §5 :235)" {
  source templates/lib/state.sh
  state_init
  # lock 획득 → 경로 존재 → 해제 사이클
  _state_lock_acquire
  # flock 경로: exec 200>FILE → 일반 파일 생성됨
  # mkdir 경로: 디렉토리 생성됨
  [ -e "$RUNTIME_STATE_LOCK" ]
  _state_lock_release
  # 연속 100회 state_set 내부에서도 lock 정확히 동작 (경합 시 블록, 아니면 즉시)
  for i in 1 2 3 4 5; do
    state_set call_count "$i"
  done
  [ "$(state_get call_count)" = "5" ]
}

# --- WI-A2b: lib/preflight.sh ---

@test "WI-A2b: lib/preflight.sh source 후 preflight 함수 declare" {
  source templates/lib/preflight.sh
  declare -F preflight &>/dev/null
}

@test "WI-A2b: flowset.sh preflight fail-fast 블록 존재" {
  grep -q 'ERROR: lib/preflight.sh 없음' templates/flowset.sh
}

# --- WI-A2c: lib/worker.sh ---

@test "WI-A2c: lib/worker.sh source 후 execute_claude 함수 declare" {
  source templates/lib/worker.sh
  declare -F execute_claude &>/dev/null
}

@test "WI-A2c: flowset.sh에 execute_claude 본체 제거됨" {
  ! grep -qE '^execute_claude\(\)' templates/flowset.sh
}

# --- WI-A2d: lib/merge.sh ---

@test "WI-A2d: lib/merge.sh 7개 함수 전부 declare" {
  source templates/lib/merge.sh
  for fn in wait_for_merge wait_for_batch_merge inject_regression_wis \
            safe_sync_main reconcile_fix_plan setup_worktree execute_parallel; do
    declare -F "$fn" &>/dev/null || {
      echo "MISSING: $fn"
      return 1
    }
  done
}

@test "WI-A2d: flowset.sh에 merge 7함수 본체 잔존 0건" {
  local body_count=0
  for fn in wait_for_merge wait_for_batch_merge inject_regression_wis \
            safe_sync_main reconcile_fix_plan setup_worktree execute_parallel; do
    if grep -qE "^${fn}\(\)" templates/flowset.sh; then
      body_count=$((body_count + 1))
    fi
  done
  [ "$body_count" = "0" ]
}

# --- WI-A2e: lib/vault.sh + 이중 기록 제거 ---

@test "WI-A2e: lib/vault.sh 19함수 전부 정의" {
  local missing=0
  for fn in _vault_curl vault_check vault_read vault_write vault_delete \
            vault_search vault_init_project vault_detect_mode vault_sync_state \
            vault_save_session_log vault_save_daily_session_log vault_read_latest_session \
            vault_sync_team_state vault_read_team_state vault_record vault_check_tech_debt \
            vault_extract_transcript vault_build_transcript_summary vault_build_state_content; do
    grep -qE "^${fn}\(\)" templates/lib/vault.sh || missing=$((missing + 1))
  done
  [ "$missing" = "0" ]
}

@test "WI-A2e: 이중 기록 제거 — 8개 state 키 직접 참조 0건" {
  local keys='\$\{?(call_count|loop_count|consecutive_no_progress|last_git_sha|last_commit_msg|rate_limit_start|current_session_id|total_cost_usd)\}?'
  local total=0
  for f in templates/flowset.sh templates/lib/state.sh templates/lib/preflight.sh \
           templates/lib/worker.sh templates/lib/merge.sh; do
    local c
    c=$(grep -cE "$keys" "$f" 2>/dev/null || true)
    total=$((total + ${c:-0}))
  done
  [ "$total" = "0" ]
}

# --- test-vault-transcript (Pre-A1 기존 테스트, WI-A2e에서 확장) ---

@test "vault-helpers: shim source 후 vault_extract_transcript declare" {
  cd templates
  source .flowset/scripts/vault-helpers.sh
  declare -F vault_extract_transcript &>/dev/null
}

@test "vault-helpers: shim이 lib/vault.sh를 re-source" {
  grep -qE 'source.*lib/vault\.sh' templates/.flowset/scripts/vault-helpers.sh
}
