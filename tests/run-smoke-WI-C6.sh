#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-C6.sh — WI-C6 (session-start-vault.sh 미완 셀 우선 주입) 전용 smoke
# 설계 §5 :226 + §7 :313 + §4 :117 (B5 차단) Group γ 후속 이행:
#   1. HAS_MATRIX 플래그 (matrix.json 부재 시 미완 셀 주입 skip — 하위 호환)
#   2. PROJECT_CLASS 분기 (code/content/hybrid)
#   3. _emit_missing_entities (code/hybrid 영역 추출 — WI-C5 jq 패턴 재사용)
#   4. _emit_missing_sections (content/hybrid 영역 추출 — WI-C5 jq 패턴 재사용)
#   5. 비정상 class에서 silent skip + stderr 경고 (SessionStart 컨텍스트 — verify와 다름)
#   6. 미완 셀 출력은 vault context 가장 앞에 마크다운 섹션으로 prepend
# 사용: bash tests/run-smoke-WI-C6.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

VAULT_SH="templates/.flowset/scripts/session-start-vault.sh"

# ============================================================================
echo "=== WI-C6-1: 정적 구조 검증 (HAS_MATRIX + PROJECT_CLASS + 3 함수 + prepend) ==="

# 1. set -euo pipefail 보존 (학습 전이 패턴)
if grep -qE '^set -euo pipefail' "$VAULT_SH"; then
  pass "set -euo pipefail 보존"
else
  fail "set -euo pipefail 누락"
fi

# 2. HAS_MATRIX 플래그 신설
if grep -qE '^HAS_MATRIX=true' "$VAULT_SH" && \
   grep -qE 'HAS_MATRIX=false' "$VAULT_SH"; then
  pass "HAS_MATRIX 플래그 신설 (true 기본 + false fallback)"
else
  fail "HAS_MATRIX 플래그 누락"
fi

# 3. matrix.json 경로 (.flowset/spec/matrix.json — WI-C1 SSOT)
if grep -qE 'MATRIX_FILE=".flowset/spec/matrix.json"' "$VAULT_SH"; then
  pass "MATRIX_FILE 경로 (WI-C1 SSOT 정합)"
else
  fail "MATRIX_FILE 경로 누락"
fi

# 4. PROJECT_CLASS 기본값 code (하위 호환)
if grep -qE 'PROJECT_CLASS="\$\{PROJECT_CLASS:-code\}"' "$VAULT_SH"; then
  pass "PROJECT_CLASS 기본 code (.flowsetrc 미설정 호환)"
else
  fail "PROJECT_CLASS 기본값 누락"
fi

# 5. _emit_missing_entities() 함수 정의 (WI-C5 패턴 차용)
if grep -qE '^_emit_missing_entities\(\) \{' "$VAULT_SH"; then
  pass "_emit_missing_entities() 함수 정의 (entities)"
else
  fail "_emit_missing_entities() 함수 누락"
fi

# 6. _emit_missing_sections() 함수 정의 (WI-C5 패턴 차용)
if grep -qE '^_emit_missing_sections\(\) \{' "$VAULT_SH"; then
  pass "_emit_missing_sections() 함수 정의 (sections)"
else
  fail "_emit_missing_sections() 함수 누락"
fi

# 7. emit_missing_cells() 함수 정의 (case 분기 진입점)
if grep -qE '^emit_missing_cells\(\) \{' "$VAULT_SH"; then
  pass "emit_missing_cells() 진입점 함수 정의"
else
  fail "emit_missing_cells() 함수 누락"
fi

# 8. case 3-class 분기 + 비정상 class silent skip
if grep -qE 'case "\$class" in' "$VAULT_SH" && \
   grep -qE '    code\)' "$VAULT_SH" && \
   grep -qE '    content\)' "$VAULT_SH" && \
   grep -qE '    hybrid\)' "$VAULT_SH"; then
  pass "case 3-class 분기 (code/content/hybrid)"
else
  fail "case 3-class 분기 누락"
fi

# 9. 비정상 class에서 silent skip (return 0) + stderr 경고
# WARN 메시지 + return 0 (verify-requirements의 return 1과 명확히 다름)
if grep -qE 'WARN: session-start-vault' "$VAULT_SH"; then
  pass "비정상 class WARN 메시지 (stderr 경고)"
else
  fail "비정상 class WARN 메시지 누락"
fi

