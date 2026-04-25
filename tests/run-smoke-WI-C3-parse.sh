#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-C3-parse.sh — parse-gherkin.sh (Gherkin bash 파서) 전용 smoke
# 설계 §4 :183-205 + §5 :229 (B4 차단 메커니즘 prerequisite):
#   1. 출력 계약 정합 (feature_file / scenarios[] / total_count)
#   2. total_count = Scenario 개수 + Scenario Outline마다 examples_rows 합산
#   3. examples_rows: Examples 헤더 행 skip + 데이터 행만 카운트
#   4. 정규화 (소문자, 공백 squeeze, trim — ASCII 공백만)
#   5. Background / 주석 / Tag / Doc String 무시
#   6. 여러 Examples 블록 누적
#   7. JSON escape 안전성 (jq -n 사용)
#   8. 인자 누락 / 파일 없음 → exit 1 + ERROR
#
# 사용: bash tests/run-smoke-WI-C3-parse.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

PARSER="templates/.flowset/scripts/parse-gherkin.sh"

# ============================================================================
echo "=== WI-C3-parse-1: 정적 구조 검증 (계약 + 정규화 + 핵심 정규식) ==="

# 1. set -euo pipefail 보존
if grep -qE '^set -euo pipefail' "$PARSER"; then
  pass "set -euo pipefail 보존"
else
  fail "set -euo pipefail 누락"
fi

# 2. UTF-8 환경변수 4종 (LANG/LC_ALL/PYTHONUTF8/PYTHONIOENCODING)
if grep -qE '^export LANG=en_US.UTF-8' "$PARSER" && \
   grep -qE '^export LC_ALL=en_US.UTF-8' "$PARSER"; then
  pass "UTF-8 환경변수 (글로벌 wi-utf8.md 준수)"
else
  fail "UTF-8 환경변수 누락"
fi

# 3. 인자 검증 (feature_file 필수)
if grep -qE 'feature_file 인자 필수' "$PARSER"; then
  pass "feature_file 인자 필수 검증 메시지"
else
  fail "인자 필수 검증 누락"
fi

# 4. 파일 존재 검증
if grep -qE 'feature 파일 없음' "$PARSER"; then
  pass "파일 존재 검증 메시지"
else
  fail "파일 존재 검증 누락"
fi

# 5. Scenario Outline / Template 정규식이 Scenario / Example 정규식보다 먼저
# (모두 "Scenario"로 시작 가능 — Outline 먼저 매칭해야 type 잘못 분류 회귀 차단)
# 1차 평가 후속: 정규식 변경에 robust하도록 || true + 새 정규식(Outline|Template) / (Scenario|Example) 매칭
outline_line=$(grep -nE 'Scenario\[\[:space:\]\]\+\(Outline\|Template\):' "$PARSER" | head -1 | cut -d: -f1 || true)
scenario_line=$(grep -nE '\(Scenario\|Example\):' "$PARSER" | head -1 | cut -d: -f1 || true)
if [[ -n "$outline_line" && -n "$scenario_line" && "$outline_line" -lt "$scenario_line" ]]; then
  pass "Scenario (Outline|Template) 정규식이 (Scenario|Example) 정규식보다 먼저"
else
  fail "정규식 우선순위 위반 (outline=$outline_line scenario=$scenario_line)"
fi

# 5b. Examples: 정규식에 `$` anchor 없음 (description 허용 — 예: `Examples: edge cases`)
if grep -qE '/\^\[\[:space:\]\]\*Examples:/' "$PARSER" && \
   ! grep -qE '/\^\[\[:space:\]\]\*Examples:\[\[:space:\]\]\*\$/' "$PARSER"; then
  pass "Examples: 정규식 description 허용 (\$ anchor 미사용 — Gherkin 문법 준수)"
else
  fail "Examples: 정규식이 \$ anchor로 description 거부함 (Gherkin 문법 위반)"
fi

# 6. Examples 헤더 skip 로직 (examples_seen_header 변수)
if grep -qE 'examples_seen_header == 0' "$PARSER" && \
   grep -qE 'examples_seen_header = 1' "$PARSER"; then
  pass "Examples 헤더 skip 로직 (§4 :196 준수)"
else
  fail "Examples 헤더 skip 로직 누락"
fi

