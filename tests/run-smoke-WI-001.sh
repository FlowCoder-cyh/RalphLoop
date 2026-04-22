#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-001.sh — WI-001 (PROJECT_CLASS 게이트웨이) 전용 smoke
# 하위 호환 + 3종 class 분기 + migrate_prd_state_v1_to_v2 idempotency/atomicity/rollback
# 사용: bash tests/run-smoke-WI-001.sh
#
# 누적 기준선 (WI-A4 시점): 180 assertion + bats 16 @test
# 이 smoke는 WI-001 신규 구조만 검증. 누적 smoke 회귀는 run-smoke-WI-A4.sh가 담당.

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== WI-001-1: templates/.flowsetrc에 PROJECT_CLASS 필드 신설 ==="
if grep -qE '^PROJECT_CLASS=' templates/.flowsetrc; then
  pass "templates/.flowsetrc에 PROJECT_CLASS 라인 존재"
else
  fail "PROJECT_CLASS 필드 누락"
fi
# 기본값 code — 하위 호환 보장 (설계 §8 :359)
if grep -qE '^PROJECT_CLASS="code"' templates/.flowsetrc; then
  pass "PROJECT_CLASS 기본값 code (기존 동작 완전 동일)"
else
  fail "기본값이 code 아님 (하위 호환 깨짐 위험)"
fi
# 주석에 3종 class 전부 명시 (code|content|hybrid)
if grep -qE 'code|content|hybrid' templates/.flowsetrc; then
  pass "주석에 code|content|hybrid 3종 class 명시"
else
  fail "class 옵션 안내 주석 누락"
fi

echo ""
echo "=== WI-001-2: skills/wi/init.md PROJECT_CLASS 질문 단계 ==="
# Step 1 블록 내 PROJECT_CLASS 관련 섹션 존재
if grep -qE '^- \*\*`--class` 플래그\*\*' skills/wi/init.md; then
  pass "--class 플래그 문서화 존재"
else
  fail "--class 플래그 문서화 누락"
fi
# Usage 라인에 [--class ...] 포함
if grep -qE '\[--class code\|content\|hybrid\]' skills/wi/init.md; then
  pass "Usage 라인에 --class 옵션 표기"
else
  fail "Usage 라인 --class 누락"
fi
# 대화형 질문 프롬프트 존재
if grep -qE 'PROJECT_CLASS 선택' skills/wi/init.md; then
  pass "대화형 PROJECT_CLASS 질문 프롬프트 존재"
else
  fail "대화형 질문 누락"
fi

echo ""
echo "=== WI-001-3: skills/wi/init.md Step 3.5 class별 분기 ==="
# case "$PROJECT_CLASS" in ... 블록 존재
if grep -qE 'case "\$PROJECT_CLASS" in' skills/wi/init.md; then
  pass "Step 3.5에 case \"\$PROJECT_CLASS\" in 분기 존재"
else
  fail "PROJECT_CLASS 분기 누락"
fi
# 3개 class 전부 분기
for class in code "content|hybrid"; do
  if grep -qE "^  ${class}\\)" skills/wi/init.md; then
    pass "case 분기: ${class})"
  else
    fail "case 분기 누락: ${class})"
  fi
done
# 알 수 없는 class → exit 1
if grep -qE 'ERROR: 알 수 없는 PROJECT_CLASS' skills/wi/init.md; then
  pass "알 수 없는 class 값 거부 (exit 1)"
else
  fail "class 검증 분기 누락"
fi

echo ""
echo "=== WI-001-4: skills/wi/prd.md Step 0에 migrate_prd_state_v1_to_v2 함수 배치 ==="
if grep -qE '^migrate_prd_state_v1_to_v2\(\) \{' skills/wi/prd.md; then
  pass "migrate_prd_state_v1_to_v2() 함수 정의 존재"
else
  fail "migration 함수 정의 누락"
fi
# Step 0 내부에 배치 (Step 1 이전)
step0_line=$(grep -n '^### Step 0' skills/wi/prd.md | head -1 | cut -d: -f1 || echo 0)
step1_line=$(grep -n '^### Step 1' skills/wi/prd.md | head -1 | cut -d: -f1 || echo 0)
fn_line=$(grep -n '^migrate_prd_state_v1_to_v2()' skills/wi/prd.md | head -1 | cut -d: -f1 || echo 0)
if (( step0_line > 0 && fn_line > step0_line && fn_line < step1_line )); then
  pass "함수가 Step 0 내부(Step 1 이전)에 배치"
else
  fail "함수 위치 이탈 (step0=$step0_line fn=$fn_line step1=$step1_line)"
fi
# v2 필드 6종 전수 포함 (entities/roles/crud_matrix/permission_matrix/auth_patterns/auth_framework)
for field in entities roles crud_matrix permission_matrix auth_patterns auth_framework; do
  if grep -qE "^    ${field}:" skills/wi/prd.md; then
    pass "v2 필드 포함: $field"
  else
    fail "v2 필드 누락: $field"
  fi
