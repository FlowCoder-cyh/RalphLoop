#!/usr/bin/env bash
set -euo pipefail

# run-smoke-WI-D1.sh — WI-D1 (CLAUDE.md / README v3.4 → v4.0 갱신) 전용 smoke
# 설계 §5 :230 (templates/CLAUDE.md class 분화) + 핸드오프 Group δ 1/2 이행:
#   1. templates/CLAUDE.md: 핵심 규칙 code/content/hybrid 3분기 + 9번 신설
#   2. README.md: v4.0 PROJECT_CLASS 시스템 + B1~B7 차단 메커니즘 + matrix SSOT
#   3. v3.4 핵심 섹션 보존 (회귀 차단)
# 사용: bash tests/run-smoke-WI-D1.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

CLAUDE_MD="templates/CLAUDE.md"
README_MD="README.md"

# ============================================================================
echo "=== WI-D1-1: templates/CLAUDE.md — class 분화 + 9번 신설 ==="

# 1. 구조 섹션에 v4.0 신규 디렉토리 (matrix/reviews/approvals)
if grep -qE '\.flowset/spec/matrix\.json.*v4\.0 매트릭스 SSOT' "$CLAUDE_MD"; then
  pass "구조 섹션에 matrix.json SSOT 명시"
else
  fail "matrix.json SSOT 명시 누락"
fi

if grep -qE '\.flowset/reviews/.*content class 리뷰 증적' "$CLAUDE_MD" && \
   grep -qE '\.flowset/approvals/.*content class 최종 승인' "$CLAUDE_MD"; then
  pass "구조 섹션에 reviews/ + approvals/ (content class 증적) 명시"
else
  fail "reviews/approvals 디렉토리 명시 누락"
fi

# 2. PROJECT_CLASS 시스템 표 신설
if grep -qE '^## v4\.0 PROJECT_CLASS 시스템' "$CLAUDE_MD"; then
  pass "PROJECT_CLASS 시스템 섹션 신설"
else
  fail "PROJECT_CLASS 시스템 섹션 누락"
fi

# 3. 핵심 규칙 (code class) — 9번 신설
if grep -qE '^## 핵심 규칙 \(code class\) — PROJECT_CLASS=code' "$CLAUDE_MD"; then
  pass "## 핵심 규칙 (code class) 헤더 (재명명)"
else
  fail "code class 헤더 누락"
fi

# code class 1~8번 보존 + 9번 신설
code_block=$(awk '/^## 핵심 규칙 \(code class\)/,/^## 핵심 규칙 \(content class\)/' "$CLAUDE_MD")
for n in 1 2 3 4 5 6 7 8 9; do
  if echo "$code_block" | grep -qE "^${n}\. \*\*"; then
    pass "code class 규칙 ${n}번 존재"
  else
    fail "code class 규칙 ${n}번 누락"
  fi
done

# 9번 — 증거 기반 완료 보고 (v4.0 신설 핵심)
if echo "$code_block" | grep -qE '9\. \*\*증거 기반 완료 보고\*\* \(v4\.0 신설\)'; then
  pass "9번 '증거 기반 완료 보고' v4.0 신설 명시"
else
  fail "9번 v4.0 신설 마커 누락"
fi

# 9번 본문에 cell_coverage/scenario_coverage 언급
if echo "$code_block" | grep -qE 'cell_coverage/scenario_coverage'; then
  pass "9번이 evaluator cell/scenario coverage (WI-C4 정합) 참조"
else
  fail "9번 cell/scenario coverage 참조 누락"
fi

# 4. 핵심 규칙 (content class) — 7개 신설
if grep -qE '^## 핵심 규칙 \(content class\) — PROJECT_CLASS=content \(v4\.0 신설\)' "$CLAUDE_MD"; then
  pass "## 핵심 규칙 (content class) 신설"
else
  fail "content class 헤더 누락"
fi

content_block=$(awk '/^## 핵심 규칙 \(content class\)/,/^## 핵심 규칙 \(hybrid class\)/' "$CLAUDE_MD")
for n in 1 2 3 4 5 6 7; do
  if echo "$content_block" | grep -qE "^${n}\. \*\*"; then
    pass "content class 규칙 ${n}번"
  else
    fail "content class 규칙 ${n}번 누락"
  fi
done

# content class 핵심 키워드 — sources/checklist/reviewer/approver/CHANGELOG/matrix.status
for keyword in "출처 URL 필수" "completeness_checklist 전체 done" "reviewer ≥ 1" "approver 최종 승인" "CHANGELOG 업데이트" "matrix.status 미완 셀 없음"; do
  if echo "$content_block" | grep -qF "$keyword"; then
    pass "content class 키워드: ${keyword}"
  else
    fail "content class 키워드 누락: ${keyword}"
  fi
done

# B1/B6/B7 참조 (WI-C3-content 정합)
for b_id in "B1" "B6" "B7"; do
  if echo "$content_block" | grep -qE "\b${b_id}\b"; then
    pass "content class에 ${b_id} 참조 — WI-C3-content/C5/C6 정합"
  else
    fail "content class ${b_id} 참조 누락"
  fi
