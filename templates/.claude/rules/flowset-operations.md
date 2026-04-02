# FlowSet 운영 규칙 (프로젝트 보충)

글로벌 규칙(`wi-flowset.md`)을 상속. 여기는 매 작업마다 지켜야 하는 핵심 규칙만 기술.
상세 가이드: `.flowset/guides/flowset-operations-guide.md`

## 파일 보호
- `requirements.md`: 수정 절대 금지 — 변경 필요 시 사용자가 직접 수정
- `fix_plan.md`: 읽기 전용 — 완료 상태는 `completed_wis.txt`가 관리
- `flowset.sh`: 직접 생성/수정 금지 — 템플릿에서 복사된 것만 사용

## PR/머지
- PR 머지: `bash .flowset/scripts/enqueue-pr.sh <PR번호>` (gh pr merge 금지)
- 머지 완료 확인 후 다음 작업 시작 (stale base 방지, timeout 15분)
- uncommitted changes 있으면 루프 시작 불가

## E2E 테스트
- 비대화형 워커 작성 금지 — 대화형 세션에서 Playwright로 실제 화면 보며 작성
- 단위 테스트(jest/vitest)는 워커 TDD 작성 가능
- 상세 품질 기준: `.flowset/guides/flowset-operations-guide.md` 참조

## RAG
- API/페이지/스키마 변경 시 `.claude/memory/rag/` 해당 파일 즉시 업데이트
