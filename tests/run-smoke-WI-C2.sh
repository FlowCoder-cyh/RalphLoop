#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-C2.sh — WI-C2 (sprint-template.md CRUD/Section 매트릭스 + Gherkin 강제) 전용 smoke
# 설계 §5 :218 + §7 :311 + §4 :109-117 + §4 :116/183-204 (Gherkin) Group γ 후속 이행:
#   1. 메타 PROJECT_CLASS 필드 (code/content/hybrid)
#   2. matrix.json (WI-C1 SSOT) 참조 명시
#   3. 수용 기준 Gherkin 강제 (자유 텍스트 금지)
#   4. CRUD 매트릭스 (code/hybrid) — entity × C/R/U/D × Role permission
#   5. Section 매트릭스 (content/hybrid) — section × draft/review/approve × Role
#   6. type 4종 (code | content | hybrid | visual)
#   7. SSOT 단일성 (rubric 가중치 review-rubric.md만 — matrix 직렬화 거부)
# 사용: bash tests/run-smoke-WI-C2.sh
#
# 누적 기준선 SSOT: `.github/workflows/flowset-ci.yml` smoke job name 참조

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

SPRINT_MD="templates/.flowset/contracts/sprint-template.md"
MATRIX_JSON="templates/.flowset/spec/matrix.json"

# ============================================================================
echo "=== WI-C2-1: 메타 PROJECT_CLASS + matrix.json 참조 ==="
# 1. 메타 섹션 헤더 + WI-C2 표지
if grep -qE '^## 메타 \(WI-C2, v4\.0\)' "$SPRINT_MD"; then
  pass "메타 섹션 헤더 (WI-C2, v4.0 표지)"
else
  fail "메타 섹션 헤더 누락"
fi

# 2. PROJECT_CLASS 3종 명시
if grep -qE 'PROJECT_CLASS.*`code`.*`content`.*`hybrid`' "$SPRINT_MD"; then
  pass "PROJECT_CLASS 3종 명시 (code | content | hybrid)"
else
  fail "PROJECT_CLASS 3종 표기 누락"
fi

# 3. matrix.json 참조 (.flowset/spec/matrix.json)
if grep -qE '\.flowset/spec/matrix\.json' "$SPRINT_MD"; then
  pass "matrix.json 경로 명시 (.flowset/spec/matrix.json)"
else
  fail "matrix.json 경로 참조 누락"
fi

# 4. WI-C1 SSOT 표지 (이전 WI 출처 명시)
if grep -qE 'WI-C1.*생성한 SSOT' "$SPRINT_MD"; then
  pass "WI-C1 SSOT 표지 (matrix.json 출처 명시)"
else
  fail "WI-C1 SSOT 표지 누락"
fi

# 5. matrix.json class 필드 정합 안내 (jq 비교 가능)
if grep -qE 'matrix\.json `class` 필드와 정확히 일치' "$SPRINT_MD"; then
  pass "matrix.json class 필드 정합 안내"
else
  fail "class 필드 정합 안내 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C2-2: 수용 기준 Gherkin 강제 ==="
# 1. Gherkin 강제 헤더
if grep -qE '^## 수용 기준.*Gherkin 강제' "$SPRINT_MD"; then
  pass "수용 기준 Gherkin 강제 헤더"
else
  fail "Gherkin 강제 헤더 누락"
fi

# 2. 자유 텍스트 금지 명시
if grep -qE '자유 텍스트 금지' "$SPRINT_MD"; then
  pass "자유 텍스트 금지 명시"
else
  fail "자유 텍스트 금지 명시 누락"
fi

# 3. Background / Scenario / Scenario Outline 키워드 안내
gherkin_kw=0
for kw in 'Background' 'Scenario' 'Scenario Outline' 'Examples'; do
  if grep -qE "$kw" "$SPRINT_MD"; then
    gherkin_kw=$((gherkin_kw + 1))
  fi