done

# 5. 핵심 규칙 (hybrid class) — code + content 전부 적용
if grep -qE '^## 핵심 규칙 \(hybrid class\) — PROJECT_CLASS=hybrid \(v4\.0 신설\)' "$CLAUDE_MD"; then
  pass "## 핵심 규칙 (hybrid class) 신설"
else
  fail "hybrid class 헤더 누락"
fi

hybrid_block=$(awk '/^## 핵심 규칙 \(hybrid class\)/,/^## 자동 강제/' "$CLAUDE_MD")
if echo "$hybrid_block" | grep -qE 'code class 9개 \+ content class 7개 전부 적용'; then
  pass "hybrid class: code 9개 + content 7개 전부 적용 명시"
else
  fail "hybrid class 적용 범위 명시 누락"
fi

if echo "$hybrid_block" | grep -qE 'ownership\.json\.teams\[\]\.class'; then
  pass "hybrid class: ownership.json.teams[].class 경로별 매핑 명시"
else
  fail "hybrid class ownership 매핑 명시 누락"
fi

if echo "$hybrid_block" | grep -qE 'coverage_mode: strict'; then
  pass "hybrid class: coverage_mode: strict (WI-C4 정합) 명시"
else
  fail "coverage_mode: strict 참조 누락"
fi

# ============================================================================
echo ""
echo "=== WI-D1-2: templates/CLAUDE.md — 자동 강제 class별 분화 ==="

# 자동 강제 섹션 — 모든 class 공통 / code 전용 / content 전용 3분기
auto_block=$(awk '/^## 자동 강제/,EOF' "$CLAUDE_MD")

if echo "$auto_block" | grep -qE '^### 모든 class 공통'; then
  pass "자동 강제: 모든 class 공통 sub-섹션"
else
  fail "공통 sub-섹션 누락"
fi

if echo "$auto_block" | grep -qE '^### code class 전용'; then
  pass "자동 강제: code class 전용 sub-섹션"
else
  fail "code class 전용 sub-섹션 누락"
fi

if echo "$auto_block" | grep -qE '^### content class 전용 \(v4\.0 신설\)'; then
  pass "자동 강제: content class 전용 sub-섹션 (v4.0 신설)"
else
  fail "content class 전용 sub-섹션 누락"
fi

# 공통 항목에 검증 에이전트 + matrix.status 미완 셀
common_block=$(echo "$auto_block" | awk '/^### 모든 class 공통/,/^### code class 전용/')
if echo "$common_block" | grep -qF "검증 에이전트" && \
   echo "$common_block" | grep -qF "matrix.status 미완 셀"; then
  pass "공통: 검증 에이전트 + matrix.status 미완 셀 (B1)"
else
  fail "공통 핵심 항목 누락"
fi

# code 전용에 B2/B3/B4 차단 명시
code_auto=$(echo "$auto_block" | awk '/^### code class 전용/,/^### content class 전용/')
for b in "B2" "B3" "B4"; do
  if echo "$code_auto" | grep -qE "\b${b}\b"; then
    pass "code 전용 자동 강제: ${b} 차단 명시"
  else
    fail "code 전용 ${b} 차단 명시 누락"
  fi
done

# content 전용에 B6/B7 차단 명시
content_auto=$(echo "$auto_block" | awk '/^### content class 전용/,EOF')
for b in "B6" "B7"; do
  if echo "$content_auto" | grep -qE "\b${b}\b"; then
    pass "content 전용 자동 강제: ${b} 차단 명시"
  else
    fail "content 전용 ${b} 차단 명시 누락"
  fi
done

if echo "$content_auto" | grep -qF ".flowset/reviews/" && \
   echo "$content_auto" | grep -qF "approver 승인 증적"; then
  pass "content 전용: reviews/ + approvals 증적 명시"
else
  fail "content 전용 증적 항목 누락"
fi

# ============================================================================
echo ""
echo "=== WI-D1-3: templates/CLAUDE.md — v3.x 회귀 차단 (8개 핵심 규칙 보존) ==="

# 기존 1~8 규칙 텍스트 보존 (재명명되었으나 본문 변형 0)
for keyword in "requirements.md 수정 금지" "요구사항 충실 이행" "머지 확인 후 다음" "코드 숙지 먼저" "영향도 평가" "전수 조사" "사이드이펙트 사전 분석" "E2E = 브라우저 UI 조작"; do
  if grep -qF "$keyword" "$CLAUDE_MD"; then
    pass "v3.x 규칙 본문 보존: ${keyword}"
  else
    fail "v3.x 규칙 본문 변형됨: ${keyword}"
  fi
done

# 자동 강제 핵심 항목 보존 (재배치되었으나 본문 변형 0)
for keyword in "scope creep (10파일 초과)" "TODO/placeholder/stub" ".env/package-lock 수정" "RAG 미업데이트" "E2E API shortcut" "TDD 미수행"; do
  if grep -qF "$keyword" "$CLAUDE_MD"; then
    pass "v3.x 자동 강제 항목 보존: ${keyword}"
  else
    fail "v3.x 자동 강제 항목 변형됨: ${keyword}"
  fi
