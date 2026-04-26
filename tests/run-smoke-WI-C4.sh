#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-C4.sh — WI-C4 (evaluator.md type: content + cell/scenario coverage) 전용 smoke
# 설계 §5 :227 + §7 :320 + §9 R2 (evaluator 채점 재캘리브레이션) Group γ 8/8 이행:
#   1. type: code/content/hybrid 채점 기준 분기
#   2. cell_coverage / scenario_coverage 산출 의사코드 (jq + parse-gherkin.sh)
#   3. content 안티패턴 (B6/B7 위반)
#   4. content few-shot 9/7/4점 (R2 재캘리브레이션)
#   5. 평가 절차 §0 PROJECT_CLASS 판정 + matrix.json 직접 읽기
#   6. 기존 v3.3 코드/비주얼 채점 보존
# 사용: bash tests/run-smoke-WI-C4.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

EVAL_MD="templates/.claude/agents/evaluator.md"

# ============================================================================
echo "=== WI-C4-1: frontmatter + 기본 구조 보존 ==="

# 1. frontmatter 보존 (v3.3 → v4.0 헤더 변경 외 동일)
if head -12 "$EVAL_MD" | grep -qE '^name: evaluator'; then
  pass "frontmatter name: evaluator 보존"
else
  fail "frontmatter name 누락"
fi

if head -12 "$EVAL_MD" | grep -qE '^model: opus'; then
  pass "frontmatter model: opus 보존"
else
  fail "frontmatter model 누락"
fi

if head -12 "$EVAL_MD" | grep -qE '^disallowedTools: Edit, Write, Agent'; then
  pass "frontmatter disallowedTools: Edit/Write/Agent 보존 (Read/Glob/Grep/Bash 허용)"
else
  fail "frontmatter disallowedTools 변형됨"
fi

# 2. v4.0 헤더 + 변경 요약 섹션
if grep -qE '^# Evaluator \(v4\.0\)' "$EVAL_MD"; then
  pass "v4.0 버전 헤더 갱신"
else
  fail "버전 헤더 v4.0 미갱신"
fi

if grep -qE '^## v4\.0 변경' "$EVAL_MD"; then
  pass "v4.0 변경 요약 섹션 신설"
else
  fail "v4.0 변경 요약 섹션 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C4-2: 4대 채점 기준 — class 분기 (code/content/hybrid/비주얼) ==="

# type: code (PROJECT_CLASS=code) 헤더
if grep -qE '^### type: code \(PROJECT_CLASS=code\)' "$EVAL_MD"; then
  pass "type: code 채점 기준 헤더"
else
  fail "type: code 헤더 누락"
fi

# type: content (PROJECT_CLASS=content) 신설
if grep -qE '^### type: content \(PROJECT_CLASS=content\) — v4\.0 신설' "$EVAL_MD"; then
  pass "type: content 채점 기준 헤더 (v4.0 신설)"
else
  fail "type: content 헤더 누락"
fi

# type: hybrid 신설
if grep -qE '^### type: hybrid \(PROJECT_CLASS=hybrid\) — v4\.0 신설' "$EVAL_MD"; then
  pass "type: hybrid 채점 기준 헤더 (v4.0 신설)"
else
  fail "type: hybrid 헤더 누락"
fi

# type: 비주얼 (legacy 보존)
if grep -qE '^### type: 비주얼 \(legacy' "$EVAL_MD"; then
  pass "type: 비주얼 (legacy) 보존"
else
  fail "type: 비주얼 헤더 누락"
fi

# code 채점 축에 cell_coverage + scenario_coverage 등장
if grep -qE 'cell_coverage.*matrix\.entities' "$EVAL_MD" && \
   grep -qE 'scenario_coverage.*matrix\.entities' "$EVAL_MD"; then
  pass "type: code에 cell_coverage + scenario_coverage 채점 축 명시"
else
  fail "type: code 채점 축에 coverage 누락"
fi

# content 채점 축 4종 (완결성/출처/리뷰/형식)
content_criteria=$(awk '/^### type: content/,/^### type: hybrid/' "$EVAL_MD")
for keyword in "완결성" "출처 무결성" "리뷰 증적" "형식 일관성"; do
  if echo "$content_criteria" | grep -qF "$keyword"; then
    pass "type: content 채점 축: ${keyword}"
  else
    fail "type: content 채점 축 누락: ${keyword}"
  fi
done

# hybrid 합산 공식
if grep -qE 'hybrid_score = \(code_lines × code_score' "$EVAL_MD"; then
  pass "hybrid 합산 공식 (변경량 가중 평균)"
