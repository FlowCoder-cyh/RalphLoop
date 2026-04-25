#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-C3-code.sh — WI-C3-code (stop-rag-check.sh code 분기) 전용 smoke
# 설계 §5 :224 + §4 :109-117 (B2/B3/B4 차단) Group γ 후속 이행:
#   1. HAS_MATRIX 플래그 (matrix.json 부재 시 신규 섹션 6/7/8 skip — 하위 호환)
#   2. 섹션 6: 타입 중복 검사 (B3) — interface/type/class 동일 이름 다른 파일 2개+ → block
#   3. 섹션 7: auth middleware 검사 (B2) — src/api/** 변경 시 auth_patterns join | grep
#   4. 섹션 8: Gherkin↔테스트 매칭 (B4) — parse-gherkin.sh로 total_count + 이름 부분 매칭
#   5. 기존 섹션 1~5 동작 보존 (가드 없음)
# 사용: bash tests/run-smoke-WI-C3-code.sh

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
PARSER_SH="templates/.flowset/scripts/parse-gherkin.sh"

# ============================================================================
echo "=== WI-C3-code-1: 정적 구조 검증 (HAS_MATRIX + 신규 섹션 6/7/8) ==="

# 1. set -euo pipefail 보존
if grep -qE '^set -euo pipefail' "$STOP_SH"; then
  pass "set -euo pipefail 보존"
else
  fail "set -euo pipefail 누락"
fi

# 2. HAS_MATRIX 플래그 신설 (WI-C5/C6와 동일 SSOT)
if grep -qE '^HAS_MATRIX=true' "$STOP_SH" && \
   grep -qE 'HAS_MATRIX=false' "$STOP_SH"; then
  pass "HAS_MATRIX 플래그 신설 (true 기본 + false fallback)"
else
  fail "HAS_MATRIX 플래그 누락"
fi

# 3. MATRIX_FILE 경로 (.flowset/spec/matrix.json — WI-C1 SSOT)
if grep -qE 'MATRIX_FILE=".flowset/spec/matrix.json"' "$STOP_SH"; then
  pass "MATRIX_FILE 경로 (WI-C1 SSOT 정합)"
else
  fail "MATRIX_FILE 경로 누락"
fi

# 4. 섹션 6 헤더 (타입 중복 검사 B3)
if grep -qE '^# 6\. 타입 중복 검사 \(B3' "$STOP_SH"; then
  pass "섹션 6 헤더: 타입 중복 검사 (B3)"
else
  fail "섹션 6 헤더 누락"
fi

# 5. 섹션 7 헤더 (auth middleware B2)
if grep -qE '^# 7\. auth middleware 검사 \(B2' "$STOP_SH"; then
  pass "섹션 7 헤더: auth middleware (B2)"
else
  fail "섹션 7 헤더 누락"
fi

# 6. 섹션 8 헤더 (Gherkin↔테스트 매칭 B4)
if grep -qE '^# 8\. Gherkin.*테스트 매칭 \(B4' "$STOP_SH"; then
  pass "섹션 8 헤더: Gherkin↔테스트 매칭 (B4)"
else
  fail "섹션 8 헤더 누락"
fi

# 7. 섹션 6/7/8 모두 if HAS_MATRIX 가드 안 (matrix.json 부재 시 skip)
guard_count=$(grep -cE 'if \[\[ "\$HAS_MATRIX" == "true"' "$STOP_SH" || true)
# 섹션 6/7/8 = 3개 + 섹션 8은 추가 조건 (parse-gherkin.sh 존재)이라 동일 형태 1번
if (( guard_count >= 3 )); then
  pass "신규 섹션 6/7/8 모두 HAS_MATRIX 가드 (${guard_count}회 등장 — 3개+)"
else
  fail "HAS_MATRIX 가드 부족 (${guard_count}회)"
fi

