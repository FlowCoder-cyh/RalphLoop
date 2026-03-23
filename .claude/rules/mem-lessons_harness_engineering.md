---
name: Harness Engineering 분석 + 컨텍스트 오염
description: AI 에이전트 제어 3층 모델, 컨텍스트 오염 감지 기준, 속도>충실함 패턴 해결 방법
type: project
---

# Harness Engineering 분석

## 3층 모델
1. **Runtime harness** — 에이전트 실행 틀 (system prompt, tools, state, budget)
2. **Verification harness** — 결과 검증 틀 (테스트, 정적 검사, 스펙 비교, LLM judge)
3. **Eval harness** — 품질 반복 측정 (태스크셋, trace, 점수 집계, 회귀 감지)

## RalphLoop 대입
- Runtime: 강함 (PROMPT.md, ALLOWED_TOOLS, MAX_TURNS, circuit breaker)
- Verification: 중간 (CI gate + hook grep + 코워크 Verifier)
- Eval: 약함 (trace.jsonl 추가했으나 자동 재실행/점수 비교 없음)

## 핵심 원칙
- "agent가 '성공했다'고 말한 것 ≠ 환경 상태가 실제로 성공"
- 규칙은 suggestions, hook은 enforcement
- 규칙이 많을수록 준수율 떨어짐 → 핵심만 유지 + 나머지 hook
- 구현 에이전트와 검증 에이전트를 분리해야 편향 방지

## 컨텍스트 오염

### 정의
세션 내 시행착오/반성/재수정이 누적되어 원래 목적보다 "규칙 지키기/안 지키기"에 매몰된 상태.

### 감지 기준
| 신호 | 임계값 |
|------|--------|
| 같은 실수 반복 ("죄송합니다/맞습니다" 빈도) | 세션 내 10회+ |
| 시스템만 고치기 (PR 수 vs 기능 WI 완료 수) | PR 5개+ 기능 0개 |
| 챗바퀴 ("또/다시/반복" 키워드) | 누적 15회+ |
| hook 우회 시도 | 3회+ |
| auto-compact 발생 | 2회+ |
| 약속만 반복 ("다음부터/앞으로") | 5회+ |

### 해결
/clear → 새 세션. knowledge/state.md로 유용한 맥락만 주입. 잡음 제거.

## "속도 > 충실함" 패턴
- 메모리(규칙/auto memory)로 해결 안 됨 — "아는데 안 한 것"
- hook(기계적 차단)으로만 해결 가능
- 간접 개선: 시스템 단순화 → 마찰 ↓ → 우회 동기 ↓
- Obsidian 도입으로 DocOps/Guardian 의존 감소 → 시스템 단순화
