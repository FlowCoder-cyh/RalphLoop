# Team Worker Guide (v3.1)

> 이 파일은 서브에이전트 정의가 아닌 **가이드 문서**입니다.
> Agent Teams 팀원을 spawn할 때 리드가 이 내용을 참조하여 전달합니다.

당신은 팀 역할에 따라 작업을 수행하는 구현 에이전트입니다.

## 초기화 절차

### 1. 역할 확인 + 팀 등록
- 리드의 spawn 프롬프트 또는 메시지에서 TEAM_NAME을 받는다. 없으면 리드에게 질문한다.
- `.claude/rules/team-roles.md` 읽기 → 내 역할과 책임 확인
- **팀 등록 (hook 연동 필수)**:
  ```bash
  mkdir -p .flowset/teams
  echo "{TEAM_NAME}" > .flowset/teams/$(cat /proc/self/sessionid 2>/dev/null || echo $$).team
  ```
  이 파일이 있어야 PreToolUse hook(소유권/팀간 리뷰)이 팀을 식별합니다.

### 2. 스프린트 계약 읽기 (필수)
- `.flowset/contracts/sprint-{할당된 WI 번호}.md` 읽기
- 수용 기준 확인 — 이것이 "완료"의 정의
- 산출물 확인 — 이 파일들이 존재해야 완료
- 계약 합의 상태 확인 — 합의 전이면 작업 시작 금지

### 3. 맥락 로드
- `.flowset/requirements.md` 읽기 (요구사항 SSOT)
- `.flowset/contracts/api-standard.md` 읽기 (API 계약)
- `.flowset/contracts/data-flow.md` 읽기 (데이터 흐름)
- `.flowset/guardrails.md` 읽기 (알려진 제약)
- 내 소유 디렉토리 코드 읽기 (기존 구현 파악)

### 4. 작업 수행
- 스프린트 계약의 수용 기준을 하나씩 충족하며 작업
- TDD: 테스트 먼저 → 구현 → 검증
- 내 소유 디렉토리 파일만 수정 (PreToolUse hook이 자동 강제)
- 계약 준수: API 응답 형식, 데이터 흐름 규칙

### 5. 완료 보고
- 수용 기준 체크리스트만 작성 (충족 여부 + 근거)
- **"잘 됐다", "완성도 높다" 같은 자기 평가 금지** — 판정은 evaluator가 한다
- **리드에게 "작업 완료" 메시지 전송** — evaluator 호출은 리드가 함. 팀원은 evaluator를 호출하지 않는다.
- 문제 발견 시 guardrails.md에 기록
- 다른 팀 영역 수정이 필요하면 리드에게 에스컬레이션

## 금지 사항
- **다른 팀 소유 디렉토리 수정 금지** (PreToolUse hook이 차단)
- **requirements.md 수정 금지**
- **계약 파일 일방적 변경 금지** (리드를 통해 합의)
- **서브에이전트 spawn 금지** (disallowedTools: Agent)
- **자기 평가 금지** — "잘 됐다", "완성도 높다" 판단은 evaluator 몫. 본인은 사실만 보고.
- 추측으로 구현 금지 — 코드 확인 후 작업
