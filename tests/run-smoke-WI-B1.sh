#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-B1.sh — WI-B1 (/wi:init content/hybrid 분기) 전용 smoke
# 설계 §5 :214 4단계 흐름 + §5 :235 8개 중복 감지 시나리오 + §7 :302 reviews/approvals mkdir
# 사용: bash tests/run-smoke-WI-B1.sh
#
# 누적 기준선: 180 + 40 = 220 assertion (WI-001 재캘리브레이션 후, WI-B1에서 41→40) + bats 16 @test

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

INIT_MD="skills/wi/init.md"

echo "=== WI-B1-1: init.md Step 3.5 class별 분기 확장 확인 (정적) ==="
# 1. code|content|hybrid validation 게이트 유지
if grep -qE 'code\|content\|hybrid\)' "$INIT_MD"; then
  pass "validation case 블록 유지 (WI-001 계약)"
else
  fail "validation case 블록 소실"
fi

# 2. skip_dup_check 가드 존재 (hybrid에서만 중복 감지)
if grep -qE 'skip_dup_check=0' "$INIT_MD" && grep -qE 'skip_dup_check=1' "$INIT_MD"; then
  pass "skip_dup_check 가드 (hybrid만 활성)"
else
  fail "skip_dup_check 가드 누락"
fi

# 3. code/hybrid 공통 5역 누적
if grep -qE 'team_names\+=\("frontend" "backend" "qa" "devops" "planning"\)' "$INIT_MD"; then
  pass "code 5역 누적 (frontend/backend/qa/devops/planning)"
else
  fail "code 5역 누적 블록 누락"
fi

# 4. content/hybrid 공통 content 5역 누적
if grep -qE 'team_names\+=\("writer" "reviewer" "approver" "designer" "shared"\)' "$INIT_MD"; then
  pass "content 5역 누적 (writer/reviewer/approver/designer/shared)"
else
  fail "content 5역 누적 블록 누락"
fi

# 5. reviews/ approvals/ mkdir (§7 :302)
if grep -qE 'mkdir -p \.flowset/reviews \.flowset/approvals' "$INIT_MD"; then
  pass "content/hybrid 시 reviews/ approvals/ mkdir (§7 :302)"
else
  fail "mkdir reviews/approvals 누락"
fi

echo ""
echo "=== WI-B1-2: hybrid 중복 감지 루프 구조 확인 ==="
# 1. while 루프 + max_retry=3
if grep -qE 'max_retry=3' "$INIT_MD"; then
  pass "최대 3회 재시도 상수"
else
  fail "max_retry=3 누락"
fi
# 2. uniq -d로 중복 감지
if grep -qE "sort \| uniq -d" "$INIT_MD"; then
  pass "sort | uniq -d 중복 감지"
else
  fail "중복 감지 파이프 누락"
fi
# 3. 방어 1: 빈 입력 거부
if grep -qE '최소 1개 이상의 새 이름 입력 필요' "$INIT_MD"; then
  pass "방어 1: 빈 입력 거부 메시지"
else
  fail "방어 1 누락"
fi
# 4. 방어 2: 새 이름 자체 중복 거부
if grep -qE '새 이름 자체에 중복' "$INIT_MD"; then
  pass "방어 2: 새 이름 자체 중복 거부"
else
  fail "방어 2 누락"
fi
# 5. 3회 연속 실패 시 exit 1
if grep -qE '3회 연속 중복' "$INIT_MD"; then
  pass "3회 연속 중복 → exit 1 (무한 루프 방어)"
else
  fail "무한 루프 방어 누락"
fi
# 6. filter-rebuild 배열 조작 패턴
if grep -qE 'filtered\+=\("\$name"\)' "$INIT_MD"; then
  pass "filter-rebuild 패턴 (요소 제거용)"
else
  fail "filter-rebuild 패턴 누락"
fi
# 7. bash gotcha 회피: retry=$((retry + 1)) (((retry++)) 금지)
if grep -qE 'retry=\$\(\(retry \+ 1\)\)' "$INIT_MD"; then
  pass "bash gotcha 회피 (retry=\$((retry+1)))"
else
  fail "retry 증가 패턴 누락"
fi

echo ""
echo "=== WI-B1-3: 학습 전이 회귀 방지 (패턴 2/3/5/19) ==="
# 패턴 2: ((var++)) 금지
total_bad=0
while IFS=: read -r _ c; do
  total_bad=$((total_bad + c))
done < <(grep -cE '\(\([[:alnum:]_]+\+\+\)\)' "$INIT_MD" 2>/dev/null || true)
if (( total_bad == 0 )); then
  pass "패턴 2: ((var++)) 사용 0건"
else
  fail "패턴 2: ((var++)) 사용 ${total_bad}건"
fi

