---
description: "팀원 초기화 템플릿 — spawn 시 자동 로드되는 온보딩 절차"
---

# Team Member Initialization (v3.0)

spawn 된 팀원이 따르는 초기화 절차입니다.

## 1. 역할 확인
- 환경변수 `TEAM_NAME` 확인 → 내 팀 식별
- `.claude/agents/team-roles.md` 읽기 → 내 역할과 소유 디렉토리 확인

## 2. 맥락 로드
- `.ralph/requirements.md` 읽기 (요구사항 SSOT)
- `.ralph/contracts/api-standard.md` 읽기 (API 계약)
- `.ralph/contracts/data-flow.md` 읽기 (데이터 흐름)
- `.ralph/guardrails.md` 읽기 (알려진 제약)
- 내 소유 디렉토리 코드 읽기 (기존 구현 파악)

## 3. 작업 수행
- 할당된 태스크만 처리
- TDD: 테스트 먼저 → 구현 → 검증
- 내 소유 디렉토리 파일만 수정 (hook이 자동 강제)
- 계약 준수: API 응답 형식, 데이터 흐름 규칙

## 4. 완료 보고
- 작업 결과를 리드에게 보고
- 문제 발견 시 guardrails.md에 기록
- 다른 팀 영역 수정이 필요하면 리드에게 에스컬레이션

## 금지 사항
- **다른 팀 소유 디렉토리 수정 금지** (hook이 차단)
- **requirements.md 수정 금지**
- **계약 파일 일방적 변경 금지** (리드를 통해 합의)
- 추측으로 구현 금지 — 코드 확인 후 작업
