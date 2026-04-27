#!/usr/bin/env bash
set -euo pipefail
# WI-E4 fix: 큰 v4_block을 echo로 grep -q 파이프할 때 mawk(Linux CI)에서
# SIGPIPE → broken pipe → pipefail 의해 fail. v4_block 누적 증가(v4.0.x 시리즈)로
# Layer 4부터 발현. 본 smoke는 검증용이므로 pipefail 해제 (set -e + set -u 유지).
set +o pipefail

# run-smoke-WI-D2.sh — WI-D2 (CHANGELOG.md v4.0 항목) 전용 smoke
# 핸드오프 Group δ 2/2 이행:
#   1. v4.0.0 항목 신설 + 22 WI 매핑
#   2. B1~B7 차단 메커니즘 표
#   3. evaluator 4-class 채점 (WI-C4 정합)
#   4. 학습 30~33 명시
#   5. 마이그레이션 가이드 (v3.x → v4.0)
#   6. 의존성 (jq/shellcheck/bats/cucumber CLI)
#   7. v3.x 항목 보존 (회귀 차단)
# 사용: bash tests/run-smoke-WI-D2.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

CHANGELOG="CHANGELOG.md"

# ============================================================================
echo "=== WI-D2-1: v4.0.0 항목 헤더 + 위치 ==="

# 1. v4.0.0 헤더 + 날짜
if grep -qE '^## \[v4\.0\.0\] - 2026-04-' "$CHANGELOG"; then
  pass "v4.0.0 헤더 + 날짜 (YYYY-MM-DD 형식)"
else
  fail "v4.0.0 헤더 누락"
fi

# 2. v4.0.0이 v3.4.0 위에 위치 (최신 항목 위로)
v4_line=$(grep -nE '^## \[v4\.0\.0\]' "$CHANGELOG" | head -1 | cut -d: -f1 || echo "0")
v34_line=$(grep -nE '^## \[v3\.4\.0\]' "$CHANGELOG" | head -1 | cut -d: -f1 || echo "0")
if (( v4_line > 0 && v34_line > 0 && v4_line < v34_line )); then
  pass "v4.0.0(line ${v4_line}) 위치가 v3.4.0(line ${v34_line}) 위 — 최신 항목 위로 정렬"
else
  fail "v4.0.0 위치 위반 (v4=${v4_line}, v3.4=${v34_line})"
fi

# 3. 슬로건 — 매트릭스 + 4-class 명시
if grep -qE '\*\*매트릭스 기반 검증 게이트웨이.*4-class' "$CHANGELOG"; then
  pass "슬로건: 매트릭스 + 4-class 시스템 명시"
else
  fail "슬로건 누락"
fi

# ============================================================================
echo ""
echo "=== WI-D2-2: 22 WI 매핑 (Group α/β/γ/δ + WI-001) ==="

# WI-E1: v4.0.x 패치 시리즈 전체를 검증 범위로 (v4.0.1 자동화 patch 포함)
v4_block=$(awk '/^## \[v4\.[0-9]+\.[0-9]+\]/,/^## \[v3\.4\.0\]/' "$CHANGELOG")

# Group α 8 WI (A1, A2a~e, A3, A4)
for wi in "WI-A1" "WI-A2a" "WI-A2b" "WI-A2c" "WI-A2d" "WI-A2e" "WI-A3" "WI-A4"; do
  if echo "$v4_block" | grep -qE "\*\*${wi}\*\*" || echo "$v4_block" | grep -qE "${wi}~"; then
    pass "Group α WI 매핑: ${wi}"
  else
    fail "Group α WI 누락: ${wi}"
  fi
done

# WI-001 게이트웨이
if echo "$v4_block" | grep -qE '\*\*WI-001\*\*'; then
  pass "WI-001 게이트웨이 매핑"
else
  fail "WI-001 누락"
fi

# Group β 3 WI
for wi in "WI-B1" "WI-B2" "WI-B3"; do
  if echo "$v4_block" | grep -qE "\*\*${wi}\*\*"; then
    pass "Group β WI 매핑: ${wi}"
  else
    fail "Group β WI 누락: ${wi}"
  fi
done

# Group γ 8 WI (C1, C2, C3-parse, C3-code, C3-content, C4, C5, C6)
for wi in "WI-C1" "WI-C2" "WI-C3-parse" "WI-C3-code" "WI-C3-content" "WI-C4" "WI-C5" "WI-C6"; do
  if echo "$v4_block" | grep -qE "\*\*${wi}\*\*"; then
    pass "Group γ WI 매핑: ${wi}"
  else
    fail "Group γ WI 누락: ${wi}"
  fi