# 7. 정규화 함수 normalize() 정의 + tolower + ASCII 공백만
if grep -qE '^[[:space:]]*function normalize\(s\)' "$PARSER" && \
   grep -qE 'tolower\(s\)' "$PARSER" && \
   grep -qE 'gsub\(/\[ \\t\\r\]\+/' "$PARSER"; then
  pass "정규화 함수: tolower + ASCII 공백 squeeze (NBSP 처리 외)"
else
  fail "정규화 함수 누락 또는 패턴 위반"
fi

# 8. flush() 함수 정의 + scenario 누적/reset
if grep -qE '^[[:space:]]*function flush\(\)' "$PARSER"; then
  pass "flush() 함수 정의 (시나리오 누적/reset)"
else
  fail "flush() 함수 누락"
fi

# 9. JSON 출력은 jq -n으로 조립 (escape 안전성)
if grep -qE 'jq -n' "$PARSER" && \
   grep -qE -- '--arg feature_file' "$PARSER" && \
   grep -qE -- '--argjson scenarios' "$PARSER" && \
   grep -qE -- '--argjson total' "$PARSER"; then
  pass "최종 JSON jq -n 조립 (name escape jq 일임)"
else
  fail "최종 JSON 조립 패턴 누락"
fi

# 10. total_count 계산: Scenario +1, Outline +examples_rows
if grep -qE 'total=\$\(\(total \+ 1\)\)' "$PARSER" && \
   grep -qE 'total=\$\(\(total \+ examples_field\)\)' "$PARSER"; then
  pass "total_count 계산 (Scenario +1 / Outline +examples_rows §4 :195)"
else
  fail "total_count 계산 패턴 누락"
fi

# 11. 주석 line skip
if grep -qE '/\^\[\[:space:\]\]\*#/ \{ next \}' "$PARSER"; then
  pass "주석 line skip"
else
  fail "주석 skip 패턴 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-2: 학습 전이 회귀 방지 (패턴 2/3/19) ==="

# 패턴 2: ((var++)) 금지 (bash 영역, awk는 별개)
# awk의 examples_seen_header++ / current_examples++ / total++은 awk 문법이라 무관
bash_only=$(awk '/^awk / { in_awk=1 } /^[[:space:]]*'"'"'[[:space:]]*$/ { in_awk=0 } !in_awk { print }' "$PARSER" \
  | sed 's/`[^`]*`//g' | sed -E 's/[[:space:]]+#.*$//' | grep -cE '\(\([[:alnum:]_]+\+\+\)\)' || true)
if (( bash_only == 0 )); then
  pass "패턴 2: bash ((var++)) 0건 (awk 영역은 별도 문법, 무관)"
else
  fail "패턴 2: bash ((var++)) ${bash_only}건"
fi

# 패턴 3: "${arr[@]/pattern}" 금지
if sed 's/`[^`]*`//g' "$PARSER" | grep -nE '\$\{[[:alnum:]_]+\[@\]/[^}]+\}' > /dev/null; then
  fail "패턴 3: \${arr[@]/pattern} 사용 발견"
else
  pass "패턴 3: 사용 0건"
fi

# 패턴 19: local x=$(cmd) 금지 (SC2155)
if grep -nE '^[[:space:]]*local[[:space:]]+[[:alnum:]_]+=\$\(' "$PARSER"; then
  fail "패턴 19: \`local x=\$(cmd)\` 사용 발견"
else
  pass "패턴 19: 사용 0건 (분리 선언 일관)"
fi

# 패턴 24: 정의 + 호출 양방향 (parser 자체는 단일 함수 미사용 — flush/normalize awk 함수만)
# awk function flush() / normalize()는 flush() / normalize(...)로 호출되어야 함
if grep -qE 'flush\(\)' "$PARSER"; then
  pass "패턴 24: flush() 정의 + 호출 양방향 (awk function)"
else
  fail "패턴 24: flush() 호출 누락"
fi
if grep -qE 'normalize\(raw\)' "$PARSER"; then
  pass "패턴 24: normalize() 정의 + 호출 양방향 (awk function)"
else
  fail "패턴 24: normalize() 호출 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-3: 인자/파일 검증 e2e ==="
