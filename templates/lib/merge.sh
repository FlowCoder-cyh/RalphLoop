#!/usr/bin/env bash
set -euo pipefail

# lib/merge.sh — FlowSet 머지 대기 + 병렬 실행 + 동기화 (v4.0 WI-A2d, WI-A2e state 전환)
#
# 목적:
#   PR 머지 완료 대기, 병렬 워커 실행(worktree), regression issue → fix WI 주입,
#   main 동기화, fix_plan 일괄 동기화 등 "머지 + 병렬 + 동기화" 통합 모듈.
#
# flowset.sh에서 source한 후 호출 (state.sh/preflight.sh/worker.sh 다음):
#   source lib/state.sh
#   source lib/preflight.sh
#   source lib/worker.sh
#   source lib/merge.sh
#
# 이관 범위 (설계 §7: wait_for_merge/wait_for_batch_merge/inject_regression_wis +
#   WI-A2c에서 이월된 execute_parallel/setup_worktree + 연속 블록 이관을 위한
#   safe_sync_main/reconcile_fix_plan 포함):
#
#   1. wait_for_merge         — 단일 PR 머지 대기 (순차 모드)
#   2. wait_for_batch_merge   — batch PR 머지 대기 (병렬 모드)
#   3. inject_regression_wis  — open regression issue → fix_plan에 WI-NNN-1-fix 주입
#   4. safe_sync_main         — main 동기화 (fetch + reset --hard, state 파일 보호)
#   5. reconcile_fix_plan     — 루프 종료 시 fix_plan.md 체크박스 일괄 동기화
#   6. setup_worktree         — 병렬 워커용 worktree + 브랜치 생성
#   7. execute_parallel       — 병렬 워커 실행 + PR 생성 + merge queue 등록
#
# 종속 함수 (flowset.sh 본체에 잔존):
#   log(), backup_state_files(), restore_state_files(),
#   recover_completed_from_history(), get_next_n_wis(), count_tasks(),
#   build_rag_context(), mark_wi_done(), record_pattern(), sedi()
#
# 종속 전역변수 (flowset.sh 또는 .flowsetrc에서 설정):
#   SCRIPT_DIR, LOG_DIR, FIX_PLAN, COMPLETED_FILE, WORKTREE_DIR,
#   PARALLEL_COUNT, PROMPT_FILE, MAX_TURNS, ALLOWED_TOOLS
#
# 상호작용 state (lib/state.sh의 RUNTIME_STATE_KEYS 중):
#   call_count, loop_count
#   (WI-A2e에서 state_get/set으로 전수 전환 완료 — WI-A2a 이중 기록 제거 약속 이행.
#    execute_parallel subshell은 cur_loop 지역변수 스냅샷으로 RUNTIME_STATE_FILE
#    공유 안전성 확보 — 절대 경로 기반 state 파일이라 subshell 가시성 보장)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

wait_for_merge() {
  # 단일 PR의 머지 완료를 대기 (순차 모드용)
  # $1: 워커가 작업한 브랜치명
  local branch="${1:-}"

  # 브랜치에서 PR 번호 조회
  local pr_number
  pr_number=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null || true)

  if [[ -z "${pr_number:-}" ]]; then
    # open PR 없음 → 이미 머지됐거나 PR 생성 실패
    pr_number=$(gh pr list --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null || true)
    if [[ -n "${pr_number:-}" ]]; then
      log "✅ PR #$pr_number 이미 머지됨"
      return 0
    fi
    log "⚠️ 브랜치 $branch에 대한 PR 없음"
    return 2
  fi

  log "⏳ PR #$pr_number 머지 대기..."
  bash .flowset/scripts/enqueue-pr.sh "$pr_number" --wait --timeout 15
  local result=$?

  case $result in
    0) log "✅ PR #$pr_number 머지 완료" ;;
    1) log "❌ PR #$pr_number 실패/닫힘 — guardrails 기록"
       echo "### [$(date '+%Y-%m-%d %H:%M')] PR #$pr_number 머지 실패 (Iteration #$(state_get loop_count))" >> .flowset/guardrails.md ;;
    2) log "⚠️ PR #$pr_number timeout — 다음 iteration에서 처리" ;;
  esac
  return $result
}

