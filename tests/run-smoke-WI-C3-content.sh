#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-C3-content.sh — WI-C3-content (stop-rag-check.sh content 분기) 전용 smoke
# 설계 §5 :224 + §4 :141-146 + §7 :317 (content 영역 검증) Group γ 후속 이행:
#   1. 섹션 9: 출처 URL/파일 존재 검증 (B6) — matrix.sections[].sources[]
#   2. 섹션 10: completeness_checklist 본문 등장 검증 (B7) — matrix.sections[].completeness_checklist
#   3. HAS_MATRIX 가드 (matrix.json 부재 시 신규 섹션 skip — 하위 호환)
#   4. content 경로 분류는 WI-C5와 동일 SSOT (`^(docs|content|research)/...`)
#   5. 학습 31/32 완전 적용 — 모든 jq -r에 tr -d '\r', decision JSON은 jq -n
# 사용: bash tests/run-smoke-WI-C3-content.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

STOP_SH="templates/.flowset/scripts/stop-rag-check.sh"

# ============================================================================
echo "=== WI-C3-content-1: 정적 구조 검증 (섹션 9/10 + HAS_MATRIX 가드) ==="

# 1. 섹션 9 헤더 (출처 URL/파일 존재 검증 B6)
if grep -qE '^# 9\. 출처 URL.*검증 \(B6' "$STOP_SH"; then
  pass "섹션 9 헤더: 출처 URL/파일 존재 검증 (B6)"
else
  fail "섹션 9 헤더 누락"
fi

# 2. 섹션 10 헤더 (completeness_checklist 본문 등장 B7)
if grep -qE '^# 10\. completeness_checklist 본문 등장 검증 \(B7' "$STOP_SH"; then
  pass "섹션 10 헤더: completeness_checklist 본문 등장 검증 (B7)"
else
  fail "섹션 10 헤더 누락"
fi

# 3. 섹션 9/10 모두 HAS_MATRIX 가드 (총 5회 등장: 6/7/8/9/10)
guard_count=$(grep -cE 'if \[\[ "\$HAS_MATRIX" == "true"' "$STOP_SH" || true)
if (( guard_count >= 5 )); then
  pass "섹션 9/10 모두 HAS_MATRIX 가드 추가 (총 ${guard_count}회 — 6/7/8/9/10)"
else
  fail "HAS_MATRIX 가드 부족 (${guard_count}회, 5+ 기대)"
fi

# 4. 섹션 위치: 8 < 9 < 10 < 5(Vault)
section8_line=$(grep -nE '^# 8\. Gherkin' "$STOP_SH" | head -1 | cut -d: -f1 || true)
section9_line=$(grep -nE '^# 9\. 출처 URL' "$STOP_SH" | head -1 | cut -d: -f1 || true)
section10_line=$(grep -nE '^# 10\. completeness_checklist' "$STOP_SH" | head -1 | cut -d: -f1 || true)
section5_line=$(grep -nE '^# 5\. v3.0: Vault' "$STOP_SH" | head -1 | cut -d: -f1 || true)
if [[ -n "$section8_line" && -n "$section9_line" && -n "$section10_line" && -n "$section5_line" && \
      "$section9_line" -gt "$section8_line" && \
      "$section10_line" -gt "$section9_line" && \
      "$section10_line" -lt "$section5_line" ]]; then
  pass "섹션 위치: 8(${section8_line}) < 9(${section9_line}) < 10(${section10_line}) < 5(${section5_line})"
else
  fail "섹션 위치 위반 (8=$section8_line 9=$section9_line 10=$section10_line 5=$section5_line)"
fi

# 5. content 경로 분류 정규식 — WI-C5와 동일 SSOT
if grep -qE "grep -E '\^\(docs\|content\|research\)/\.\*\\\\\.\(md\|mdx\|markdown\|txt\|rst\)\\\$'" "$STOP_SH"; then
  pass "content 경로 분류: ^(docs|content|research)/...md|mdx|markdown|txt|rst (WI-C5 SSOT 정합)"
else
  fail "content 경로 정규식 형태 위반"
fi

# 6. URL 정적 검증 패턴 (^https?:// — 외부 호출 금지 가드)
# grep -F (fixed-string)로 bash regex literal 매칭 — ERE escape 차이 회피
if grep -qF 'source_ref" =~ ^https?://' "$STOP_SH"; then
  pass "URL 정적 검증 (^https?:// — 외부 HTTP 호출 금지)"