else
  fail "hybrid 합산 공식 누락"
fi

if grep -qE 'min\(code_score, content_score\)' "$EVAL_MD"; then
  pass "hybrid strict mode (min) 명시"
else
  fail "hybrid strict mode 누락"
fi

# 평가자 [LOW 해소]: hybrid strict 발동 키워드 + 변경량 0 영역 상호작용 명시
hybrid_block=$(awk '/^### type: hybrid/,/^### type: 비주얼/' "$EVAL_MD")
if echo "$hybrid_block" | grep -qE 'coverage_mode: strict'; then
  pass "[LOW 해소] hybrid strict 발동 키워드 (coverage_mode: strict) sprint contract frontmatter 형식 명시"
else
  fail "[LOW] strict 발동 키워드 미정의"
fi

if echo "$hybrid_block" | grep -qE '한쪽 0이면 strict 비활성화 → weighted로 폴백'; then
  pass "[LOW 해소] strict + 변경량 0 영역 상호작용 — 한쪽 0 시 strict 폴백 명시"
else
  fail "[LOW] strict + 변경량 0 상호작용 모호"
fi

if echo "$hybrid_block" | grep -qE 'weighted 모드 \(기본\)' && \
   echo "$hybrid_block" | grep -qE 'strict 모드'; then
  pass "[LOW 해소] hybrid weighted/strict 두 모드 명시적 분기"
else
  fail "[LOW] hybrid 모드 분기 모호"
fi

# ============================================================================
echo ""
echo "=== WI-C4-3: cell_coverage / scenario_coverage 산출 의사코드 ==="

# cell_coverage 섹션
if grep -qE '^## cell_coverage / scenario_coverage 산출' "$EVAL_MD"; then
  pass "cell_coverage / scenario_coverage 산출 섹션"
else
  fail "산출 섹션 누락"
fi

# code class jq 의사코드 (entities × status)
if grep -qE 'jq .*entities.*\.status \| to_entries' "$EVAL_MD"; then
  pass "code class jq 의사코드 (entities × status to_entries)"
else
  fail "code class jq 의사코드 누락"
fi

# content class jq 의사코드 (sections × status)
if grep -qE 'jq .*sections.*\.status \| to_entries' "$EVAL_MD"; then
  pass "content class jq 의사코드 (sections × status to_entries)"
else
  fail "content class jq 의사코드 누락"
fi

# scenario_coverage parse-gherkin.sh 호출 (WI-C3p 의존)
if grep -qE 'parse-gherkin\.sh' "$EVAL_MD"; then
  pass "scenario_coverage가 parse-gherkin.sh 호출 (WI-C3p 의존)"
else
  fail "parse-gherkin.sh 호출 누락"
fi

# 학습 31 적용 — cell_coverage 의사코드 4건 + scenario_coverage 의사코드 모두 tr -d '\r'
# 평가자 [MEDIUM] 해소: cell_coverage code/content jq 4건 (total + done_n) 모두 적용 의무
cell_cov_block=$(awk '/^### cell_coverage/,/^### scenario_coverage/' "$EVAL_MD")
cell_cov_tr_count=$(echo "$cell_cov_block" | grep -E 'jq .*matrix\.json \| tr -d' | wc -l | tr -d ' ')
if (( cell_cov_tr_count >= 4 )); then
  pass "[학습 31][MEDIUM 해소] cell_coverage jq 4건(code total/done + content total/done) 모두 tr -d '\\r' (${cell_cov_tr_count}건)"
else
  fail "[학습 31] cell_coverage jq tr -d '\\r' 부족 (${cell_cov_tr_count}건, 4+ 기대)"
fi

# scenario_coverage matched_scenarios 누적 로직 명시 (CRITICAL 해소)
sce_cov_block=$(awk '/^### scenario_coverage/,/^### 평가 절차에 통합/' "$EVAL_MD")
if echo "$sce_cov_block" | grep -qE 'matched_scenarios=\$\(\(matched_scenarios \+ 1\)\)'; then
  pass "[CRITICAL 해소] scenario_coverage matched_scenarios 누적 로직 명시 (의사코드 자기 완결성)"
else
  fail "[CRITICAL] matched_scenarios 누적 로직 누락 — LLM 따라가도 0/N=0 항상 발생"
fi

# scenario_coverage 정규화 + grep -qF 매칭 명시 (stop-rag-check.sh:206-211 동일)
if echo "$sce_cov_block" | grep -qE "tr '\[:upper:\]' '\[:lower:\]'" && \
   echo "$sce_cov_block" | grep -qE 'grep -qF -- "\$gname'; then
  pass "[CRITICAL 해소] scenario_coverage 정규화 + grep -qF 매칭 (stop-rag-check.sh 섹션 8 동일 로직 명시)"