wait_for_batch_merge() {
  # batch 내 모든 PR의 머지 완료를 대기 (병렬 모드용)
  # $@: PR 번호 목록
  local pr_numbers=("$@")
  local total=${#pr_numbers[@]}

  if [[ $total -eq 0 ]]; then
    return 0
  fi

  log "⏳ batch ${total}개 PR 머지 대기..."

  local merged=0
  local failed=0
  local timeout_sec=$((15 * 60))
  local elapsed=0
  local poll_interval=15

  # 각 PR 상태 추적
  declare -A pr_states
  for pr in "${pr_numbers[@]}"; do
    pr_states[$pr]="pending"
  done

  while [[ $elapsed -lt $timeout_sec ]]; do
    local all_done=true

    for pr in "${pr_numbers[@]}"; do
      [[ "${pr_states[$pr]}" != "pending" ]] && continue
      all_done=false

      local state
      state=$(gh pr view "$pr" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")

      case "$state" in
        MERGED)
          pr_states[$pr]="merged"
          merged=$((merged + 1))
          log "  ✅ PR #$pr 머지됨 ($merged/$total)"
          ;;
        CLOSED)
          pr_states[$pr]="failed"
          failed=$((failed + 1))
          log "  ❌ PR #$pr 실패/닫힘 ($failed failed)"
          echo "### [$(date '+%Y-%m-%d %H:%M')] batch PR #$pr 머지 실패" >> .flowset/guardrails.md
          ;;
      esac
    done

    $all_done && break

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
    printf "\r  ⏳ %dm %02ds / 15m | 머지: %d/%d | 실패: %d  " "$((elapsed/60))" "$((elapsed%60))" "$merged" "$total" "$failed"
  done
  echo ""

  # timeout된 PR 처리
  for pr in "${pr_numbers[@]}"; do
    if [[ "${pr_states[$pr]}" == "pending" ]]; then
      log "  ⚠️ PR #$pr timeout"
    fi
  done

  log "📊 batch 결과: 머지 $merged / 실패 $failed / timeout $((total - merged - failed))"
  return 0
}

