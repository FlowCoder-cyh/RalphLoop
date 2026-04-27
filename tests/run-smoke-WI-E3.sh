#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-E3.sh — flowset.sh + lib/merge.sh + task-completed-eval.sh
# 영숫자 WI ID 통일 (학습 37 일반화 — 8개 위치)
#
# evaluator WI-E2 회의적 검증에서 POINT-NEW 3건 발굴 (실제 8개 위치):
# - templates/flowset.sh: 262/271/371/467/927 (5건)
# - templates/lib/merge.sh: 161/445 (2건)
# - templates/.flowset/scripts/task-completed-eval.sh: 20 (1건)
#
# 모두 WI-[0-9]+ 또는 WI-[0-9]{3,4} 패턴 → 영숫자 미지원으로 silent fail.
# fix: WI-[0-9A-Za-z]+(-[0-9]+)?-... 패턴으로 통일 (학습 37).

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

FLOWSET_SH="templates/flowset.sh"
MERGE_SH="templates/lib/merge.sh"
EVAL_SH="templates/.flowset/scripts/task-completed-eval.sh"

# ============================================================================
echo "=== WI-E3-1: flowset.sh 영숫자 ID 통일 (5개 위치) ==="

# 262, 271, 371: WI-[0-9A-Za-z]+(-[0-9]+)?-[a-z]+ 패턴
for line_pattern in \
  "262:prefix" \
  "271:git log" \
  "371:wi_prefix"; do
  line_num=$(echo "$line_pattern" | cut -d: -f1)
  actual=$(sed -n "${line_num}p" "$FLOWSET_SH")
  if echo "$actual" | grep -qE 'WI-\[0-9A-Za-z\]\+\(-\[0-9\]\+\)\?-\[a-z\]\+'; then
    pass "flowset.sh:${line_num} 영숫자+서브넘버링 패턴 적용"
  else
    fail "flowset.sh:${line_num} 영숫자 패턴 미적용 (현재: $actual)"
  fi
done

# 467: validate_post_iteration() 정규식 + PATTERN_REVERT
if grep -qE 'pattern="\^WI-\[0-9A-Za-z\]\+\(-\[0-9\]\+\)\?-' "$FLOWSET_SH"; then
  pass "flowset.sh:467 validate_post_iteration 영숫자+서브넘버링 통일"
else
  fail "flowset.sh:467 영숫자 패턴 미적용"
fi
if grep -qE 'pattern_revert="\^Revert ' "$FLOWSET_SH"; then
  pass "flowset.sh validate_post_iteration: PATTERN_REVERT 추가"
else
  fail "flowset.sh PATTERN_REVERT 누락 (Revert 커밋 violation 기록 위험)"
fi

# 927: domain 추출 sed -E ERE
if grep -qE "sed -E 's/WI-\[0-9A-Za-z\]\+\(-\[0-9\]\+\)\?-\[a-z\]\+ //'" "$FLOWSET_SH"; then
  pass "flowset.sh:927 domain 추출 sed -E 영숫자 패턴"
else
  fail "flowset.sh:927 domain 추출 영숫자 미적용"
fi

# ============================================================================
echo ""
echo "=== WI-E3-2: lib/merge.sh 영숫자 ID 통일 (2개 위치) ==="

# 161, 445: WI-[0-9A-Za-z]+ 패턴
merge_count=$(grep -cE "grep -oE 'WI-\[0-9A-Za-z\]\+'" "$MERGE_SH" || echo 0)
if [[ "$merge_count" -ge 2 ]]; then
  pass "lib/merge.sh: WI-[0-9A-Za-z]+ 패턴 ${merge_count}회 등장 (≥2 정합)"
else
  fail "lib/merge.sh: 영숫자 패턴 ${merge_count}회 (예상 2회) — 일부 위치 미적용"
fi

# 잔존 WI-[0-9]+ (영숫자 미지원) 검색 — 0건이어야 함
if grep -qE "WI-\[0-9\]\+'" "$MERGE_SH"; then
  fail "lib/merge.sh: 영숫자 미지원 WI-[0-9]+ 잔존"
else
  pass "lib/merge.sh: 영숫자 미지원 패턴 잔존 없음"
fi

# ============================================================================
echo ""
echo "=== WI-E3-3: task-completed-eval.sh 영숫자 ID 통일 ==="

if grep -qE "grep -oE 'WI-\[0-9A-Za-z\]\+\(-\[0-9\]\+\)\?'" "$EVAL_SH"; then
  pass "task-completed-eval.sh:20 영숫자+서브넘버링 패턴 적용"
else
  fail "task-completed-eval.sh:20 영숫자 미적용 (TaskCompleted hook이 영숫자 WI에 silent skip)"
fi

# 잔존 WI-[0-9]{3,4} 검색
if grep -qE "WI-\[0-9\]\{3,4\}" "$EVAL_SH"; then
  fail "task-completed-eval.sh: 숫자 한정 패턴 WI-[0-9]{3,4} 잔존"
else
  pass "task-completed-eval.sh: 숫자 한정 패턴 잔존 없음"
fi