TMP_DIR="${TMPDIR:-/tmp}/wi-c3p-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# A. 인자 누락 → exit 1
set +e
out=$(bash "$PARSER" 2>&1)
rc=$?
set -e
if (( rc == 1 )) && echo "$out" | grep -qE 'feature_file 인자 필수'; then
  pass "A. 인자 누락 → exit 1 + ERROR 메시지"
else
  fail "A. 인자 누락 처리 실패 (rc=$rc, out=$out)"
fi

# B. 파일 없음 → exit 1
set +e
out=$(bash "$PARSER" "$TMP_DIR/nonexistent.feature" 2>&1)
rc=$?
set -e
if (( rc == 1 )) && echo "$out" | grep -qE 'feature 파일 없음'; then
  pass "B. 파일 없음 → exit 1 + ERROR 메시지"
else
  fail "B. 파일 없음 처리 실패 (rc=$rc, out=$out)"
fi

# C. 빈 파일 → scenarios=[], total_count=0
: > "$TMP_DIR/empty.feature"
out=$(bash "$PARSER" "$TMP_DIR/empty.feature")
total=$(echo "$out" | jq -r '.total_count')
scenarios=$(echo "$out" | jq -r '.scenarios | length')
if [[ "$total" == "0" && "$scenarios" == "0" ]]; then
  pass "C. 빈 파일 → scenarios=[], total_count=0"
else
  fail "C. 빈 파일 처리 실패 (total=$total scenarios=$scenarios)"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-4: Scenario / Background / 주석 e2e ==="

# D. Scenario 단독 (Background 무시 + 주석 무시)
cat > "$TMP_DIR/d.feature" <<'EOF'
Feature: Test

  Background:
    Given a thing

  # 주석 무시되어야 함
  Scenario: Do the thing
    When I do it
    Then it is done
EOF
out=$(bash "$PARSER" "$TMP_DIR/d.feature")
total=$(echo "$out" | jq -r '.total_count')
sc=$(echo "$out" | jq -r '.scenarios | length')
name=$(echo "$out" | jq -r '.scenarios[0].name')
type=$(echo "$out" | jq -r '.scenarios[0].type')
if [[ "$total" == "1" && "$sc" == "1" && "$name" == "do the thing" && "$type" == "Scenario" ]]; then
  pass "D. Scenario 1 + Background 무시 + 주석 무시 (total=1, name 정규화)"
else
  fail "D. 처리 실패 (total=$total sc=$sc name='$name' type='$type')"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-5: Scenario Outline + Examples 헤더 skip e2e ==="

# E. Outline 1개 + Examples 데이터 3행 (헤더 skip)
cat > "$TMP_DIR/e.feature" <<'EOF'
Feature: Test

  Scenario Outline: Try with input "<x>"
    When I try "<x>"
    Then result is "<y>"
    Examples:
      | x       | y     |
      | first   | one   |
      | second  | two   |
      | third   | three |
EOF
out=$(bash "$PARSER" "$TMP_DIR/e.feature")
total=$(echo "$out" | jq -r '.total_count')
sc=$(echo "$out" | jq -r '.scenarios | length')
name=$(echo "$out" | jq -r '.scenarios[0].name')
type=$(echo "$out" | jq -r '.scenarios[0].type')
ex=$(echo "$out" | jq -r '.scenarios[0].examples_rows')
if [[ "$total" == "3" && "$sc" == "1" && "$type" == "Scenario Outline" && "$ex" == "3" && "$name" == 'try with input "<x>"' ]]; then
  pass "E. Outline 1 + Examples 헤더 skip + 데이터 3 → total=3"
else
  fail "E. 처리 실패 (total=$total sc=$sc type='$type' ex=$ex name='$name')"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-6: Mixed (Scenario 2 + Outline 1) total 합산 e2e ==="

cat > "$TMP_DIR/f.feature" <<'EOF'
Feature: Mixed

  Scenario: Alpha
    When ...
    Then ...

  Scenario Outline: Beta with <x>
    When ...
    Examples:
      | x |
      | 1 |
      | 2 |

  Scenario: Gamma
    When ...
EOF
out=$(bash "$PARSER" "$TMP_DIR/f.feature")
total=$(echo "$out" | jq -r '.total_count')
sc=$(echo "$out" | jq -r '.scenarios | length')
# 기대: Scenario(1) + Outline(2 examples) + Scenario(1) = 4
if [[ "$total" == "4" && "$sc" == "3" ]]; then
  pass "F. Mixed: Scenario 2 + Outline 1×2 examples → total=4 (sc 항목=3)"