else
  fail "URL 정적 검증 패턴 누락"
fi

# 7. 학습 31: 섹션 9/10의 jq -r 결과에 tr -d '\r' 파이프 (Windows jq.exe CRLF)
# 섹션 9의 .sections 추출 1건 + 섹션 10의 section_keys/section_paths/section_items 3건 = 총 4건
# (섹션 10 리팩토링: section 단위 처리로 jq 3회 호출)
jq_tr_count=$(grep -cE "jq -r .*tr -d '" "$STOP_SH" || echo "0")
if (( jq_tr_count >= 5 )); then
  pass "[학습 31] 모든 jq -r 호출에 tr -d '\\r' 적용 (${jq_tr_count}회 — STOP_HOOK_ACTIVE 1 + auth_patterns 1 + parse-gherkin 3 + sections 4)"
else
  fail "[학습 31] jq -r tr -d '\\r' 미적용 (${jq_tr_count}회, 5+ 기대)"
fi

# 7b. 섹션 10의 section 단위 jq 호출 3건 (section_keys/section_paths/section_items)
sec10_jq=$(awk '/^# 10\. completeness_checklist/,/^# 5\. v3.0: Vault/' "$STOP_SH" | grep -cE 'jq -r' || echo "0")
if (( sec10_jq >= 3 )); then
  pass "섹션 10: section 단위 jq 호출 ${sec10_jq}건 (keys + paths + items)"
else
  fail "섹션 10 jq 호출 부족 (${sec10_jq}건, 3+ 기대)"
fi

# 7c. [LOW-2 해소] 섹션 10 헬퍼 함수 분리 (가독성 + 테스트 용이성)
if grep -qE '^_compute_matching_files\(\)' "$STOP_SH" && \
   grep -qE '^_check_section_completeness\(\)' "$STOP_SH"; then
  pass "[LOW-2 해소] 섹션 10 헬퍼 함수 2개 분리 (_compute_matching_files + _check_section_completeness)"
else
  fail "[LOW-2] 헬퍼 함수 미분리"
fi

