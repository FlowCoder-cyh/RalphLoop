#!/usr/bin/env bash
set -euo pipefail

# Stop hook: RAG + E2E + requirements + 검증 에이전트 + vault 동기화 (v3.0)
# .claude/settings.json의 Stop hook으로 등록됨
# 문제 발견 시 decision:"block" → Claude가 수정 작업 계속

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# stdin에서 hook 입력 읽기 (stop_hook_active 확인)
INPUT=$(cat 2>/dev/null || true)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null | tr -d '\r' || echo "false")

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

# ============================================================================
# v4.0 (WI-C3-code): 매트릭스 기반 검증 게이트웨이
# ============================================================================
# 설계 §5 :224 + §4 :109-117 (B2/B3/B4 차단) 이행:
# - HAS_MATRIX 플래그로 matrix.json 부재 시 신규 섹션 6/7/8 skip (하위 호환)
# - 기존 섹션 1~5는 가드 없음 → 기존 동작 그대로 유지
# - WI-C5/C6와 동일 SSOT 패턴 (.flowset/spec/matrix.json)
HAS_MATRIX=true
MATRIX_FILE=".flowset/spec/matrix.json"
[[ -f "$MATRIX_FILE" ]] || HAS_MATRIX=false

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

# ============================================================================
# 6. 타입 중복 검사 (B3 — WI-C3-code)
# ============================================================================
# 설계 §4 :115 — 변경 파일에서 interface|type|class {Name} 선언 추출 후
# 같은 이름이 다른 파일 2개 이상에서 선언되면 block. 단 *.test.*/*.spec.*/__tests__/tests/ 경로 제외.
# TypeScript interface merging(동일 module 내 의도적 중복)은 본 검사 범위 외 — 다른 파일이면 다른 모듈 가정.
if [[ "$HAS_MATRIX" == "true" ]]; then
  changed_code_files=$(echo "$changed_files" \
    | grep -E '\.(ts|tsx|js|jsx|py|go|rs)$' \
    | grep -vE '(^|/)(tests?|spec|__tests__|e2e)/' \
    | grep -vE '\.(test|spec)\.(ts|tsx|js|jsx)$' \
    | sort -u \
    || true)

  if [[ -n "$changed_code_files" ]]; then
    declarations=""
    for cf in $changed_code_files; do
      [[ ! -f "$cf" ]] && continue
      file_decls=$(grep -nE '^[[:space:]]*(export[[:space:]]+)?(interface|type|class)[[:space:]]+[A-Z][A-Za-z0-9_]*' "$cf" 2>/dev/null \
        | sed -E 's/^[0-9]+:[[:space:]]*(export[[:space:]]+)?(interface|type|class)[[:space:]]+([A-Z][A-Za-z0-9_]*).*/\3/' \
        | sort -u || true)
      while IFS= read -r decl; do
        [[ -z "$decl" ]] && continue
        declarations+="${decl}	${cf}"$'\n'
      done <<< "$file_decls"
    done

    # 같은 이름이 다른 파일 2개+ 등장하는지 확인 (awk 그룹화)
    duplicates=$(echo "$declarations" | sort -u | awk -F'\t' '
      NF == 2 && $1 != "" {
        names[$1]++
        files[$1] = files[$1] " " $2
      }
      END {
        for (n in names) if (names[n] > 1) print n "\t" files[n]
      }
    ')
    while IFS=$'\t' read -r dup_name dup_files; do
      [[ -z "$dup_name" ]] && continue
      issues+=("타입 중복 감지 (B3): ${dup_name} —${dup_files} (다른 파일 ${dup_files##* /}+ 선언, 단일 SSOT 모듈로 통합 필요)")
    done <<< "$duplicates"
  fi
fi

# ============================================================================
# 7. auth middleware 검사 (B2 — WI-C3-code)
# ============================================================================
# 설계 §4 :114 — src/api/** 또는 src/app/api/** 수정 시 matrix.json.auth_patterns[]에 등록된
# 패턴을 모두 grep, 하나도 매칭 안 되면 block. 정규식 OR 매칭(framework 무관 — | join).
if [[ "$HAS_MATRIX" == "true" ]]; then
  changed_api_files=$(echo "$changed_files" \
    | grep -E '^src/(api|app/api)/.*\.(ts|tsx|js|jsx|py|go|rs)$' \
    | grep -vE '\.(test|spec)\.(ts|tsx|js|jsx)$' \
    | sort -u \
    || true)

  if [[ -n "$changed_api_files" ]]; then
    # tr -d '\r' — Windows jq.exe stdout CRLF 정합 (Linux jq는 LF, tr 무영향)
    auth_patterns=$(jq -r '(.auth_patterns // [])[]' "$MATRIX_FILE" 2>/dev/null | tr -d '\r' || true)
    if [[ -z "$auth_patterns" ]]; then
      issues+=("auth middleware 검증 불가 (B2): matrix.json.auth_patterns[] 비어있음 — /wi:prd Step 2.5에서 auth_framework 등록 필요")
    else
      auth_regex=$(echo "$auth_patterns" | tr '\n' '|' | sed 's/|$//')
      for af in $changed_api_files; do
        [[ ! -f "$af" ]] && continue
        if ! grep -qE "$auth_regex" "$af" 2>/dev/null; then
          issues+=("auth middleware 누락 (B2): $af — auth_patterns 중 어느 것도 매칭 안 됨 (정규식: $auth_regex). 인증 우회 위험")
        fi
      done
    fi
  fi
fi

# ============================================================================
# 8. Gherkin↔테스트 매칭 (B4 — WI-C3-code)
# ============================================================================
# 설계 §4 :116 — parse-gherkin.sh로 total_count 계산 + scenarios[].name 추출 → 대응 테스트 파일의
# test()/it() 블록 수와 비교 + 이름 부분 매칭(정규화 후). 단순 개수 비교 금지 — 이름 매칭도 강제.
# 1순위: cucumber CLI(npm 환경) — 본 hook은 fallback parse-gherkin.sh 우선. 동일 출력 계약.
if [[ "$HAS_MATRIX" == "true" && -f ".flowset/scripts/parse-gherkin.sh" ]]; then
  changed_feature_files=$(echo "$changed_files" \
    | grep -E '\.feature$' \
    | sort -u \
    || true)

  for ff in $changed_feature_files; do
    [[ ! -f "$ff" ]] && continue

    # tr -d '\r' — Windows jq.exe stdout CRLF 정합 (parse-gherkin.sh JSON + jq -r 모두)
    parser_output=$(bash .flowset/scripts/parse-gherkin.sh "$ff" 2>/dev/null | tr -d '\r' || echo '{}')
    gherkin_total=$(echo "$parser_output" | jq -r '.total_count // 0' | tr -d '\r')
    gherkin_names=$(echo "$parser_output" | jq -r '.scenarios[].name // empty' | tr -d '\r')

    # matrix.entities[].gherkin[]에서 본 feature 파일 매칭하는 entity의 tests[] 추출
    test_files=$(jq -r --arg ff "$ff" '
      [.entities // {} | to_entries[] |
       select((.value.gherkin // []) | any(. == $ff)) |
       .value.tests // [] | .[]
      ] | .[]
    ' "$MATRIX_FILE" 2>/dev/null | tr -d '\r' || true)

    [[ -z "$test_files" ]] && continue

    # 각 테스트 파일에서 test()/it() 블록 수 + 이름 추출
    test_count=0
    test_names=""
    for tf in $test_files; do
      [[ ! -f "$tf" ]] && continue
      tf_count=$(grep -cE '(^|[^a-zA-Z_])(test|it)\(' "$tf" 2>/dev/null || echo "0")
      test_count=$((test_count + tf_count))
      tf_names=$(grep -oE '(test|it)\([\"'"'"'][^\"'"'"']+' "$tf" 2>/dev/null \
        | sed -E 's/^(test|it)\([\"'"'"']//' \
        | tr '[:upper:]' '[:lower:]' \
        | tr -s '[:space:]' ' ' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)
      test_names+="$tf_names"$'\n'
    done

    # 개수 비교
    if (( gherkin_total != test_count )); then
      issues+=("Gherkin↔테스트 개수 불일치 (B4): $ff (Gherkin=${gherkin_total}, tests=${test_count}) — 시나리오 수와 테스트 수 일치 필요")
    fi

    # 이름 부분 매칭 — Gherkin scenario 이름이 test 이름의 부분 문자열이어야 함 (정규화 후)
    # gherkin_names를 array로 변환 후 nested for loop — bash here-string 변수 처리 안정성 확보
    gherkin_names_arr=()
    while IFS= read -r _gn; do
      [[ -n "$_gn" ]] && gherkin_names_arr+=("$_gn")
    done <<< "$gherkin_names"

    for gname in "${gherkin_names_arr[@]}"; do
      [[ -z "$gname" ]] && continue
      # printf로 trailing newline 제어 + grep -qF로 fixed-string contains 검사
      if ! printf '%s' "$test_names" | grep -qF -- "$gname"; then
        issues+=("Gherkin 시나리오 미매핑 (B4): \"${gname}\" → 대응 테스트 이름에 미포함 (부분 문자열 매칭 실패)")
      fi
    done
  done
fi

# ============================================================================
# 9. 출처 URL/파일 존재 검증 (B6 — WI-C3-content)
# ============================================================================
# 설계 §4 :141-146 + §5 :224 + §7 :317 — content 경로 변경 시
# matrix.sections[].sources[] 모두 존재 검증.
# - URL(http/https): 외부 호출 금지(Stop hook 성능 가드) → 형식 정적 검증만
# - 파일 경로: [[ -f ]] 존재 검증
# 변경 파일 분류 정규식은 WI-C5와 동일(`^(docs|content|research)/.*\.확장자$`) — SSOT 단일성.
# changed_content_files는 섹션 10에서 재사용 (한 번만 산출).
if [[ "$HAS_MATRIX" == "true" ]]; then
  changed_content_files=$(echo "$changed_files" \
    | grep -E '^(docs|content|research)/.*\.(md|mdx|markdown|txt|rst)$' \
    | sort -u \
    || true)

  if [[ -n "$changed_content_files" ]]; then
    # 학습 31: jq -r 결과에 tr -d '\r' (Windows jq.exe stdout CRLF 정합)
    while IFS=$'\t' read -r section_key source_ref; do
      [[ -z "$section_key" || -z "$source_ref" ]] && continue
      # URL은 형식만 검증 (HTTP 호출 금지)
      if [[ "$source_ref" =~ ^https?:// ]]; then
        if [[ ! "$source_ref" =~ ^https?://[^[:space:]/]+ ]]; then
          issues+=("출처 URL 형식 위반 (B6): section=${section_key} URL=\"${source_ref}\" — http(s)://host 형태 필요")
        fi
        continue
      fi
      # 파일 경로: 존재 검증
      if [[ ! -f "$source_ref" ]]; then
        issues+=("출처 파일 누락 (B6): section=${section_key} sources=\"${source_ref}\" — 매트릭스 등록 파일 미존재")
      fi
    done < <(jq -r '.sections // {} | to_entries[] | .key as $k | (.value.sources // [])[] | [$k, .] | @tsv' "$MATRIX_FILE" 2>/dev/null | tr -d '\r' || true)
  fi
fi

# ============================================================================
# 10. completeness_checklist 본문 등장 검증 (B7 — WI-C3-content)
# ============================================================================
# 설계 §4 :141-146 + §7 :317 — content 경로 변경 시 section의 checklist 항목이
# section의 paths(매트릭스 옵션 필드)와 매칭되는 변경 파일에 등장해야 함.
# - paths 있음: 변경 파일과 paths 교집합만 대상 (false positive 차단 — 평가자 [MEDIUM] 해소)
# - paths 없음(레거시): 모든 변경 content 파일에 union grep (후방 호환)
# - paths 있는데 매칭 변경 파일 없음: 본 section은 변경 안 된 것으로 보고 skip
# 매칭 규칙: 정확 일치 OR 디렉토리 prefix("docs/3.2/" 등록 시 "docs/3.2/sub.md" 매칭)
# fixed-string(grep -F)로 메타문자 안전.
if [[ "$HAS_MATRIX" == "true" ]]; then
  changed_content_files="${changed_content_files:-}"
  if [[ -n "$changed_content_files" ]]; then
    # 학습 31: 모든 jq -r 결과에 tr -d '\r' (Windows jq.exe stdout CRLF 정합)
    section_keys=$(jq -r '.sections // {} | keys[]' "$MATRIX_FILE" 2>/dev/null | tr -d '\r' || true)

    while IFS= read -r section_key; do
      [[ -z "$section_key" ]] && continue

      # 1. 본 section의 paths 추출 (옵션 필드)
      section_paths=$(jq -r --arg k "$section_key" '.sections[$k].paths // [] | .[]' "$MATRIX_FILE" 2>/dev/null | tr -d '\r' || true)

      # 2. paths 매핑으로 검사 대상 파일 결정
      matching_files=""
      if [[ -n "$section_paths" ]]; then
        # paths 있음: 변경 파일과 교집합 (정확 일치 또는 디렉토리 prefix)
        for cf in $changed_content_files; do
          while IFS= read -r p; do
            [[ -z "$p" ]] && continue
            if [[ "$cf" == "$p" || "$cf" == "$p"/* ]]; then
              matching_files+="$cf"$'\n'
              break
            fi
          done <<< "$section_paths"
        done
        matching_files=$(echo "$matching_files" | sed '/^$/d' | sort -u)
        # paths 있는데 매칭 변경 파일 없음 → 본 section 변경 없음 → skip
        [[ -z "$matching_files" ]] && continue
      else
        # paths 없음(레거시): 후방 호환 — 모든 변경 content 파일 union grep
        matching_files="$changed_content_files"
      fi

      # 3. 본 section의 checklist 항목 추출
      section_items=$(jq -r --arg k "$section_key" '.sections[$k].completeness_checklist // [] | .[]' "$MATRIX_FILE" 2>/dev/null | tr -d '\r' || true)

      # 4. 각 item이 matching_files 중 어느 하나에라도 등장하는지 검사
      while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        found=false
        for cf in $matching_files; do
          [[ ! -f "$cf" ]] && continue
          if grep -qF -- "$item" "$cf" 2>/dev/null; then
            found=true
            break
          fi
        done
        if [[ "$found" == "false" ]]; then
          issues+=("completeness_checklist 미등장 (B7): section=${section_key} 항목=\"${item}\" — 매핑된 content 파일 본문에 미등장")
        fi
      done <<< "$section_items"
    done <<< "$section_keys"
  fi
fi

# 5. v3.0: Vault 세션 맥락 저장 (루프/대화형/팀 범용)
if [[ -f ".flowsetrc" ]]; then
  source .flowsetrc 2>/dev/null || true
  if [[ "${VAULT_ENABLED:-false}" == "true" && -n "${VAULT_API_KEY:-}" ]]; then
    # vault-helpers.sh 로드
    [[ -f ".flowset/scripts/vault-helpers.sh" ]] && source .flowset/scripts/vault-helpers.sh 2>/dev/null || true

    # --- transcript 추출 (v3.4 — vault-helpers.sh 함수) ---
    transcript_path=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
    last_msg=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo "")

    vault_extract_transcript "$transcript_path"
    vault_build_transcript_summary "$last_msg"
    summary="$TRANSCRIPT_SUMMARY"

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

    # B. 구조화된 state.md 업데이트 (대화형/팀만 — 루프는 flowset.sh가 관리)
    if [[ "$mode" != "loop" ]]; then
      vault_build_state_content "${VAULT_PROJECT_NAME:-project}" "$mode" "$local_team" "${change_summary}" "$last_msg"
      vault_write "${VAULT_PROJECT_NAME:-project}/state.md" "$TRANSCRIPT_STATE_CONTENT" 2>/dev/null || true
    fi

    # C. 팀 state 업데이트 (팀 모드만)
    if [[ -n "$local_team" ]]; then
      vault_sync_team_state "$local_team" "$summary" 2>/dev/null || true
    fi
  fi
fi

# 결과 출력
if [[ ${#issues[@]} -gt 0 ]]; then
  # decision: "block" → Claude가 문제를 수정하도록 계속 작업
  # 평가자 [MEDIUM] 해소: jq -n으로 JSON escape 일임 (B2 차단 메시지에 포함된 \( 등 backslash 안전 처리)
  # WI-C3-parse line 166-170 동일 패턴 차용 → SSOT 단일성 (WI-C3-content가 동일 패턴 차용 가능)
  reason_text=""
  for issue in "${issues[@]}"; do
    reason_text+="- $issue"$'\n'
  done
  jq -nc --arg reason "$reason_text" '{"decision":"block", reason: $reason}'
  exit 0
fi

exit 0
