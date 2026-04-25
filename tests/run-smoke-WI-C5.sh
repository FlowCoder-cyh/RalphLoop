#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-C5.sh — WI-C5 (verify-requirements.sh 매트릭스 대조) 전용 smoke
# 설계 §5 :225 + §7 :312 + §4 :109-117/158-181 Group γ 후속 이행:
#   1. HAS_MATRIX 플래그 (matrix.json 부재 시 매트릭스 대조 skip — 하위 호환)
#   2. PROJECT_CLASS 분기 (code/content/hybrid)
#   3. _emit_missing_entities (code/hybrid 영역 검증)
#   4. _emit_missing_sections (content/hybrid 영역 검증)
#   5. 매트릭스 issue + LLM issue 합산 → exit 2
# 사용: bash tests/run-smoke-WI-C5.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

VERIFY_SH="templates/.flowset/scripts/verify-requirements.sh"

# ============================================================================
echo "=== WI-C5-1: 정적 구조 검증 (HAS_MATRIX + PROJECT_CLASS + 4 함수) ==="

# 1. set -euo pipefail 보존
if grep -qE '^set -euo pipefail' "$VERIFY_SH"; then
  pass "set -euo pipefail 보존 (학습 전이 패턴)"
else
  fail "set -euo pipefail 누락"
fi

# 2. HAS_MATRIX 플래그 신설
if grep -qE '^HAS_MATRIX=true' "$VERIFY_SH" && \
   grep -qE 'HAS_MATRIX=false' "$VERIFY_SH"; then
  pass "HAS_MATRIX 플래그 신설 (true 기본 + false fallback)"
else
  fail "HAS_MATRIX 플래그 누락"
fi

# 3. matrix.json 경로 명시 (.flowset/spec/matrix.json — WI-C1 SSOT)
if grep -qE 'MATRIX_FILE=".flowset/spec/matrix.json"' "$VERIFY_SH"; then
  pass "MATRIX_FILE 경로 (WI-C1 SSOT 정합)"
else
  fail "MATRIX_FILE 경로 누락"
fi

# 4. PROJECT_CLASS 로드 + 기본값 code (하위 호환)
if grep -qE 'PROJECT_CLASS="code"' "$VERIFY_SH" && \
   grep -qE 'source \.flowsetrc' "$VERIFY_SH"; then
  pass "PROJECT_CLASS 기본 code + .flowsetrc 로드 (하위 호환)"
else
  fail "PROJECT_CLASS 로드 누락"
fi

# 5. verify_matrix_against_diff() 함수 정의
if grep -qE '^verify_matrix_against_diff\(\) \{' "$VERIFY_SH"; then
  pass "verify_matrix_against_diff() 함수 정의"
else
  fail "verify_matrix_against_diff() 함수 누락"
fi

# 6. _emit_missing_entities() 함수 정의
if grep -qE '^_emit_missing_entities\(\) \{' "$VERIFY_SH"; then
  pass "_emit_missing_entities() 함수 정의 (entities 영역)"
else
  fail "_emit_missing_entities() 함수 누락"
fi

# 7. _emit_missing_sections() 함수 정의
if grep -qE '^_emit_missing_sections\(\) \{' "$VERIFY_SH"; then
  pass "_emit_missing_sections() 함수 정의 (sections 영역)"
else
  fail "_emit_missing_sections() 함수 누락"
fi

# 8. case "$class" in code/content/hybrid + 알 수 없는 class → exit 1
if grep -qE 'case "\$class" in' "$VERIFY_SH" && \
   grep -qE '    code\)' "$VERIFY_SH" && \
   grep -qE '    content\)' "$VERIFY_SH" && \
   grep -qE '    hybrid\)' "$VERIFY_SH" && \
   grep -qE '알 수 없는 PROJECT_CLASS' "$VERIFY_SH"; then
  pass "case 분기 3-class + 비정상 class 거부"
else
  fail "case 분기 누락 또는 부분 매칭"
fi

# 9. 매트릭스 issue + LLM issue 합산 (TOTAL_FAIL)
if grep -qE 'TOTAL_FAIL=\$\(\(LLM_MISSING \+ LLM_INCOMPLETE \+ MATRIX_ISSUES\)\)' "$VERIFY_SH"; then
  pass "매트릭스 + LLM issue 합산 로직"
else
  fail "issue 합산 로직 누락"