# 7d. [LOW-1 해소] 섹션 10 영역에 `for cf in $...` 패턴 0건 (공백 파일명 안전 — while read 통일)
# pipefail + grep 0건(exit 1) 회피: awk 단일 호출로 추출+카운트 (awk만 사용 — pipefail 안전)
sec10_word_split=$(awk '
  /^# 10\. completeness_checklist/ { capture = 1 }
  /^# 5\. v3.0: Vault/ { capture = 0 }
  capture && /^[[:space:]]*for [[:alnum:]_]+ in \$/ { c++ }
  END { print c+0 }
' "$STOP_SH")
if (( sec10_word_split == 0 )); then
  pass "[LOW-1 해소] 섹션 10/헬퍼: 'for cf in \$X' word-splitting 0건 (while read 통일)"
else
  fail "[LOW-1] 섹션 10/헬퍼에 word-splitting ${sec10_word_split}건"
fi

# 8. 변경 파일 추출 1회 (changed_content_files 재사용 — 중복 산출 금지)
content_assign_count=$(grep -cE '^[[:space:]]*changed_content_files=\$\(echo' "$STOP_SH" || echo "0")
if (( content_assign_count == 1 )); then
  pass "changed_content_files 단일 산출 (섹션 9에서 1회, 섹션 10에서 재사용)"
else
  fail "changed_content_files 산출 횟수 위반 (${content_assign_count}회 — 1회 기대)"
fi

# 9. set -u 방어 (changed_content_files 재사용 시 빈 변수 안전)
if grep -qE 'changed_content_files="\$\{changed_content_files:-\}"' "$STOP_SH"; then
  pass "set -u 방어: changed_content_files=\${changed_content_files:-}"
else
  fail "set -u 방어 누락 — 섹션 10에서 changed_content_files 재사용 시 unbound 위험"
fi

# 10. issues+= 누적 (학습 27 — Stop hook 컨텍스트, silent skip 아닌 block)
if grep -qE 'issues\+=\(.*B6' "$STOP_SH" && \
   grep -qE 'issues\+=\(.*B7' "$STOP_SH"; then
  pass "[학습 27] B6/B7 issues+= 누적 (block 결과 — silent skip 아님)"
else
  fail "[학습 27] B6/B7 issues+= 누적 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C3-content-2: 학습 전이 회귀 방지 (패턴 2/3/19/32) ==="

# 패턴 2: ((var++)) 금지
total_bad=$(sed 's/`[^`]*`//g' "$STOP_SH" | sed -E 's/[[:space:]]+#.*$//' | grep -cE '\(\([[:alnum:]_]+\+\+\)\)' || true)
if (( total_bad == 0 )); then
  pass "패턴 2: ((var++)) 0건"
else
  fail "패턴 2: ((var++)) ${total_bad}건"
fi

# 패턴 3: ${arr[@]/pattern} 금지
if sed 's/`[^`]*`//g' "$STOP_SH" | grep -nE '\$\{[[:alnum:]_]+\[@\]/[^}]+\}' > /dev/null; then
  fail "패턴 3: \${arr[@]/pattern} 사용 발견"
else
  pass "패턴 3: 사용 0건"
fi

# 패턴 19: local x=$(cmd) 금지
if grep -nE '^[[:space:]]*local[[:space:]]+[[:alnum:]_]+=\$\(' "$STOP_SH"; then
  fail "패턴 19: local x=\$(cmd) 사용 발견"
else
  pass "패턴 19: 사용 0건"
fi

# 패턴 32: decision JSON jq -nc 패턴 보존 (escape SSOT — WI-C3-code-fix 학습)
if grep -qE 'jq -nc --arg reason' "$STOP_SH"; then
  pass "[학습 32] decision JSON jq -nc 패턴 보존 (escape SSOT)"
else
  fail "[학습 32] jq -nc 패턴 변형 — escape 회귀 위험"
fi

# ============================================================================
echo ""
echo "=== WI-C3-content-3: HAS_MATRIX=false → 섹션 9/10 skip e2e ==="
TMP_DIR="${TMPDIR:-/tmp}/wi-c3content-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# 신규 섹션 9/10을 awk로 추출 (섹션 9 헤더 ~ 섹션 5 헤더 직전)
EXTRACT="$TMP_DIR/sections_910.sh"
awk '
  /^# 9\. 출처 URL/ { capture = 1 }
  /^# 5\. v3.0: Vault/ { capture = 0 }
  capture { print }
' "$STOP_SH" > "$EXTRACT"

if grep -q "출처 URL" "$EXTRACT" && grep -q "completeness_checklist" "$EXTRACT"; then
  pass "섹션 9/10 추출 성공"
else
  fail "섹션 9/10 추출 실패"
  echo "=== 총: PASS=$PASS FAIL=$FAIL ==="
  exit 1
fi

# 시나리오 A: HAS_MATRIX=false → 섹션 9/10 skip → issues 0건
WORK="$TMP_DIR/work-no-matrix"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
export HAS_MATRIX=false
export MATRIX_FILE="$WORK/.flowset/spec/matrix.json"
export changed_files="docs/3.2-User-Flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if (( ${#issues[@]} == 0 )); then
  pass "A. HAS_MATRIX=false → 섹션 9/10 skip (issues 0건, 하위 호환)"
else
  fail "A. HAS_MATRIX=false인데 issues=${issues[*]}"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-content-4: 섹션 9 (출처 URL/파일 존재 B6) e2e ==="

WORK="$TMP_DIR/work-sources"
mkdir -p "$WORK/.flowset/spec" "$WORK/docs" "$WORK/research/users"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "3.2-User-Flow": {
      "sources": ["research/users/2026.md", "https://example.com/research"],
      "completeness_checklist": []
    }
  }
}
EOF
echo "interview notes" > "$WORK/research/users/2026.md"
echo "# user flow" > "$WORK/docs/3.2-User-Flow.md"

pushd "$WORK" > /dev/null

# E-1. sources 모두 존재 (파일 + URL 정상) → block 없음
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"
export changed_files="docs/3.2-User-Flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE '출처 (URL|파일) (형식 위반|누락) \(B6\)'; then
  pass "E-1. sources 정상 (파일 존재 + URL 형식 OK) → B6 block 없음"
else
  fail "E-1. 정상 sources에서 잘못 block (issues=${issues[*]})"
fi

# E-2. sources 파일 누락 → block
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "3.2-User-Flow": {
      "sources": ["research/missing.md"],
      "completeness_checklist": []
    }
  }
}
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE '출처 파일 누락 \(B6\): section=3\.2-User-Flow'; then
  pass "E-2. sources 파일 누락 → B6 block (출처 파일 누락 — section명 포함)"
else
  fail "E-2. B6 파일 누락 block 미발생 (issues=${issues[*]:-})"