else
  fail "F. Mixed 합산 실패 (total=$total sc=$sc out=$out)"
fi

# 각 항목 검증
n0=$(echo "$out" | jq -r '.scenarios[0].name')
n1=$(echo "$out" | jq -r '.scenarios[1].name')
n2=$(echo "$out" | jq -r '.scenarios[2].name')
if [[ "$n0" == "alpha" && "$n1" == "beta with <x>" && "$n2" == "gamma" ]]; then
  pass "F. 시나리오 순서 + 정규화 (alpha / beta with <x> / gamma)"
else
  fail "F. 순서/정규화 실패 (n0='$n0' n1='$n1' n2='$n2')"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-7: 정규화 e2e (대소문자 + 연속 공백 + trim) ==="

cat > "$TMP_DIR/g.feature" <<'EOF'
Feature: Norm

  Scenario:    Create   Leave   Request
    When ...
EOF
out=$(bash "$PARSER" "$TMP_DIR/g.feature")
name=$(echo "$out" | jq -r '.scenarios[0].name')
# 기대: "create leave request" (3중 공백 squeeze + 선/후 trim + lowercase)
if [[ "$name" == "create leave request" ]]; then
  pass "G. 정규화: 대소문자 + 연속 공백 squeeze + trim ('$name')"
else
  fail "G. 정규화 실패 (got='$name', expected='create leave request')"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-8: JSON escape 안전성 e2e (따옴표/백슬래시 포함 name) ==="

cat > "$TMP_DIR/h.feature" <<'EOF'
Feature: Escape

  Scenario: Order with "premium" tier and \backslash
    When I order
    Then it works
EOF
out=$(bash "$PARSER" "$TMP_DIR/h.feature")
# JSON parser로 다시 읽어서 정상 escape 검증 — jq 통과 시 valid JSON
if echo "$out" | jq -e '.scenarios[0].name' > /dev/null 2>&1; then
  name=$(echo "$out" | jq -r '.scenarios[0].name')
  if echo "$name" | grep -qF '"premium"' && echo "$name" | grep -qF '\backslash'; then
    pass "H. JSON escape: 따옴표 + 백슬래시 포함 name 정상 ('$name')"
  else
    fail "H. JSON escape: 특수문자 보존 실패 (name='$name')"
  fi
else
  fail "H. JSON escape: jq parse 실패 (invalid JSON)"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-9: 여러 Examples 블록 누적 e2e ==="

cat > "$TMP_DIR/i.feature" <<'EOF'
Feature: Multi Examples

  Scenario Outline: try with <x>
    When ...
    Examples:
      | x |
      | a |
      | b |
    Examples: more
      | x |
      | c |
EOF
out=$(bash "$PARSER" "$TMP_DIR/i.feature")
ex=$(echo "$out" | jq -r '.scenarios[0].examples_rows')
total=$(echo "$out" | jq -r '.total_count')
# 기대: 첫 블록 2 + 둘째 블록 1 = 3
if [[ "$ex" == "3" && "$total" == "3" ]]; then
  pass "I. 여러 Examples 블록 누적 (2+1=3)"
else
  fail "I. 여러 Examples 블록 누적 실패 (ex=$ex total=$total)"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-10: Examples 없는 Outline + 헤더만 있는 Examples e2e ==="

# J. Outline에 Examples 없음 → examples_rows=0, total += 0 (정의상 valid)
cat > "$TMP_DIR/j.feature" <<'EOF'
Feature: Outline No Examples

  Scenario Outline: try with <x>
    When I try "<x>"
EOF
out=$(bash "$PARSER" "$TMP_DIR/j.feature")
ex=$(echo "$out" | jq -r '.scenarios[0].examples_rows')
total=$(echo "$out" | jq -r '.total_count')
type=$(echo "$out" | jq -r '.scenarios[0].type')
if [[ "$ex" == "0" && "$total" == "0" && "$type" == "Scenario Outline" ]]; then
  pass "J. Outline + Examples 없음 → examples_rows=0, total=0"
else
  fail "J. 처리 실패 (ex=$ex total=$total type='$type')"
fi

