# Changelog

## [v3.0.0] - 2026-03-23

### Obsidian Vault 통합
- `vault-helpers.sh`: Obsidian Local REST API 연동 (읽기/쓰기/검색)
- `ralph.sh`: save_state()에서 vault state.md 자동 동기화
- `ralph.sh`: preflight()에서 vault 연결 확인 + graceful degradation
- `ralph.sh`: build_rag_context()에서 vault 시맨틱 검색 추가 (이전 세션 지식)
- `ralph.sh`: record_pattern()에서 vault에 패턴 기록
- `stop-rag-check.sh`: 세션 종료 시 vault에 변경사항 기록
- `.ralphrc`: VAULT_ENABLED, VAULT_URL, VAULT_API_KEY, VAULT_PROJECT_NAME 추가
- VAULT_ENABLED=false 기본값 — v2.x 호환, vault 없이도 동작

### 소유권 기반 파일 수정 제한
- `check-ownership.sh`: PreToolUse hook (Edit|Write 매칭)
- `ownership.json`: 팀별 소유 디렉토리 매핑 템플릿
- TEAM_NAME 미설정 시 무동작 (solo 모드 호환)
- hotfix/ 브랜치에서 소유권 제한 완화
- settings.json: PreToolUse + Stop hook 구성

### 계약 기반 팀 간 소통
- `.ralph/contracts/api-standard.md`: API 응답 형식, HTTP 상태 코드, 변경 규칙
- `.ralph/contracts/data-flow.md`: SSOT 엔드포인트, 팀 간 데이터 공유 규칙

### Agent Teams 템플릿
- `.claude/agents/lead-workflow.md`: 리드 5단계 워크플로우 (요구사항→복잡도→태스크→spawn→통합)
- `.claude/agents/spawn-template.md`: 팀원 초기화 절차
- `.claude/agents/team-roles.md`: 5개 기본 역할 (frontend/backend/qa/devops/planning)
- Agent Teams 없이도 전체 시스템 동작 — 선택적 활성화

### 스킬 업데이트
- `wi:init`: vault-helpers, check-ownership, ownership.json, contracts, agents 복사 추가
- `wi:start`: Phase 4.7 Vault 연동 설정 추가

### SessionStart hook + 컨텍스트 자동 주입
- `session-start-vault.sh`: startup/resume/clear/compact 모두에서 vault state.md 주입
- PostCompact은 additionalContext 미지원 (공식 스펙) → SessionStart(source:compact)가 대체

### 팀간 리뷰 차단 (PreToolUse)
- `check-cross-team-impact.sh`: contracts/, prisma/schema, requirements.md 변경 시 차단
- devops/planning 팀은 허용 (알림만), 일반 팀원은 리드 경유 필수

### 기술부채 관리
- `.ralph/tech-debt.md`: 부채 등록 템플릿 (P0/P1/P2 우선순위)
- `vault-helpers.sh`: vault_check_tech_debt() 임계치 경고
- `ralph.sh`: preflight에서 open 부채 10건 초과 시 경고

### 롤백/복구
- `rollback.sh`: code (git revert → PR), db (prisma migrate resolve), deploy (vercel rollback)
- 롤백도 정상 PR 프로세스 유지 (hotfix 제외)

### 계약 변경 알림 (PostToolUse)
- `notify-contract-change.sh`: contracts/ 변경 시 관련 팀 알림

### Agent 정의 공식 스펙 준수
- `lead-workflow.md`: name 필드, disallowedTools 적용
- `spawn-template.md` → `team-worker.md`: 정식 서브에이전트
- `team-roles.md`: agents/ → rules/ 이동 (참조 문서)

### 설계 원칙
- v2.x 하위 호환: VAULT_ENABLED=false, TEAM_NAME 미설정 시 기존 동작 유지
- vault 연결 실패 시 파일 기반 RAG 폴백 (graceful degradation)
- ralph.sh 메인 루프(Section 9) 구조 변경 없음

---

## [v2.2.0] - 2026-03-21

### 머지 대기 — stale base 완전 제거
- `enqueue-pr.sh --wait`: PR 머지 완료까지 15초 간격 폴링 (timeout 15분)
- Exit codes: 0=머지완료, 1=CI실패/PR닫힘, 2=timeout
- ralph.sh 순차 모드: `wait_for_merge()` — 워커 종료 후 머지 대기 → safe_sync_main
- ralph.sh 병렬 모드: `wait_for_batch_merge()` — batch 전체 머지 대기 → safe_sync_main
- PROMPT.md: 워커 CI 폴링 제거 — 머지 대기는 ralph.sh가 관리 (워커 턴 12~30% 절약)

