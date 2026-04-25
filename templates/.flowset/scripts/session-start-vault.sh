#!/usr/bin/env bash
set -euo pipefail

# session-start-vault.sh — SessionStart hook (v3.0 범용)
# 세션 시작/resume/clear/compact 시 vault 맥락 주입
# 루프/대화형/팀 모드 모두에서 동작
# VAULT_ENABLED=false이면 무동작
#
# v4.0 (WI-C6): 매트릭스 미완 셀 우선 주입 (설계 §5 :226 + §7 :313 + §4 :117 B5)
#   - .flowset/spec/matrix.json에서 status != "done" 셀을 추출하여
#     vault 맥락 가장 앞에 마크다운 섹션으로 prepend
#   - SessionStart + PostCompact(source=compact) 양쪽 모두에서 호출 (B5)
#   - matrix.json 부재 → skip (HAS_MATRIX=false, 하위 호환)
#   - PROJECT_CLASS에 따라 entities(code) / sections(content) / 양쪽(hybrid) 분기
#   - WI-C5 _emit_missing_entities/_emit_missing_sections jq 패턴 차용 (SSOT 단일성)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# stdin에서 hook 입력 읽기
INPUT=$(cat 2>/dev/null || true)
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"' 2>/dev/null || echo "startup")

# .flowsetrc 로드
if [[ -f ".flowsetrc" ]]; then
  source .flowsetrc 2>/dev/null || true
fi

# vault 미활성화 시 종료
if [[ "${VAULT_ENABLED:-false}" != "true" || -z "${VAULT_API_KEY:-}" ]]; then
  exit 0
fi

# vault 연결 확인 (타임아웃 3초)
VAULT_URL="${VAULT_URL:-https://localhost:27124}"
vault_response=$(curl -s -k --max-time 3 \
  "${VAULT_URL}/vault/" \
  -H "Authorization: Bearer ${VAULT_API_KEY}" 2>/dev/null)

if [[ -z "$vault_response" ]]; then
  exit 0
fi

# 인라인 vault 헬퍼 (vault-helpers.sh와 독립 — hook은 독립 프로세스)
_vread() {
  curl -s -k --max-time 3 \
    "${VAULT_URL}/vault/${1}" \
    -H "Authorization: Bearer ${VAULT_API_KEY}" 2>/dev/null
}
_vsearch() {
  local encoded
  encoded=$(printf '%s' "$1" | jq -sRr @uri 2>/dev/null || printf '%s' "$1" | sed 's/ /%20/g')
  curl -s -k --max-time 3 \
    "${VAULT_URL}/search/simple/?query=${encoded}" \
    -H "Authorization: Bearer ${VAULT_API_KEY}" \
    -X POST 2>/dev/null
}

context=""

# ============================================================================
# v4.0 (WI-C6): 매트릭스 미완 셀 우선 주입
# ============================================================================
# 설계 §5 :226 + §7 :313 + §4 :117 B5 이행:
# - HAS_MATRIX 플래그로 matrix.json 부재 시 skip (하위 호환)
# - PROJECT_CLASS에 따라 entities(code) / sections(content) / 양쪽(hybrid) 분기
# - status != "done" 셀을 vault 맥락 가장 앞에 마크다운 섹션으로 prepend
# - SessionStart + PostCompact(source=compact) 모두 호출 (이 스크립트가 양쪽 hook의 진입점)
# - jq/matrix 손상으로 함수 실패 시 stderr 경고 + skip (SessionStart 자체는 차단 금지)
#   ※ verify-requirements.sh의 if/else 차단 패턴(WI-C5 학습 27)과 다른 컨텍스트 —
#     SessionStart는 컨텍스트 주입용이므로 비정상 시 hook 자체 차단 시 사용자 진입 불가.

HAS_MATRIX=true
MATRIX_FILE=".flowset/spec/matrix.json"
[[ -f "$MATRIX_FILE" ]] || HAS_MATRIX=false

# PROJECT_CLASS는 위 .flowsetrc source 단계에서 이미 로드됨 (없으면 code 기본값)
PROJECT_CLASS="${PROJECT_CLASS:-code}"

# WI-C5와 동일 jq 추출 패턴 (SSOT 단일성: select(.value != "done") | .key)
_emit_missing_entities() {
  local matrix="$1"
  local entity missing_cells
  while IFS=$'\t' read -r entity missing_cells; do
    [[ -z "$entity" ]] && continue
    [[ -z "$missing_cells" ]] && continue
    echo "- entity=$entity 미완 셀 [$missing_cells]"
  done < <(jq -r '
    .entities | to_entries[] |
    [.key,
     ([.value.status | to_entries[] | select(.value != "done") | .key] | join(","))
    ] | @tsv
  ' "$matrix" 2>/dev/null | grep -vE '	$' || true)
}

_emit_missing_sections() {
  local matrix="$1"
  local section missing_cells
  while IFS=$'\t' read -r section missing_cells; do
    [[ -z "$section" ]] && continue
    [[ -z "$missing_cells" ]] && continue
    echo "- section=$section 미완 셀 [$missing_cells]"
  done < <(jq -r '
    .sections | to_entries[] |
    [.key,
     ([.value.status | to_entries[] | select(.value != "done") | .key] | join(","))
    ] | @tsv
  ' "$matrix" 2>/dev/null | grep -vE '	$' || true)
}

emit_missing_cells() {
  [[ "$HAS_MATRIX" == "true" ]] || return 0
  local matrix="$MATRIX_FILE"
  local class
  class=$(jq -r '.class // "code"' "$matrix" 2>/dev/null || echo "code")

  case "$class" in
    code)
      _emit_missing_entities "$matrix"
      ;;
    content)
      _emit_missing_sections "$matrix"
      ;;
    hybrid)
      _emit_missing_entities "$matrix"
      _emit_missing_sections "$matrix"
      ;;
    *)
      # 비정상 class — hook은 silent skip + stderr 경고 (verify-requirements와 다른 컨텍스트)
      echo "WARN: session-start-vault: 알 수 없는 PROJECT_CLASS in matrix.json: $class (skip)" >&2
      return 0
      ;;
  esac
  return 0
}

