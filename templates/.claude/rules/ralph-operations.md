# Ralph Loop v2.0.0 운영 규칙

이 규칙은 Ralph Loop이 설치된 프로젝트에서 모든 세션(대화형 + 비대화형)에 적용됩니다.

## 1. fix_plan.md — 읽기 전용
- **절대 직접 수정하지 않음** (sed, 에디터, 수동 체크 금지)
- 완료 상태는 `.ralph/completed_wis.txt`가 관리
- fix_plan 동기화는 ralph.sh가 루프 종료 시 자동 수행 (`reconcile_fix_plan`)
- fix_plan을 보고 "미완료"로 보여도 completed_wis.txt에 있으면 완료된 것

## 2. ralph.sh — 직접 생성/수정 금지
- `~/.claude/templates/ralph/`에서 복사된 것만 사용
- 직접 작성하거나 내용을 수정하지 않음
- 버전 확인: `grep RALPH_VERSION ralph.sh` → `2.0.0`이어야 함

## 3. PR 머지 — enqueue-pr.sh 사용
- `gh pr merge --auto --squash` 사용 금지
- 반드시 `bash .ralph/scripts/enqueue-pr.sh <PR번호>` 사용
- merge queue가 CI 통과 후 자동 머지 처리

## 4. completed_wis.txt — 단일 진실 원천 (SSOT)
- 수동으로 추가/삭제하지 않음
- ralph.sh의 `mark_wi_done`, `recover_completed_from_history`, `cleanup_stale_completed`가 관리
- 이 파일은 `.gitignore` 대상 (untracked, reset --hard에서 보존)

## 5. 루프 실행
- 새 터미널에서 실행: `bash .ralph/scripts/launch-loop.sh`
- 또는 직접: `bash ralph.sh`
- Claude Code 세션 안에서 `bash ralph.sh` 직접 실행 금지 (claude -p 중첩 불가)

## 6. uncommitted changes
- 루프 시작 전 uncommitted changes가 있으면 에러
- 루프 중 수동으로 파일 수정하지 않음
- 수정이 필요하면 루프를 먼저 멈추고 PR로 진행