# K. Examples 헤더만 (데이터 0행) → examples_rows=0
cat > "$TMP_DIR/k.feature" <<'EOF'
Feature: Header Only

  Scenario Outline: foo
    When ...
    Examples:
      | x | y |
EOF
out=$(bash "$PARSER" "$TMP_DIR/k.feature")
ex=$(echo "$out" | jq -r '.scenarios[0].examples_rows')
total=$(echo "$out" | jq -r '.total_count')
if [[ "$ex" == "0" && "$total" == "0" ]]; then
  pass "K. Examples 헤더만(데이터 0행) → examples_rows=0"
else
  fail "K. 헤더만 처리 실패 (ex=$ex total=$total)"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-11: Examples 블록 안 주석/빈줄 e2e ==="

cat > "$TMP_DIR/l.feature" <<'EOF'
Feature: Examples With Comments

  Scenario Outline: try
    Examples:
      | x |
      | a |
      # 중간 주석 무시
      | b |

      | c |
EOF
out=$(bash "$PARSER" "$TMP_DIR/l.feature")
ex=$(echo "$out" | jq -r '.scenarios[0].examples_rows')
# 기대: 헤더 skip + a/b/c = 3 (중간 주석/빈 줄은 블록 종료시키지 않음)
if [[ "$ex" == "3" ]]; then
  pass "L. Examples 안 주석/빈줄 무시 + 데이터 3행 누적 (a,b,c)"
else
  fail "L. 처리 실패 (ex=$ex out=$out)"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-12: 출력 계약 정합 (필수 키 + 타입) ==="

cat > "$TMP_DIR/m.feature" <<'EOF'
Feature: Contract

  Scenario: Foo
    When ...
EOF
out=$(bash "$PARSER" "$TMP_DIR/m.feature")

# 필수 키 3종 모두 존재
keys=$(echo "$out" | jq -r 'keys | sort | join(",")')
if [[ "$keys" == "feature_file,scenarios,total_count" ]]; then
  pass "M. 출력 계약: feature_file + scenarios + total_count (3 키 모두 존재)"
else
  fail "M. 출력 계약 위반 (keys='$keys')"
fi

# scenarios[].각 항목의 필수 키
sc_keys=$(echo "$out" | jq -r '.scenarios[0] | keys | sort | join(",")')
if [[ "$sc_keys" == "examples_rows,name,type" ]]; then
  pass "M. 출력 계약: scenarios[] 항목 키 (examples_rows + name + type)"
else
  fail "M. scenarios 키 위반 (keys='$sc_keys')"
fi

# total_count 타입 (number)
total_type=$(echo "$out" | jq -r '.total_count | type')
ex_type=$(echo "$out" | jq -r '.scenarios[0].examples_rows | type')
if [[ "$total_type" == "number" && "$ex_type" == "number" ]]; then
  pass "M. 출력 계약: total_count + examples_rows 타입 number (string 아님)"
else
  fail "M. 타입 위반 (total=$total_type ex=$ex_type)"
fi

# feature_file은 인자 그대로 (Windows MSYS path 변환 회피 위해 상대 경로로 재호출)
# bash가 절대 경로 인자를 native path로 변환할 수 있어 검증 우회 — 상대 경로는 변환 무관
pushd "$TMP_DIR" > /dev/null
out_rel=$(bash "$REPO_ROOT/$PARSER" "m.feature")
ff_rel=$(echo "$out_rel" | jq -r '.feature_file')
popd > /dev/null
if [[ "$ff_rel" == "m.feature" ]]; then
  pass "M. 출력 계약: feature_file은 인자 그대로 보존 (상대 경로 검증)"
else
  fail "M. feature_file 변형됨 (got='$ff_rel' expected='m.feature')"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-13: 한글 시나리오 이름 (multi-byte 안전성) e2e ==="

cat > "$TMP_DIR/n.feature" <<'EOF'
Feature: 한글 테스트

  Scenario: 직원으로서 휴가를 신청한다
    When 신청 폼을 제출하면
    Then 신청이 저장된다

  Scenario Outline: 잘못된 날짜로 신청한다
    When start "<start>" end "<end>"로 제출
    Examples:
      | start      | end        |
      | 2026-04-30 | 2026-04-29 |
      | 2026-04-30 | 2026-04-30 |