missing_cells_output=$(emit_missing_cells 2>/dev/null || true)
if [[ -n "$missing_cells_output" ]]; then
  context+="[VAULT MATRIX MISSING — 미완 매트릭스 셀 우선 주입 (source: ${SOURCE})]
## 🚨 미완 매트릭스 셀 (자동 주입)

다음 셀은 \`.flowset/spec/matrix.json\`에서 status != \"done\" 상태입니다.
컨텍스트 압축 후에도 우선 복원되어 \"지금 뭘 만들어야 하는지\"를 즉시 인지하기 위함입니다.

${missing_cells_output}

"
fi

# --- 1. state.md 읽기 (범용 포맷) ---
if [[ -n "${VAULT_PROJECT_NAME:-}" ]]; then
  state_content=$(_vread "${VAULT_PROJECT_NAME}/state.md")
  if [[ -n "$state_content" && "$state_content" != *'"errorCode"'* ]]; then
    context+="[VAULT STATE — 프로젝트 현재 상태 (source: ${SOURCE})]
${state_content}
"
  fi
fi

# --- 2. 최근 세션 로그 1건 읽기 ---
if [[ -n "${VAULT_PROJECT_NAME:-}" ]]; then
  session_results=$(_vsearch "${VAULT_PROJECT_NAME} session")
  if [[ -n "$session_results" && "$session_results" != "[]" ]]; then
    latest_file=$(echo "$session_results" | jq -r '[.[] | select(.filename | test("sessions/"))] | .[0].filename // empty' 2>/dev/null)
    if [[ -n "$latest_file" ]]; then
      session_content=$(_vread "$latest_file" | head -30)
      if [[ -n "$session_content" && "$session_content" != *'"errorCode"'* ]]; then
        context+="
[VAULT LAST SESSION — 이전 세션 작업 내역]
${session_content}
"
      fi
    fi
  fi
fi

# --- 3. 팀 모드: 팀별 state 로드 ---
team_name=""
if [[ -n "${TEAM_NAME:-}" ]]; then
  team_name="$TEAM_NAME"
elif [[ -f ".flowset/scripts/resolve-team.sh" ]]; then
  source ".flowset/scripts/resolve-team.sh" 2>/dev/null || true
  resolve_team_name "$INPUT" 2>/dev/null
  team_name="${RESOLVED_TEAM_NAME:-}"
fi

if [[ -n "$team_name" && -n "${VAULT_PROJECT_NAME:-}" ]]; then
  team_content=$(_vread "${VAULT_PROJECT_NAME}/teams/${team_name}.md")
  if [[ -n "$team_content" && "$team_content" != *'"errorCode"'* ]]; then
    context+="
[VAULT TEAM STATE — ${team_name} 팀 상태]
${team_content}
"
  fi
fi

# --- 4. compact/resume 시 추가 맥락 (알려진 이슈) ---
if [[ "$SOURCE" == "compact" || "$SOURCE" == "resume" ]]; then
  if [[ -n "${VAULT_PROJECT_NAME:-}" ]]; then
    recent_issues=$(_vsearch "${VAULT_PROJECT_NAME} issue")
    if [[ -n "$recent_issues" && "$recent_issues" != "[]" ]]; then
      issue_files=$(echo "$recent_issues" | jq -r '.[0:2] | .[].filename' 2>/dev/null)
      if [[ -n "$issue_files" ]]; then
        context+="
[VAULT ISSUES — 알려진 이슈]"
        while IFS= read -r vf; do
          [[ -z "$vf" ]] && continue
          vc=$(_vread "$vf" | head -20)
          [[ -n "$vc" && "$vc" != *'"errorCode"'* ]] && context+="
--- ${vf} ---
${vc}"
        done <<< "$issue_files"
      fi
    fi
  fi
fi

# 컨텍스트가 비어있으면 종료
if [[ -z "$context" ]]; then
  exit 0
fi

# cch attestation 문자열 sanitize (캐시 무효화 방지)
context=$(echo "$context" | sed 's/cch=[a-f0-9]\{4,\}/cch=REDACTED/g')

# additionalContext로 반환
jq -n --arg ctx "$context" '{"additionalContext": $ctx}'
