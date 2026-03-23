# WI System - FlowSet Rules

FlowSet 실행 중 Claude가 반드시 따라야 하는 규칙입니다.
이 규칙은 `.claude/rules/`에 있으므로 컨텍스트 압축과 무관하게 항상 적용됩니다.

## 1. 반복 규칙
- **1회 반복 = 1개 WI만 처리** (한 번에 여러 WI를 하지 않음)
- 완료한 WI는 즉시 fix_plan.md에서 `- [ ]` → `- [x]` 업데이트
- 전체 WI가 `[x]`이면 `EXIT_SIGNAL: true` 출력

## 2. 구현 규칙
- 구현 전 반드시 기존 코드를 먼저 읽을 것 — "구현되지 않았다"고 가정 금지
- 플레이스홀더, TODO, stub 코드 절대 금지
- 검증 순서: lint → build → test (AGENT.md에 정의된 명령 사용)
- 검증 실패 시 최대 3회 재시도, 3회 실패 시 guardrails.md에 기록 후 다음 WI

## 3. 가드레일
- `.flowset/guardrails.md`의 규칙을 절대 위반하지 않음
- 새로운 실패 패턴 발견 시 guardrails.md에 즉시 추가
- `.flowset/` 디렉토리의 파일을 절대 삭제하지 않음

## 4. 상태 출력 형식
매 반복 종료 시 반드시 출력:
```
---FLOWSET_STATUS---
STATUS: IN_PROGRESS | COMPLETE
TASKS_COMPLETED_THIS_LOOP: {수}
FILES_MODIFIED: {수}
TESTS_STATUS: PASSING | FAILING | NOT_RUN
EXIT_SIGNAL: false | true
SUMMARY: {한 줄 요약}
---END_FLOWSET_STATUS---
```

## 5. Git 작업
- 브랜치 생성: main에서 분기 (`git checkout main && git pull && git checkout -b ...`)
- 커밋: `WI-NNN-[type] 한글 작업명` 형식 (wi-global.md 참조)
- PR 생성: `gh pr create` 사용
- main에 직접 커밋 절대 금지