fi

# E-3. URL 정상 형태 → block 없음
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "3.2-User-Flow": {
      "sources": ["https://example.com/research", "http://localhost:8080/docs"],
      "completeness_checklist": []
    }
  }
}
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE '출처 URL 형식 위반 \(B6\)'; then
  pass "E-3. URL 정상 형태 (https/http) → B6 block 없음 (외부 호출 0건)"
else
  fail "E-3. 정상 URL에서 잘못 block (issues=${issues[*]})"
fi

# E-4. content 외 변경 (코드만) → 섹션 9 skip (false positive 0건)
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "3.2-User-Flow": {
      "sources": ["research/missing.md"],
      "completeness_checklist": []
    }
  }
}
EOF
export changed_files="src/api/leaves/route.ts"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
# 섹션 9/10은 content 변경이 없으면 skip → sources 누락이라도 issue 0건
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'B[67]'; then
  pass "E-4. content 외 변경 (src/api) → 섹션 9/10 skip (false positive 0건)"
else
  fail "E-4. content 외 변경에서 잘못 block (issues=${issues[*]})"
fi

# E-5. matrix.sections 비어있음 → 섹션 9 skip
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {}
}
EOF
export changed_files="docs/3.2-User-Flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if (( ${#issues[@]} == 0 )); then
  pass "E-5. matrix.sections 비어있음 → 섹션 9/10 skip (issues 0건)"
else
  fail "E-5. sections 빈 매트릭스에서 issues=${issues[*]}"
fi

popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-content-5: 섹션 10 (completeness_checklist 본문 등장 B7) e2e ==="

WORK="$TMP_DIR/work-checklist"
mkdir -p "$WORK/.flowset/spec" "$WORK/docs"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "3.2-User-Flow": {
      "sources": [],
      "completeness_checklist": ["goal", "flow", "edge-case"]
    }
  }
}
EOF

pushd "$WORK" > /dev/null
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"

# F-1. 항목 모두 본문에 등장 → block 없음
cat > "docs/3.2-User-Flow.md" <<'EOF'
# 3.2 User Flow

## goal
Allow employee to request leave.

## flow
1. submit form → 2. manager approves

## edge-case
Reject overlapping ranges.
EOF
export changed_files="docs/3.2-User-Flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\)'; then
  pass "F-1. 모든 항목 (goal/flow/edge-case) 본문 등장 → B7 block 없음"
else
  fail "F-1. 완전한 본문에서 잘못 block (issues=${issues[*]})"
fi

# F-2. 항목 1개 미등장 → block (본문에 'edge-case' 문자열이 어디에도 없음)
cat > "docs/3.2-User-Flow.md" <<'EOF'
# 3.2 User Flow

## goal
Allow employee to request leave.

## flow
1. submit form -> 2. manager approves
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\): section=3\.2-User-Flow.*edge-case'; then
  pass "F-2. 항목 'edge-case' 미등장 → B7 block (section명 + 항목명 포함)"
else
  fail "F-2. B7 미등장 block 미발생 (issues=${issues[*]:-})"
fi

# F-3. union grep — 다른 변경 파일에 항목 등장하면 PASS
mkdir -p "docs/edges"
cat > "docs/edges/edge.md" <<'EOF'
edge-case description here.
EOF
export changed_files="docs/3.2-User-Flow.md
docs/edges/edge.md"
# 3.2-User-Flow.md에는 edge-case 없지만 docs/edges/edge.md에 있음 → union grep 통과
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\)'; then
  pass "F-3. union grep — 다른 변경 파일에 항목 등장 → B7 block 없음"
else
  fail "F-3. union grep 실패 (issues=${issues[*]})"
fi

# F-4. completeness_checklist 비어있음 → 섹션 10 skip
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "3.2-User-Flow": {
      "sources": [],
      "completeness_checklist": []
    }
  }
}
EOF
export changed_files="docs/3.2-User-Flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if (( ${#issues[@]} == 0 )); then
  pass "F-4. completeness_checklist 비어있음 → 섹션 10 skip (issues 0건)"
else
  fail "F-4. 빈 checklist에서 issues=${issues[*]}"
fi

