#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-B2.sh — WI-B2 (/wi:start 3모드 분기) 전용 smoke
# 설계 §5 :216 3모드 선택 분기 + Phase 5.9 Ruleset class별 조건부 + Phase 6 재구성(루프/대화형/팀)
# 설계 §3 축 Y (루프/대화형/팀 + class별 기본 매핑)
# 사용: bash tests/run-smoke-WI-B2.sh
#
# 누적 기준선 SSOT: `.github/workflows/flowset-ci.yml` smoke job name 참조
#   CI 호출분(A4 미포함): test-vault 31 + A1 14 + A2a-e 81 + A3 17 + 001 40 + B1 27 + B2 36 = 246 assertion
#   로컬 regression (A4 21 포함): 246 + 21 = 267 assertion
#   bats core.bats: 16 @test (class 무관)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

START_MD="skills/wi/start.md"
FLOWSETRC="templates/.flowsetrc"

echo "=== WI-B2-1: Phase 5.9 Ruleset class별 조건부 확인 (정적) ==="
# 1. content 분기 if 블록 존재
if grep -qE 'if \[\[ "\$PROJECT_CLASS" == "content" \]\]; then' "$START_MD"; then
  pass "Phase 5.9: content 분기 if 블록"
else
  fail "Phase 5.9: content 분기 if 누락"
fi

# 2. content 전용 ruleset 이름
if grep -qE '"name": "Protect main \(content\)"' "$START_MD"; then
  pass "Phase 5.9: content 전용 ruleset 이름"
else
  fail "Phase 5.9: content 전용 ruleset 이름 누락"
fi

# 3. content 최소 보호 규칙 — non_fast_forward + deletion만 (status checks 없음)
# content 블록 내부에서 required_status_checks가 등장하지 않아야 함
content_block=$(awk '/content 프로젝트 — 최소 Ruleset/,/^RULES$/' "$START_MD" | head -30)
if echo "$content_block" | grep -qE '"type": "non_fast_forward"' && \
   echo "$content_block" | grep -qE '"type": "deletion"' && \
   ! echo "$content_block" | grep -qE 'required_status_checks'; then
  pass "Phase 5.9: content 최소 보호 (non_fast_forward + deletion, status checks 없음)"
else
  fail "Phase 5.9: content 최소 보호 블록 이상"
fi

# 4. code/hybrid else 분기 존재
if grep -qE 'else$' "$START_MD" && grep -qE 'code 또는 hybrid — 기존 strict ruleset' "$START_MD"; then
  pass "Phase 5.9: code/hybrid else 분기 (기존 strict 유지)"
else
  fail "Phase 5.9: code/hybrid else 분기 누락"
fi

# 5. class 기록 출력
if grep -qE 'Ruleset 설정 완료 \(class=\$PROJECT_CLASS\)' "$START_MD"; then
  pass "Phase 5.9: class 라벨 포함 완료 메시지"
else
  fail "Phase 5.9: class 라벨 누락"
fi

echo ""
echo "=== WI-B2-2: Phase 5.95 실행 모드 선택 블록 확인 (정적) ==="
# 1. Phase 5.95 제목
if grep -qE '^### Phase 5\.95: 실행 모드 선택' "$START_MD"; then
  pass "Phase 5.95 제목 존재"
else
  fail "Phase 5.95 제목 누락"
fi

# 2. DEFAULT_MODE 매핑 case (3종 모두 존재)
if grep -qE 'code\)[[:space:]]+DEFAULT_MODE="loop"' "$START_MD" && \
   grep -qE 'content\)[[:space:]]+DEFAULT_MODE="interactive"' "$START_MD" && \
   grep -qE 'hybrid\)[[:space:]]+DEFAULT_MODE="team"' "$START_MD"; then
  pass "Phase 5.95: DEFAULT_MODE 매핑 3종 (code→loop, content→interactive, hybrid→team)"
else
  fail "Phase 5.95: DEFAULT_MODE 매핑 누락 또는 잘못됨"
fi

# 3. MODE_CHOICE 사용자 선택 case (1|loop, 2|interactive, 3|team, 빈값)
if grep -qE '1\|loop\)' "$START_MD" && grep -qE '2\|interactive\)' "$START_MD" && grep -qE '3\|team\)' "$START_MD"; then
  pass "Phase 5.95: 사용자 선택 case (1/2/3 및 영문)"
else
  fail "Phase 5.95: 사용자 선택 case 누락"
fi

# 4. 잘못된 입력 → exit 1 (엄격한 validation)
if grep -qE '알 수 없는 모드' "$START_MD"; then
  pass "Phase 5.95: 잘못된 모드 입력 → 에러"
else
  fail "Phase 5.95: 잘못된 모드 validation 누락"