# 10. 미완 셀 출력은 context 가장 앞 (state.md 읽기 위)
# 'VAULT MATRIX MISSING' 라벨이 'VAULT STATE' 라벨보다 먼저 등장해야 함
matrix_line=$(grep -nE 'VAULT MATRIX MISSING' "$VAULT_SH" | head -1 | cut -d: -f1)
state_line=$(grep -nE 'VAULT STATE' "$VAULT_SH" | head -1 | cut -d: -f1)
if [[ -n "$matrix_line" && -n "$state_line" && "$matrix_line" -lt "$state_line" ]]; then
  pass "미완 셀 prepend (VAULT MATRIX MISSING이 VAULT STATE보다 먼저)"
else
  fail "미완 셀 prepend 순서 위반 (matrix=$matrix_line state=$state_line)"
fi

# 11. 마크다운 섹션 형식 (## ... 미완 매트릭스 셀 (자동 주입))
# GNU grep 3.0이 4-byte UTF-8 이모지(🚨, U+1F6A8) 매칭 실패하는 환경 회피 — 한글+ASCII만으로 검증
# 의도: 마크다운 H2 헤더(`## `) + "미완 매트릭스 셀 (자동 주입)" 라벨이 vault context에 자동 prepend되는지
if grep -qE '^## .+ 미완 매트릭스 셀 \(자동 주입\)' "$VAULT_SH"; then
  pass "마크다운 섹션 형식 (## ... 미완 매트릭스 셀 (자동 주입))"
else
  fail "마크다운 섹션 헤더 누락 (## ... 미완 매트릭스 셀 (자동 주입))"
fi

# 12. SOURCE 변수가 미완 셀 라벨에 포함 (compact/startup/resume 추적)
if grep -qE 'VAULT MATRIX MISSING.*source: \$\{SOURCE\}' "$VAULT_SH"; then
  pass "SOURCE(startup/compact/resume) 라벨 포함 (B5 컨텍스트 추적)"
else
  fail "SOURCE 라벨 누락"
fi

# 13. PostCompact 호환 — 기존 'compact' source 처리 보존 + 미완 셀 주입은 모든 source에서 동작
# emit_missing_cells 호출이 SOURCE 분기 밖에 있어야 함 (모든 source에서 prepend)
# emit_missing_cells 호출 라인의 들여쓰기가 함수 안이 아닌 top-level이어야 함
if grep -qE '^missing_cells_output=\$\(emit_missing_cells' "$VAULT_SH"; then
  pass "emit_missing_cells 호출이 top-level (모든 SOURCE에서 동작)"
else
  fail "emit_missing_cells 호출이 SOURCE 조건 분기 안에 갇힘 (B5 위반)"
fi

# ============================================================================
echo ""
echo "=== WI-C6-2: 학습 전이 회귀 방지 (패턴 2/3/4/19/27/28) ==="

# 패턴 2: ((var++)) 금지
total_bad=$(sed 's/`[^`]*`//g' "$VAULT_SH" | sed -E 's/[[:space:]]+#.*$//' | grep -cE '\(\([[:alnum:]_]+\+\+\)\)' || true)
if (( total_bad == 0 )); then
  pass "패턴 2: ((var++)) 사용 0건"
else
  fail "패턴 2: ((var++)) 사용 ${total_bad}건"
fi

# 패턴 3: "${arr[@]/pattern}" 금지
if sed 's/`[^`]*`//g' "$VAULT_SH" | grep -nE '\$\{[[:alnum:]_]+\[@\]/[^}]+\}' > /dev/null; then
  fail "패턴 3: \${arr[@]/pattern} 사용 발견"
else
  pass "패턴 3: 사용 0건"
fi

# 패턴 19: local x=$(cmd) 금지 (SC2155)
if grep -nE '^[[:space:]]*local[[:space:]]+[[:alnum:]_]+=\$\(' "$VAULT_SH"; then
  fail "패턴 19: \`local x=\$(cmd)\` 사용 발견"
else
  pass "패턴 19: 사용 0건 (분리 선언 일관)"
fi

# 패턴 23: jq pipeline 일관 — entities/sections 동일 패턴
emit_consistency=$(grep -cE 'select\(\.value != "done"\) \| \.key' "$VAULT_SH" || true)
if (( emit_consistency >= 2 )); then
  pass "패턴 23: jq status 추출 패턴 일관 (entities + sections 동일 = ${emit_consistency}건)"
else
  fail "패턴 23: jq 추출 패턴 불일치 (${emit_consistency}건)"
fi

