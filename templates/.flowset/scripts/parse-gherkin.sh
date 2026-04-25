#!/usr/bin/env bash
set -euo pipefail

# parse-gherkin.sh — bash 기반 Gherkin 간이 파서 (cucumber CLI fallback)
#
# 설계 §4 :183-205 + §5 :229 (B4 차단 메커니즘 prerequisite):
#   - 1순위: @cucumber/gherkin CLI (npm 설치 환경)
#   - fallback (본 스크립트): 모든 환경 동작, 동일 JSON 출력 계약
#   - 후속 WI-C3-code의 stop-rag-check.sh가 본 스크립트를 호출하여
#     Gherkin total_count를 테스트 파일의 test()/it() 블록 수와 비교 (B4 차단)
#
# 사용:
#   bash parse-gherkin.sh <feature_file>
#
# 출력 계약 (stdout, JSON):
#   {
#     "feature_file": "<인자 그대로>",
#     "scenarios": [
#       {"name": "<정규화된 이름>", "type": "Scenario|Scenario Outline", "examples_rows": <int>}
#     ],
#     "total_count": <int>  // Scenario 개수 + Scenario Outline마다 examples_rows 합산
#   }
#
# 정규화 규칙 (§4 :199-203, ASCII 공백만 처리, NBSP 등 Unicode 공백은 처리 범위 외):
#   1. 소문자 변환 (awk tolower — ASCII만)
#   2. 연속 공백([ \t])을 단일 공백으로 squeeze
#   3. 선행/후행 공백 제거
#
# Examples 헤더 skip (§4 :196):
#   - Examples: 키워드 직후 첫 `|` 행은 헤더 → skip
#   - 이후 `|` 시작 행만 데이터로 카운트
#   - 여러 Examples 블록 연속 시 각 블록마다 헤더 reset

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

feature_file="${1:-}"

if [[ -z "$feature_file" ]]; then
  echo "ERROR: feature_file 인자 필수 — usage: parse-gherkin.sh <feature_file>" >&2
  exit 1
fi

if [[ ! -f "$feature_file" ]]; then
  echo "ERROR: feature 파일 없음: $feature_file" >&2
  exit 1
fi

# awk로 raw 필드(type / examples_rows / name)를 TSV 출력 → bash + jq로 안전한 JSON 조립
# (awk 직접 JSON 출력 시 name 안의 따옴표/백슬래시 escape 누락 위험 — jq로 일임)
SCENARIOS_TSV=$(awk '
  BEGIN {
    in_examples = 0
    examples_seen_header = 0
    in_doc_string = 0
    current_name = ""
    current_type = ""
    current_examples = 0
  }

  # 1차 평가 [MEDIUM] 해소: Doc String("""/```) 토글 + 안에서 모든 키워드 무시
  # cucumber Gherkin 표준: """ 또는 ``` 안 코드는 step body — Scenario:/Examples:/| 키워드를
  # 의도적으로 포함할 수 있음 (예: API 문서화). false positive 방지 차원에서 무시 필수.
  # 본 토글은 다른 모든 패턴보다 우선 검사 (priority 1).
  /^[[:space:]]*("""|```)/ {
    in_doc_string = !in_doc_string
    next
  }
  in_doc_string { next }

  # 주석 (Gherkin: # 시작 라인)
  /^[[:space:]]*#/ { next }

  # Scenario Outline / Template (cucumber v6+ 별칭) — Scenario:보다 먼저 검사 (둘 다 "Scenario"로 시작)
  # 1차 평가 [MEDIUM] 해소: Scenario Template 별칭 인식 (cucumber 출력 계약 호환)
  /^[[:space:]]*Scenario[[:space:]]+(Outline|Template):/ {
    flush()
    raw = $0
    sub(/^[[:space:]]*Scenario[[:space:]]+Outline:[[:space:]]*/, "", raw)
    sub(/^[[:space:]]*Scenario[[:space:]]+Template:[[:space:]]*/, "", raw)
    current_name = normalize(raw)
    current_type = "Scenario Outline"
    in_examples = 0
    examples_seen_header = 0
    next
  }

  # Scenario / Example (cucumber v6+ Example: 단수 별칭)
  # 1차 평가 [LOW] 해소: Example: 별칭 인식 (정규식 1줄 확장으로 즉시 해소 가능)
  /^[[:space:]]*(Scenario|Example):/ {
    flush()
    raw = $0
    sub(/^[[:space:]]*Scenario:[[:space:]]*/, "", raw)
    sub(/^[[:space:]]*Example:[[:space:]]*/, "", raw)
    current_name = normalize(raw)
    current_type = "Scenario"
    in_examples = 0
    examples_seen_header = 0
    next
  }

  # Examples: 블록 진입 (Scenario Outline 내부에서만 의미 있음)
  # Gherkin 문법상 Examples: 뒤 description 허용 (예: `Examples: edge cases`)
  # 따라서 `$` anchor 제거 — 키워드 prefix만 매칭
  /^[[:space:]]*Examples:/ {
    in_examples = 1
    examples_seen_header = 0
    next
  }

  # Examples 블록 안에서 | 시작 행
  in_examples && /^[[:space:]]*\|/ {
    if (examples_seen_header == 0) {
      # Examples: 직후 첫 | 행은 헤더 — skip (§4 :196)
      examples_seen_header = 1
    } else {
      current_examples++
    }
    next
  }

  # Examples 블록 안 빈 줄 — 블록 유지 (헤더 상태 reset 안 함)
  in_examples && /^[[:space:]]*$/ { next }

  # Examples 블록 안에서 | 도 빈 줄도 comment도 아닌 다른 라인 → 블록 종료
  in_examples {
    in_examples = 0
    examples_seen_header = 0
  }

  END { flush() }

  # 현재 누적된 시나리오를 TSV 한 줄로 출력 + 상태 reset
  function flush() {
    if (current_name != "") {
      printf "%s\t%d\t%s\n", current_type, current_examples, current_name
      current_name = ""
      current_type = ""
      current_examples = 0
    }
  }

  # 정규화 (§4 :199-203 ASCII 공백만 처리)
  function normalize(s) {
    s = tolower(s)
    gsub(/[ \t\r]+/, " ", s)
    sub(/^[ \t\r]+/, "", s)
    sub(/[ \t\r]+$/, "", s)
    return s
  }
' "$feature_file")

# bash + jq로 안전한 JSON 조립 (name escape 책임은 jq에 일임)
scenarios_json="[]"
total=0
type_field=""
examples_field=0
name_field=""

if [[ -n "$SCENARIOS_TSV" ]]; then
  while IFS=$'\t' read -r type_field examples_field name_field; do
    [[ -z "$name_field" ]] && continue
    scenarios_json=$(jq -c \
      --arg name "$name_field" \
      --arg type "$type_field" \
      --argjson examples "$examples_field" \
      '. + [{name: $name, type: $type, examples_rows: $examples}]' \
      <<< "$scenarios_json")

    if [[ "$type_field" == "Scenario" ]]; then
      total=$((total + 1))
    else
      # Scenario Outline → examples_rows만큼 시나리오 인스턴스 (§4 :195)
      total=$((total + examples_field))
    fi
  done <<< "$SCENARIOS_TSV"
fi

jq -n \
  --arg feature_file "$feature_file" \
  --argjson scenarios "$scenarios_json" \
  --argjson total "$total" \
  '{feature_file: $feature_file, scenarios: $scenarios, total_count: $total}'
