# FlowSet 운영 가이드

rules(`flowset-operations.md`)에서 분리된 참조 문서입니다.
특정 상황에서만 필요한 내용을 담고 있으며, 필요 시 로드하여 참조합니다.

## v3.0 기능 개요
- **Obsidian vault 연동**: VAULT_ENABLED=true 시 세션 간 맥락 자동 동기화
- **소유권 hook**: TEAM_NAME 설정 시 팀 소유 디렉토리만 수정 가능 (PreToolUse hook)
- **계약 기반 소통**: .flowset/contracts/ 파일로 팀 간 인터페이스 합의
- **Agent Teams**: 선택적 — 리드가 팀 구성, 역할별 작업 분배
- **팀간 리뷰 차단**: contracts/schema 변경 시 PreToolUse hook이 일반 팀원 차단 → 리드 경유 필수
- **기술부채 관리**: .flowset/tech-debt.md에 누적, 임계치(10건) 초과 시 preflight 경고
- **롤백**: `bash .flowset/scripts/rollback.sh [code|db|deploy]` — 정상 PR 프로세스 유지

## completed_wis.txt — 단일 진실 원천 (SSOT)
- 수동으로 추가/삭제하지 않음
- flowset.sh의 `mark_wi_done`, `recover_completed_from_history`, `cleanup_stale_completed`가 관리
- 이 파일은 `.gitignore` 대상 (untracked, reset --hard에서 보존)

## 루프 실행
- 새 터미널에서 실행: `bash .flowset/scripts/launch-loop.sh`
- 또는 직접: `bash flowset.sh`
- Claude Code 세션 안에서 `bash flowset.sh` 직접 실행 금지 (claude -p 중첩 불가)

## E2E 테스트

### 기본 규칙
- E2E/Playwright 테스트 코드 작성은 비대화형 워커(`claude -p`)가 처리할 수 없음
- 워커는 브라우저를 띄울 수 없어 실제 UI 셀렉터를 확인할 방법이 없음
- PRD/코드에서 셀렉터를 추측하면 거의 전부 실패함
- E2E WI가 할당되면 스킵 처리 (guardrails.md에 기록)
- E2E 테스트는 대화형 세션에서 Playwright로 실제 화면을 보며 작성
- **단위 테스트(jest/vitest)는 워커가 TDD로 작성** — 이건 정상 처리

### 품질 기준 — 대화형 작성 시 필수

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
// API 직접 호출은 E2E가 아니라 integration test
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