fi

# 5. 알 수 없는 PROJECT_CLASS → exit 1
if grep -qE '알 수 없는 PROJECT_CLASS' "$START_MD"; then
  pass "Phase 5.95: 알 수 없는 PROJECT_CLASS validation"
else
  fail "Phase 5.95: PROJECT_CLASS validation 누락"
fi

# 6. EXECUTION_MODE .flowsetrc 영속화 (sed 대체 또는 append)
if grep -qE 'EXECUTION_MODE=.*>>.*\.flowsetrc' "$START_MD"; then
  pass "Phase 5.95: EXECUTION_MODE .flowsetrc 영속화"
else
  fail "Phase 5.95: EXECUTION_MODE 영속화 누락"
fi

echo ""
echo "=== WI-B2-3: Phase 6 재구성 (루프/대화형/팀) 확인 (정적) ==="
# 1. Phase 6.0 공통 커밋 + GITHUB_ACCOUNT_TYPE 조건부 push
if grep -qE '#### 6\.0: 공통 커밋' "$START_MD"; then
  pass "Phase 6.0: 공통 커밋 서브섹션"
else
  fail "Phase 6.0: 공통 커밋 서브섹션 누락"
fi

# 2. GITHUB_ACCOUNT_TYPE 조건부 push
if grep -qE 'if \[\[ -n "\$\{GITHUB_ACCOUNT_TYPE:-\}" \]\]; then' "$START_MD"; then
  pass "Phase 6.0: GITHUB_ACCOUNT_TYPE 조건부 push (content class 고려)"
else
  fail "Phase 6.0: GITHUB_ACCOUNT_TYPE 조건부 push 누락"
fi

# 3. Phase 6.1 모드별 case 분기
if grep -qE 'case "\$\{EXECUTION_MODE:-loop\}" in' "$START_MD"; then
  pass "Phase 6.1: case 분기 + loop 기본값 (하위 호환)"
else
  fail "Phase 6.1: case 분기 누락"
fi

# 4. 3모드 섹션 제목 존재
if grep -qE '^### 모드 A: 루프' "$START_MD" && \
   grep -qE '^### 모드 B: 대화형' "$START_MD" && \
   grep -qE '^### 모드 C: 팀' "$START_MD"; then
  pass "Phase 6: 3모드 섹션 제목 (A 루프 / B 대화형 / C 팀)"
else
  fail "Phase 6: 3모드 섹션 제목 누락"
fi

# 5. 팀 모드 — lead-workflow spawn
if grep -qE 'subagent_type: "lead-workflow"' "$START_MD"; then
  pass "모드 C (팀): lead-workflow Agent spawn"
else
  fail "모드 C (팀): lead-workflow spawn 누락"
fi

# 6. 대화형 모드 — fix_plan.md 미완 WI 루프 (mapfile + PENDING + fix_plan.md 키워드 조합)
if grep -qE 'mapfile -t PENDING' "$START_MD" && grep -qE '\.flowset/fix_plan\.md' "$START_MD" && grep -qE '미완' "$START_MD"; then
  pass "모드 B (대화형): fix_plan.md 미완 WI 추출 의사코드 (mapfile + PENDING)"
else
  fail "모드 B (대화형): fix_plan.md 의사코드 누락"
fi

# 7. 루프 모드 — 기존 flowset.sh 플랫폼 감지 블록 (find_windows_bash) 유지 (회귀 방지)
if grep -qE 'find_windows_bash\(\)' "$START_MD"; then
  pass "모드 A (루프): find_windows_bash 함수 유지 (v3.x 호환)"
else
  fail "모드 A (루프): find_windows_bash 함수 소실 (v3.x 회귀)"
fi

echo ""
echo "=== WI-B2-4: templates/.flowsetrc EXECUTION_MODE 필드 확인 ==="
# 1. EXECUTION_MODE 필드 존재
if grep -qE '^EXECUTION_MODE=' "$FLOWSETRC"; then
  pass "templates/.flowsetrc: EXECUTION_MODE 필드 선언"
else
  fail "templates/.flowsetrc: EXECUTION_MODE 필드 누락"
fi

# 2. 기본값 빈 문자열 (하위 호환)
if grep -qE '^EXECUTION_MODE=""$' "$FLOWSETRC"; then
  pass "templates/.flowsetrc: EXECUTION_MODE 기본값 빈 문자열 (PROJECT_CLASS 매핑)"
else
  fail "templates/.flowsetrc: EXECUTION_MODE 기본값 이상"
fi

# 3. 3모드 주석 설명 (loop/interactive/team 모두 언급)
if grep -qE 'loop.*interactive.*team' "$FLOWSETRC" || \
   (grep -qE 'loop' "$FLOWSETRC" && grep -qE 'interactive' "$FLOWSETRC" && grep -qE 'team' "$FLOWSETRC"); then
  pass "templates/.flowsetrc: 3모드 주석 설명 (loop/interactive/team)"