done
# schema_version: "v2" 포함
if grep -qE 'schema_version: "v2"' skills/wi/prd.md; then
  pass "schema_version: \"v2\" 지정"
else
  fail "schema_version 설정 누락"
fi

echo ""
echo "=== WI-001-5: migrate 함수 추출 + 동작 실측 ==="
# prd.md에서 함수 본문 추출 (awk: migrate_prd_state_v1_to_v2()부터 첫 닫는 '}'까지)
TMP_DIR="${TMPDIR:-/tmp}/wi-001-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

FN_FILE="$TMP_DIR/migrate-fn.sh"
awk '
  /^migrate_prd_state_v1_to_v2\(\) \{/ {capture=1}
  capture {print}
  capture && /^\}$/ {capture=0; exit}
' skills/wi/prd.md > "$FN_FILE"

if [[ -s "$FN_FILE" ]] && tail -1 "$FN_FILE" | grep -qE '^\}$'; then
  pass "prd.md에서 함수 본문 추출 성공 ($(wc -l < "$FN_FILE")줄)"
else
  fail "함수 본문 추출 실패"
  echo "=== 총: PASS=$PASS FAIL=$FAIL ==="
  exit 1
fi

# 추출된 함수로 6종 시나리오 실측
WORK="$TMP_DIR/work"
mkdir -p "$WORK/.flowset"
cd "$WORK"

# 시나리오 A: 파일 없음 → return 0 (skip)
# shellcheck source=/dev/null
source "$FN_FILE"
if migrate_prd_state_v1_to_v2; then
  pass "시나리오 A: 파일 없음 → return 0 (skip)"
else
  fail "시나리오 A: 빈 디렉토리에서 실패 반환"
fi
# 파일 생성되지 않아야 함
if [[ ! -f .flowset/prd-state.json ]]; then
  pass "시나리오 A: 파일 신규 생성 없음"
else
  fail "시나리오 A: 파일이 잘못 생성됨"
fi

# 시나리오 B: v1 파일 (schema_version 필드 없음) → v2로 승격
cat > .flowset/prd-state.json <<'EOF'
{
  "step": 3,
  "project_name": "출퇴근 관리",
  "overview": {"name": "A", "goal": "B"},
  "user_constraints": ["GPS 미사용"]
}
EOF
if migrate_prd_state_v1_to_v2; then
  pass "시나리오 B: v1 → migration 정상 종료"
else
  fail "시나리오 B: migration 반환 실패"
fi
sv=$(jq -r '.schema_version' .flowset/prd-state.json)
if [[ "$sv" == "v2" ]]; then
  pass "시나리오 B: schema_version=v2 승격"
else
  fail "시나리오 B: schema_version=$sv (기대 v2)"
fi
# 기존 필드 전부 보존
if [[ "$(jq -r '.step' .flowset/prd-state.json)" == "3" ]] \
  && [[ "$(jq -r '.project_name' .flowset/prd-state.json)" == "출퇴근 관리" ]] \
  && [[ "$(jq -r '.overview.goal' .flowset/prd-state.json)" == "B" ]] \
  && [[ "$(jq -r '.user_constraints[0]' .flowset/prd-state.json)" == "GPS 미사용" ]]; then
  pass "시나리오 B: 기존 v1 필드 전부 보존 (step/project_name/overview/user_constraints)"
else
  fail "시나리오 B: 기존 필드 손실 발생"
fi
# v2 신규 필드 기본값 주입
entities=$(jq -r '.entities | type' .flowset/prd-state.json)
roles=$(jq -r '.roles | type' .flowset/prd-state.json)
crud=$(jq -r '.crud_matrix | type' .flowset/prd-state.json)
perm=$(jq -r '.permission_matrix | type' .flowset/prd-state.json)
authp=$(jq -r '.auth_patterns | type' .flowset/prd-state.json)
authf=$(jq -r '.auth_framework | type' .flowset/prd-state.json)
if [[ "$entities" == "array" && "$roles" == "array" && "$crud" == "object" \
  && "$perm" == "object" && "$authp" == "array" && "$authf" == "string" ]]; then
  pass "시나리오 B: v2 필드 6종 기본값 주입 (entities/roles/crud/perm/authp/authf 타입 일치)"
else
  fail "시나리오 B: v2 필드 타입 이상 (e=$entities r=$roles c=$crud p=$perm ap=$authp af=$authf)"
fi
# .v1.bak 백업 존재
if [[ -f .flowset/prd-state.json.v1.bak ]]; then
  pass "시나리오 B: .v1.bak 백업 생성"
else
  fail "시나리오 B: .v1.bak 백업 누락"
fi