else
  fail "scenario_coverage 정규화/매칭 의사코드 누락"
fi

# 채점 환산 표 (1.00 → 10점, 0.80 → 7점, 0.50 → 4점, 0.00 → 0점)
if grep -qE '1\.00 → 만점' "$EVAL_MD" && \
   grep -qE '0\.80 → 7점' "$EVAL_MD" && \
   grep -qE '0\.50 → 4점' "$EVAL_MD"; then
  pass "coverage → 점수 환산 표 (1.00/0.80/0.50/0.00 anchor)"
else
  fail "coverage 환산 표 누락"
fi

# 0 나누기 방어 ($total > 0 ? ... : 0)
if grep -qE '\$total > 0 \? .* : 0' "$EVAL_MD"; then
  pass "산출 의사코드에 0 나누기 방어 (total > 0 ? : 0)"
else
  fail "0 나누기 방어 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C4-4: 안티패턴 (코드 + content + 비주얼) ==="

# 기존 코드 안티패턴 보존 + B1/B2/B3/B4 위반 추가
code_antipatterns=$(awk '/^### 코드 안티패턴/,/^### content 안티패턴/' "$EVAL_MD")
for pattern in "TODO" "FIXME" "B1 위반" "B2 위반" "B3 위반" "B4 위반"; do
  if echo "$code_antipatterns" | grep -qF "$pattern"; then
    pass "코드 안티패턴: ${pattern}"
  else
    fail "코드 안티패턴 누락: ${pattern}"
  fi
done

# content 안티패턴 신설
content_antipatterns=$(awk '/^### content 안티패턴/,/^### 비주얼 안티패턴/' "$EVAL_MD")
for pattern in "B6 위반" "B7 위반" "익명 리뷰 차단 위반" "TBD" "heading 위계 건너뜀" "코드블록 언어 명시 누락" "깨진 마크다운 링크"; do
  if echo "$content_antipatterns" | grep -qF "$pattern"; then
    pass "content 안티패턴: ${pattern}"
  else
    fail "content 안티패턴 누락: ${pattern}"
  fi
done

# 비주얼 안티패턴 보존 (legacy)
visual_antipatterns=$(awk '/^### 비주얼 안티패턴/,/^## few-shot/' "$EVAL_MD")
if echo "$visual_antipatterns" | grep -qF "보라색"; then
  pass "비주얼 안티패턴 보존 (legacy — 보라색 그라디언트)"
else
  fail "비주얼 안티패턴 변형됨"
fi

# ============================================================================
echo ""
echo "=== WI-C4-5: few-shot — content 9/7/4점 예시 (R2 재캘리브레이션) ==="

# content 프로젝트 few-shot 섹션
if grep -qE '^### content 프로젝트 예시 \(v4\.0 신설 — R2 재캘리브레이션\)' "$EVAL_MD"; then
  pass "content few-shot 섹션 (R2 재캘리브레이션)"
else
  fail "content few-shot 섹션 누락"
fi

content_fewshot=$(awk '/^### content 프로젝트 예시/,/^## 평가 절차/' "$EVAL_MD")

# 9/7/4점 anchor
for anchor in "9점 (우수)" "7점 (통과 경계)" "4점 (실패)"; do
  if echo "$content_fewshot" | grep -qF "$anchor"; then
    pass "content few-shot anchor: ${anchor}"
  else
    fail "content few-shot anchor 누락: ${anchor}"
  fi
done

# 9점 예시에 cell_coverage=1.00 명시
if echo "$content_fewshot" | grep -qE 'cell_coverage=1\.00'; then
  pass "content 9점 예시: cell_coverage=1.00 명시"
else
  fail "content 9점 예시 cell_coverage 누락"
fi

# 7점 통과 경계 — 1-2건 누락 허용
if echo "$content_fewshot" | grep -qE '1-2'; then
  pass "content 7점: 1-2건 부분 누락 허용 (통과 경계)"
else
  fail "content 7점 부분 허용 표현 누락"
fi

# 4점 실패 — 익명 리뷰 차단 위반
if echo "$content_fewshot" | grep -qE '익명 리뷰 차단 위반'; then
  pass "content 4점: 익명 리뷰 차단 위반 anchor"
else
  fail "content 4점 anchor 누락"
fi

# 기존 코드/비주얼 few-shot 보존 (회귀 차단)
if grep -qE '^### 코드 프로젝트 예시' "$EVAL_MD" && \
   grep -qE '^### 비주얼 프로젝트 예시' "$EVAL_MD"; then
  pass "기존 코드/비주얼 few-shot 보존 (legacy 회귀 차단)"