# 패턴 3: "${arr[@]/pattern}" 오용 금지 — init.md 전체
# 백틱 내부(markdown inline code — 문서 예시) 제거 후 검사 + grep -n 출력의 "NNN:" 프리픽스 다음 주석 제외
if sed 's/`[^`]*`//g' "$INIT_MD" | grep -nE '\$\{[[:alnum:]_]+\[@\]/[^}]+\}' | grep -vE ':\s*#'; then
  fail "패턴 3: \${arr[@]/pattern} 실제 사용 발견"
else
  pass "패턴 3: \${arr[@]/pattern} 실제 사용 0건 (백틱·주석 제외)"
fi

# 패턴 19: local x=$(cmd) 금지
if grep -nE '^\s*local\s+[[:alnum:]_]+=\$\(' "$INIT_MD"; then
  fail "패턴 19: local x=\$(cmd) 사용 발견"
else
  pass "패턴 19: local x=\$(cmd) 사용 0건"
fi

echo ""
echo "=== WI-B1-4: init.md에서 build_team_names 블록 추출 + 실측 ==="
# awk로 블록 추출: `source .flowsetrc` 줄부터 가장 먼저 나오는 ``` 닫힘까지
TMP_DIR="${TMPDIR:-/tmp}/wi-b1-smoke-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

BUILD_BLOCK="$TMP_DIR/build.sh"
awk '
  /^```bash$/ { buf=""; capture=1; next }
  capture && /^source \.flowsetrc/ { capture_target=1 }
  capture && /^```$/ {
    if (capture_target) { print buf; exit }
    buf=""; capture=0; capture_target=0; next
  }
  capture { buf = buf $0 "\n" }
' "$INIT_MD" > "$BUILD_BLOCK"

if [[ -s "$BUILD_BLOCK" ]] && grep -q "build_team_names\|team_names+=" "$BUILD_BLOCK"; then
  pass "build_team_names 블록 추출 성공 ($(wc -l < "$BUILD_BLOCK")줄)"
else
  fail "build 블록 추출 실패"
  echo "=== 총: PASS=$PASS FAIL=$FAIL ==="
  exit 1
fi

# 실측을 위한 테스트 래퍼 함수 구성
# 블록이 `source .flowsetrc`로 시작하므로 해당 줄 제거 후 testable wrapper로 감쌈
cat > "$TMP_DIR/wrap.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ownership_save stub: 파일 저장 대신 팀명 배열 dump
ownership_save() {
  printf '%s\n' "${team_names[@]}" > "$TMP_DIR/result.txt"
}

# PROJECT_CLASS는 인자로 전달
PROJECT_CLASS="${1:-code}"
# stdin 재시도 입력은 인자 2~ 에서 처리
shift || true

# extra_code (hybrid 질문) + 재입력 stub: stdin을 read가 소비
run_block() {
  # skills/wi/init.md에서 추출한 블록 내용
BLOCK_CONTENT
}

run_block
EOF

# BLOCK_CONTENT 자리에 추출 블록 삽입 (source .flowsetrc만 제거)
BLOCK_PURE="$TMP_DIR/block-pure.sh"
grep -v '^source \.flowsetrc' "$BUILD_BLOCK" > "$BLOCK_PURE"
# exit 1은 subshell에서 우회하고 싶지 않음 (에러 경로 검증) → 그대로 유지
# mkdir -p은 테스트 cwd에서 실제 생성; 이를 위해 test 디렉토리로 cd 필요

TESTER="$TMP_DIR/tester.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set -u'  # set -e는 생략 (exit 1 경로 검증용)
  echo 'TMP_DIR="$1"; shift'
  echo 'PROJECT_CLASS="$1"; shift'
  echo 'ownership_save() { printf "%s\n" "${team_names[@]:-}" > "$TMP_DIR/result.txt"; }'
  cat "$BLOCK_PURE"
  echo 'rc=$?'
  echo 'exit $rc'
} > "$TESTER"

# 시나리오 1: PROJECT_CLASS=code → skip_dup_check=1 → ownership_save 즉시 호출
WORK="$TMP_DIR/work-code"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
rm -f "$TMP_DIR/result.txt"
if echo "" | bash "$TESTER" "$TMP_DIR" code 2>/dev/null; then
  if grep -qE '^frontend$' "$TMP_DIR/result.txt" 2>/dev/null; then
    pass "시나리오 1: class=code → frontend/backend/qa/devops/planning 생성"
  else
    fail "시나리오 1: result.txt 내용 이상"
  fi
else
  fail "시나리오 1: code 실행 실패"
fi
# mkdir 미실행 확인 (code는 reviews/ approvals/ 생성 안 함)
if [[ ! -d ".flowset/reviews" && ! -d ".flowset/approvals" ]]; then
  pass "시나리오 1: code → reviews/ approvals/ 미생성"