# 8. 섹션 4와 섹션 5 사이에 섹션 6/7/8 위치 (설계 §5 :224 삽입 위치)
section4_line=$(grep -nE '^# 4\. 검증 에이전트' "$STOP_SH" | head -1 | cut -d: -f1 || true)
section5_line=$(grep -nE '^# 5\. v3.0: Vault' "$STOP_SH" | head -1 | cut -d: -f1 || true)
section6_line=$(grep -nE '^# 6\. 타입 중복' "$STOP_SH" | head -1 | cut -d: -f1 || true)
section7_line=$(grep -nE '^# 7\. auth middleware' "$STOP_SH" | head -1 | cut -d: -f1 || true)
section8_line=$(grep -nE '^# 8\. Gherkin' "$STOP_SH" | head -1 | cut -d: -f1 || true)
if [[ -n "$section4_line" && -n "$section5_line" && -n "$section6_line" && \
      "$section6_line" -gt "$section4_line" && "$section8_line" -lt "$section5_line" ]]; then
  pass "섹션 6/7/8 위치: 섹션 4(${section4_line}) < 6(${section6_line})/7(${section7_line})/8(${section8_line}) < 5(${section5_line})"
else
  fail "섹션 위치 위반 (4=$section4_line 6=$section6_line 7=$section7_line 8=$section8_line 5=$section5_line)"
fi

# 9. parse-gherkin.sh 호출 (WI-C3p 신설 의존)
if grep -qE 'bash \.flowset/scripts/parse-gherkin\.sh' "$STOP_SH"; then
  pass "parse-gherkin.sh 호출 (WI-C3p 의존)"
else
  fail "parse-gherkin.sh 호출 누락"
fi

# 10. jq 사용 (auth_patterns + entities tests 추출)
if grep -qE 'jq -r .\(\.auth_patterns' "$STOP_SH" && \
   grep -qE 'jq -r --arg ff' "$STOP_SH"; then
  pass "jq 추출 (auth_patterns + entities 매칭)"
else
  fail "jq 추출 패턴 누락"
fi

# 11. 정규식 false positive 차단 (학습 28): src/api 디렉토리 AND 코드 확장자
if grep -qE 'grep -E .\^src/\(api\|app/api\)/\.\*\\\.\(ts\|tsx\|js\|jsx\|py\|go\|rs\)\$.' "$STOP_SH"; then
  pass "[학습 28] auth API 분류: 디렉토리 AND 확장자 (false positive 차단)"
else
  fail "[학습 28] auth API 정규식 형태 위반"
fi

# 12. test 경로 제외 (학습 28 차원 — 타입 중복에서 test 파일 false positive 방지)
if grep -qE "grep -vE '\(\\^\|/\)\(tests\?\|spec\|__tests__\|e2e\)/'" "$STOP_SH" || \
   grep -qE 'tests\?\|spec\|__tests__\|e2e' "$STOP_SH"; then
  pass "[학습 28] 타입 중복: test 경로 제외 (false positive 차단)"
else
  fail "[학습 28] 타입 중복 test 경로 제외 누락"
fi

# 13. 기존 섹션 1~5 동작 보존 (가드 없음)
# 섹션 1 (RAG)이 그대로 있고 HAS_MATRIX 가드 없는 형태
if awk '/^# 1\. RAG/,/^# 2\. E2E/' "$STOP_SH" | grep -qE 'rag_needed=false'; then
  pass "기존 섹션 1 (RAG) 보존 + HAS_MATRIX 가드 없음 (하위 호환)"
else
  fail "기존 섹션 1 변형됨"
fi

# ============================================================================
echo ""
echo "=== WI-C3-code-2: 학습 전이 회귀 방지 (패턴 2/3/19/27) ==="

# 패턴 2: ((var++)) 금지 (bash 영역만 — awk는 별개)
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

# 패턴 19: local x=$(cmd) 금지 — 단 stop-rag-check은 함수 미사용, top-level 변수만
if grep -nE '^[[:space:]]*local[[:space:]]+[[:alnum:]_]+=\$\(' "$STOP_SH"; then
  fail "패턴 19: local x=\$(cmd) 사용 발견"
else
  pass "패턴 19: 사용 0건"
fi