fi

# 10. exit 2 (failure) 보존 — 기존 v3.0 인터페이스 호환
if grep -qE '^  exit 2$' "$VERIFY_SH"; then
  pass "exit 2 보존 (기존 v3.0 Stop hook 인터페이스 호환)"
else
  fail "exit 2 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C5-2: 학습 전이 회귀 방지 (패턴 2/3/4/19) ==="

# 패턴 2: ((var++)) 금지
total_bad=$(sed 's/`[^`]*`//g' "$VERIFY_SH" | sed -E 's/[[:space:]]+#.*$//' | grep -cE '\(\([[:alnum:]_]+\+\+\)\)' || true)
if (( total_bad == 0 )); then
  pass "패턴 2: ((var++)) 사용 0건"
else
  fail "패턴 2: ((var++)) 사용 ${total_bad}건"
fi

# 패턴 3: "${arr[@]/pattern}" 금지
if sed 's/`[^`]*`//g' "$VERIFY_SH" | grep -nE '\$\{[[:alnum:]_]+\[@\]/[^}]+\}' > /dev/null; then
  fail "패턴 3: \${arr[@]/pattern} 사용 발견"
else
  pass "패턴 3: 사용 0건"
fi

# 패턴 4: || echo 0 — 기존 코드는 wc 결과 fallback이라 보존 (line 17 SRC_CHANGED + line 60 LLM_MISSING)
# WI-C5는 || echo "0" 형태(따옴표 + 변수 분리 선언) 사용 — 의도적 회귀 차단 패턴
# 새로 도입한 코드(매트릭스 영역)에서는 0건이어야 함
new_bad_p4=$(sed -n '/# v4.0 (WI-C5)/,/# v3.0: requirements.md LLM 검증/p' "$VERIFY_SH" \
  | grep -cE '\|\| echo 0' || true)
if (( new_bad_p4 == 0 )); then
  pass "패턴 4: WI-C5 신규 코드 \`|| echo 0\` 0건 (\\\"0\\\" 따옴표 형태만 허용)"
else
  fail "패턴 4: WI-C5 신규 코드에 \`|| echo 0\` ${new_bad_p4}건"
fi

# 패턴 19: local x=$(cmd) 금지 (SC2155)
if grep -nE '^[[:space:]]*local[[:space:]]+[[:alnum:]_]+=\$\(' "$VERIFY_SH"; then
  fail "패턴 19: \`local x=\$(cmd)\` 사용 발견"
else
  pass "패턴 19: 사용 0건 (분리 선언 일관)"
fi

# 패턴 23: jq pipeline 일관 — entities/sections status 추출이 동일 패턴
# `.X | to_entries[] | select(.value != "done") | .key`
emit_consistency=$(grep -cE 'select\(\.value != "done"\) \| \.key' "$VERIFY_SH" || true)
if (( emit_consistency >= 2 )); then
  pass "패턴 23: jq status 추출 패턴 일관 (entities + sections 동일 = ${emit_consistency}건)"
else
  fail "패턴 23: jq 추출 패턴 불일치 (${emit_consistency}건)"
fi