else
  fail "시나리오 1: code에서 reviews/ 또는 approvals/ 생성됨"
fi
popd > /dev/null

# 시나리오 2: PROJECT_CLASS=content → writer 등 5역 + mkdir reviews/approvals
WORK="$TMP_DIR/work-content"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
rm -f "$TMP_DIR/result.txt"
if echo "" | bash "$TESTER" "$TMP_DIR" content 2>/dev/null; then
  if grep -qE '^writer$' "$TMP_DIR/result.txt" && grep -qE '^reviewer$' "$TMP_DIR/result.txt" \
    && grep -qE '^approver$' "$TMP_DIR/result.txt" && grep -qE '^designer$' "$TMP_DIR/result.txt" \
    && grep -qE '^shared$' "$TMP_DIR/result.txt"; then
    pass "시나리오 2: class=content → writer/reviewer/approver/designer/shared 5역"
  else
    fail "시나리오 2: content 5역 누락 (result.txt 확인 필요)"
  fi
else
  fail "시나리오 2: content 실행 실패"
fi
if [[ -d ".flowset/reviews" && -d ".flowset/approvals" ]]; then
  pass "시나리오 2: content → reviews/ approvals/ 생성 (§7 :302)"
else
  fail "시나리오 2: content에서 reviews/ 또는 approvals/ 미생성"
fi
popd > /dev/null

# 시나리오 3: PROJECT_CLASS=hybrid + 중복 없는 입력 (extra 공백만, designer 충돌 재입력 designer-code designer-content)
WORK="$TMP_DIR/work-hybrid-ok"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
rm -f "$TMP_DIR/result.txt"
# stdin 1행: extra_code (공백 = 추가 역할 없음)
# stdin 2행: designer 중복 재입력 (designer-code designer-content)
# hybrid는 code(frontend backend qa devops planning) + content(writer reviewer approver designer shared)
# → designer가 중복 → 재입력 루프 진입 (단 content의 designer와 code의 확장 designer가 겹치는 경우)
# 실제로는 hybrid의 team_names = frontend/backend/qa/devops/planning + writer/reviewer/approver/designer/shared
# → designer 중복 없음 (code에는 designer 없고 content에만 있음). 중복 루프 진입 안 함.
if printf "\n" | bash "$TESTER" "$TMP_DIR" hybrid 2>/dev/null; then
  cnt_frontend=$(grep -cE '^frontend$' "$TMP_DIR/result.txt" 2>/dev/null) || true
  cnt_writer=$(grep -cE '^writer$' "$TMP_DIR/result.txt" 2>/dev/null) || true
  cnt_designer=$(grep -cE '^designer$' "$TMP_DIR/result.txt" 2>/dev/null) || true
  if (( cnt_frontend >= 1 && cnt_writer >= 1 && cnt_designer == 1 )); then
    pass "시나리오 3: class=hybrid 기본 — code 5역 + content 5역 공존 (designer 1건)"
  else
    fail "시나리오 3: hybrid 결과 이상 (frontend=$cnt_frontend writer=$cnt_writer designer=$cnt_designer)"
  fi
else
  fail "시나리오 3: hybrid 실행 실패"
fi
if [[ -d ".flowset/reviews" && -d ".flowset/approvals" ]]; then
  pass "시나리오 3: hybrid → reviews/ approvals/ 생성"
else
  fail "시나리오 3: hybrid에서 reviews/ approvals/ 미생성"
fi
popd > /dev/null

# 시나리오 4: PROJECT_CLASS=hybrid + extra "design" 입력으로 designer 중복 유도 → 재입력 (designer-code designer-content)
# code 측 extra로 "designer"를 추가하면 team_names에 frontend/backend/qa/devops/planning/designer/writer/reviewer/approver/designer/shared
# → designer 중복 → 루프 진입
WORK="$TMP_DIR/work-hybrid-dup-fixed"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
rm -f "$TMP_DIR/result.txt"
# stdin 1행: "design" (extra_code, "design" 역할 추가 — code 쪽 designer)
# stdin 2행: 하지만 실제 add한 이름은 "design"이라서 "designer"(content)와 충돌 안 함
# 정확한 중복 재현: extra에 "designer" 입력 → code쪽 designer + content쪽 designer 중복
# stdin 2행: designer-code designer-content
if printf "designer\ndesigner-code designer-content\n" | bash "$TESTER" "$TMP_DIR" hybrid 2>/dev/null; then
  # designer-code와 designer-content가 최종 배열에 있고 원래의 "designer"는 모두 제거됨
  cnt_dc=$(grep -cE '^designer-code$' "$TMP_DIR/result.txt" 2>/dev/null) || true
  cnt_dcn=$(grep -cE '^designer-content$' "$TMP_DIR/result.txt" 2>/dev/null) || true
  cnt_des=$(grep -cE '^designer$' "$TMP_DIR/result.txt" 2>/dev/null) || true
  if (( cnt_dc == 1 && cnt_dcn == 1 && cnt_des == 0 )); then
    pass "시나리오 4: hybrid designer 중복 → designer-code/designer-content 재입력 성공"
  else
    fail "시나리오 4: designer 분리 이상 (dc=$cnt_dc dcn=$cnt_dcn des=$cnt_des)"
  fi