# 패턴 27: Stop hook 컨텍스트 — 신규 섹션 6/7/8이 SessionStart 같은 silent skip 아닌 block 결과 (issues+= 누적)
# verify-requirements와 다름: stop hook은 issues 누적 후 decision: block 출력 (exit 0 + JSON)
if grep -qE 'issues\+=\(.*B3' "$STOP_SH" && \
   grep -qE 'issues\+=\(.*B2' "$STOP_SH" && \
   grep -qE 'issues\+=\(.*B4' "$STOP_SH"; then
  pass "[학습 27] Stop hook 컨텍스트: issues+= 누적 (block 결과 — silent skip 아님)"
else
  fail "[학습 27] issues+= 누적 패턴 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C3-code-3: matrix.json 부재 시 신규 섹션 6/7/8 skip e2e ==="
TMP_DIR="${TMPDIR:-/tmp}/wi-c3code-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# 신규 섹션 6/7/8을 awk로 추출 (섹션 6 헤더 ~ 섹션 5 헤더 직전)
EXTRACT="$TMP_DIR/sections_678.sh"
awk '
  /^# 6\. 타입 중복 검사/ { capture = 1 }
  /^# 5\. v3.0: Vault/ { capture = 0 }
  capture { print }
' "$STOP_SH" > "$EXTRACT"

if grep -q "타입 중복 검사" "$EXTRACT" && \
   grep -q "auth middleware" "$EXTRACT" && \
   grep -q "Gherkin" "$EXTRACT"; then
  pass "섹션 6/7/8 추출 성공"
else
  fail "섹션 추출 실패"
  echo "=== 총: PASS=$PASS FAIL=$FAIL ==="
  exit 1
fi