# F-5. 메타문자 포함 항목 — fixed-string grep 안전 (정규식 폭발 방지)
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "regex-test": {
      "sources": [],
      "completeness_checklist": ["a.b.c", "[bracket]", "(paren)"]
    }
  }
}
EOF
cat > "docs/3.2-User-Flow.md" <<'EOF'
content with a.b.c literal
[bracket] literal
(paren) literal
EOF
export changed_files="docs/3.2-User-Flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\)'; then
  pass "F-5. 메타문자 포함 항목 (a.b.c, [bracket], (paren)) → grep -F fixed-string 안전 매칭"
else
  fail "F-5. fixed-string 매칭 실패 (issues=${issues[*]})"
fi

popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-content-6: 섹션 10 paths 매핑 — 평가자 [MEDIUM] 해소 ==="

# matrix.sections[].paths 옵션 필드: 변경 파일과 paths 교집합만 검사 (false positive 차단)
WORK="$TMP_DIR/work-paths"
mkdir -p "$WORK/.flowset/spec" "$WORK/docs/3.2" "$WORK/docs/data"

pushd "$WORK" > /dev/null
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"

# G-1. paths 정확 일치 + 본문에 모든 항목 등장 → block 없음
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "user-flow": {
      "paths": ["docs/user-flow.md"],
      "completeness_checklist": ["goal", "flow"]
    }
  }
}
EOF
mkdir -p "docs"
cat > "docs/user-flow.md" <<'EOF'
goal: leave request
flow: submit -> approve
EOF
export changed_files="docs/user-flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\)'; then
  pass "G-1. paths 정확 일치 + 본문 모든 항목 등장 → B7 block 없음"
else
  fail "G-1. paths 정확 매칭 정상에서 잘못 block (issues=${issues[*]})"
fi

# G-2. paths 매칭 + 본문 미등장 → block (정확한 section명 + 항목명)
cat > "docs/user-flow.md" <<'EOF'
goal: leave request
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\): section=user-flow.*flow'; then
  pass "G-2. paths 매칭 + 항목 'flow' 미등장 → B7 block (정확한 section명 + 항목명)"
else
  fail "G-2. B7 미등장 block 미발생 (issues=${issues[*]:-})"
fi

# G-3. 디렉토리 prefix 매칭: paths=["docs/3.2/"] → docs/3.2/sub.md 매칭
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "section-3.2": {
      "paths": ["docs/3.2/"],
      "completeness_checklist": ["overview"]
    }
  }
}
EOF
cat > "docs/3.2/sub.md" <<'EOF'
overview: chapter 3.2 introduction
EOF
export changed_files="docs/3.2/sub.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\)'; then
  pass "G-3. 디렉토리 prefix 매칭 (docs/3.2/ → docs/3.2/sub.md) → B7 통과"
else
  fail "G-3. prefix 매칭 실패 (issues=${issues[*]})"
fi

# G-4. **평가자 [MEDIUM] 핵심 해소**: paths 비매칭 section은 skip
# 매트릭스에 user-flow + data-model 2개 section, user-flow.md만 편집
# → data-model의 paths(docs/data-model.md)와 매칭 안 됨 → data-model section skip
# (구버전: data-model의 모든 checklist 항목이 user-flow.md에 강제 → false positive)
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "user-flow": {
      "paths": ["docs/user-flow.md"],
      "completeness_checklist": ["goal", "flow"]
    },
    "data-model": {
      "paths": ["docs/data-model.md"],
      "completeness_checklist": ["entity", "relation"]
    }
  }
}
EOF
cat > "docs/user-flow.md" <<'EOF'
goal: leave request
flow: submit -> approve
EOF
export changed_files="docs/user-flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
# data-model section의 entity/relation은 user-flow.md에 없지만 paths 비매칭이라 skip 되어야 함
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\): section=data-model'; then
  pass "G-4. [MEDIUM 해소] 다른 section(data-model) paths 비매칭 → skip (false positive 0건)"
else
  fail "G-4. data-model section이 false positive로 block (issues=${issues[*]})"
fi

# G-5. paths 있는 + 없는 section 혼재 → 각각 정확히 처리
# legacy(paths 없음)는 후방 호환 union grep, paths 있음은 path 교집합
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "modern": {
      "paths": ["docs/modern.md"],
      "completeness_checklist": ["modern-key"]
    },
    "legacy": {
      "completeness_checklist": ["legacy-key"]
    }
  }
}
EOF
cat > "docs/modern.md" <<'EOF'
modern-key: modern content
legacy-key: also here for legacy union grep
EOF
export changed_files="docs/modern.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
# modern: paths 매칭 + modern-key 등장 → PASS
# legacy: paths 없음 → 모든 변경 파일 union grep → modern.md에 legacy-key 있음 → PASS
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\)'; then
  pass "G-5. 혼재 (paths 있는 modern + 없는 legacy) → 각각 정확히 처리 (block 없음)"
