#!/usr/bin/env bash
# Stop hook: RAG + E2E + requirements + 검증 에이전트 + vault 동기화 (v3.0)
# .claude/settings.json의 Stop hook으로 등록됨
# 문제 발견 시 decision:"block" → Claude가 수정 작업 계속

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# stdin에서 hook 입력 읽기 (stop_hook_active 확인)
INPUT=$(cat 2>/dev/null || true)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")

# 이미 Stop hook에서 재실행 중이면 무한 루프 방지
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

# 최근 변경 파일 확인 (staged + unstaged + last commit)
changed_files=""
changed_files+=$(git diff --name-only HEAD 2>/dev/null || true)
changed_files+=$'\n'
changed_files+=$(git diff --cached --name-only 2>/dev/null || true)
changed_files+=$'\n'
changed_files+=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)

issues=()

# 1. RAG 업데이트 검사
if [[ -d ".claude/memory/rag" ]]; then
  rag_needed=false
  reasons=""
  echo "$changed_files" | grep -qE '^(src/)?app/api/' 2>/dev/null && { rag_needed=true; reasons+="API 변경, "; }
  echo "$changed_files" | grep -qE 'page\.tsx$' 2>/dev/null && { rag_needed=true; reasons+="페이지 변경, "; }
  echo "$changed_files" | grep -qE '^prisma/' 2>/dev/null && { rag_needed=true; reasons+="스키마 변경, "; }

  if [[ "$rag_needed" == true ]]; then
    rag_updated=false
    echo "$changed_files" | grep -qE '^\.claude/memory/rag/' 2>/dev/null && rag_updated=true
    if [[ "$rag_updated" == false ]]; then
      issues+=("RAG 업데이트 필요: ${reasons%, } — .claude/memory/rag/ 파일을 업데이트하세요")
    fi
  fi
fi

# 2. E2E 테스트 품질 검사
e2e_files=$(echo "$changed_files" | grep -E '\.(spec|test)\.(ts|js)$' 2>/dev/null || true)
if [[ -z "$e2e_files" ]]; then
  e2e_files=$(echo "$changed_files" | grep -E '^e2e/' 2>/dev/null || true)
fi
if [[ -n "$e2e_files" ]]; then
  for ef in $e2e_files; do
    [[ ! -f "$ef" ]] && continue
    if grep -E 'request\.(get|post|put|delete|patch)\(' "$ef" 2>/dev/null | grep -vq 'beforeAll\|beforeEach\|seed\|setup' 2>/dev/null; then
      issues+=("E2E에 API shortcut 감지: $ef — request.get/post는 seed에서만 허용")
      break
    fi
    if ! grep -q 'page\.goto\|page\.click\|page\.fill' "$ef" 2>/dev/null; then
      issues+=("E2E에 UI 인터랙션 없음: $ef — page.goto/click/fill 사용 필수")
      break
    fi
  done
fi

# 3. requirements.md 수정 감지
if [[ -f ".flowset/requirements.md" ]]; then
  if echo "$changed_files" | grep -qF '.flowset/requirements.md' 2>/dev/null; then
    issues+=("requirements.md 수정 감지 — 사용자 원본이며 수정 금지. git checkout -- .flowset/requirements.md 실행")
  fi
fi

# 4. 검증 에이전트 트리거 (소스 3파일+ 변경 시)
if [[ -f ".flowset/scripts/verify-requirements.sh" && -f ".flowset/requirements.md" ]]; then
  src_count=$(echo "$changed_files" | grep -cE '\.(ts|tsx|js|jsx|py|go|rs)$' 2>/dev/null || echo "0")
  if [[ "$src_count" -ge 3 ]]; then
    verify_output=$(bash .flowset/scripts/verify-requirements.sh 2>&1 || true)
    verify_exit=$?
    if [[ $verify_exit -eq 2 ]]; then
      issues+=("검증 에이전트: 요구사항 누락 감지 — $verify_output")
    fi
  fi
fi

# 5. v3.0: Vault 세션 맥락 저장 (루프/대화형/팀 범용)
if [[ -f ".flowsetrc" ]]; then
  source .flowsetrc 2>/dev/null || true
  if [[ "${VAULT_ENABLED:-false}" == "true" && -n "${VAULT_API_KEY:-}" ]]; then
    # vault-helpers.sh 로드
    [[ -f ".flowset/scripts/vault-helpers.sh" ]] && source .flowset/scripts/vault-helpers.sh 2>/dev/null || true

    # last_assistant_message에서 작업 요약 추출 (처음 500자)
    last_msg=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")
    summary=""
    if [[ -n "$last_msg" ]]; then
      summary=$(printf '%.500s' "$last_msg" | tr '\n' ' ' | tr '\r' ' ')
    fi

    # 변경 파일 요약
    change_summary=$(echo "$changed_files" | sed '/^$/d' | sort -u | head -20 | tr '\n' ', ')
    change_summary="${change_summary%,}"

    # TEAM_NAME 해소
    local_team=""
    if [[ -f ".flowset/scripts/resolve-team.sh" ]]; then
      source ".flowset/scripts/resolve-team.sh" 2>/dev/null || true
      resolve_team_name "$INPUT" 2>/dev/null
      local_team="${RESOLVED_TEAM_NAME:-}"
    fi

    # 모드 감지
    mode=$(vault_detect_mode 2>/dev/null || echo "interactive")

    # A. 세션 로그 저장 (변경 있을 때만, 일별 통합, 5분 쿨다운)
    _should_log=false
    if [[ -n "$change_summary" && "$change_summary" != "none" ]] || [[ ${#issues[@]} -gt 0 ]]; then
      _cooldown_file="/tmp/.vault_session_cooldown_$$_${VAULT_PROJECT_NAME:-flowset}"
      _now=$(date +%s)
      _last=0
      [[ -f "$_cooldown_file" ]] && _last=$(cat "$_cooldown_file" 2>/dev/null || echo 0)
      if [[ $(( _now - _last )) -ge 300 ]]; then
        _should_log=true
        echo "$_now" > "$_cooldown_file"
      fi
    fi
    if [[ "$_should_log" == "true" ]]; then
      vault_save_daily_session_log "$summary" "${change_summary:-none}" "${#issues[@]}" 2>/dev/null || true
    fi

    # B. state.md 업데이트 (대화형/팀만 — 루프는 flowset.sh가 관리)
    if [[ "$mode" != "loop" ]]; then
      vault_sync_state "idle" "" "" "" "" "$summary" "$local_team" 2>/dev/null || true
    fi

    # C. 팀 state 업데이트 (팀 모드만)
    if [[ -n "$local_team" ]]; then
      vault_sync_team_state "$local_team" "$summary" 2>/dev/null || true
    fi
  fi
fi

# 결과 출력
if [[ ${#issues[@]} -gt 0 ]]; then
  reason=""
  for issue in "${issues[@]}"; do
    reason+="- $issue\n"
  done
  # decision: "block" → Claude가 문제를 수정하도록 계속 작업
  printf '{"decision":"block","reason":"%s"}' "$(echo -e "$reason" | sed 's/"/\\"/g' | tr '\n' ' ')"
  exit 0
fi

exit 0