# ============================================================================
echo ""
echo "=== WI-E3-4: 영숫자 WI commit 메시지 추출 시뮬레이션 ==="

# flowset.sh:262/271/371 패턴으로 영숫자/서브넘버링 메시지 추출 검증
for msg in \
  "abc1234 WI-001-feat 사용자 인증" \
  "def5678 WI-A2a-refactor lib/state.sh" \
  "1234abc WI-C3code-fix evaluator MEDIUM" \
  "fedcba9 WI-E1cifix-fix evaluator CRITICAL" \
  "0123abc WI-001-1-fix 후속 fix" \
  "0fed987 WI-A2a-1-fix 추가 보강"; do
  # 262/271 패턴 (`^[a-f0-9]+ WI-[0-9A-Za-z]+(-[0-9]+)?-[a-z]+`)
  extracted=$(echo "$msg" | grep -oE '^[a-f0-9]+ WI-[0-9A-Za-z]+(-[0-9]+)?-[a-z]+' | head -1)
  if [[ -n "$extracted" ]]; then
    pass "flowset.sh recover 추출: $msg → $extracted"
  else
    fail "flowset.sh recover 추출 실패: $msg"
  fi
done

# ============================================================================
echo ""
echo "=== WI-E3-5: lib/merge.sh wi_num 추출 시뮬레이션 ==="

# 161/445 패턴 (`WI-[0-9A-Za-z]+`)
for msg in \
  "WI-001 e2e 실패 issue" \
  "WI-A2a 머지 실패" \
  "WI-C3code 워커 출력" \
  "WI-E1cifix fix 진행"; do
  wi_num=$(echo "$msg" | grep -oE 'WI-[0-9A-Za-z]+' | head -1)
  if [[ -n "$wi_num" ]]; then
    pass "merge.sh wi_num 추출: '$msg' → $wi_num"
  else
    fail "merge.sh wi_num 추출 실패: $msg"
  fi
done

# ============================================================================
echo ""
echo "=== WI-E3-6: task-completed-eval WI_NUM 추출 시뮬레이션 ==="

# 20 패턴 (`WI-[0-9A-Za-z]+(-[0-9]+)?`)
for subject in \
  "WI-001-feat 사용자 인증 추가" \
  "WI-A2a-refactor lib/state.sh 모듈 분리" \
  "WI-C3code-fix evaluator MEDIUM 즉시 해소" \
  "WI-E1cifix-fix evaluator CRITICAL" \
  "WI-001-1-fix 후속 fix 보강"; do
  wi_num=$(echo "$subject" | grep -oE 'WI-[0-9A-Za-z]+(-[0-9]+)?' | head -1)
  if [[ -n "$wi_num" ]]; then
    pass "task-completed-eval WI_NUM: '$subject' → $wi_num"
  else
    fail "task-completed-eval WI_NUM 추출 실패: $subject (TaskCompleted hook silent skip)"
  fi
done

# ============================================================================
echo ""
echo "=== WI-E3-7: validate_post_iteration() bash regex 매칭 시뮬레이션 ==="

pattern="^WI-[0-9A-Za-z]+(-[0-9]+)?-(feat|fix|docs|style|refactor|test|chore|perf|ci|revert) .+"
pattern_system="^WI-(chore|docs) .+"
pattern_merge="^Merge "
pattern_revert="^Revert "

for msg in \
  "WI-001-feat 사용자 인증" \
  "WI-A2a-refactor 모듈 분리" \
  "WI-C3code-fix evaluator MEDIUM" \
  "WI-001-1-fix 서브넘버링" \
  "WI-chore 환경 셋업" \
  "WI-docs PRD 작성" \
  "Merge pull request #1" \
  "Revert \"WI-001-feat\""; do
  if [[ "$msg" =~ $pattern || "$msg" =~ $pattern_system || "$msg" =~ $pattern_merge || "$msg" =~ $pattern_revert ]]; then
    pass "validate_post_iteration 매칭: $msg"
  else
    fail "validate_post_iteration 미매칭: $msg (기존 통과하던 메시지가 reject되면 회귀)"
  fi
done

# ============================================================================
echo ""
echo "=== WI-E3-8: domain 추출 (flowset.sh:932) sed -E 시뮬레이션 ==="

for wi_name in \
  "WI-001-feat 사용자 인증 추가" \
  "WI-A2a-refactor lib/state.sh 모듈 분리" \
  "WI-001-1-fix 후속 fix"; do
  domain=$(echo "$wi_name" | sed -E 's/WI-[0-9A-Za-z]+(-[0-9]+)?-[a-z]+ //' | cut -c1-30)
  expected_not="WI-"  # WI- prefix가 제거되었으면 OK
  if [[ "$domain" != *"$expected_not"* ]] && [[ -n "$domain" ]]; then
    pass "domain 추출: '$wi_name' → '$domain'"
  else
    fail "domain 추출 실패: '$wi_name' → '$domain' (WI prefix 제거 안 됨)"
  fi
done

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"

if [[ $FAIL -eq 0 ]]; then
  echo "  ✅ WI-E3 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-E3 SMOKE FAILED"
  exit 1
fi