done

# Group δ 2 WI
for wi in "WI-D1" "WI-D2"; do
  if echo "$v4_block" | grep -qE "\*\*${wi}\*\*"; then
    pass "Group δ WI 매핑: ${wi}"
  else
    fail "Group δ WI 누락: ${wi}"
  fi
done

# ============================================================================
echo ""
echo "=== WI-D2-3: B1~B7 Stop hook 차단 메커니즘 표 ==="

# B1~B7 모두 등장
for b in "B1" "B2" "B3" "B4" "B5" "B6" "B7"; do
  if echo "$v4_block" | grep -qE "\| ${b} \|"; then
    pass "B-id 표 행: ${b}"
  else
    fail "B-id 표 행 누락: ${b}"
  fi
done

# 각 B-id의 영역 매핑 (code/content)
if echo "$v4_block" | grep -qE 'B2.*code' && \
   echo "$v4_block" | grep -qE 'B3.*code' && \
   echo "$v4_block" | grep -qE 'B4.*code' && \
   echo "$v4_block" | grep -qE 'B6.*content' && \
   echo "$v4_block" | grep -qE 'B7.*content'; then
  pass "B-id 영역 매핑 (B2/B3/B4=code, B6/B7=content)"
else
  fail "B-id 영역 매핑 누락"
fi

# stop-rag-check.sh §6/7/8/9/10 섹션 번호 명시 (WI-C3-code/content 정합)
if echo "$v4_block" | grep -qE 'stop-rag-check\.sh §[0-9]'; then
  pass "stop-rag-check.sh 섹션 번호 명시 (WI-C3-code/content 정합)"
else
  fail "Stop hook 섹션 번호 누락"
fi

# session-start-vault.sh (B5) 명시 — WI-C6 정합
if echo "$v4_block" | grep -qE 'session-start-vault\.sh'; then
  pass "session-start-vault.sh (B5) 명시 — WI-C6 정합"
else
  fail "session-start-vault.sh (B5) 누락"
fi

# ============================================================================
echo ""
echo "=== WI-D2-4: evaluator 4-class 채점 (WI-C4 정합) ==="

# 4-class 모두 명시
for class in "type: code" "type: content" "type: hybrid" "type: 비주얼"; do
  if echo "$v4_block" | grep -qF "$class"; then
    pass "evaluator class: ${class}"
  else
    fail "evaluator class 누락: ${class}"
  fi
done

# cell_coverage / scenario_coverage / coverage_mode strict 키워드
for keyword in "cell_coverage" "scenario_coverage" "coverage_mode: strict"; do
  if echo "$v4_block" | grep -qF "$keyword"; then
    pass "WI-C4 정합 키워드: ${keyword}"
  else
    fail "WI-C4 키워드 누락: ${keyword}"
  fi
done

# legacy 보존 (visual)
if echo "$v4_block" | grep -qE 'legacy 보존'; then
  pass "비주얼 legacy 보존 명시"
else
  fail "비주얼 legacy 보존 명시 누락"
fi

# ============================================================================
echo ""
echo "=== WI-D2-5: 학습 패턴 30~33 명시 ==="

# 학습 30/31/32/33 모두 명시
for n in 30 31 32 33; do
  if echo "$v4_block" | grep -qE "\*\*${n}\*\*:"; then
    pass "학습 패턴 ${n} 명시"
  else
    fail "학습 패턴 ${n} 누락"
  fi
done

# 학습 31 핵심 키워드 — Windows jq.exe CRLF + tr -d '\r'
if echo "$v4_block" | grep -qE 'Windows jq\.exe.*CRLF' && \
   echo "$v4_block" | grep -qE "tr -d '\\\\r'"; then
  pass "학습 31: Windows jq.exe CRLF + tr -d '\\r' 키워드"
else
  fail "학습 31 핵심 키워드 누락"
fi

# 학습 32 핵심 키워드 — decision JSON jq -nc
if echo "$v4_block" | grep -qE 'decision JSON.*jq -nc'; then
  pass "학습 32: decision JSON jq -nc 키워드"
else
  fail "학습 32 핵심 키워드 누락"
fi

# 학습 33 핵심 키워드 — verify-requirements.sh underscore_prefix
if echo "$v4_block" | grep -qE '_underscore_prefix'; then
  pass "학습 33: _underscore_prefix 컨벤션 키워드"
else
  fail "학습 33 핵심 키워드 누락"
fi

# ============================================================================
echo ""
echo "=== WI-D2-6: 마이그레이션 가이드 (v3.x → v4.0) ==="