done
if (( gherkin_kw == 4 )); then
  pass "Gherkin 4 키워드 안내 (Background/Scenario/Scenario Outline/Examples)"
else
  fail "Gherkin 키워드 부족 ($gherkin_kw/4)"
fi

# 4. Given / When / Then 강제
gwt_count=$(grep -cE '^\s*(Given|When|Then|And) ' "$SPRINT_MD" || true)
if (( gwt_count >= 6 )); then
  pass "Given/When/Then 예시 6건 이상 ($gwt_count건)"
else
  fail "Gherkin 예시 부족 ($gwt_count/6)"
fi

# 5. code 예시 + content 예시 둘 다 존재
if grep -qE '# code 예시' "$SPRINT_MD" && grep -qE '# content 예시' "$SPRINT_MD"; then
  pass "Gherkin 예시 2종 (code + content)"
else
  fail "Gherkin 예시 1종 누락"
fi

# 6. Gherkin 강제 규칙 5건 (Feature/Scenario/GWT/자유텍스트금지/이름매칭)
rules_hit=0
for rule in 'Feature: 헤더' 'Scenario.*1개 이상 필수' 'Given.*When.*Then.*키워드' '자유 텍스트.*금지' '이름 매칭'; do
  if grep -qE "$rule" "$SPRINT_MD"; then
    rules_hit=$((rules_hit + 1))
  fi
done
if (( rules_hit >= 4 )); then
  pass "Gherkin 강제 규칙 4건 이상 명시 ($rules_hit/5)"
else
  fail "Gherkin 강제 규칙 부족 ($rules_hit/5)"
fi

# 7. parse-gherkin.sh 참조 (WI-C3 예약 + 설계 §4 :183 정합)
if grep -qE 'parse-gherkin\.sh' "$SPRINT_MD" && \
   grep -qE 'WI-C3' "$SPRINT_MD"; then
  pass "parse-gherkin.sh 참조 (WI-C3 예약 + 설계 §4 :183)"
else
  fail "parse-gherkin.sh 참조 누락"
fi

# 8. Scenario Outline + Examples 데이터 행 합산 규칙 (설계 §4 :195-196)
if grep -qE 'Examples 데이터 행 수가 시나리오 수에 합산' "$SPRINT_MD"; then
  pass "Scenario Outline Examples 합산 규칙 (§4 :195-196 정합)"
else
  fail "Examples 합산 규칙 누락"
fi