EOF
out=$(bash "$PARSER" "$TMP_DIR/n.feature")
total=$(echo "$out" | jq -r '.total_count')
n0=$(echo "$out" | jq -r '.scenarios[0].name')
n1=$(echo "$out" | jq -r '.scenarios[1].name')
# 한글은 tolower 영향 없음 + 정상 보존
if [[ "$total" == "3" && "$n0" == "직원으로서 휴가를 신청한다" && "$n1" == "잘못된 날짜로 신청한다" ]]; then
  pass "N. 한글 시나리오 이름 정상 (multi-byte 보존, tolower 영향 없음)"
else
  fail "N. 한글 처리 실패 (total=$total n0='$n0' n1='$n1')"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-14: Doc String 안 키워드 무시 e2e (1차 평가 [MEDIUM] 회귀 차단) ==="
# 1차 평가 발견: smoke prose에 "Doc String 무시" 명시했으나 실 검증 0건 (학습 25 회귀)
# 본 sub-section은 Doc String 안 Scenario:/Examples:/| 키워드가 false positive로 카운트되지 않음을 보장

# O. Doc String(""") 안 Scenario: 무시
cat > "$TMP_DIR/o.feature" <<'EOF'
Feature: Doc String

  Scenario: Document the API
    When I show
      """
      Scenario: this is fake inside doc
      Examples:
        | should be | ignored |
        | really    | ignored |
      """
    Then it works
EOF
out=$(bash "$PARSER" "$TMP_DIR/o.feature")
total=$(echo "$out" | jq -r '.total_count')
sc=$(echo "$out" | jq -r '.scenarios | length')
ex=$(echo "$out" | jq -r '.scenarios[0].examples_rows')
name=$(echo "$out" | jq -r '.scenarios[0].name')
# 기대: Scenario 1개(real), examples_rows=0 (Doc String 안 모두 무시)
if [[ "$total" == "1" && "$sc" == "1" && "$ex" == "0" && "$name" == "document the api" ]]; then
  pass "O. Doc String(\"\"\") 안 Scenario:/Examples:/| 모두 무시 (학습 25 회귀 차단)"
else
  fail "O. Doc String 무시 실패 (total=$total sc=$sc ex=$ex name='$name')"
fi

# P. Doc String(```) 안에서도 동일 무시
cat > "$TMP_DIR/p.feature" <<'EOF'
Feature: Backtick Doc

  Scenario: Real one
    When I document
      ```
      Scenario: fake backtick inside
      ```
    Then OK
EOF
out=$(bash "$PARSER" "$TMP_DIR/p.feature")
total=$(echo "$out" | jq -r '.total_count')
if [[ "$total" == "1" ]]; then
  pass "P. Doc String(\`\`\`) 안 Scenario: 무시 (백틱 변형도 처리)"
else
  fail "P. 백틱 Doc String 처리 실패 (total=$total)"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-15: Scenario Template 별칭 e2e (1차 평가 [MEDIUM] 회귀 차단) ==="
# Q. Scenario Template (Outline 별칭) → type="Scenario Outline"으로 통합 인식
cat > "$TMP_DIR/q.feature" <<'EOF'
Feature: Template

  Scenario Template: Try with template <x>
    When I try "<x>"
    Examples:
      | x |
      | a |
      | b |
EOF
out=$(bash "$PARSER" "$TMP_DIR/q.feature")
total=$(echo "$out" | jq -r '.total_count')
type=$(echo "$out" | jq -r '.scenarios[0].type')
ex=$(echo "$out" | jq -r '.scenarios[0].examples_rows')
name=$(echo "$out" | jq -r '.scenarios[0].name')
# 기대: type="Scenario Outline" (출력 계약 단일 type), examples_rows=2, total=2
if [[ "$total" == "2" && "$type" == "Scenario Outline" && "$ex" == "2" && "$name" == "try with template <x>" ]]; then
  pass "Q. Scenario Template: → type=\"Scenario Outline\" 통합 인식 (cucumber 호환)"
else
  fail "Q. Template 별칭 처리 실패 (total=$total type='$type' ex=$ex name='$name')"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-16: Example 단수 별칭 e2e (1차 평가 [LOW] 회귀 차단) ==="
# R. Example: (Scenario 단수 별칭) → type="Scenario"으로 통합 인식
cat > "$TMP_DIR/r.feature" <<'EOF'
Feature: Example singular

  Example: Single example
    When I do
    Then OK

  Scenario: Mixed with Scenario:
    When I do