# 패턴 24: 정의 + 호출 양방향 grep (stub 회귀 차단)
# emit_missing_cells 정의 + 호출 둘 다 있어야 함
if grep -qE '^emit_missing_cells\(\) \{' "$VAULT_SH" && \
   grep -qE '\$\(emit_missing_cells' "$VAULT_SH"; then
  pass "패턴 24: emit_missing_cells 정의 + 호출 양방향 존재 (stub 회귀 차단)"
else
  fail "패턴 24: emit_missing_cells 정의/호출 한쪽 누락"
fi

# 패턴 27: SessionStart 컨텍스트 — 비정상 class에서 return 0 (silent skip + 경고)
# verify-requirements의 return 1 + exit 2와 다른 컨텍스트
# emit_missing_cells의 default case가 return 0이어야 함 (hook 자체 차단 금지)
default_case_return=$(awk '
  /^emit_missing_cells\(\) \{/ {capture=1}
  capture && /\*\)/ {in_default=1; next}
  capture && in_default && /return [01]/ {print; in_default=0}
  capture && /^\}$/ {capture=0}
' "$VAULT_SH")
if echo "$default_case_return" | grep -qE 'return 0'; then
  pass "패턴 27 차이 인지: default case return 0 (SessionStart silent skip — verify의 return 1과 다름)"
else
  fail "패턴 27 차이 인지: default case가 return 0이 아님: '$default_case_return'"
fi

# 패턴 27 추가: 미완 셀 함수 실패가 SessionStart 자체를 차단하지 않음
# emit_missing_cells 호출에 || true 또는 stderr 마스킹이 있어야 함 (hook 차단 금지)
if grep -qE 'missing_cells_output=\$\(emit_missing_cells.*\|\| true\)' "$VAULT_SH"; then
  pass "패턴 27 차이 인지: emit_missing_cells 실패 시 || true (SessionStart 차단 금지 — 컨텍스트 적합)"
else
  fail "패턴 27 차이 인지: emit_missing_cells 호출에 fallback 누락"
fi

# 패턴 28: WI-C6는 정규식 매칭 없음 (file path 분류 안 함)
# matrix.json 셀 추출은 jq로 직접 처리 — false positive 없음
# 단, 본 스크립트가 다른 파일 경로 패턴 매칭을 추가했는지 회귀 검사 (없어야 함)
if grep -qE 'grep -E .\^src/\(api\|app/api\|lib\)' "$VAULT_SH"; then
  fail "패턴 28: 파일 경로 정규식 잘못 추가됨 (SessionStart는 변경 파일 분류 안 함)"
else
  pass "패턴 28: SessionStart는 파일 경로 분류 미수행 (jq만 사용)"
fi