# 9. 1차 평가 LOW: Scenario Outline Examples self-consistency
# 시나리오 이름 "Reject invalid"는 모든 Examples 행이 invalid 의도여야 정합.
# WI-B3 패턴 23 정신: status=201/Reject 의도 모순 행 잔존 거부.
# 마지막 행 의도 모순(예: same-day allowed) 회귀 시 즉시 FAIL.
if awk '
  /Scenario Outline: Reject/ {in_outline=1; next}
  in_outline && /^      \| / && !/^      \| start_date/ {
    # 데이터 행에서 status 컬럼 추출 (4번째 |)
    n = split($0, fields, /\|/)
    status = fields[4]
    msg = fields[5]
    gsub(/^[ \t]+|[ \t]+$/, "", status)
    gsub(/^[ \t]+|[ \t]+$/, "", msg)
    # Reject Outline에서 status=201은 의도 모순
    if (status == "201") { exit_code=1; print "INTENT_VIOLATION: status=201 in Reject Outline (msg=" msg ")" }
    # message에 allowed/valid가 있으면서 Reject Outline이면 의도 모순
    if (msg ~ /allowed|^valid/) { exit_code=1; print "INTENT_VIOLATION: allowed/valid in Reject Outline (msg=" msg ")" }
  }
  in_outline && /^```$/ {exit exit_code+0}
  END {exit exit_code+0}
' "$SPRINT_MD"; then
  pass "패턴 23: Scenario Outline 'Reject' Examples 의도 정합 (모든 행이 invalid case)"
else
  fail "패턴 23: Scenario Outline 의도 모순 발견 (Reject Outline에 allowed/valid 행)"
fi

# ============================================================================
echo ""
echo "=== WI-C2-3: CRUD 매트릭스 (code/hybrid) ==="
# 1. CRUD 매트릭스 섹션 헤더
if grep -qE '^## CRUD 매트릭스 \(code \| hybrid only\)' "$SPRINT_MD"; then
  pass "CRUD 매트릭스 섹션 헤더 (code/hybrid only 명시)"
else
  fail "CRUD 매트릭스 헤더 누락"
fi

# 2. 표 컬럼: Entity | C 셀 | R 셀 | U 셀 | D 셀 | type_ssot | endpoints
if grep -qE '\| Entity \| C 셀 \| R 셀 \| U 셀 \| D 셀 \| type_ssot \| endpoints \|' "$SPRINT_MD"; then
  pass "CRUD 표 7컬럼 (Entity/C/R/U/D/type_ssot/endpoints)"
else
  fail "CRUD 표 컬럼 부족"
fi

# 3. Role × CRUD 권한 매트릭스 (employee/manager/admin)
if grep -qE 'Role × CRUD 권한' "$SPRINT_MD" && \
   grep -qE 'employee.*\|.*manager.*\|.*admin' "$SPRINT_MD" -z; then
  pass "Role × CRUD 권한 매트릭스 (employee/manager/admin 3종)"
else
  fail "Role × CRUD 권한 매트릭스 누락"
fi

# 4. 셀 의무 규칙 — pain point B1/B2/B3
if grep -qE 'pain point B1 차단' "$SPRINT_MD" && \
   grep -qE 'pain point B2 차단' "$SPRINT_MD" && \
   grep -qE 'pain point B3 차단' "$SPRINT_MD"; then
  pass "code 매트릭스 pain point B1/B2/B3 명시"
else
  fail "pain point 명시 부족 (B1/B2/B3)"
fi

# 5. type_ssot 단일 SSOT 명시 (예: prisma/schema.prisma#Leave)
if grep -qE 'prisma/schema\.prisma#' "$SPRINT_MD"; then
  pass "type_ssot 단일 SSOT 예시 (prisma/schema.prisma#Entity)"
else
  fail "type_ssot 예시 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C2-4: Section 매트릭스 (content/hybrid) ==="
# 1. Section 매트릭스 섹션 헤더
if grep -qE '^## Section 매트릭스 \(content \| hybrid only\)' "$SPRINT_MD"; then
  pass "Section 매트릭스 섹션 헤더 (content/hybrid only 명시)"
else
  fail "Section 매트릭스 헤더 누락"
fi

# 2. 표 컬럼: Section | draft | review | approve | sources | completeness_checklist
if grep -qE '\| Section \| draft \| review \| approve \| sources' "$SPRINT_MD"; then
  pass "Section 표 6컬럼 (Section/draft/review/approve/sources/checklist)"
else
  fail "Section 표 컬럼 부족"
fi

# 3. Role × Action 권한 (writer/reviewer/approver)
if grep -qE 'writer.*\|.*reviewer.*\|.*approver' "$SPRINT_MD" -z; then
  pass "Role × Action 권한 매트릭스 (writer/reviewer/approver 3종)"
else
  fail "Role × Action 권한 누락"
fi

# 4. 출처 + completeness_checklist 의무 (WI-B3 SSOT 참조)
# backtick으로 감싸진 `sources[]` 형태도 매칭 (markdown 인라인 코드 + 한글 텍스트)
if grep -qE '`sources\[\]` 1개 이상' "$SPRINT_MD" && \
   grep -qE 'WI-B3 style-guide\.md' "$SPRINT_MD"; then
  pass "출처 1개 이상 + WI-B3 style-guide.md SSOT 참조"
else
  fail "출처/style-guide 참조 누락"
fi

# 5. 익명 리뷰 금지 (.flowset/reviews/{section}-{reviewer}.md 파일명 규칙)
if grep -qE '\.flowset/reviews/\{section\}-\{reviewer\}\.md' "$SPRINT_MD" && \
   grep -qE '익명 리뷰 금지' "$SPRINT_MD"; then
  pass "익명 리뷰 금지 규칙 + 파일명 규칙 (설계 §4 :143)"
else
  fail "익명 리뷰 금지 규칙 누락"
fi

# 6. SSOT 단일성 (rubric 가중치 직렬화 거부, review-rubric.md만 SSOT)
if grep -qE 'WI-B3 `review-rubric\.md`만 SSOT' "$SPRINT_MD" && \
   grep -qE '본 매트릭스에 직렬화하지 않음' "$SPRINT_MD"; then
  pass "SSOT 단일성 (rubric 가중치 직렬화 거부)"
else
  fail "SSOT 단일성 명시 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C2-5: 평가 type 4종 + 검증 방법 + 제약 ==="
# 1. type 4종 (code | content | hybrid | visual)
if grep -qE 'type:.*code.*\|.*content.*\|.*hybrid.*\|.*visual' "$SPRINT_MD"; then
  pass "평가 type 4종 (code | content | hybrid | visual)"
else
  fail "평가 type 4종 표기 누락"
fi

# 2. 신규 type=content 예약 (WI-C4 evaluator type 예약)
if grep -qE 'WI-C4 evaluator type 신설 예약' "$SPRINT_MD"; then
  pass "type=content WI-C4 evaluator 예약"
else
  fail "WI-C4 type 예약 누락"
fi

# 3. content 가중치 (review-rubric.md 5축 25/25/20/15/15)
if grep -qE '사실성 25.*완결성 25.*명료성 20.*일관성 15.*출처 15' "$SPRINT_MD"; then
  pass "content type 가중치 (review-rubric.md 5축)"
else
  fail "content 가중치 부족"
fi

# 3b. 1차 평가 LOW: 가중치 산술 합계 100 self-consistency (WI-B3 패턴 23)
# code 30+25+25+20=100, content 25+25+20+15+15=100, visual 25+30+25+20=100
# 미래 PR이 가중치 변경 시 산술이 100을 깨뜨리면 즉시 FAIL
sum_code=$(grep -oE '기능완성도\([0-9]+%\) / 코드품질\([0-9]+%\) / 테스트\([0-9]+%\) / 계약준수\([0-9]+%\)' "$SPRINT_MD" \
  | grep -oE '[0-9]+' | awk '{s+=$1} END {print s}')
sum_content=$(grep -oE '사실성 [0-9]+ / 완결성 [0-9]+ / 명료성 [0-9]+ / 일관성 [0-9]+ / 출처 [0-9]+' "$SPRINT_MD" \
  | grep -oE '[0-9]+' | awk '{s+=$1} END {print s}')
sum_visual=$(grep -oE '디자인품질\([0-9]+%\) / 독창성\([0-9]+%\) / 기술완성도\([0-9]+%\) / 정확성\([0-9]+%\)' "$SPRINT_MD" \
  | grep -oE '[0-9]+' | awk '{s+=$1} END {print s}')
if [[ "$sum_code" == "100" ]] && [[ "$sum_content" == "100" ]] && [[ "$sum_visual" == "100" ]]; then
  pass "패턴 23: type 4종 가중치 산술 합계 100 (code=$sum_code / content=$sum_content / visual=$sum_visual)"
else
  fail "패턴 23: 가중치 합계 산술 위반 (code=$sum_code / content=$sum_content / visual=$sum_visual, 기대 모두 100)"
fi

# 4. 검증 방법 (parse-gherkin.sh + jq matrix.json + reviews/approvals)
verify_hit=0
for v in 'parse-gherkin\.sh' "jq '.entities" "jq '.sections" '\.flowset/reviews/' '\.flowset/approvals/'; do
  if grep -qE "$v" "$SPRINT_MD"; then
    verify_hit=$((verify_hit + 1))
  fi
done
if (( verify_hit >= 5 )); then
  pass "검증 방법 5건 명시 (parse-gherkin / jq entities / jq sections / reviews / approvals)"
else
  fail "검증 방법 부족 ($verify_hit/5)"
fi

# 5. 제약 — 자유 텍스트 금지 / matrix.json 외 entity 신설 금지 / verify_matrix_cells 차단
constraint_hit=0
for c in '자유 텍스트 수용 기준 작성 금지' 'matrix\.json에 없는 entity/section.*sprint-template.*만들지 않음' 'verify_matrix_cells \|\| exit 1.*차단'; do
  if grep -qE "$c" "$SPRINT_MD"; then
    constraint_hit=$((constraint_hit + 1))
  fi
done
if (( constraint_hit == 3 )); then
  pass "제약 3건 명시 (자유텍스트/entity 신설/verify_matrix_cells 차단)"
else
  fail "제약 부족 ($constraint_hit/3)"
fi

# ============================================================================
echo ""
echo "=== WI-C2-6: matrix.json (WI-C1 SSOT) 정합성 ==="
# 1. matrix.json 파일 존재 (WI-C1 산출물 의존)
if [[ -s "$MATRIX_JSON" ]]; then
  pass "matrix.json (WI-C1 산출물) 존재"
else
  fail "matrix.json 없음 — WI-C1 회귀"
fi

# 2. sprint-template의 entity 예시 키가 matrix.json _schema_code 예시 키와 일치
# sprint: {Leave}, matrix.json _schema_code.entities_example: Leave
matrix_code_keys=$(jq -r '._schema_code.entities_example | keys[0]' "$MATRIX_JSON")
if grep -qE "\| \{${matrix_code_keys}\}" "$SPRINT_MD"; then
  pass "sprint-template entity 예시 키 ($matrix_code_keys) ↔ matrix.json _schema_code 일치"
else
  fail "entity 키 정합 깨짐 (matrix.json: $matrix_code_keys)"
fi

# 3. sprint-template의 section 예시 키가 matrix.json _schema_content 예시 키와 일치
matrix_content_keys=$(jq -r '._schema_content.sections_example | keys[0]' "$MATRIX_JSON")
if grep -qE "\| \{${matrix_content_keys}\}" "$SPRINT_MD"; then
  pass "sprint-template section 예시 키 ($matrix_content_keys) ↔ matrix.json _schema_content 일치"
else
  fail "section 키 정합 깨짐 (matrix.json: $matrix_content_keys)"
fi

# 3b. 1차 평가 LOW: matrix.json _schema_hybrid example_root_skeleton 키 정합
# _schema_code/_schema_content와 동일한 키(Leave, 3.2-User-Flow)를 hybrid skeleton도 사용해야
# sprint-template의 hybrid 분기 정합이 SSOT 단일성으로 유지됨
hybrid_entity_key=$(jq -r '._schema_hybrid.example_root_skeleton.entities | keys[0]' "$MATRIX_JSON")
hybrid_section_key=$(jq -r '._schema_hybrid.example_root_skeleton.sections | keys[0]' "$MATRIX_JSON")
# _comment 키는 무시 — 실제 entity/section 키만 추출
if [[ "$hybrid_entity_key" == "_comment" ]]; then
  hybrid_entity_key=$(jq -r '._schema_hybrid.example_root_skeleton.entities | keys[1]' "$MATRIX_JSON")
fi
if [[ "$hybrid_section_key" == "_comment" ]]; then
  hybrid_section_key=$(jq -r '._schema_hybrid.example_root_skeleton.sections | keys[1]' "$MATRIX_JSON")
fi
if [[ "$hybrid_entity_key" == "$matrix_code_keys" ]] && [[ "$hybrid_section_key" == "$matrix_content_keys" ]]; then
  pass "_schema_hybrid skeleton 키 정합 (entity=$hybrid_entity_key=Leave, section=$hybrid_section_key=3.2-User-Flow — _schema_code/_schema_content와 동일)"
else
  fail "_schema_hybrid skeleton 키 ↔ _schema_code/_schema_content 불일치 (hybrid_entity=$hybrid_entity_key vs code=$matrix_code_keys, hybrid_section=$hybrid_section_key vs content=$matrix_content_keys)"
fi

# 4. status 3-state (missing/pending/done) 일관 사용
state_consistency=$(grep -cE 'missing|pending|done' "$SPRINT_MD" || true)
if (( state_consistency >= 8 )); then
  pass "status 3-state 일관 사용 (${state_consistency}건, matrix.json과 동일 어휘)"
else
  fail "status 3-state 일관성 부족 (${state_consistency}건)"
fi

# 5. role 어휘 정합 — code(employee/manager/admin) + content(writer/reviewer/approver)
code_roles=$(grep -cE 'employee|manager|admin' "$SPRINT_MD" || true)
content_roles=$(grep -cE 'writer|reviewer|approver' "$SPRINT_MD" || true)
if (( code_roles >= 3 )) && (( content_roles >= 3 )); then
  pass "role 어휘 정합 (code 3종 + content 3종, matrix.json 예시와 동일)"
else
  fail "role 어휘 부족 (code:$code_roles, content:$content_roles)"
fi

# ============================================================================
echo ""
echo "=== WI-C2-7: 학습 전이 회귀 방지 (패턴 2/3/4/19/23) ==="
# 패턴 2: ((var++)) — markdown anti-example 무관 (sprint-template은 의사코드 거의 없음)
total_bad=$(sed 's/`[^`]*`//g' "$SPRINT_MD" | sed -E 's/[[:space:]]+#.*$//' | grep -cE '\(\([[:alnum:]_]+\+\+\)\)' || true)
if (( total_bad == 0 )); then
  pass "패턴 2: ((var++)) 사용 0건"
else
  fail "패턴 2: ((var++)) 사용 ${total_bad}건"
fi

# 패턴 3: "${arr[@]/pattern}" 금지
if sed 's/`[^`]*`//g' "$SPRINT_MD" | grep -nE '\$\{[[:alnum:]_]+\[@\]/[^}]+\}' | grep -vE ':\s*#' > /dev/null; then
  fail "패턴 3: \${arr[@]/pattern} 사용 발견"
else
  pass "패턴 3: 사용 0건"
fi

# 패턴 4: || echo 0 금지
if grep -nE '\|\| echo 0' "$SPRINT_MD"; then
  fail "패턴 4: \`|| echo 0\` 사용 발견"
else
  pass "패턴 4: \`|| echo 0\` 사용 0건"
fi

# 패턴 19: local x=$(cmd) 금지 — sprint-template은 의사코드 거의 없음
if grep -nE '^\s*local\s+[[:alnum:]_]+=\$\(' "$SPRINT_MD"; then
  fail "패턴 19: \`local x=\$(cmd)\` 사용 발견"
else
  pass "패턴 19: 사용 0건"
fi

# 패턴 23: SSOT 계약 self-consistency — Gherkin 키워드 일관성 (Background/Scenario/Examples 어휘 통일)
# 같은 의미를 다른 어휘로 적지 않았는지 확인 (Scenario Outline ≠ ScenarioOutline)
if grep -qE 'ScenarioOutline' "$SPRINT_MD"; then
  fail "패턴 23: Gherkin 어휘 불일치 (ScenarioOutline 발견 — 표준은 'Scenario Outline')"
else
  pass "패턴 23: Gherkin 어휘 일관 (Scenario Outline 표준)"
fi

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-C2 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-C2 SMOKE FAILED"
  exit 1
fi