# 시나리오 A: HAS_MATRIX=false → 섹션 6/7/8 모두 skip → issues 0건
WORK="$TMP_DIR/work-no-matrix"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
export HAS_MATRIX=false
export MATRIX_FILE="$WORK/.flowset/spec/matrix.json"
export changed_files="src/api/leaves/route.ts"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if (( ${#issues[@]} == 0 )); then
  pass "A. HAS_MATRIX=false → 섹션 6/7/8 모두 skip (issues 0건, 하위 호환)"
else
  fail "A. HAS_MATRIX=false인데 issues=${issues[*]}"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-code-4: 섹션 7 (auth middleware B2) e2e ==="

WORK="$TMP_DIR/work-auth"
mkdir -p "$WORK/.flowset/spec" "$WORK/src/api/leaves"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "code",
  "auth_framework": "next-auth",
  "auth_patterns": ["getServerSession\\(", "auth\\(\\)"],
  "entities": {}
}
EOF

# B-1. auth 패턴 매칭 안 됨 → block
cat > "$WORK/src/api/leaves/route.ts" <<'EOF'
export async function POST() {
  return new Response("OK")  // auth 누락
}
EOF
pushd "$WORK" > /dev/null
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"
export changed_files="src/api/leaves/route.ts"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if (( ${#issues[@]} >= 1 )) && printf '%s\n' "${issues[@]}" | grep -qE 'auth middleware 누락 \(B2\)'; then
  pass "B-1. auth 패턴 매칭 실패 → B2 block (issue 누적)"
else
  fail "B-1. B2 block 미발생 (issues=${issues[*]:-})"
fi

# B-2. auth 패턴 매칭 됨 → block 없음
cat > "$WORK/src/api/leaves/route.ts" <<'EOF'
import { getServerSession } from 'next-auth'
export async function POST() {
  const session = await getServerSession()
  return new Response("OK")
}
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE 'auth middleware 누락 \(B2\)'; then
  pass "B-2. auth 패턴 매칭 → B2 block 없음 (false positive 0건)"
else
  fail "B-2. auth 정상인데 B2 block 발생 (issues=${issues[*]})"
fi

# B-3. matrix.auth_patterns[] 비어있음 → 검증 불가 issue
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{"schema_version":"v2","class":"code","auth_patterns":[],"entities":{}}
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE 'auth middleware 검증 불가'; then
  pass "B-3. auth_patterns[] 비어있음 → '검증 불가' issue (B2 안전망)"
else
  fail "B-3. 검증 불가 issue 미생성 (issues=${issues[*]:-})"
fi

# B-4. src/api 외 변경 (예: src/components/) → 검증 skip
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{"schema_version":"v2","class":"code","auth_patterns":["getServerSession\\("],"entities":{}}
EOF
export changed_files="src/components/Button.tsx"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if (( ${#issues[@]} == 0 )); then
  pass "B-4. src/api 외 변경 → 섹션 7 skip (false positive 0건)"
else
  fail "B-4. src/api 외 변경에서 issues=${issues[*]}"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-code-5: 섹션 6 (타입 중복 B3) e2e ==="

WORK="$TMP_DIR/work-types"
mkdir -p "$WORK/.flowset/spec" "$WORK/src/api" "$WORK/src/lib" "$WORK/tests"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{"schema_version":"v2","class":"code","entities":{}}
EOF

# C-1. 같은 interface 이름이 다른 파일 2개 → block
cat > "$WORK/src/api/leave.ts" <<'EOF'
export interface Leave {
  id: string
}
EOF
cat > "$WORK/src/lib/leave.ts" <<'EOF'
export interface Leave {
  date: Date
}
EOF
pushd "$WORK" > /dev/null
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"
export changed_files="src/api/leave.ts
src/lib/leave.ts"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE '타입 중복 감지 \(B3\): Leave'; then
  pass "C-1. 같은 interface Leave 이름 다른 파일 2개 → B3 block"
else
  fail "C-1. B3 block 미발생 (issues=${issues[*]:-})"
fi

# C-2. test 파일은 제외 (false positive 차단)
cat > "$WORK/tests/leave.test.ts" <<'EOF'
interface Leave {  // test 파일이라 제외되어야 함
  id: string
}
EOF
export changed_files="src/api/leave.ts
tests/leave.test.ts"
# src/api/leave.ts와 tests/leave.test.ts 둘 다 Leave 선언 → tests/는 제외 → 1개만 → block 없음
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE '타입 중복 감지 \(B3\)'; then
  pass "C-2. test 경로(tests/) 제외 → B3 block 없음 (false positive 차단)"
else
  fail "C-2. test 경로에서 잘못 block (issues=${issues[*]})"
fi

# C-3. 변경 없음 → block 없음
export changed_files=""
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if (( ${#issues[@]} == 0 )); then
  pass "C-3. 변경 없음 → 섹션 6 skip (issues 0건)"
else
  fail "C-3. 변경 없음에서 issues=${issues[*]}"
fi

# C-4. 동일 파일 안 같은 이름 (수정만) → block 없음
cat > "$WORK/src/api/single.ts" <<'EOF'
export interface Foo {
  a: string
}
EOF
export changed_files="src/api/single.ts"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE '타입 중복 감지 \(B3\): Foo'; then
  pass "C-4. 단일 파일 단일 선언 → B3 block 없음"
else
  fail "C-4. 단일 선언에서 잘못 block (issues=${issues[*]})"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-code-6: 섹션 8 (Gherkin↔테스트 매칭 B4) e2e ==="

WORK="$TMP_DIR/work-gherkin"
mkdir -p "$WORK/.flowset/spec/gherkin" "$WORK/.flowset/scripts" "$WORK/tests"
cp "$REPO_ROOT/$PARSER_SH" "$WORK/.flowset/scripts/parse-gherkin.sh"

# matrix.entities[].gherkin/tests 매핑
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "code",
  "entities": {
    "Leave": {
      "gherkin": [".flowset/spec/gherkin/leave.feature"],
      "tests": ["tests/leave.test.ts"]
    }
  }
}
EOF

cat > "$WORK/.flowset/spec/gherkin/leave.feature" <<'EOF'
Feature: Leave

  Scenario: Create leave request
    When I submit
    Then OK

  Scenario: Approve as manager
    When I approve
    Then OK
EOF

# D-1. 정확히 매칭 (Gherkin 2 + tests 2 + 이름 부분 매칭)
cat > "$WORK/tests/leave.test.ts" <<'EOF'
test('create leave request as employee', () => {})
test('approve as manager flow', () => {})
EOF

pushd "$WORK" > /dev/null
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"
export changed_files=".flowset/spec/gherkin/leave.feature"
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if ! printf '%s\n' "${issues[@]:-}" | grep -qE '(Gherkin↔테스트 개수 불일치|Gherkin 시나리오 미매핑) \(B4\)'; then
  pass "D-1. 정확히 매칭 (Gherkin 2 = tests 2, 이름 부분 매칭) → B4 block 없음"
else
  fail "D-1. 정상 매칭에서 잘못 block (issues=${issues[*]})"
fi

# D-2. 개수 불일치 (tests 1개만)
cat > "$WORK/tests/leave.test.ts" <<'EOF'
test('create leave request as employee', () => {})
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE '개수 불일치 \(B4\)'; then
  pass "D-2. Gherkin 2 vs tests 1 → B4 개수 불일치 block"
else
  fail "D-2. B4 개수 불일치 미block (issues=${issues[*]:-})"
fi

# D-3. 이름 부분 매칭 실패 (개수 같지만 이름 다름)
cat > "$WORK/tests/leave.test.ts" <<'EOF'
test('completely unrelated name one', () => {})
test('completely unrelated name two', () => {})
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if printf '%s\n' "${issues[@]:-}" | grep -qE '시나리오 미매핑 \(B4\)'; then
  pass "D-3. 개수 같지만 이름 매칭 실패 → B4 시나리오 미매핑 block"
else
  fail "D-3. B4 이름 매칭 미block (issues=${issues[*]:-})"
fi

# D-4. matrix에 entity gherkin 매핑 없음 → 섹션 8 skip (해당 entity 0건)
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{"schema_version":"v2","class":"code","entities":{}}
EOF
issues=()
# shellcheck source=/dev/null
source "$EXTRACT"
if (( ${#issues[@]} == 0 )); then
  pass "D-4. matrix entity 매핑 없음 → 섹션 8 skip (false positive 0건)"
else
  fail "D-4. entity 매핑 없음에서 issues=${issues[*]}"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C3-code-7: 전체 스크립트 실행 — 기존 섹션 1~5 보존 회귀 차단 ==="

# 기존 섹션 1~5가 변형되지 않았는지 라벨 grep
if grep -qE '^# 1\. RAG 업데이트 검사' "$STOP_SH"; then
  pass "기존 섹션 1 헤더 보존: RAG 업데이트 검사"
else
  fail "기존 섹션 1 헤더 변형됨"
fi
if grep -qE '^# 2\. E2E 테스트 품질 검사' "$STOP_SH"; then
  pass "기존 섹션 2 헤더 보존: E2E 테스트 품질 검사"
else
  fail "기존 섹션 2 헤더 변형됨"
fi
if grep -qE '^# 3\. requirements\.md 수정 감지' "$STOP_SH"; then
  pass "기존 섹션 3 헤더 보존: requirements.md 수정 감지"
else
  fail "기존 섹션 3 헤더 변형됨"
fi
if grep -qE '^# 4\. 검증 에이전트 트리거' "$STOP_SH"; then
  pass "기존 섹션 4 헤더 보존: 검증 에이전트 트리거"
else
  fail "기존 섹션 4 헤더 변형됨"
fi
if grep -qE '^# 5\. v3.0: Vault 세션 맥락 저장' "$STOP_SH"; then
  pass "기존 섹션 5 헤더 보존: Vault 세션 맥락 저장"
else
  fail "기존 섹션 5 헤더 변형됨"
fi

# 결과 출력 (decision: block) 보존
if grep -qE '"decision":"block"' "$STOP_SH"; then
  pass "decision:block 출력 보존 (Stop hook 인터페이스)"
else
  fail "decision:block 출력 누락"
fi

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-C3-code ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-C3-code SMOKE FAILED"
  exit 1
fi
