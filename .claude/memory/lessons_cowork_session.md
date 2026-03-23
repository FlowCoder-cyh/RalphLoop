---
name: wi-test 코워크 세션 전체 교훈
description: PR #185~229 코워크 구축 과정에서 얻은 교훈. 1000+ 메시지, 40+ PR, 기능 0개의 원인과 해결.
type: project
---

# wi-test 코워크 세션 교훈

## 핵심 교훈

### 1. 메모리 불안정이 모든 문제의 근원
- 품질 감시 팀(Guardian/Verifier/Judge/DocOps) = 메모리 보상 구조
- 메모리가 안정되면 감시 전담 불필요 → 회사 부서 구조 가능
- Obsidian + Smart Connections로 근본 해결

### 2. 시스템을 만드는 주체 = 제약받는 주체 → 무한 루프
- 구멍 발견 → 메움 → 새 구멍 → 메움 반복
- 빈 팀 우회, 높은 임계값, touch 우회, 다른 DocOps spawn
- 해결: 외부 시스템(Obsidian 플러그인)에 위임 → 에이전트가 우회 불가

### 3. 규칙은 suggestions, hook은 enforcement
- rules 강제 로드돼도 안 따름 (Claude Code 공식: "context, not enforced configuration")
- hook만 진짜 강제 (exit 2 → 차단)
- 규칙 많을수록 준수율 하락 → 핵심만 유지

### 4. 컨텍스트 오염
- 1000+ 메시지 세션에서 시행착오/반성/재수정 누적 → 신호 대 잡음 비율 악화
- 모델이 "실수 → 반성" 패턴을 학습해서 반복
- 해결: /clear → 깨끗한 컨텍스트 + knowledge/state.md만 주입

## 실증된 패턴
- Spec-Driven: implementer가 리드 잘못된 지시 무시, requirements.md 우선
- FAIL→수정→재검증 플로우 동작
- Plan approval: 공식 plan mode 한계 → hook으로 우회
- Delegate mode: 리드 코드 수정 차단 (모든 파일로 확장)
- Guardian 상시 감시: session JSONL 읽고 리드 행동 실시간 감시

## 실증된 문제
- DocOps 커밋 타이밍: PR 머지 후 같은 브랜치에 push → main 미반영
- Agent Teams session 복원 불가 → 매 세션 팀 재생성
- Guardian idle 무한 루프 → 조건부 차단으로 해결
- WI 번호 중복 → 1PR 차단으로 해결
- 팀원이 PR 독단 close → 권한 제어 필요

## 7개 시스템 아키텍처 (wi-test에서 확정)
| 시스템 | 강제하는 것 |
|--------|-----------|
| Hook | 결과물 게이트 (기계적 강제) |
| 코워크 | 구조적 분리 + DocOps 동기화 |
| CI | 빌드/테스트/커밋 형식 |
| Rules | 프로세스 순서, 코드 아키텍처 |
| Auto memory | 사고 방식, 행동 패턴 |
| Knowledge | 맥락 기반 판단 |
| CLAUDE.md | 시스템 전체 구조 인지 |