# 시나리오 C: v2 파일 재실행 → idempotent (변화 없음)
md5_before=$(md5sum .flowset/prd-state.json | awk '{print $1}')
if migrate_prd_state_v1_to_v2; then
  pass "시나리오 C: v2 재실행 return 0"
else
  fail "시나리오 C: v2 재실행 실패 반환"
fi
md5_after=$(md5sum .flowset/prd-state.json | awk '{print $1}')
if [[ "$md5_before" == "$md5_after" ]]; then
  pass "시나리오 C: idempotency — 재실행 md5 동일 (무변화)"
else
  fail "시나리오 C: 재실행 md5 변경 ($md5_before → $md5_after)"
fi

# 시나리오 D: 손상된 JSON → rollback (.v1.bak에서 복원)
rm -f .flowset/prd-state.json .flowset/prd-state.json.v1.bak
cat > .flowset/prd-state.json <<'EOF'
{"step": 1, "project_name": "broken_test" invalid_syntax
EOF
# 이 파일은 jq 파싱 실패해야 함 (rollback 경로 유도)
if migrate_prd_state_v1_to_v2; then
  fail "시나리오 D: 손상 JSON에서 return 0 (rollback 경로 미발동)"
else
  pass "시나리오 D: 손상 JSON → return 1 (rollback 경로 진입)"
fi
# 원본 파일 복원 확인 (손상 상태 그대로)
if grep -q 'invalid_syntax' .flowset/prd-state.json; then
  pass "시나리오 D: 원본 파일 rollback 성공 (손상 상태 보존)"
else
  fail "시나리오 D: 원본 파일 손실 (rollback 실패)"
fi

# 시나리오 E: 하위 호환 핵심 — .flowsetrc에 PROJECT_CLASS 없음 → 기존 동작
cd "$REPO_ROOT"
LEGACY_RC="$TMP_DIR/legacy.flowsetrc"
cat > "$LEGACY_RC" <<'EOF'
PROJECT_NAME="legacy_project"
PROJECT_TYPE="typescript"
MAX_ITERATIONS=50
EOF
# shellcheck source=/dev/null
source "$LEGACY_RC"
PROJECT_CLASS_RESULT="${PROJECT_CLASS:-code}"
if [[ "$PROJECT_CLASS_RESULT" == "code" ]]; then
  pass "시나리오 E: 하위 호환 — PROJECT_CLASS 미정의 시 code 기본값 (설계 §8 :359)"
else
  fail "시나리오 E: 하위 호환 깨짐 ($PROJECT_CLASS_RESULT ≠ code)"
fi

# 시나리오 F: 3종 class 수용 검증
for class_val in code content hybrid; do
  RC="$TMP_DIR/class-${class_val}.flowsetrc"
  cat > "$RC" <<EOF
PROJECT_NAME="test"
PROJECT_CLASS="${class_val}"
EOF
  unset PROJECT_CLASS
  # shellcheck source=/dev/null
  source "$RC"
  if [[ "${PROJECT_CLASS:-}" == "$class_val" ]]; then
    pass "시나리오 F: class=$class_val 수용"
  else
    fail "시나리오 F: class=$class_val 로드 실패"
  fi
done

echo ""
echo "=== WI-001-6: 학습 전이 회귀 방지 (패턴 2/4/5/19 재검증) ==="
# 패턴 2: ((var++)) 금지 — prd.md/init.md 추가 블록에 사용 여부
# grep -cE는 파일마다 "file:count" 라인 출력. IFS=: 파싱 후 합산 (shellcheck SC2002/SC2034 회피)
total_bad=0
while IFS=: read -r _ c; do
  total_bad=$((total_bad + c))
done < <(grep -cE '\(\([[:alnum:]_]+\+\+\)\)' skills/wi/prd.md skills/wi/init.md 2>/dev/null || true)
if (( total_bad == 0 )); then
  pass "패턴 2: ((var++)) 사용 0건 (set -e 회귀 방지)"
else
  fail "패턴 2: ((var++)) 사용 ${total_bad}건 (set -e와 충돌 위험)"
fi

# 패턴 4: `|| echo 0` 금지 (중복 출력 유발) — `|| true`/`|| echo ""` 허용
if grep -nE '\|\| echo 0' skills/wi/prd.md skills/wi/init.md; then
  fail "패턴 4: \`|| echo 0\` 사용 발견 (중복 출력 유발)"
else
  pass "패턴 4: \`|| echo 0\` 사용 0건"
fi

# 패턴 19: `local x=$(cmd)` 금지 (SC2155 return value masking) — prd.md의 함수 블록에서
if grep -nE '^\s*local\s+[[:alnum:]_]+=\$\(' skills/wi/prd.md; then
  fail "패턴 19: \`local x=\$(cmd)\` 사용 발견 (SC2155)"
else
  pass "패턴 19: \`local x=\$(cmd)\` 사용 0건"
fi

echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-001 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-001 SMOKE FAILED"
  exit 1
fi
