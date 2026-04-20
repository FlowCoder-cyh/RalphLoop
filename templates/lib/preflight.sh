#!/usr/bin/env bash
set -euo pipefail

# lib/preflight.sh — FlowSet 사전 검증 (v4.0 WI-A2b)
#
# 목적:
#   flowset.sh 시작 시 필수 CLI/파일/hook/vault 연결 상태 검증.
#   main() 진입 전 실패 조건을 발견하여 즉시 중단 (fail-fast).
#
# flowset.sh에서 source한 후 호출 (lib/state.sh 다음):
#   source lib/state.sh
#   source lib/preflight.sh
#   ...
#   main() { preflight || exit 1; ... }
#
# 종속 함수 (flowset.sh 본체에 정의):
#   log()                    — 로그 출력 (:415)
#   get_all_unchecked_wis()  — fix_plan WI 카운트 (:764)
#
# 종속 함수 (vault-helpers.sh에 정의, 조건부 source):
#   vault_check, vault_init_project, vault_check_tech_debt
#
# 종속 전역변수 (flowset.sh에서 설정):
#   LOG_DIR, PROMPT_FILE, FIX_PLAN, PARALLEL_COUNT, VAULT_ENABLED, VAULT_URL

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

preflight() {
  local errors=0

  # claude CLI 확인
  if ! command -v claude &> /dev/null; then
    echo "ERROR: claude CLI가 설치되어 있지 않습니다."
    errors=$((errors + 1))
  fi

  # gh CLI 확인
  if ! command -v gh &> /dev/null; then
    echo "ERROR: gh CLI가 설치되어 있지 않습니다."
    errors=$((errors + 1))
  elif ! gh auth status &> /dev/null; then
    echo "ERROR: gh CLI가 인증되지 않았습니다. 'gh auth login'을 실행하세요."
    errors=$((errors + 1))
  fi

  # git 확인
  if ! git rev-parse --git-dir &> /dev/null; then
    echo "ERROR: git 저장소가 아닙니다."
    errors=$((errors + 1))
  fi

  # jq 확인 (v4.0부터 필수 — execute_claude()의 JSON 응답 파싱에 사용)
  if ! command -v jq &> /dev/null; then
    echo "ERROR: jq가 설치되어 있지 않습니다. v4.0부터 필수 의존성입니다."
    echo "  Windows: winget install jqlang.jq"
    echo "  macOS:   brew install jq"
    echo "  Linux:   apt install jq  (또는 yum install jq)"
    errors=$((errors + 1))
  fi

  # 필수 파일 확인
  local files=("$PROMPT_FILE" "$FIX_PLAN" ".flowset/AGENT.md" ".flowsetrc" ".flowset/guardrails.md")
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "ERROR: 필수 파일 없음: $f"
      errors=$((errors + 1))
    fi
  done

  # Git hooks 설치 확인 (clone 후 미설치 대응)
  if [[ -d ".flowset/hooks" ]]; then
    for hook in .flowset/hooks/*; do
      [[ -f "$hook" ]] || continue
      local hook_name
      hook_name=$(basename "$hook")
      if [[ ! -f ".git/hooks/$hook_name" ]]; then
        echo "⚠️  Git hook 미설치 감지: $hook_name → 자동 설치"
        cp "$hook" ".git/hooks/$hook_name"
        chmod +x ".git/hooks/$hook_name"
      fi
    done
  fi

  # fix_plan에 실제 WI가 있는지 확인 (빈 상태 방지)
  # completed_wis.txt 반영: fix_plan [ ] 중 로컬 완료 항목 제외
  local unchecked
  unchecked=$(get_all_unchecked_wis 2>/dev/null | wc -l)
  if [[ "$unchecked" == "0" ]]; then
    local total_wis
    total_wis=$(grep -c '^\- \[' "$FIX_PLAN" 2>/dev/null || echo "0")
    if [[ "$total_wis" == "0" ]]; then
      echo "ERROR: fix_plan.md에 WI가 없습니다. /wi:start로 WI를 생성하세요."
      errors=$((errors + 1))
    else
      echo "✅ 모든 WI가 완료되었습니다."
      return 0
    fi
  fi

  # 병렬 모드: uncommitted changes 감지 (자동 커밋하지 않음 — v2.0.0)
  if [[ ${PARALLEL_COUNT:-1} -gt 1 ]]; then
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      echo "ERROR: uncommitted changes가 있습니다. 병렬 모드 시작 전 커밋하세요."
      echo "  git status 로 변경사항을 확인하세요."
      errors=$((errors + 1))
    fi
  fi

  # 병렬 모드: stale worktree/branch 자동 정리
  if [[ ${PARALLEL_COUNT:-1} -gt 1 ]]; then
    local stale_wt
    # Windows 경로 정규화: pwd는 /c/... 반환, git worktree list는 C:/... 반환
    local main_wt
    main_wt=$(cd "$(pwd)" && pwd -W 2>/dev/null || pwd)
    stale_wt=$(git worktree list --porcelain 2>/dev/null | grep "^worktree " | sed 's/^worktree //' | grep -v "^${main_wt}$" | grep -v "^$(pwd)$")
    if [[ -n "$stale_wt" ]]; then
      echo "🧹 stale worktree 정리 중..."
      while IFS= read -r wt; do
        git worktree remove "$wt" --force 2>/dev/null || {
          log "WARN: stale worktree 제거 실패 — $wt (수동 정리 필요)"
        }
      done <<< "$stale_wt"
      git worktree prune 2>/dev/null || true
    fi
    local stale_br
    stale_br=$(git branch --list 'parallel/*' 2>/dev/null)
    if [[ -n "$stale_br" ]]; then
      echo "🧹 stale parallel 브랜치 정리 중..."
      while IFS= read -r b; do
        b=$(echo "$b" | tr -d ' *')
        [[ -n "$b" ]] && git branch -D "$b" 2>/dev/null || true
      done <<< "$stale_br"
    fi
  fi

  # v3.0: Obsidian vault 연결 확인 (실패해도 비차단 — graceful degradation)
  if [[ "${VAULT_ENABLED:-false}" == "true" ]]; then
    if vault_check; then
      log "Obsidian vault 연결 확인 (${VAULT_URL})"
      vault_init_project
    else
      log "Obsidian vault 연결 실패 — 파일 기반 RAG만 사용"
    fi
  fi

  # v3.0: 기술부채 임계치 경고 (비차단)
  local debt_warning
  debt_warning=$(vault_check_tech_debt 10 2>/dev/null)
  if [[ -n "$debt_warning" ]]; then
    log "WARN: $debt_warning"
  fi

  if [[ $errors -gt 0 ]]; then
    echo ""
    echo "$errors개 오류. FlowSet을 시작할 수 없습니다."
    return 1
  fi
  return 0
}