# 마이그레이션 섹션
if echo "$v4_block" | grep -qE '^### 마이그레이션 \(v3\.x → v4\.0\)'; then
  pass "마이그레이션 섹션 신설"
else
  fail "마이그레이션 섹션 누락"
fi

# 자동 덮어쓰기 금지 명시 (사용자 커스터마이징 보존)
if echo "$v4_block" | grep -qE '\*\*자동 덮어쓰기 금지\*\*' && \
   echo "$v4_block" | grep -qE '사용자 커스터마이징 보존'; then
  pass "자동 덮어쓰기 금지 + 커스터마이징 보존 명시"
else
  fail "자동 덮어쓰기 금지 명시 누락"
fi

# 마이그레이션 6단계 모두 등장
for keyword in ".flowsetrc" "prd-state.json" "stop-rag-check.sh" "CLAUDE.md" "team-roles.md" "sprint-{NNN}.md"; do
  if echo "$v4_block" | grep -qF "$keyword"; then
    pass "마이그레이션 대상: ${keyword}"
  else
    fail "마이그레이션 대상 누락: ${keyword}"
  fi
done

# HAS_MATRIX 플래그 (v3.x 무영향 핵심) — backtick 포함 가능
if echo "$v4_block" | grep -qE 'HAS_MATRIX' && \
   echo "$v4_block" | grep -qE '기존 프로젝트 무영향'; then
  pass "HAS_MATRIX 플래그 + 기존 프로젝트 무영향 명시"
else
  fail "HAS_MATRIX 플래그 명시 누락"
fi

# type: code (legacy) 플래그 — R9 정합
if echo "$v4_block" | grep -qE 'type: code \(legacy\)'; then
  pass "type: code (legacy) 플래그 명시 — R9 정합"
else
  fail "type: code (legacy) 누락"
fi

# ============================================================================
echo ""
echo "=== WI-D2-7: 의존성 + CI ==="

# 의존성 섹션
if echo "$v4_block" | grep -qE '^### 의존성 \(신규\)'; then
  pass "의존성 (신규) 섹션"
else
  fail "의존성 섹션 누락"
fi

# 4종 의존성 (jq 필수, shellcheck/bats 개발용, cucumber CLI 옵션)
for dep in "jq" "shellcheck" "bats" "cucumber CLI"; do
  if echo "$v4_block" | grep -qF "$dep"; then
    pass "의존성: ${dep}"
  else
    fail "의존성 누락: ${dep}"
  fi
done

# jq 필수 vs cucumber 옵션 명시
if echo "$v4_block" | grep -qE 'jq.*필수' && \
   echo "$v4_block" | grep -qE 'cucumber CLI.*옵션'; then
  pass "jq 필수 vs cucumber CLI 옵션 구분 명시"
else
  fail "의존성 필수/옵션 구분 누락"
fi

# CI 섹션 — smoke 카운트 형식 검증 (자기참조 무한 갱신 회피: 숫자 hardcode 안 함)
# 정확한 카운트는 아래 cross-check가 담당
if echo "$v4_block" | grep -qE 'smoke: 126 → \*\*[0-9]+ assertion\*\*'; then
  pass "CI smoke 카운트 형식 (126 → N assertion)"
else
  fail "CI smoke 카운트 형식 누락"
fi

# [CRITICAL 해소] CI 카운트가 flowset-ci.yml 실제 job name과 정합 검증 (재발 방지 cross-check)
# 본 PR 머지 시점에 두 파일이 일치하지 않으면 fail — 자기참조 결함 영구 차단
# WI-E1: v4.0.x 시리즈 어딘가에 최신 ci_count가 등장하면 OK (v4.0.0 섹션은 그 시점 사실 보존)
ci_count=$(grep -oE 'bash smoke \(.*= ([0-9]+) assertion\)' .github/workflows/flowset-ci.yml | grep -oE '[0-9]+ assertion' | grep -oE '[0-9]+' || echo "0")
if echo "$v4_block" | grep -qE "\*\*${ci_count} assertion\*\*"; then
  pass "[CRITICAL 해소] CHANGELOG v4.0.x 시리즈 smoke 카운트(${ci_count}) ↔ flowset-ci.yml job name 정합"
else
  fail "[CRITICAL] CHANGELOG v4.0.x ↔ flowset-ci.yml 카운트 불일치 (CI: ${ci_count})"
fi

# bats / shellcheck / commit-check 4종 CI job 명시
for ci_job in "bats: 16 @test" "shellcheck severity" "commit-check"; do
  if echo "$v4_block" | grep -qF "$ci_job"; then
    pass "CI job: ${ci_job}"
  else
    fail "CI job 누락: ${ci_job}"
  fi