else
  fail "기존 few-shot 변형됨"
fi

# ============================================================================
echo ""
echo "=== WI-C4-6: 평가 절차 — §0 PROJECT_CLASS 판정 + matrix.json 직접 읽기 ==="

# §0 PROJECT_CLASS 판정 신설
if grep -qE '^### 0\. PROJECT_CLASS 판정 \(v4\.0\)' "$EVAL_MD"; then
  pass "평가 절차 §0 PROJECT_CLASS 판정 신설"
else
  fail "§0 PROJECT_CLASS 판정 누락"
fi

# .flowsetrc source + 기본값 code
if grep -qE 'source .flowsetrc' "$EVAL_MD" && \
   grep -qE 'PROJECT_CLASS:-code' "$EVAL_MD"; then
  pass "PROJECT_CLASS .flowsetrc 읽기 + 기본값 code"
else
  fail "PROJECT_CLASS 판정 의사코드 누락"
fi

# §1 스프린트 계약 type: code (legacy) 마이그레이션 (R9)
if grep -qE 'type: code \(legacy\)' "$EVAL_MD"; then
  pass "§1 스프린트 계약 type: code (legacy) 마이그레이션 (R9)"
else
  fail "type: code (legacy) 마이그레이션 누락"
fi

# §2 결과물 심층 검증에 matrix.json 직접 읽기 명시
section_2=$(awk '/^### 2\. 결과물 심층 검증/,/^### 3\. 채점표 작성/' "$EVAL_MD")
if echo "$section_2" | grep -qF "matrix.json 직접 읽어"; then
  pass "§2 matrix.json 직접 읽기 명시 (회의적 검증 — 자동 검증 신뢰 안 함)"
else
  fail "§2 matrix.json 직접 읽기 명시 누락"
fi

if echo "$section_2" | grep -qE 'parse-gherkin\.sh.*scenario_coverage'; then
  pass "§2 parse-gherkin.sh + scenario_coverage 산출 명시"
else
  fail "§2 scenario_coverage 산출 명시 누락"
fi

if echo "$section_2" | grep -qF ".flowset/reviews/"; then
  pass "§2 type: content reviews/ 파일 존재 grep 명시"
else
  fail "§2 reviews/ grep 명시 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C4-7: 채점표 SCORES — class별 분기 ==="

# SCORES (type=code) 섹션
if grep -qE 'SCORES \(type=code\):' "$EVAL_MD"; then
  pass "채점표 SCORES (type=code) 섹션"
else
  fail "SCORES (type=code) 누락"
fi

# SCORES (type=content) 섹션
if grep -qE 'SCORES \(type=content\):' "$EVAL_MD"; then
  pass "채점표 SCORES (type=content) 섹션"
else
  fail "SCORES (type=content) 누락"
fi

# SCORES (type=hybrid) 섹션
if grep -qE 'SCORES \(type=hybrid\):' "$EVAL_MD"; then
  pass "채점표 SCORES (type=hybrid) 섹션"
else
  fail "SCORES (type=hybrid) 누락"
fi

# code SCORES에 cell_coverage / scenario_coverage 슬롯
code_scores=$(awk '/SCORES \(type=code\):/,/SCORES \(type=content\):/' "$EVAL_MD")
if echo "$code_scores" | grep -qE 'cell_coverage=X\.XX' && \
   echo "$code_scores" | grep -qE 'scenario_coverage=X\.XX'; then
  pass "code SCORES에 cell_coverage + scenario_coverage 슬롯"
else
  fail "code SCORES coverage 슬롯 누락"
fi

# content SCORES에 .flowset/reviews/ 슬롯
content_scores=$(awk '/SCORES \(type=content\):/,/SCORES \(type=hybrid\):/' "$EVAL_MD")
if echo "$content_scores" | grep -qF ".flowset/reviews/"; then
  pass "content SCORES에 .flowset/reviews/ 증적 슬롯"
else
  fail "content SCORES reviews 슬롯 누락"
fi

# hybrid SCORES에 합산 모드 + git diff --shortstat
hybrid_scores=$(awk '/SCORES \(type=hybrid\):/,/WEIGHTED_TOTAL:/' "$EVAL_MD")
if echo "$hybrid_scores" | grep -qE '합산 모드: weighted \| strict' && \
   echo "$hybrid_scores" | grep -qE 'git diff --shortstat'; then
  pass "hybrid SCORES에 합산 모드 + git diff --shortstat 슬롯"
