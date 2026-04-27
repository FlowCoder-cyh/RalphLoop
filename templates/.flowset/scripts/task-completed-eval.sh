#!/usr/bin/env bash
set -euo pipefail

# task-completed-eval.sh — TaskCompleted hook
# 태스크 완료 시 스프린트 계약이 존재하면 평가자 검증을 요구
# 스프린트 계약이 없으면 통과 (기존 호환)

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

INPUT=$(cat 2>/dev/null || true)

# 태스크 정보 추출 (TASK_DESC는 향후 확장을 위한 참조 슬롯)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // ""' 2>/dev/null || echo "")
# TASK_DESC는 evaluator 재실행 시 참조 예정 placeholder
# shellcheck disable=SC2034
TASK_DESC=$(echo "$INPUT" | jq -r '.task_description // ""' 2>/dev/null || echo "")

# WI 번호 추출 (WI-NNN 패턴, 영숫자 ID + 서브넘버링 지원 — WI-E3 통일)
WI_NUM=$(echo "$TASK_SUBJECT" | grep -oE 'WI-[0-9A-Za-z]+(-[0-9]+)?' | head -1)

if [[ -z "$WI_NUM" ]]; then
  # WI 번호 없으면 일반 태스크 — 통과
  exit 0
fi

# 스프린트 계약 파일 존재 확인
SPRINT_FILE=".flowset/contracts/sprint-${WI_NUM##WI-}.md"
if [[ ! -f "$SPRINT_FILE" ]]; then
  # 스프린트 계약 없으면 통과 (기존 호환)
  exit 0
fi

# 스프린트 계약이 있는데 평가 결과가 없으면 차단
EVAL_MARKER=".flowset/eval-results/${WI_NUM}.pass"
if [[ -f "$EVAL_MARKER" ]]; then
  # 평가 통과 마커가 있으면 완료 허용
  exit 0
fi

# 차단 — 평가자 검증 필요
echo "스프린트 계약이 존재합니다: $SPRINT_FILE" >&2
echo "평가자(evaluator) 에이전트로 검증을 수행한 뒤 태스크를 완료하세요." >&2
echo "" >&2
echo "평가 방법:" >&2
echo "  1. evaluator 서브에이전트를 spawn하여 $SPRINT_FILE 기준으로 채점" >&2
echo "  2. PASS(7.0+) 시 mkdir -p .flowset/eval-results && touch $EVAL_MARKER" >&2
echo "  3. 태스크 다시 완료 처리" >&2
exit 2