else
  fail "G-5. 혼재 시나리오 잘못 block (issues=${issues[*]})"
fi

# G-6. paths 매칭이지만 변경 안 된 파일은 grep 대상 외
cat > ".flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "user-flow": {
      "paths": ["docs/user-flow.md", "docs/extra.md"],
      "completeness_checklist": ["goal"]
    }
  }
}
EOF
cat > "docs/user-flow.md" <<'EOF'
nothing relevant here
EOF
cat > "docs/extra.md" <<'EOF'
goal: but extra not in changed list
EOF
# extra.md에 goal이 있지만 changed_files에 없으므로 매칭 대상 외 → block
export changed_files="docs/user-flow.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\): section=user-flow.*goal'; then
  pass "G-6. paths 등록되었지만 변경 안 된 파일은 grep 대상 외 → 미등장 정확 감지"
else
  fail "G-6. 변경 외 파일까지 grep해서 false negative (issues=${issues[*]:-})"
fi

popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-content-6b: [LOW-1 해소] 공백 파일명 안전 처리 e2e ==="

WORK="$TMP_DIR/work-whitespace"
mkdir -p "$WORK/.flowset/spec" "$WORK/docs"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "ws-section": {
      "paths": ["docs/with space.md"],
      "completeness_checklist": ["whitespace-key"]
    }
  }
}
EOF
cat > "$WORK/docs/with space.md" <<'EOF'
whitespace-key: documented in whitespace file
EOF

pushd "$WORK" > /dev/null
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"

# G-7. 공백 파일명 + paths 정확 매칭 + 본문 등장 → block 없음
# (이전 버전: `for cf in $changed_content_files`이 IFS로 word-splitting 되어
#  "docs/with"과 "space.md" 2개로 쪼개짐 → paths 매칭 실패 → silent skip false negative)
export changed_files="docs/with space.md"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\)'; then
  pass "G-7. [LOW-1 해소] 공백 파일명 (docs/with space.md) + paths 매칭 → B7 정상 (block 없음)"
else
  fail "G-7. 공백 파일명 처리 실패 (issues=${issues[*]})"
fi

# G-8. 공백 파일명 + 항목 미등장 → 정확한 block (false negative 방어)
cat > "docs/with space.md" <<'EOF'
some unrelated content
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE 'completeness_checklist 미등장 \(B7\): section=ws-section.*whitespace-key'; then
  pass "G-8. 공백 파일명 + 항목 미등장 → 정확한 section/항목명 block (false negative 0건)"
else
  fail "G-8. 공백 파일명 미등장 감지 실패 (issues=${issues[*]:-})"
fi

popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-content-7: 회귀 차단 — 기존 섹션 1~8 + decision JSON 보존 ==="

# 기존 섹션 1~5 헤더 보존 (WI-C3-code 회귀 차단과 동일 항목)
for sec_pattern in '^# 1\. RAG' '^# 2\. E2E' '^# 3\. requirements' '^# 4\. 검증 에이전트' '^# 5\. v3.0: Vault' '^# 6\. 타입 중복' '^# 7\. auth middleware' '^# 8\. Gherkin'; do
  if grep -qE "$sec_pattern" "$STOP_SH"; then
    pass "기존 섹션 헤더 보존: $sec_pattern"
  else
    fail "기존 섹션 헤더 변형됨: $sec_pattern"
  fi
done

# decision JSON 출력 (Stop hook 인터페이스) 보존
if grep -qE '"decision":"block"' "$STOP_SH"; then
  pass "decision:block 출력 보존 (Stop hook 인터페이스)"
else
  fail "decision:block 출력 누락"
fi

# B6/B7 reason이 jq -n으로 escape 안전 — backslash/quote 포함 메시지가 valid JSON
test_reason='출처 파일 누락 (B6): section=3.2 sources="research/x.md" — \(missing\)'
test_json=$(jq -nc --arg reason "$test_reason" '{"decision":"block", reason: $reason}')
if echo "$test_json" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  pass "[학습 32 회귀 차단] B6/B7 reason backslash 포함 → jq -n으로 valid JSON"
else
  fail "[학습 32] decision JSON invalid"
fi

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-C3-content ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-C3-content SMOKE FAILED"
  exit 1
fi