# ============================================================================
echo ""
echo "=== WI-C5-3: matrix.json 부재 시 skip (하위 호환 e2e) ==="
TMP_DIR="${TMPDIR:-/tmp}/wi-c5-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# verify_matrix_against_diff 함수만 추출 + 헬퍼 2개도 함께
EXTRACT="$TMP_DIR/extracted.sh"
awk '
  /^verify_matrix_against_diff\(\) \{/ {capture=1}
  /^_emit_missing_entities\(\) \{/ {capture=1}
  /^_emit_missing_sections\(\) \{/ {capture=1}
  capture {print}
  capture && /^\}$/ {capture=0}
' "$VERIFY_SH" > "$EXTRACT"

# 함수 추출 성공 확인
if grep -qE '^verify_matrix_against_diff\(\) \{' "$EXTRACT" && \
   grep -qE '^_emit_missing_entities\(\) \{' "$EXTRACT" && \
   grep -qE '^_emit_missing_sections\(\) \{' "$EXTRACT"; then
  pass "함수 3개 추출 (verify + _emit_entities + _emit_sections)"
else
  fail "함수 추출 실패"
  echo "=== 총: PASS=$PASS FAIL=$FAIL ==="
  exit 1
fi

# 시나리오 A: HAS_MATRIX=false → return 0, 출력 없음
WORK="$TMP_DIR/work-no-matrix"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
HAS_MATRIX=false
MATRIX_FILE="$WORK/.flowset/spec/matrix.json"  # 존재 안 함
CHANGED="src/api/leaves/route.ts"
# shellcheck source=/dev/null
source "$EXTRACT"
output=$(verify_matrix_against_diff 2>&1 || true)
if [[ -z "$output" ]]; then
  pass "A. matrix.json 부재(HAS_MATRIX=false) → 출력 없음 (skip)"
else
  fail "A. HAS_MATRIX=false인데 출력 발생: $output"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C5-4: code class 분기 e2e (matrix.json + git diff 매핑) ==="
WORK="$TMP_DIR/work-code"
mkdir -p "$WORK/.flowset/spec"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "code",
  "auth_framework": "next-auth",
  "auth_patterns": ["getServerSession\\("],
  "entities": {
    "Leave": {
      "crud": {"C": {}, "R": {}, "U": {}, "D": {}},
      "status": {"C": "done", "R": "done", "U": "missing", "D": "missing"}
    },
    "Attendance": {
      "crud": {"C": {}, "R": {}, "U": {}, "D": {}},
      "status": {"C": "done", "R": "done", "U": "done", "D": "done"}
    }
  }
}
EOF

pushd "$WORK" > /dev/null
HAS_MATRIX=true
MATRIX_FILE=".flowset/spec/matrix.json"
CHANGED="src/api/leaves/route.ts"
# shellcheck source=/dev/null
source "$EXTRACT"

# code 분기에서 코드 변경 있음 → Leave는 미완(U/D), Attendance는 완료
output=$(verify_matrix_against_diff 2>&1 || true)
if echo "$output" | grep -qE 'MATRIX_ISSUE: entity=Leave 미완 셀 \[U,D\]' || \
   echo "$output" | grep -qE 'MATRIX_ISSUE: entity=Leave 미완 셀 \[D,U\]'; then
  pass "B. code 분기: Leave 미완 셀 [U,D] 검출"
else
  fail "B. Leave 미완 셀 검출 실패: $output"
fi
# Attendance는 모두 done이므로 issue 없음
if ! echo "$output" | grep -qE 'entity=Attendance'; then
  pass "B. code 분기: Attendance(전수 done) 미보고 (false positive 없음)"
else
  fail "B. Attendance가 잘못 보고됨"
fi

# 코드 변경 없음 → MATRIX_ISSUE 0건
CHANGED=""
output=$(verify_matrix_against_diff 2>&1 || true)
if [[ -z "$output" ]]; then
  pass "C. code 분기: 변경 0건 → 출력 없음 (skip)"
else
  fail "C. 변경 0건인데 출력 발생: $output"
fi

# 변경이 있되 src/ 영역이 아니면 (예: README.md만) → MATRIX_ISSUE 0건
CHANGED="README.md"
output=$(verify_matrix_against_diff 2>&1 || true)
if [[ -z "$output" ]]; then
  pass "D. code 분기: src 외 변경(README만) → 출력 없음"
else
  fail "D. README 변경에서 잘못 출력: $output"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C5-5: content class 분기 e2e ==="
WORK="$TMP_DIR/work-content"
mkdir -p "$WORK/.flowset/spec"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "content",
  "sections": {
    "3.2-User-Flow": {
      "status": {"draft": "done", "review": "pending", "approve": "missing"}
    },
    "4.1-API-Spec": {
      "status": {"draft": "done", "review": "done", "approve": "done"}
    }
  }
}
EOF

pushd "$WORK" > /dev/null
HAS_MATRIX=true
MATRIX_FILE=".flowset/spec/matrix.json"
CHANGED="docs/3.2-user-flow.md"
# shellcheck source=/dev/null
source "$EXTRACT"

output=$(verify_matrix_against_diff 2>&1 || true)
# 미완 셀: 3.2-User-Flow의 review,approve
# (jq 출력 순서는 보장 안 됨 — review가 먼저 나오거나 approve가 먼저)
if echo "$output" | grep -qE 'MATRIX_ISSUE: section=3\.2-User-Flow 미완 셀 \[(review,approve|approve,review)\]'; then
  pass "E. content 분기: 3.2-User-Flow 미완 셀 [review,approve] 검출"