done

# ============================================================================
echo ""
echo "=== WI-D2-8: 주요 파일 변경 + matrix SSOT ==="

# 주요 파일 변경 섹션
if echo "$v4_block" | grep -qE '^### 주요 파일 변경'; then
  pass "주요 파일 변경 섹션"
else
  fail "주요 파일 변경 섹션 누락"
fi

# 신규 파일 명시 — matrix.json + parse-gherkin.sh + lib/state.sh + tests/bats_tests
for new_file in "templates/.flowset/spec/matrix.json" "parse-gherkin.sh" "lib/state.sh" "tests/bats_tests/core.bats" "flowset-ci.yml"; do
  if echo "$v4_block" | grep -qF "$new_file"; then
    pass "신규 파일: ${new_file}"
  else
    fail "신규 파일 누락: ${new_file}"
  fi
done

# 확장 파일 명시 (줄수 변동)
for ext_file in "evaluator.md" "CLAUDE.md" "stop-rag-check.sh" "session-start-vault.sh"; do
  if echo "$v4_block" | grep -qF "$ext_file"; then
    pass "확장 파일: ${ext_file}"
  else
    fail "확장 파일 누락: ${ext_file}"
  fi
done

# 줄수 변동 형식 — 평가자 [MEDIUM] 해소: 실제 파일 줄수와 cross-check
# CHANGELOG에 명시된 변동 후 줄수가 현재 파일의 실제 wc -l과 일치해야 함
declare -A expected_line_counts=(
  ["templates/.claude/agents/evaluator.md"]="371"
  ["templates/CLAUDE.md"]="97"
  ["templates/.flowset/scripts/stop-rag-check.sh"]="434"
  ["templates/.flowset/scripts/session-start-vault.sh"]="229"
)
for file_path in "${!expected_line_counts[@]}"; do
  expected="${expected_line_counts[$file_path]}"
  actual=$(wc -l < "$file_path" 2>/dev/null | tr -d ' ' || echo "0")
  if [[ "$actual" == "$expected" ]]; then
    if echo "$v4_block" | grep -qF "→${expected}줄"; then
      pass "[MEDIUM 해소] ${file_path}: CHANGELOG ${expected}줄 = 실제 ${actual}줄"
    else
      fail "[MEDIUM] ${file_path}: 실제 ${actual}줄이지만 CHANGELOG에 →${expected}줄 미명시"
    fi
  else
    fail "${file_path}: 예상 ${expected}줄 ≠ 실제 ${actual}줄 (테스트 anchor 갱신 필요)"
  fi
done

# tests 22개 (실제 ls와 일치) — 백틱 등 마크다운 wrapper 무시
actual_tests=$(ls tests/run-smoke-WI-*.sh 2>/dev/null | wc -l | tr -d ' ')
if echo "$v4_block" | grep -qE "run-smoke-WI[^[:space:]]* ${actual_tests}개"; then
  pass "[LOW 해소] tests/run-smoke-WI-*.sh ${actual_tests}개 (CHANGELOG ↔ 실제 ls 일치)"
else
  fail "[LOW] tests 카운트 불일치 (CHANGELOG vs 실제 ${actual_tests}개)"
fi

# templates/lib/ prefix 통일
if echo "$v4_block" | grep -qE 'templates/lib/state\.sh'; then
  pass "[LOW 해소] templates/lib/ prefix 통일 (다른 파일과 일관)"
else
  fail "[LOW] lib/state.sh prefix 비일관"
fi

# ============================================================================
echo ""
echo "=== WI-D2-9: v3.x 항목 보존 (회귀 차단) ==="

# v3.4.0 / v3.3.0 / v3.0.0 헤더 모두 보존
for ver in "v3.4.0" "v3.3.0" "v3.0.0"; do
  if grep -qE "^## \[${ver}\]" "$CHANGELOG"; then
    pass "v3.x 헤더 보존: ${ver}"
  else
    fail "v3.x 헤더 변형됨: ${ver}"
  fi
done

# v3.x 핵심 항목 본문 보존 (최소 5개 키워드 grep)
for v3_keyword in "vault-helpers.sh" "Obsidian Vault" "evaluator 채점 정밀화" "PostCompact hook" "transcript 기반 vault 저장"; do
  if grep -qF "$v3_keyword" "$CHANGELOG"; then
    pass "v3.x 본문 보존: ${v3_keyword}"
  else
    fail "v3.x 본문 변형됨: ${v3_keyword}"
  fi
done

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-D2 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-D2 SMOKE FAILED"
  exit 1
fi