### 와이어프레임 필수
- `/wi:prd` Step 3.5: HTML 와이어프레임 생성 (스킵 불가)
- data-testid 속성 필수 (E2E 셀렉터 기준)
- wireframes/{page}.html 저장, 사용자 피드백 → 확정
- PROMPT.md/AGENT.md: 와이어프레임 참조 규칙

### RAG 강제 매커니즘
- Stop hook (`stop-rag-check.sh`): 파일 변경 시 RAG 업데이트 자동 알림
- `.claude/settings.json`: Stop hook 등록
- ralph.sh `validate_post_iteration`: API/페이지/스키마 변경 시 RAG 미업데이트 감지
- `/wi:start` Phase 4.5: RAG 초기화 (PRD 도메인별 RAG 파일 + rag-context.md 자동 생성)

### 아키텍처 계약
- `/wi:start` Phase 4.6: `.ralph/contracts/` 자동 생성
  - `api-standard.md`: API 응답/에러 형식 표준
  - `data-flow.md`: 모델별 SSOT + 역할별 접근 경로
- PROMPT.md/AGENT.md: contracts/ 참조 규칙

### 검증 강화 (validate_post_iteration 확장)
- scope creep 감지 (변경 파일 10개 초과)
- 금지 파일 수정 감지 (.env, package-lock)
- 빈 구현 감지 (TODO/placeholder/stub)
- API 형식 검증 (contracts/ 존재 시)
- WI 수용 기준 자동 검증 (GET/POST 핸들러 매칭)
- requirements.md 수정 차단 + 자동 복원

### RALPH_STATUS 확장
- FILES_LIST, TESTS_ADDED, TESTS_TOTAL 필드 추가
- TESTS_ADDED=0 시 TDD 미수행 경고

### trace 구조화
- `log_trace()`: `.ralph/logs/trace.jsonl` (JSON Lines, 200건 rotation)
- iteration별: wi, result, files, elapsed, cost 기록

### 사용자 원본 요구사항 보호
- `/wi:prd` Step 6: `.ralph/requirements.md` 자동 생성 (사용자 원본 고정)
- 에이전트 수정 금지 — validate에서 변경 감지 시 위반 처리 + 자동 복원
- ralph-operations.md Section 0: requirements.md 수정 절대 금지

### 검증 에이전트 분리
- `verify-requirements.sh`: 별도 `claude -p` 실행 (Read/Grep/Glob만 허용)
- requirements.md vs git diff 대조 → 누락/불완전/미구현 판정
- ralph.sh 순차/병렬 모드: validate 후 자동 실행
- Stop hook: 소스 3파일+ 변경 시 자동 트리거

### E2E 테스트 품질 강제
- ralph-operations.md Section 7.1: E2E 품질 기준
  - 필수: page.goto + click/fill + data-testid
  - 금지: request.get/post (seed/setup 제외)
- Stop hook: E2E 파일에 API shortcut / UI 미사용 감지 → 경고

### 템플릿 강화
- CLAUDE.md: 핵심 규칙 8개 + 자동 강제 항목 명시
- project.md: 코드 품질 체크리스트 (경계분리/모듈화/캡슐화/재사용/하드코딩 금지)
- ralph-operations.md: v2.2.0 운영 규칙 (머지 대기, RAG, requirements 보호)

### 신규 파일
- `verify-requirements.sh`: 검증 전용 에이전트 스크립트
- `stop-rag-check.sh`: Stop hook (RAG + E2E + requirements + 검증 에이전트 트리거)
- `.claude/settings.json`: Stop hook 등록

---

## [v2.1.0] - 2026-03-16

### 워커 CRUD 강제
- `/wi:env` 후 DB 연결 확인되면 AGENT.md에 "mock 금지" 자동 주입
- PROMPT.md: Prisma 존재 시 하드코딩/mock 데이터 사용 금지 규칙 추가
- `/wi:prd`: DB 기술 스택 있으면 WI 설명에 `(Prisma {모델} CRUD)` 자동 명시
- `/wi:start` Phase 4-1: Prisma 스키마 감지 → DB 연결 테스트 → 조건부 주입
- 3중 방어: WI 설명 + AGENT.md + PROMPT.md (하나 무시해도 나머지에서 잡힘)
- DB 연결 실패 시 mock 금지 미주입 (기존 동작 유지, 장점 상쇄 방지)

### E2E 테스트 워커 작성 금지
- PROMPT.md: Step 3 "WI 유형 판별" 추가 — E2E WI는 스킵 + guardrails 기록
- `/wi:prd`: E2E 테스트를 WI로 포함하지 않도록 경고 추가
- `/wi:guide`: L4 규칙 테이블에 "E2E 금지" 행 추가
- `ralph-operations.md`: Section 7 "E2E 테스트 — 워커 작성 금지" 추가
- 근거: wi-test WI-088~096에서 111개 E2E 테스트 전멸 (셀렉터 추측 실패)