else
  fail "E. 3.2-User-Flow 미완 셀 검출 실패: $output"
fi
# 4.1-API-Spec는 전수 done → 미보고
if ! echo "$output" | grep -qE 'section=4\.1-API-Spec'; then
  pass "E. content 분기: 4.1-API-Spec(전수 done) 미보고"
else
  fail "E. 4.1-API-Spec 잘못 보고됨"
fi

# content 변경 없음 (코드만 변경) → skip
CHANGED="src/api/leaves/route.ts"
output=$(verify_matrix_against_diff 2>&1 || true)
if [[ -z "$output" ]]; then
  pass "F. content 분기: content 변경 0건(code만) → 출력 없음"
else
  fail "F. 코드만 변경인데 content 분기에서 출력: $output"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C5-6: hybrid class 분기 e2e (양쪽 동시) ==="
WORK="$TMP_DIR/work-hybrid"
mkdir -p "$WORK/.flowset/spec"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "hybrid",
  "entities": {
    "Leave": {
      "crud": {"C": {}, "R": {}, "U": {}, "D": {}},
      "status": {"C": "done", "R": "missing", "U": "missing", "D": "missing"}
    }
  },
  "sections": {
    "3.2-User-Flow": {
      "status": {"draft": "done", "review": "missing", "approve": "missing"}
    }
  }
}
EOF

pushd "$WORK" > /dev/null
HAS_MATRIX=true
MATRIX_FILE=".flowset/spec/matrix.json"
# 양쪽 영역 동시 변경
CHANGED="src/api/leaves/route.ts
docs/3.2-user-flow.md"
# shellcheck source=/dev/null
source "$EXTRACT"

output=$(verify_matrix_against_diff 2>&1 || true)
# entity Leave + section 3.2-User-Flow 둘 다 보고
if echo "$output" | grep -qE 'entity=Leave' && \
   echo "$output" | grep -qE 'section=3\.2-User-Flow'; then
  pass "G. hybrid 분기: entity + section 둘 다 미완 셀 검출"
else
  fail "G. hybrid 양쪽 영역 동시 검출 실패: $output"
fi

# 코드만 변경 → entity만 보고 (section 미보고)
CHANGED="src/api/leaves/route.ts"
output=$(verify_matrix_against_diff 2>&1 || true)
if echo "$output" | grep -qE 'entity=Leave' && \
   ! echo "$output" | grep -qE 'section=3\.2-User-Flow'; then
  pass "H. hybrid: 코드만 변경 → entity만 보고 (section skip)"
else
  fail "H. hybrid 코드만 변경에서 section 잘못 보고: $output"
fi

# content만 변경 → section만 보고
CHANGED="docs/3.2-user-flow.md"
output=$(verify_matrix_against_diff 2>&1 || true)
if echo "$output" | grep -qE 'section=3\.2-User-Flow' && \
   ! echo "$output" | grep -qE 'entity=Leave'; then
  pass "I. hybrid: content만 변경 → section만 보고 (entity skip)"
else
  fail "I. hybrid content만 변경에서 entity 잘못 보고: $output"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C5-7: 비정상 class 거부 e2e ==="
WORK="$TMP_DIR/work-bad-class"
mkdir -p "$WORK/.flowset/spec"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "unknown_class",
  "entities": {}
}
EOF

pushd "$WORK" > /dev/null
HAS_MATRIX=true
MATRIX_FILE=".flowset/spec/matrix.json"
CHANGED="src/api/route.ts"
# shellcheck source=/dev/null
source "$EXTRACT"

# 비정상 class → return 1 + ERROR 메시지
# set -e + return 1 조합 + 파이프라인 SIGPIPE 회피 위해 output 캡처 후 grep
set +e
bad_output=$(verify_matrix_against_diff 2>&1)
bad_rc=$?
set -e

if echo "$bad_output" | grep -qE 'ERROR: 알 수 없는 PROJECT_CLASS'; then
  pass "J. 비정상 class → ERROR 메시지 출력"
else
  fail "J. 비정상 class 거부 실패 (output: $bad_output, rc: $bad_rc)"
fi
if (( bad_rc != 0 )); then
  pass "J. 비정상 class → return 1 (rc=$bad_rc, set -e 친화)"
else
  fail "J. 비정상 class에서 return 0 (잘못)"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-C5 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-C5 SMOKE FAILED"
  exit 1
fi