else
  fail "hybrid SCORES 슬롯 누락"
fi

# PROJECT_CLASS 슬롯 (출력 예시에)
if grep -qE 'PROJECT_CLASS: code \| content \| hybrid \| visual' "$EVAL_MD"; then
  pass "EVAL_RESULT 헤더에 PROJECT_CLASS 슬롯"
else
  fail "PROJECT_CLASS 슬롯 누락"
fi

# ============================================================================
echo ""
echo "=== WI-C4-8: 회귀 차단 — 기존 v3.3 핵심 섹션 보존 ==="

# 평가 철학 섹션 보존
for section in '^## 평가 철학' '^## 지향점' '^## 평가 절차' '^## 허위주장 방어' '^## 금지 사항'; do
  if grep -qE "$section" "$EVAL_MD"; then
    pass "v3.3 핵심 섹션 보존: $section"
  else
    fail "v3.3 핵심 섹션 변형됨: $section"
  fi
done

# 회의적 자세 (학습 27 — 평가자 핵심 원칙)
if grep -qE '회의적' "$EVAL_MD"; then
  pass "[학습 27] 회의적 평가 자세 보존"
else
  fail "[학습 27] 회의적 자세 누락"
fi

# 임계치 7.0 보존
if grep -qE 'THRESHOLD: 7\.0' "$EVAL_MD" && \
   grep -qE '\*\*7\.0 이상\*\*: PASS' "$EVAL_MD"; then
  pass "임계치 7.0 보존 (PASS 기준)"
else
  fail "임계치 7.0 변형됨"
fi

# 허위주장 방어 (v3.4) 보존
if grep -qE '허위주장률이 29-30%' "$EVAL_MD"; then
  pass "허위주장 방어 (v3.4) 보존"
else
  fail "허위주장 방어 변형됨"
fi

# 금지 사항 보존
forbidden=$(awk '/^## 금지 사항/,/^$/' "$EVAL_MD")
if echo "$forbidden" | grep -qF "코드/파일 수정 금지" && \
   echo "$forbidden" | grep -qF "점수 부풀리기 금지"; then
  pass "금지 사항 핵심 항목 보존 (수정 금지 + 점수 부풀리기 금지)"
else
  fail "금지 사항 변형됨"
fi

# ============================================================================
echo ""
echo "=== WI-C4-9: SSOT 정합 — WI-C1/C3-code/C3-content 산출 정확 반영 ==="

# B1 (matrix.status missing) — WI-C1/C5/C6 정합
if grep -qE 'B1' "$EVAL_MD"; then
  pass "B1 (matrix.status 미완) 참조 — WI-C1/C5/C6 정합"
else
  fail "B1 참조 누락"
fi

# B2 (auth_patterns) — WI-C3-code 정합
if grep -qE 'auth_patterns 매칭.*B2' "$EVAL_MD"; then
  pass "B2 (auth_patterns) 참조 — WI-C3-code 정합"
else
  fail "B2 참조 누락"
fi

# B3 (타입 중복) — WI-C3-code 정합
if grep -qE 'interface/type.*B3' "$EVAL_MD"; then
  pass "B3 (타입 중복) 참조 — WI-C3-code 정합"
else
  fail "B3 참조 누락"
fi

# B4 (Gherkin↔테스트) — WI-C3-code/C3-parse 정합
if grep -qE 'Gherkin.*테스트.*B4' "$EVAL_MD"; then
  pass "B4 (Gherkin↔테스트) 참조 — WI-C3-code/C3-parse 정합"
else
  fail "B4 참조 누락"
fi

# B6 (sources) — WI-C3-content 정합
if grep -qE 'sources.*B6' "$EVAL_MD"; then
  pass "B6 (sources) 참조 — WI-C3-content 정합"
else
  fail "B6 참조 누락"
fi

# B7 (completeness_checklist) — WI-C3-content 정합
if grep -qE 'completeness_checklist.*B7' "$EVAL_MD"; then
  pass "B7 (completeness_checklist) 참조 — WI-C3-content 정합"
else
  fail "B7 참조 누락"
fi

# matrix.json 경로 SSOT (.flowset/spec/matrix.json — WI-C1)
matrix_path_count=$(grep -c '\.flowset/spec/matrix\.json' "$EVAL_MD" || echo "0")
if (( matrix_path_count >= 3 )); then
  pass "matrix.json 경로 SSOT 일관성 (.flowset/spec/matrix.json ${matrix_path_count}회)"
else
  fail "matrix.json 경로 SSOT 부족 (${matrix_path_count}회)"
fi

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-C4 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-C4 SMOKE FAILED"
  exit 1
fi