else
  fail "templates/.flowsetrc: 3모드 주석 설명 누락"
fi

echo ""
echo "=== WI-B2-5: 학습 전이 회귀 방지 (패턴 2/3/19) ==="
# 패턴 2: ((var++)) 금지 — start.md 전체 (백틱/주석 제거)
# 백틱 inline code 제거 + grep -n 프리픽스 이후 주석 제외
# pipefail 환경에서 grep -c match 0건 시 exit 1이므로 || true 방어 필수
stripped=$(sed 's/`[^`]*`//g' "$START_MD" | sed -E 's/[[:space:]]+#.*$//')
cnt=$(echo "$stripped" | grep -cE '\(\([[:alnum:]_]+\+\+\)\)' || true)
if (( cnt == 0 )); then
  pass "패턴 2: ((var++)) 실제 사용 0건 (백틱·주석 제거)"
else
  fail "패턴 2: ((var++)) 사용 ${cnt}건"
fi

# 패턴 3: "${arr[@]/pattern}" 실제 사용 금지
if sed 's/`[^`]*`//g' "$START_MD" | grep -nE '\$\{[[:alnum:]_]+\[@\]/[^}]+\}' | grep -vE ':\s*#' > /dev/null; then
  fail "패턴 3: \${arr[@]/pattern} 실제 사용 발견"
else
  pass "패턴 3: \${arr[@]/pattern} 실제 사용 0건 (백틱·주석 제외)"
fi

# 패턴 19: local x=$(cmd) 금지
if grep -nE '^\s*local\s+[[:alnum:]_]+=\$\(' "$START_MD" > /dev/null; then
  fail "패턴 19: local x=\$(cmd) 사용 발견"
else
  pass "패턴 19: local x=\$(cmd) 사용 0건"
fi

# 패턴 4: || echo 0 (중복 출력 유발) 금지 — 정당한 || true / || { } 는 허용
if grep -nE '\|\|[[:space:]]+echo[[:space:]]+0\b' "$START_MD" > /dev/null; then
  fail "패턴 4: || echo 0 사용 발견 (중복 출력 유발)"
else
  pass "패턴 4: || echo 0 사용 0건"
fi

echo ""
echo "=== WI-B2-6: Phase 5.95 모드 선택 블록 추출 + 실측 ==="
TMP_DIR="${TMPDIR:-/tmp}/wi-b2-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# Phase 5.95 블록(MODE 선택) 추출 — `source \.flowsetrc` 이후 PROJECT_CLASS/DEFAULT_MODE case + read + MODE_CHOICE 처리
MODE_BLOCK="$TMP_DIR/mode-block.sh"
awk '
  /^### Phase 5\.95:/ { in_section=1 }
  in_section && /^```bash$/ { capture=1; next }
  in_section && capture && /^```$/ { exit }
  in_section && capture { print }
' "$START_MD" > "$MODE_BLOCK"

if [[ -s "$MODE_BLOCK" ]] && grep -qE 'DEFAULT_MODE=' "$MODE_BLOCK" && grep -qE 'EXECUTION_MODE=' "$MODE_BLOCK"; then
  pass "Phase 5.95 블록 추출 성공 ($(wc -l < "$MODE_BLOCK")줄)"
else
  fail "Phase 5.95 블록 추출 실패"
  echo "=== 총: PASS=$PASS FAIL=$FAIL ==="
  exit 1
fi

# 테스트 래퍼: stdin으로 MODE_CHOICE, 인자로 PROJECT_CLASS
TESTER="$TMP_DIR/tester.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set -u'
  echo 'PROJECT_CLASS="${1:-code}"'
  # source .flowsetrc 제거 (stub)
  grep -v '^source \.flowsetrc' "$MODE_BLOCK"
  echo 'echo "FINAL_MODE=$EXECUTION_MODE"'
} > "$TESTER"
chmod +x "$TESTER"

# 시나리오 1: code + 빈 입력 (Enter) → loop
WORK="$TMP_DIR/work1"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
out=$(echo "" | bash "$TESTER" code 2>/dev/null | grep "^FINAL_MODE=" || true)
if [[ "$out" == "FINAL_MODE=loop" ]]; then
  pass "실측 1: class=code + Enter → loop (기본 매핑)"
else
  fail "실측 1: class=code Enter 결과 이상 ($out)"
fi
popd > /dev/null

# 시나리오 2: content + 빈 입력 → interactive
WORK="$TMP_DIR/work2"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
out=$(echo "" | bash "$TESTER" content 2>/dev/null | grep "^FINAL_MODE=" || true)
if [[ "$out" == "FINAL_MODE=interactive" ]]; then
  pass "실측 2: class=content + Enter → interactive (기본 매핑)"