inject_regression_wis() {
  # open regression issue → fix_plan에 WI-NNN-1-fix 추가 (원본 WI 바로 아래)
  local issues
  issues=$(gh issue list --label regression --state open --json number,title,body 2>/dev/null || true)
  [[ -z "${issues:-}" || "$issues" == "[]" ]] && return 0

  local injected=0
  local titles
  titles=$(echo "$issues" | sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

  while IFS= read -r title; do
    [[ -z "$title" ]] && continue
    # 이슈 제목에서 WI 번호 추출 (예: "WI-063 e2e 실패: ...")
    local wi_num
    wi_num=$(echo "$title" | grep -oE 'WI-[0-9]+' | head -1)
    [[ -z "$wi_num" ]] && continue

    # 기존 서브넘버 확인 → 다음 번호 결정
    local max_sub=0
    local existing
    existing=$(grep -oE "${wi_num}-[0-9]+-fix" "$FIX_PLAN" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
    if [[ -n "${existing:-}" ]]; then
      max_sub=$existing
    fi
    local next_sub=$((max_sub + 1))
    local fix_wi="${wi_num}-${next_sub}-fix"

    # 이미 fix_plan에 있으면 스킵
    grep -qF "$fix_wi" "$FIX_PLAN" 2>/dev/null && continue

    # 원본 WI 바로 아래에 추가
    local orig_line
    orig_line=$(grep -nE "^\- \[[x ]\] ${wi_num}-(feat|fix|docs|test|chore)" "$FIX_PLAN" 2>/dev/null | tail -1 | cut -d: -f1 || true)
    if [[ -n "${orig_line:-}" ]]; then
      sedi "${orig_line}a\\- [ ] ${fix_wi} ${title}" "$FIX_PLAN"
      injected=$((injected + 1))
    else
      log "⚠️ ${wi_num}: fix_plan에 원본 WI 없음 — fix WI 추가 불가"
    fi
  done <<< "$titles"

  if [[ $injected -gt 0 ]]; then
    log "🔄 regression issue에서 ${injected}건 fix WI 추가"
  fi
}

safe_sync_main() {
  # main 동기화: fetch + reset --hard (로컬 main에 커밋 없으므로 안전)
  # 상태 파일은 untracked이므로 backup/restore로 보호
  backup_state_files
  git fetch origin main 2>/dev/null || true
  git reset --hard origin/main 2>/dev/null || true
  restore_state_files
}

reconcile_fix_plan() {
  # At loop end, sync fix_plan.md checkboxes from completed_wis.txt
  [[ -f "$COMPLETED_FILE" ]] || return 0
  local changed=0
  while IFS= read -r prefix; do
    [[ -z "$prefix" ]] && continue
    local line_num
    line_num=$(grep -nF -- "- [ ] ${prefix}" "$FIX_PLAN" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -n "$line_num" ]]; then
      sedi "${line_num}s/^\- \[ \]/- [x]/" "$FIX_PLAN"
      changed=$((changed + 1))
    fi
  done < "$COMPLETED_FILE"
  if [[ $changed -gt 0 ]]; then
    log "📋 fix_plan.md ${changed}건 동기화"
    local fp_branch="chore/WI-chore-fix-plan-sync-$(date +%H%M%S)"
    if git checkout -b "$fp_branch" 2>/dev/null; then
      git add "$FIX_PLAN"
      git commit -m "WI-chore fix_plan 동기화 (${changed}건 완료)" 2>/dev/null || true
      if git push -u origin "$fp_branch" 2>/dev/null; then
        local fp_pr_url
        fp_pr_url=$(gh pr create --base main --head "$fp_branch" --title "WI-chore fix_plan 동기화 (${changed}건)" --body "FlowSet 종료 시 자동 생성" 2>/dev/null) || true
        if [[ -n "${fp_pr_url:-}" ]]; then
          local fp_pr_number
          fp_pr_number=$(echo "$fp_pr_url" | grep -oE '[0-9]+$')
          bash .flowset/scripts/enqueue-pr.sh "$fp_pr_number" 2>/dev/null || true
          log "📋 fix_plan PR: $fp_pr_url"
        fi
      fi
      git checkout main 2>/dev/null || git checkout main --force 2>/dev/null || true
      git branch -D "$fp_branch" 2>/dev/null || true
    fi
  fi
}

setup_worktree() {
  local wi_name="$1"
  local idx="$2"
  local sanitized
  sanitized=$(echo "$wi_name" | sed 's/[^a-zA-Z0-9_-]/-/g' | cut -c1-40)
  local branch_name="parallel/worker-${idx}-${sanitized}"
  local worktree_path="${WORKTREE_DIR}/worker-${idx}"

  # Clean stale worktree (git 등록 해제 + 디렉토리 삭제)
  if [[ -d "$worktree_path" ]]; then
    git worktree remove "$worktree_path" --force 2>/dev/null || {
      # git 등록은 해제됐지만 빈 디렉토리만 남은 경우
      rmdir "$worktree_path" 2>/dev/null || {
        log "WARN: worktree 디렉토리 제거 실패 — $worktree_path (수동 정리 필요)"
        return 1
      }
    }
  fi
  git branch -D "$branch_name" 2>/dev/null || true

  git worktree add "$worktree_path" -b "$branch_name" HEAD > /dev/null 2>&1 || {
    log "ERROR: worktree 생성 실패 - worker-${idx}"
    return 1
  }

  # Copy gitignored/untracked files needed by claude
  for f in .flowsetrc; do
    [[ -f "$f" ]] && cp "$f" "$worktree_path/$f" 2>/dev/null || true
  done
  mkdir -p "$worktree_path/$LOG_DIR"

  echo "$worktree_path|$branch_name"
}

execute_parallel() {
  local -a wis=()
  local -a pids=()
  local -a worktree_info=()
  local -a worktree_wi=()   # worktree_info와 1:1 매핑되는 WI 이름

  # PR auto-merge 완료 반영 (이전 iteration PR이 머지됐을 수 있음)
  safe_sync_main

  # 워커 실행 전 git log에서 완료 WI 복구
  recover_completed_from_history

  # WI-A2e: state_get 1회 스냅샷 (subshell 내부에서도 동일 값 유효 — RUNTIME_STATE_FILE은 절대 경로)
  local cur_loop
  cur_loop=$(state_get loop_count)

  while IFS= read -r wi; do
    [[ -n "$wi" ]] && wis+=("$wi")
  done < <(get_next_n_wis "$PARALLEL_COUNT")

  local wi_count=${#wis[@]}
  if [[ $wi_count -eq 0 ]]; then
    return 1
  fi

  log "🔀 병렬 실행: ${wi_count}개 WI 동시 처리"

  # Setup worktrees and launch claude in each
  for i in "${!wis[@]}"; do
    local idx=$((i + 1))
    local wi="${wis[$i]}"
    log "  [Worker $idx] $wi"

    local info
    info=$(setup_worktree "$wi" "$idx") || continue
    worktree_info+=("$info")
    worktree_wi+=("$wi")

    local wt_path="${info%%|*}"

    # Build parallel context (RAG 포함)
    local counts completed unchecked total
    counts=$(count_tasks)
    completed="${counts%% *}"
    unchecked="${counts##* }"
    total=$((completed + unchecked))

    local context
    context=$(cat <<'_FLOWSET_CTX_END_'
[PARALLEL MODE] 이미 작업 브랜치에 있음. 별도 브랜치 생성·PR 생성 불필요. 현재 브랜치에서 직접 커밋할 것. fix_plan.md는 절대 수정하지 말 것(외부 루프가 처리).
_FLOWSET_CTX_END_
)
    # RAG 컨텍스트 조립 (워커별 — WI에 맞는 파일 힌트 포함)
    local rag_context
    rag_context=$(build_rag_context "$wi")

    context="[FlowSet #${cur_loop} - Worker $idx/$wi_count] Completed: $completed | Remaining: $unchecked
[TARGET] ${wi}
[RULE] 위 TARGET 작업 1개만 처리하고 FLOWSET_STATUS 출력 후 즉시 종료. 다른 WI 절대 금지.
${context}
${rag_context}"

    local prompt_content
    prompt_content=$(cat "$PROMPT_FILE")
    local logfile="${SCRIPT_DIR}/${LOG_DIR}/claude_parallel_${cur_loop}_${idx}.log"

    # Launch in worktree (background)
    local max_turns_args=()
    if [[ "$MAX_TURNS" -gt 0 ]]; then
      max_turns_args=(--max-turns "$MAX_TURNS")
    fi

    (
      cd "$wt_path" || exit 1
      env -u CLAUDECODE claude -p "$prompt_content" \
        --output-format json \
        --append-system-prompt "$context" \
        --allowedTools "$ALLOWED_TOOLS" \
        "${max_turns_args[@]}" \
        > "$logfile" 2>&1
    ) &
    pids+=($!)
    log "  [Worker $idx] PID ${pids[-1]} 시작"
  done

  if [[ ${#pids[@]} -eq 0 ]]; then
    log "ERROR: 실행된 워커 없음"
    return 1
  fi

  # Wait with progress display
  log "⏳ ${#pids[@]}개 워커 대기 중..."
  local elapsed=0
  local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  while true; do
    local running=0
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && running=$((running + 1))
    done
    [[ $running -eq 0 ]] && break
    local sidx=$((elapsed % 10))
    printf "\r  ${spin[$sidx]} %dm %02ds | 실행 중: %d/%d  " "$((elapsed/60))" "$((elapsed%60))" "$running" "${#pids[@]}"
    sleep 1
    elapsed=$((elapsed + 1))
  done
  printf "\r  ✅ 전체 완료 (%dm %02ds)                                    \n" "$((elapsed/60))" "$((elapsed%60))"

  # Sequential merge back to current branch
  local merged=0 failed=0 skipped=0
  for i in "${!worktree_info[@]}"; do
    local info="${worktree_info[$i]}"
    local wt_path="${info%%|*}"
    local branch="${info##*|}"
    local idx=$((i + 1))

    # Check for new commits vs base
    local wt_sha base_sha
    wt_sha=$(git -C "$wt_path" rev-parse HEAD 2>/dev/null || echo "none")
    base_sha=$(git merge-base HEAD "$branch" 2>/dev/null || echo "none")

    # 워커 로그에서 FLOWSET_STATUS 존재 확인 (--max-turns 도달 시 미출력)
    local worker_log="${SCRIPT_DIR}/${LOG_DIR}/claude_parallel_${cur_loop}_${idx}.log"
    local has_status=false
    if grep -q 'FLOWSET_STATUS\|STATUS:' "$worker_log" 2>/dev/null; then
      has_status=true
    fi

    # 워커 변경 파일 목록 (패턴 기록용)
    local changed_files=""
    if [[ "$wt_sha" != "$base_sha" ]]; then
      changed_files=$(git diff-tree --no-commit-id --name-only -r "$wt_sha" 2>/dev/null | head -5 | tr '\n' ', ')
      changed_files="${changed_files%,}"
    fi

    # 리밋 감지: 워커 로그에서 rate limit / overloaded 키워드 확인
    local is_rate_limited=false
    if grep -qiE 'rate.limit|rate_limit|"status":\s*429|overloaded|too many requests|throttl' "$worker_log" 2>/dev/null; then
      is_rate_limited=true
    fi

    if [[ "$is_rate_limited" == true ]]; then
      log "  [Worker $idx] 🚫 API 리밋 감지 — 5분 쿨다운 후 재시도"
      record_pattern "${worktree_wi[$i]}" "rate_limited" "" "$elapsed" || true
      skipped=$((skipped + 1))
      # 쿨다운: 남은 워커 결과 처리 후 루프에서 대기
      RATE_LIMITED=true
    elif [[ "$wt_sha" == "$base_sha" ]]; then
      # 코드 변경 없음
      if [[ "$has_status" == true ]] && grep -q 'TASKS_COMPLETED_THIS_LOOP: 1' "$worker_log" 2>/dev/null; then
        mark_wi_done "${worktree_wi[$i]}" || true
        log "  [Worker $idx] 이미 구현됨 — completed_wis.txt 기록"
      elif [[ "$has_status" == false ]]; then
        log "  [Worker $idx] ⚠️ 턴 제한 도달 (FLOWSET_STATUS 없음) — 스킵"
        record_pattern "${worktree_wi[$i]}" "timeout" "" "$elapsed" || true
      else
        log "  [Worker $idx] 변경 없음 — 스킵"
        record_pattern "${worktree_wi[$i]}" "skipped" "" "$elapsed" || true
      fi
      skipped=$((skipped + 1))
    elif [[ "$has_status" == false ]]; then
      # 코드 변경은 있지만 FLOWSET_STATUS 없음 → 불완전 가능성
      log "  [Worker $idx] ⚠️ 턴 제한 도달 (불완전 코드) — 머지 건너뜀"
      record_pattern "${worktree_wi[$i]}" "timeout" "$changed_files" "$elapsed" || true
      skipped=$((skipped + 1))
    else
      # PR 플로우: worker 브랜치를 push → PR 생성 → auto-merge 설정
      local wi="${worktree_wi[$i]}"
      local wi_type
      wi_type=$(echo "$wi" | grep -oE '(feat|fix|docs|test|chore|refactor|style|perf)' | head -1)
      wi_type="${wi_type:-feat}"
      local wi_num
      wi_num=$(echo "$wi" | grep -oE 'WI-[0-9]+' | head -1)
      local pr_branch="${wi_type}/${wi_num}-${wi_type}-$(echo "$wi" | sed "s/.*${wi_type} //" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/-$//' | cut -c1-40)"

      log "  [Worker $idx] PR 생성: $pr_branch"

      # 이전 실패로 남은 동명 브랜치 정리 (로컬 + remote)
      git branch -D "$pr_branch" 2>/dev/null || true
      git push origin --delete "$pr_branch" 2>/dev/null || true

      # worker 브랜치를 PR용 브랜치명으로 rename 후 push
      git branch -m "$branch" "$pr_branch" 2>/dev/null || {
        log "  [Worker $idx] ❌ 브랜치 rename 실패"
        failed=$((failed + 1))
        record_pattern "$wi" "conflict" "$changed_files" "$elapsed" || true
        continue
      }

      if git push -u origin "$pr_branch" 2>"$LOG_DIR/push_${idx}.log"; then
        # PR 생성
        local pr_url
        pr_url=$(gh pr create \
          --base main \
          --head "$pr_branch" \
          --title "$wi" \
          --body "FlowSet 자동 생성 PR" \
          2>"$LOG_DIR/pr_${idx}.log") || true

        if [[ -n "$pr_url" ]]; then
          merged=$((merged + 1))
          mark_wi_done "${worktree_wi[$i]}" || true
          log "  [Worker $idx] ✅ PR 생성: $pr_url"
          record_pattern "$wi" "merged" "$changed_files" "$elapsed" || true

          # merge queue에 등록 (CI 통과 시 자동 머지)
          local pr_number
          pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
          bash .flowset/scripts/enqueue-pr.sh "$pr_number" 2>/dev/null || {
            log "  [Worker $idx] ⚠️ merge queue 등록 실패 (수동 머지 필요)"
          }
        else
          failed=$((failed + 1))
          log "  [Worker $idx] ❌ PR 생성 실패"
          log "  [Worker $idx] 원인: $(head -3 "$LOG_DIR/pr_${idx}.log" 2>/dev/null)"
          record_pattern "$wi" "conflict" "$changed_files" "$elapsed" || true
        fi
      else
        failed=$((failed + 1))
        log "  [Worker $idx] ❌ push 실패"
        log "  [Worker $idx] 원인: $(head -3 "$LOG_DIR/push_${idx}.log" 2>/dev/null)"
        record_pattern "$wi" "conflict" "$changed_files" "$elapsed" || true
      fi

    fi

    # Cleanup: worktree 먼저 제거 → 브랜치 삭제 (순서 중요)
    git worktree remove "$wt_path" --force 2>/dev/null || {
      log "WARN: worktree 제거 실패 — $wt_path (수동 정리 필요)"
    }
    # rename 후 브랜치명이 바뀌었을 수 있으므로 둘 다 시도
    [[ -n "${pr_branch:-}" ]] && git branch -D "$pr_branch" 2>/dev/null || true
    git branch -D "$branch" 2>/dev/null || true
  done

  git worktree prune 2>/dev/null || true
  rmdir "$WORKTREE_DIR" 2>/dev/null || true

  log "🔀 병렬 결과: ${merged} PR, ${failed} 실패, ${skipped} 스킵"
  local cur_calls
  cur_calls=$(state_get call_count)
  state_set call_count "$((cur_calls + wi_count))"

  # API 리밋 감지 시 쿨다운
  if [[ "${RATE_LIMITED:-false}" == true ]]; then
    log "🚫 API 리밋 감지 — 5분 대기 후 재개"
    sleep 300
    RATE_LIMITED=false
  fi

  # 전부 실패면 에러
  [[ $failed -eq $wi_count ]] && return 1
  return 0
}