EOF
out=$(bash "$PARSER" "$TMP_DIR/r.feature")
total=$(echo "$out" | jq -r '.total_count')
sc=$(echo "$out" | jq -r '.scenarios | length')
n0=$(echo "$out" | jq -r '.scenarios[0].name')
n1=$(echo "$out" | jq -r '.scenarios[1].name')
t0=$(echo "$out" | jq -r '.scenarios[0].type')
t1=$(echo "$out" | jq -r '.scenarios[1].type')
# 기대: 둘 다 type="Scenario", total=2
if [[ "$total" == "2" && "$sc" == "2" && "$t0" == "Scenario" && "$t1" == "Scenario" && \
      "$n0" == "single example" && "$n1" == "mixed with scenario:" ]]; then
  pass "R. Example: 단수 별칭 → type=\"Scenario\" 통합 인식 (cucumber 호환)"
else
  fail "R. Example 별칭 처리 실패 (total=$total sc=$sc n0='$n0' n1='$n1' t0='$t0' t1='$t1')"
fi

# ============================================================================
echo ""
echo "=== WI-C3-parse-17: 정적 회귀 차단 — 1차 평가 항목 ==="

# 17-1. in_doc_string 변수 + Doc String 토글 정규식 정의
if grep -qE 'in_doc_string = 0' "$PARSER" && \
   grep -qE 'in_doc_string = !in_doc_string' "$PARSER" && \
   grep -qE 'in_doc_string \{ next \}' "$PARSER"; then
  pass "17-1. in_doc_string 상태 변수 + 토글 + skip 가드"
else
  fail "17-1. Doc String 처리 패턴 누락"
fi

# 17-2. Doc String 정규식이 """ 또는 ``` 양쪽 인식
if grep -qE '\\"\\"\\"\|\`\`\`' "$PARSER" || \
   grep -qE '"""\|```' "$PARSER"; then
  pass "17-2. Doc String 정규식 \"\"\" + \`\`\` 양쪽 인식"
else
  fail "17-2. Doc String 정규식 누락"
fi

# 17-3. Scenario Template 별칭 정규식 인식
if grep -qE 'Scenario\[\[:space:\]\]\+\(Outline\|Template\):' "$PARSER"; then
  pass "17-3. Scenario Template 별칭 정규식 (Outline|Template)"
else
  fail "17-3. Template 별칭 정규식 누락"
fi

# 17-4. Example 단수 별칭 정규식 인식
if grep -qE '\(Scenario\|Example\):' "$PARSER"; then
  pass "17-4. Example 단수 별칭 정규식 (Scenario|Example)"
else
  fail "17-4. Example 별칭 정규식 누락"
fi

# 17-5. Doc String 토글이 다른 모든 패턴보다 먼저 (priority 1)
# || true 가드: pipefail 환경에서 grep miss 시 set -e 종료 회피
doc_line=$(grep -nE 'in_doc_string = !in_doc_string' "$PARSER" | head -1 | cut -d: -f1 || true)
sc_line=$(grep -nE 'Scenario\|Example' "$PARSER" | head -1 | cut -d: -f1 || true)
if [[ -n "$doc_line" && -n "$sc_line" && "$doc_line" -lt "$sc_line" ]]; then
  pass "17-5. Doc String 토글이 Scenario 매칭보다 먼저 (priority 1)"
else
  fail "17-5. Doc String 우선순위 위반 (doc=$doc_line sc=$sc_line)"
fi

# 17-6. in_doc_string skip이 토글 직후 (이중 안전 — Doc String 라인 자체도 next로 빠짐)
skip_line=$(grep -nE '^[[:space:]]*in_doc_string \{ next \}' "$PARSER" | head -1 | cut -d: -f1 || true)
if [[ -n "$skip_line" && -n "$doc_line" && "$skip_line" -gt "$doc_line" ]]; then
  pass "17-6. in_doc_string skip이 토글 직후 위치 (Doc String 안 모든 라인 skip)"
else
  fail "17-6. in_doc_string skip 위치 위반 (skip=$skip_line doc=$doc_line)"
fi

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-C3-parse ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-C3-parse SMOKE FAILED"
  exit 1
fi