else
  fail "실측 2: class=content Enter 결과 이상 ($out)"
fi
popd > /dev/null

# 시나리오 3: hybrid + 빈 입력 → team
WORK="$TMP_DIR/work3"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
out=$(echo "" | bash "$TESTER" hybrid 2>/dev/null | grep "^FINAL_MODE=" || true)
if [[ "$out" == "FINAL_MODE=team" ]]; then
  pass "실측 3: class=hybrid + Enter → team (기본 매핑)"
else
  fail "실측 3: class=hybrid Enter 결과 이상 ($out)"
fi
popd > /dev/null

# 시나리오 4: code + 명시적 "interactive" 입력 → interactive (override)
WORK="$TMP_DIR/work4"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
out=$(echo "interactive" | bash "$TESTER" code 2>/dev/null | grep "^FINAL_MODE=" || true)
if [[ "$out" == "FINAL_MODE=interactive" ]]; then
  pass "실측 4: class=code + 'interactive' 입력 → interactive (override)"
else
  fail "실측 4: override 실패 ($out)"
fi
popd > /dev/null

# 시나리오 5: content + 숫자 "1" 입력 → loop
WORK="$TMP_DIR/work5"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
out=$(echo "1" | bash "$TESTER" content 2>/dev/null | grep "^FINAL_MODE=" || true)
if [[ "$out" == "FINAL_MODE=loop" ]]; then
  pass "실측 5: 숫자 '1' 입력 → loop (숫자 선택지 매핑)"
else
  fail "실측 5: 숫자 선택 실패 ($out)"
fi
popd > /dev/null

# 시나리오 6: hybrid + 숫자 "3" → team
WORK="$TMP_DIR/work6"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
out=$(echo "3" | bash "$TESTER" hybrid 2>/dev/null | grep "^FINAL_MODE=" || true)
if [[ "$out" == "FINAL_MODE=team" ]]; then
  pass "실측 6: 숫자 '3' 입력 → team"
else
  fail "실측 6: 숫자 3 선택 실패 ($out)"
fi
popd > /dev/null

# 시나리오 7: 잘못된 모드 "foobar" → exit 1
WORK="$TMP_DIR/work7"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
actual_exit=0
echo "foobar" | bash "$TESTER" code >/dev/null 2>&1 || actual_exit=$?
if (( actual_exit != 0 )); then
  pass "실측 7: 잘못된 모드 'foobar' → exit $actual_exit (validation)"
else
  fail "실측 7: 잘못된 모드인데 정상 종료"
fi
popd > /dev/null

# 시나리오 8: 알 수 없는 PROJECT_CLASS "weird" → exit 1
WORK="$TMP_DIR/work8"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
actual_exit=0
echo "" | bash "$TESTER" weird >/dev/null 2>&1 || actual_exit=$?
if (( actual_exit != 0 )); then
  pass "실측 8: 잘못된 PROJECT_CLASS 'weird' → exit $actual_exit (validation)"
else
  fail "실측 8: 잘못된 class인데 정상 종료"
fi
popd > /dev/null

# 시나리오 9: EXECUTION_MODE가 .flowsetrc에 기록되는지 (영속화)
WORK="$TMP_DIR/work9"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
# 빈 .flowsetrc 생성
touch .flowsetrc
echo "" | bash "$TESTER" content 2>/dev/null >/dev/null || true
if grep -qE '^EXECUTION_MODE="interactive"$' .flowsetrc 2>/dev/null; then
  pass "실측 9: .flowsetrc에 EXECUTION_MODE 영속화"
else
  fail "실측 9: .flowsetrc 영속화 실패"
fi
popd > /dev/null

# 시나리오 10: 하위 호환 — .flowsetrc에 기존 EXECUTION_MODE="loop" 존재 시 덮어쓰기
WORK="$TMP_DIR/work10"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
printf 'EXECUTION_MODE="loop"\n' > .flowsetrc
echo "team" | bash "$TESTER" hybrid 2>/dev/null >/dev/null || true
if grep -qE '^EXECUTION_MODE="team"$' .flowsetrc 2>/dev/null && \
   ! grep -qE '^EXECUTION_MODE="loop"$' .flowsetrc 2>/dev/null; then
  pass "실측 10: 기존 EXECUTION_MODE 덮어쓰기 (중복 없이)"
else
  fail "실측 10: 덮어쓰기 실패 또는 중복 ($(grep EXECUTION_MODE .flowsetrc))"
fi
popd > /dev/null

echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-B2 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-B2 SMOKE FAILED"
  exit 1
fi
