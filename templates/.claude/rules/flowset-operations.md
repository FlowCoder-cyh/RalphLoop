# FlowSet v3.0 운영 규칙

이 규칙은 FlowSet이 설치된 프로젝트에서 모든 세션(대화형 + 비대화형)에 적용됩니다.

## v3.0 추가 사항
- **Obsidian vault 연동**: VAULT_ENABLED=true 시 세션 간 맥락 자동 동기화
- **소유권 hook**: TEAM_NAME 설정 시 팀 소유 디렉토리만 수정 가능 (PreToolUse hook)
- **계약 기반 소통**: .flowset/contracts/ 파일로 팀 간 인터페이스 합의
- **Agent Teams**: 선택적 — 리드가 팀 구성, 역할별 작업 분배
- **팀간 리뷰 차단**: contracts/schema 변경 시 PreToolUse hook이 일반 팀원 차단 → 리드 경유 필수
- **기술부채 관리**: .flowset/tech-debt.md에 누적, 임계치(10건) 초과 시 preflight 경고
- **롤백**: `bash .flowset/scripts/rollback.sh [code|db|deploy]` — 정상 PR 프로세스 유지

## 0. requirements.md — 사용자 원본 (수정 절대 금지)
- `.flowset/requirements.md`는 `/wi:prd` 확정 시 사용자 요구사항에서 자동 생성됨
- **에이전트가 이 파일을 수정/삭제/이동하면 validate_post_iteration에서 위반 처리**
- 요구사항 변경이 필요하면 **사용자에게 확인**받고, **사용자가 직접 수정**
- 이 파일이 모든 검증의 기준 — 기획안(PRD)이 아닌 이 파일과 구현을 대조
- 기획 단계에서 범위 축소하려면 사용자 승인 필수 (에이전트 임의 축소 금지)

## 1. fix_plan.md — 읽기 전용
- **절대 직접 수정하지 않음** (sed, 에디터, 수동 체크 금지)
- 완료 상태는 `.flowset/completed_wis.txt`가 관리
- fix_plan 동기화는 flowset.sh가 루프 종료 시 자동 수행 (`reconcile_fix_plan`)
- fix_plan을 보고 "미완료"로 보여도 completed_wis.txt에 있으면 완료된 것

## 2. flowset.sh — 직접 생성/수정 금지
- `~/.claude/templates/flowset/`에서 복사된 것만 사용
- 직접 작성하거나 내용을 수정하지 않음
- 버전 확인: `grep FLOWSET_VERSION flowset.sh` → `2.0.0`이어야 함

## 3. PR 머지 — enqueue-pr.sh 사용
- `gh pr merge --auto --squash` 사용 금지
- 반드시 `bash .flowset/scripts/enqueue-pr.sh <PR번호>` 사용
- merge queue가 CI 통과 후 자동 머지 처리

## 4. completed_wis.txt — 단일 진실 원천 (SSOT)
- 수동으로 추가/삭제하지 않음
- flowset.sh의 `mark_wi_done`, `recover_completed_from_history`, `cleanup_stale_completed`가 관리
- 이 파일은 `.gitignore` 대상 (untracked, reset --hard에서 보존)

## 5. 루프 실행
- 새 터미널에서 실행: `bash .flowset/scripts/launch-loop.sh`
- 또는 직접: `bash flowset.sh`
- Claude Code 세션 안에서 `bash flowset.sh` 직접 실행 금지 (claude -p 중첩 불가)

## 6. uncommitted changes
- 루프 시작 전 uncommitted changes가 있으면 에러
- 루프 중 수동으로 파일 수정하지 않음
- 수정이 필요하면 루프를 먼저 멈추고 PR로 진행

## 7. E2E 테스트 — 워커 작성 금지
- E2E/Playwright 테스트 코드 작성은 비대화형 워커(`claude -p`)가 처리할 수 없음
- 워커는 브라우저를 띄울 수 없어 실제 UI 셀렉터를 확인할 방법이 없음
- PRD/코드에서 셀렉터를 추측하면 거의 전부 실패함
- E2E WI가 할당되면 스킵 처리 (guardrails.md에 기록)
- E2E 테스트는 대화형 세션에서 Playwright로 실제 화면을 보며 작성
- **단위 테스트(jest/vitest)는 워커가 TDD로 작성** — 이건 정상 처리

## 7.1 E2E 테스트 품질 기준 — 대화형 작성 시 필수 (v2.2.0)

E2E 테스트는 **실제 브라우저에서 사용자 동작을 재현**해야 합니다.

**필수 패턴 (Browser UI interaction):**
```typescript
// 1. 페이지 이동
await page.goto('/attendance');

// 2. UI 조작 (wireframes/의 data-testid 사용)
await page.fill('[data-testid="date-input"]', '2026-03-18');
await page.click('[data-testid="check-in-btn"]');

// 3. 응답 대기
await page.waitForResponse('**/api/attendance');

// 4. UI 상태 검증
await expect(page.locator('[data-testid="status"]')).toContainText('출근 완료');
```

**금지 패턴 (API shortcut — E2E가 아님):**
```typescript
// ❌ API 직접 호출은 E2E가 아니라 integration test
const response = await request.post('/api/attendance', { data: {...} });
expect(response.status()).toBe(201);
```

**규칙:**
- `request.get()`, `request.post()` 등 API 직접 호출은 E2E 테스트 본문에서 금지
  - 예외: `beforeAll`/`beforeEach`에서 seed 데이터 준비 시에만 허용
- 모든 E2E 테스트는 최소 1개의 `page.goto()` + UI 인터랙션(`click`, `fill`, `select`) 포함
- 셀렉터는 wireframes/의 `data-testid` 속성 사용 (CSS 클래스/태그 셀렉터 금지)
- CRUD 흐름: 생성 → 목록 확인 → 수정 → 삭제 → 목록에서 제거 확인 (전체 사이클)
- 3권한 검증: admin/employee/platform 각 역할에서 동일 흐름 테스트

**검증 체크리스트 (E2E 작성 완료 전):**
- [ ] `page.goto()` 있는가? (브라우저 네비게이션)
- [ ] `page.click()` / `page.fill()` 있는가? (UI 인터랙션)
- [ ] `data-testid` 셀렉터 사용하는가? (안정적 셀렉터)
- [ ] `request.post/get`이 본문에 없는가? (API shortcut 금지)
- [ ] UI 상태 변화를 검증하는가? (텍스트/요소 존재 확인)

## 8. 머지 대기 (v2.2.0)
- PR enqueue 후 **머지 완료를 확인한 다음** 다음 작업 시작
- 이전 PR이 머지 안 된 상태에서 다음 브랜치 작업 금지 (stale base 방지)
- 대화형: `enqueue-pr.sh --wait`로 머지 확인 후 `git checkout main && git pull`
- 루프: flowset.sh의 `wait_for_merge` / `wait_for_batch_merge`가 자동 처리
- timeout 15분 → 다음으로 이동 (guardrails 기록)

## 9. RAG 업데이트 강제 (v2.2.0)
- API, 페이지, 스키마 변경 시 `.claude/memory/rag/` 해당 파일 업데이트 필수
- 루프: `validate_post_iteration`이 자동 감지 → 다음 워커에 업데이트 지시 주입
- 대화형: Stop hook(`stop-rag-check.sh`)이 파일 변경 감지 → 알림
- `/mem:save` 시 RAG 동기화 검증