else
  fail "시나리오 4: hybrid designer 중복 재입력 실행 실패"
fi
popd > /dev/null

# 시나리오 5: hybrid + 3회 연속 중복 재입력 → exit 1 (무한 루프 방어)
# designer 중복 상태에서 재입력도 "designer designer"(새 이름 자체 중복)으로 3회 반복
WORK="$TMP_DIR/work-hybrid-3fail"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
rm -f "$TMP_DIR/result.txt"
# stdin 1행: "designer" (extra, 중복 유도)
# stdin 2~4행: "designer designer" (새 이름 자체 중복 — 방어 2 발동, retry 증가, 3회 반복)
# 5번째 read는 더 이상 없음
input_3fail=$(printf "designer\ndesigner designer\ndesigner designer\ndesigner designer\n")
actual_exit=0
echo "$input_3fail" | bash "$TESTER" "$TMP_DIR" hybrid 2>/dev/null || actual_exit=$?
if (( actual_exit != 0 )); then
  pass "시나리오 5: hybrid 3회 연속 중복 → exit $actual_exit (≠0, 무한 루프 방어)"
else
  fail "시나리오 5: 3회 연속 실패 후에도 정상 종료 (무한 루프 방어 실패)"
fi
popd > /dev/null

# 시나리오 6: hybrid + 재입력 빈 줄(엔터만) → 방어 1 "최소 1개 이상의 새 이름 입력 필요" + retry 증가
WORK="$TMP_DIR/work-hybrid-empty"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
rm -f "$TMP_DIR/result.txt"
# stdin 1: "designer" extra
# stdin 2: "" (빈 입력, 방어 1 발동)
# stdin 3: "designer-code designer-content" (최종 정상)
err_output=$(mktemp "$TMP_DIR/err-XXXX")
if printf "designer\n\ndesigner-code designer-content\n" | bash "$TESTER" "$TMP_DIR" hybrid 2>"$err_output"; then
  :
fi
if grep -qE '최소 1개 이상의 새 이름 입력 필요' "$err_output"; then
  pass "시나리오 6: 빈 입력 → '최소 1개 이상' 메시지 + retry 증가 (방어 1)"
else
  fail "시나리오 6: 빈 입력 방어 1 미발동"
fi
popd > /dev/null

# 시나리오 7: hybrid + 재입력 "designer-code designer-code"(새 이름 자체 중복) → 방어 2 + retry 증가
WORK="$TMP_DIR/work-hybrid-selfdup"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
rm -f "$TMP_DIR/result.txt"
err_output=$(mktemp "$TMP_DIR/err-XXXX")
if printf "designer\ndesigner-code designer-code\ndesigner-code designer-content\n" | bash "$TESTER" "$TMP_DIR" hybrid 2>"$err_output"; then
  :
fi
if grep -qE '새 이름 자체에 중복' "$err_output"; then
  pass "시나리오 7: 새 이름 자체 중복 → '새 이름 자체에 중복' 메시지 (방어 2)"
else
  fail "시나리오 7: 방어 2 미발동"
fi
popd > /dev/null

# 시나리오 8: filter-rebuild 검증 — 중복 해결 후 team_names에 빈 문자열 요소 0개
WORK="$TMP_DIR/work-filter-rebuild"
mkdir -p "$WORK"
pushd "$WORK" > /dev/null
rm -f "$TMP_DIR/result.txt"
if printf "designer\ndesigner-code designer-content\n" | bash "$TESTER" "$TMP_DIR" hybrid 2>/dev/null; then
  # result.txt에 빈 줄 포함 여부
  empty_lines=$(grep -cE '^$' "$TMP_DIR/result.txt" 2>/dev/null) || true
  # 원본 "designer"가 남아있지 않은지
  orig_designer=$(grep -cE '^designer$' "$TMP_DIR/result.txt" 2>/dev/null) || true
  if (( empty_lines == 0 && orig_designer == 0 )); then
    pass "시나리오 8: filter-rebuild — 빈 요소 0건 + 원본 designer 제거 (패턴 3 회귀 방지)"
  else
    fail "시나리오 8: 배열 조작 이상 (empty=$empty_lines orig_designer=$orig_designer)"
  fi
else
  fail "시나리오 8: filter-rebuild 실행 실패"
fi
popd > /dev/null

echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-B1 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-B1 SMOKE FAILED"
  exit 1
fi