### enqueue-pr.sh 버그 수정
- grep 패턴 매칭 → merge queue API 존재 확인 방식으로 변경
- `gh api repos/.../rulesets`에서 merge_queue 타입 확인
- merge queue 있는데 enqueue 실패 → `--auto` (squash 없이) + 에러 메시지 출력
- merge queue 없음 → `--auto --squash` fallback (기존 동작)
- "merge queue 미지원" 오탐 문제 해결

### macOS 호환성
- ralph.sh: `sedi()` 래퍼 추가 (macOS BSD `sed -i ''` 호환)
- launch-loop.sh: macOS에서 tmux 우선 사용 (osascript fallback)
- tmux로 Claude Code 세션과 완전 독립 실행 (stdout 리다이렉트 문제 해결)

### 순차 모드 mark_wi_done 누락 수정
- 순차 모드에서 SHA 변경 시 `mark_wi_done()` 호출 추가
- 기존: `execute_parallel`에서만 호출 → 순차 모드에서 completed_wis.txt 미기록
- WI 머지 후 재실행되는 문제 해결

---

## [v2.0.0] - 2026-03-15

### 핵심 변경
- **ralph.sh v2.0.0**: 전면 리팩토링
  - fix_plan.md 읽기 전용 (루프 중 수정 금지)
  - completed_wis.txt = 단일 진실 원천 (SSOT)
  - safe_sync_main: 로컬 main에 커밋 없음 → reset --hard 안전
  - reconcile_fix_plan: 루프 종료 시 fix_plan 일괄 동기화 → 단일 PR
  - recover_completed_from_history: crash 후 git log에서 자동 복구
  - cleanup_stale_completed: PR 충돌 close 시 자동 재실행
  - resolve_conflicting_prs: 충돌 PR 자동 rebase → 실패 시 close + 재실행

### CI gate 강화
- TDD 강제 (PROMPT.md: RED → GREEN → 커밋)
- e2e.yml: 머지 후 Playwright 실행 → 실패 시 regression issue 자동 생성
- smoke 테스트: /wi:start Phase 5.5에서 도메인별 자동 생성
- WI-NNN-1 서브넘버링: regression fix WI 자동 추가

### GH Issue Regression
- CI/e2e 실패 → `gh issue create --label regression`
- inject_regression_wis: open issue → fix_plan에 WI-NNN-1-fix 추가
- closed issue → guardrails.md RAG 흡수

### Merge Queue
- 조직 계정: merge queue ruleset 자동 설정 (/wi:init)
- 개인 계정: strict: false fallback
- enqueuePullRequest GraphQL 연동
- enqueue-pr.sh 래퍼 스크립트

### 신규 스킬
- `/wi:env`: 인프라 환경 구성 (DB, 배포, Secrets 등록)

### 신규 스크립트
- `.ralph/scripts/enqueue-pr.sh`: merge queue PR 등록
- `.ralph/scripts/launch-loop.sh`: 새 터미널에서 루프 실행

### 운영 규칙
- `.claude/rules/ralph-operations.md`: 모든 세션에 자동 적용
  - fix_plan 수정 금지, enqueue-pr.sh 사용, completed_wis SSOT 등

### 도메인 분리 분석
- /wi:start에서 WI 수 + L1 도메인 분리 분석 → 병렬/순차 자동 권장

### 템플릿 복사 방식 변경
- init 스킬: ralph.sh 직접 생성 → `~/.claude/templates/ralph/`에서 복사
- 모든 프로젝트에서 동일한 v2.0.0 보장

### 기타
- commit-msg hook: WI-NNN-N-fix 서브넘버링 허용
- commit-check.yml: 동일 패턴
- pre-push hook: push 대상 ref 기반 판단 + merge queue 브랜치 예외
- .gitignore: completed_wis.txt, loop_state.json 추가
- MAX_TURNS: 25 → 40
- 429 false positive 수정 ("status":\s*429 패턴)

### 검증
- wi-test (FlowHR): 99 WI 완료, 중복 0회, fix_plan 충돌 0개
- MakeLanding: 소규모 프로젝트 테스트

---

## [v1.0.0] - 2026-03-14

### 초기 릴리즈
- Ralph Loop 기본 구조 (순차 + 병렬 worktree)
- RAG 시스템 (codebase-map, wi-history, patterns, guardrails)
- WI 기반 자동 개발 루프
- /wi:init, /wi:prd, /wi:start, /wi:status, /wi:guide, /wi:note 스킬
- CI/CD (lint, build, test, commit-check)
- Git hooks (commit-msg, pre-push)