done

# ============================================================================
echo ""
echo "=== WI-D1-4: README.md — v4.0 갱신 ==="

# v4.0 명시
if grep -qE '\*\*v4\.0 \(현재\)\*\*' "$README_MD"; then
  pass "README v4.0 (현재) 명시"
else
  fail "README v4.0 명시 누락"
fi

# Keywords에 v4.0 관련 키워드 추가
if grep -qE 'matrix-based validation, code-content hybrid' "$README_MD"; then
  pass "Keywords에 matrix-based + code-content hybrid 추가"
else
  fail "v4.0 Keywords 누락"
fi

# v4.0 PROJECT_CLASS 시스템 섹션 신설
if grep -qE '^### v4\.0 PROJECT_CLASS 시스템' "$README_MD"; then
  pass "README v4.0 PROJECT_CLASS 시스템 섹션 신설"
else
  fail "PROJECT_CLASS 섹션 누락"
fi

readme_class_block=$(awk '/^### v4\.0 PROJECT_CLASS/,/^### FlowSet 동작 원리/' "$README_MD")

# 4-class 표 (code/content/hybrid/visual)
for class in "\`code\`" "\`content\`" "\`hybrid\`" "\`visual\`"; do
  if echo "$readme_class_block" | grep -qF "$class"; then
    pass "README 4-class 표: ${class}"
  else
    fail "README class 누락: ${class}"
  fi
done

# B1~B7 모두 명시 (B5는 SessionStart, evaluator/Stop hook 무관)
for b in "B1" "B2" "B3" "B4" "B6" "B7"; do
  if echo "$readme_class_block" | grep -qE "\b${b}\b"; then
    pass "README B-id 명시: ${b}"
  else
    fail "README B-id 누락: ${b}"
  fi
done

# matrix SSOT 경로 명시
if echo "$readme_class_block" | grep -qE '\.flowset/spec/matrix\.json'; then
  pass "README matrix.json SSOT 경로 명시"
else
  fail "matrix.json 경로 누락"
fi

# evaluator type 분기 (cell+scenario coverage / 출처+리뷰+형식 / weighted+strict)
if echo "$readme_class_block" | grep -qE 'cell\+scenario coverage' && \
   echo "$readme_class_block" | grep -qE 'weighted/strict'; then
  pass "README evaluator type 분기 (WI-C4 정합)"
else
  fail "README evaluator type 분기 누락"
fi

# Stop hook §6/7/8/9/10 명시 (WI-C3-code/C3-content 정합)
if echo "$readme_class_block" | grep -qE '§6/7/8/9/10'; then
  pass "README Stop hook §6/7/8/9/10 (WI-C3-code/C3-content 섹션 정합)"
else
  fail "Stop hook 섹션 번호 누락"
fi

# hybrid 동시 변경 처리 명시 (설계 §4 :158-181)
if echo "$readme_class_block" | grep -qE 'hybrid 동시 변경.*class별로 분리'; then
  pass "README hybrid 동시 변경 처리 명시"
else
  fail "hybrid 동시 변경 처리 누락"
fi

# FlowSet 동작 원리 헤더 v3.4 → v4.0 갱신
if grep -qE '^### FlowSet 동작 원리 \(v4\.0\)' "$README_MD"; then
  pass "FlowSet 동작 원리 헤더 v3.4 → v4.0 갱신"
else
  fail "FlowSet 동작 원리 v4.0 갱신 누락"
fi

# ============================================================================
echo ""
echo "=== WI-D1-5: README.md — v3.x 본문 회귀 차단 ==="

# v3.x 핵심 본문 보존 (사용법, 설치, 명령어 표 등)
for section in '^## 설치' '^## 사용법' '^## 명령어 요약' '^## 개발자 가이드' '^### 시스템 구조' '^## 지원 환경' '^## 라이선스'; do
  if grep -qE "$section" "$README_MD"; then
    pass "README v3.x 섹션 보존: $section"
  else
    fail "README v3.x 섹션 변형됨: $section"
  fi
done

# 명령어 7종 (init/prd/env/start/status/guide/note) 보존
for cmd in '/wi:init' '/wi:prd' '/wi:env' '/wi:start' '/wi:status' '/wi:guide' '/wi:note'; do
  if grep -qF "$cmd" "$README_MD"; then
    pass "README 명령어 보존: ${cmd}"
  else
    fail "README 명령어 누락: ${cmd}"
  fi
done

# 핵심 설계 원칙 보존
for principle in "요구사항 보호" "생성자-평가자 분리" "스프린트 계약" "채점 기반 평가" "Agent Teams 상주" "소유권 hook 강제" "vault 세션 연속성"; do
  if grep -qF "$principle" "$README_MD"; then
    pass "README 핵심 설계 원칙 보존: ${principle}"
  else
    fail "README 핵심 설계 원칙 변형됨: ${principle}"
  fi
done

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
if (( FAIL == 0 )); then
  echo "  ✅ WI-D1 ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ WI-D1 SMOKE FAILED"
  exit 1
fi