# ============================================================================
echo ""
echo "=== WI-C6-3: matrix.json 부재 시 skip (하위 호환 e2e) ==="
TMP_DIR="${TMPDIR:-/tmp}/wi-c6-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# emit 함수 3종 추출
EXTRACT="$TMP_DIR/extracted.sh"
awk '
  /^_emit_missing_entities\(\) \{/ {capture=1}
  /^_emit_missing_sections\(\) \{/ {capture=1}
  /^emit_missing_cells\(\) \{/ {capture=1}
  capture {print}
  capture && /^\}$/ {capture=0}
' "$VAULT_SH" > "$EXTRACT"

if grep -qE '^emit_missing_cells\(\) \{' "$EXTRACT" && \
   grep -qE '^_emit_missing_entities\(\) \{' "$EXTRACT" && \
   grep -qE '^_emit_missing_sections\(\) \{' "$EXTRACT"; then
  pass "함수 3개 추출 (emit_missing_cells + _emit_entities + _emit_sections)"
else
  fail "함수 추출 실패"
  echo "=== 총: PASS=$PASS FAIL=$FAIL ==="
  exit 1
fi

# 시나리오 A: HAS_MATRIX=false → return 0, 출력 없음
# WI-C5 SC2034 fix 패턴 차용 (학습 28): source된 함수가 변수 사용 시 export로 추적 보강
WORK="$TMP_DIR/work-no-matrix"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
export HAS_MATRIX=false
export MATRIX_FILE="$WORK/.flowset/spec/matrix.json"  # 존재 안 함
# shellcheck source=/dev/null
source "$EXTRACT"
output=$(emit_missing_cells 2>&1 || true)
if [[ -z "$output" ]]; then
  pass "A. matrix.json 부재(HAS_MATRIX=false) → 출력 없음 (skip, 하위 호환)"
else
  fail "A. HAS_MATRIX=false인데 출력: $output"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C6-4: code class 분기 e2e (entities 미완 셀 추출) ==="
WORK="$TMP_DIR/work-code"
mkdir -p "$WORK/.flowset/spec"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "code",
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
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"
# shellcheck source=/dev/null
source "$EXTRACT"

output=$(emit_missing_cells 2>&1 || true)
# Leave 미완 (U,D), Attendance 전수 done
if echo "$output" | grep -qE '^- entity=Leave 미완 셀 \[U,D\]' || \
   echo "$output" | grep -qE '^- entity=Leave 미완 셀 \[D,U\]'; then
  pass "B. code 분기: Leave 미완 셀 [U,D] 추출 (마크다운 \`- \` 형식)"
else
  fail "B. Leave 미완 셀 추출 실패: $output"
fi
if ! echo "$output" | grep -qE 'entity=Attendance'; then
  pass "B. code 분기: Attendance(전수 done) 미보고 (false positive 0건)"
else
  fail "B. Attendance가 잘못 보고됨"
fi
# WI-C5와 다르게 prefix가 'MATRIX_ISSUE: '가 아닌 마크다운 '- ' (vault context용)
if ! echo "$output" | grep -qE 'MATRIX_ISSUE'; then
  pass "B. code 분기: MATRIX_ISSUE prefix 없음 (vault context는 마크다운 형식)"
else
  fail "B. WI-C5의 MATRIX_ISSUE prefix가 잘못 사용됨"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C6-5: content class 분기 e2e (sections 미완 셀 추출) ==="
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
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"
# shellcheck source=/dev/null
source "$EXTRACT"

output=$(emit_missing_cells 2>&1 || true)
# 3.2-User-Flow의 review,approve 미완
if echo "$output" | grep -qE '^- section=3\.2-User-Flow 미완 셀 \[(review,approve|approve,review)\]'; then
  pass "C. content 분기: 3.2-User-Flow 미완 셀 [review,approve] 추출"
else
  fail "C. 3.2-User-Flow 미완 셀 추출 실패: $output"
fi
if ! echo "$output" | grep -qE 'section=4\.1-API-Spec'; then
  pass "C. content 분기: 4.1-API-Spec(전수 done) 미보고"
else
  fail "C. 4.1-API-Spec 잘못 보고됨"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C6-6: hybrid class 분기 e2e (entities + sections 동시 추출) ==="
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
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"
# shellcheck source=/dev/null
source "$EXTRACT"

output=$(emit_missing_cells 2>&1 || true)
# entity Leave + section 3.2-User-Flow 둘 다 추출 (verify와 달리 file path 무관 — 항상 양쪽)
if echo "$output" | grep -qE 'entity=Leave' && \
   echo "$output" | grep -qE 'section=3\.2-User-Flow'; then
  pass "D. hybrid 분기: entity + section 둘 다 추출 (SessionStart는 file path 무관 — 항상 전체 컨텍스트 주입)"
else
  fail "D. hybrid 양쪽 영역 동시 추출 실패: $output"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C6-7: 비정상 class silent skip + WARN 경고 (verify와 다른 컨텍스트) ==="
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
export HAS_MATRIX=true
export MATRIX_FILE=".flowset/spec/matrix.json"
# shellcheck source=/dev/null
source "$EXTRACT"

# 비정상 class → return 0 (silent skip) + stderr 경고 (verify-requirements와 다름)
set +e
bad_output=$(emit_missing_cells 2>&1)
bad_rc=$?
set -e

# E-1. WARN 메시지 (stderr) 출력
if echo "$bad_output" | grep -qE 'WARN: session-start-vault'; then
  pass "E. 비정상 class → WARN 메시지 (stderr 경고)"
else
  fail "E. WARN 메시지 누락 (output: $bad_output)"
fi
# E-2. return 0 (SessionStart 자체 차단 금지 — verify의 return 1과 다름)
if (( bad_rc == 0 )); then
  pass "E. 비정상 class → return 0 (SessionStart 컨텍스트 — hook 차단 금지)"
else
  fail "E. 비정상 class에서 return $bad_rc (기대 0, hook 차단 위반)"
fi
# E-3. stdout에는 미완 셀 출력 0건 (stderr만 사용)
stdout_only=$(emit_missing_cells 2>/dev/null || true)
if [[ -z "$stdout_only" ]]; then
  pass "E. 비정상 class → stdout 빈 출력 (vault context 오염 0건)"
else
  fail "E. 비정상 class에서 stdout 출력: $stdout_only"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C6-8: 전체 스크립트 e2e (VAULT_ENABLED=false 시 무동작 — 기존 동작 보존) ==="
# session-start-vault.sh 통째로 호출 + VAULT_ENABLED 미설정 → exit 0 + stdout 무출력
# 매트릭스 미완 셀 주입 로직이 vault gate 통과 후에 와야 함 (기존 hook 인터페이스 보존)

WORK="$TMP_DIR/work-vault-disabled"
mkdir -p "$WORK/.flowset/spec"
cat > "$WORK/.flowset/spec/matrix.json" <<'EOF'
{
  "schema_version": "v2",
  "class": "code",
  "entities": {
    "Leave": {
      "crud": {"C": {}, "R": {}},
      "status": {"C": "missing", "R": "missing"}
    }
  }
}
EOF

pushd "$WORK" > /dev/null
# VAULT_ENABLED=false (기본 — .flowsetrc 없음)
set +e
fullflow_output=$(echo '{"source":"startup"}' | bash "$REPO_ROOT/$VAULT_SH" 2>&1)
fullflow_rc=$?
set -e

# F-1. exit 0 (성공) — vault 미활성화 시 무동작
if (( fullflow_rc == 0 )); then
  pass "F. VAULT_ENABLED=false → exit 0 (기존 동작 보존)"
else
  fail "F. VAULT_ENABLED=false에서 exit $fullflow_rc (기대 0)"
fi
# F-2. 매트릭스가 있어도 stdout 무출력 (vault gate 통과 못 함)
if [[ -z "$fullflow_output" ]]; then
  pass "F. VAULT_ENABLED=false → stdout 무출력 (vault gate 차단)"
else
  fail "F. VAULT_ENABLED=false인데 출력 발생: $fullflow_output"
fi
popd > /dev/null

# ============================================================================
echo ""
echo "=== WI-C6-9: 기존 vault 동작 보존 회귀 차단 (4섹션 + 인터페이스) ==="
# 기존 4섹션 라벨이 그대로 유지되는지 + jq -n additionalContext 인터페이스 유지

# 기존 라벨 4종 그대로 유지
if grep -qE 'VAULT STATE — 프로젝트 현재 상태' "$VAULT_SH"; then
  pass "G. 기존 라벨: VAULT STATE 보존"
else
  fail "G. VAULT STATE 라벨 누락"
fi
if grep -qE 'VAULT LAST SESSION' "$VAULT_SH"; then
  pass "G. 기존 라벨: VAULT LAST SESSION 보존"
else
  fail "G. VAULT LAST SESSION 라벨 누락"
fi
if grep -qE 'VAULT TEAM STATE' "$VAULT_SH"; then
  pass "G. 기존 라벨: VAULT TEAM STATE 보존"
else
  fail "G. VAULT TEAM STATE 라벨 누락"
fi
if grep -qE 'VAULT ISSUES' "$VAULT_SH"; then
  pass "G. 기존 라벨: VAULT ISSUES 보존"
else
  fail "G. VAULT ISSUES 라벨 누락"
fi

# additionalContext 인터페이스 보존 (Claude Code SessionStart hook 계약)
if grep -qE 'additionalContext' "$VAULT_SH"; then
  pass "G. SessionStart hook 인터페이스: additionalContext 보존"
else
  fail "G. additionalContext 인터페이스 누락 (hook 호환성 깨짐)"
fi

# cch attestation sanitize 보존 (캐시 무효화 방지)
if grep -qE 'cch=REDACTED' "$VAULT_SH"; then
  pass "G. cch sanitize 보존 (캐시 무효화 방지)"
else
  fail "G. cch sanitize 누락"
fi

# 매트릭스 주입 로직이 VAULT_ENABLED 게이트 뒤에 위치 (기존 vault 차단 의미 보존)
matrix_inject_line=$(grep -nE 'missing_cells_output=\$\(emit_missing_cells' "$VAULT_SH" | head -1 | cut -d: -f1)
vault_gate_line=$(grep -nE 'VAULT_ENABLED.*!= "true"' "$VAULT_SH" | head -1 | cut -d: -f1)
if [[ -n "$matrix_inject_line" && -n "$vault_gate_line" && "$matrix_inject_line" -gt "$vault_gate_line" ]]; then
  pass "G. 매트릭스 주입이 VAULT_ENABLED 게이트 뒤 (vault 미활성화 시 무동작 보존)"
else
  fail "G. 매트릭스 주입이 vault 게이트 앞 (matrix=$matrix_inject_line gate=$vault_gate_line)"
fi

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-C6 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-C6 SMOKE FAILED"
  exit 1
fi
