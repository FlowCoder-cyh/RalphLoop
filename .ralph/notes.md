# Session Notes

## 이 프로젝트의 목적
settings 프로젝트 = PRD만 넣으면 자동으로 돌아가는 범용 개발 환경 템플릿.
테스트 후 스킬로 패키징하여 아무 프로젝트에서 재사용.

---

### [2026-03-12] wi:* 시스템 설계 — 전체 아키텍처
- **결정**: Ralph Loop + CI/CD + PR 워크플로우를 Claude Code 스킬(`wi:*`)로 패키징
- **근거**: 매번 수동 셋업 대신 `/wi:init` 한 번으로 전체 환경 구성
- **스킬 목록**: init, prd, start, status, guide, note (6개)

### [2026-03-12] Ralph Loop 채택
- **결정**: Ralph Wiggum Loop 방법론으로 자율 개발 구현
- **근거**: PRD 항목을 while 루프로 반복 투입, fix_plan.md 체크리스트로 진행 추적
- **참고**: snarktank/ralph (단순), frankbria/ralph-claude-code (프로덕션급) 두 구현체 조사 완료

### [2026-03-12] mem:* 시스템 제거 → 파일 기반 통합
- **결정**: mem:save/load/resume/note를 wi:* 파일 기반 시스템으로 완전 대체
- **근거**: Ralph Loop은 매 반복 독립적이라 세션 메모리 불필요. 모든 상태를 디스크에.
- **기각**: mem:* 유지안 — Ralph Loop과 이중 관리가 되어 복잡성 증가

### [2026-03-12] 규칙 단일 소스화 (.claude/rules/)
- **결정**: 모든 규칙을 ~/.claude/rules/wi-*.md 에 집중. 나머지 파일은 참조만.
- **근거**: .claude/rules/는 오토컴팩트 대상이 아님 (매 턴 시스템 레벨 주입). 14개 파일에 분산된 45개 규칙, 27% 중복 문제 해결.
- **규칙 파일**: wi-global.md, wi-ralph-loop.md, wi-utf8.md (3개)
- **우선순위**: rules/ > project.md > guardrails.md > CLAUDE.md

### [2026-03-12] 규칙 강제 5단계 방어
- **결정**: Claude가 규칙을 무시해도 기계적으로 차단하는 다층 방어
- **Layer 1**: .claude/rules/ (압축 불가, 매 턴 주입)
- **Layer 2**: Git hooks (commit-msg, pre-push) — 로컬 강제
- **Layer 3**: CI Gate (commit-check.yml, ci.yml) — 원격 강제
- **Layer 4**: ralph.sh validate_post_iteration() — 루프 내 사후 검증
- **Layer 5**: 규칙 우선순위 명시 (충돌 해결)

### [2026-03-12] /wi:prd에 결정 맥락(WHY) 보존
- **결정**: prd-state.json에 decisions[], user_constraints[] 필드 추가
- **근거**: 오토컴팩트 시 "왜 그렇게 결정했는지"가 유실되는 문제
- **기각**: 대화 전체 저장 — 너무 크고 비효율적

### [2026-03-12] /wi:note 스킬 추가
- **결정**: 어느 단계에서든 결정사항을 .ralph/notes.md에 즉시 기록
- **근거**: /wi:prd 외의 일반 대화(설계, 기획)에서도 오토컴팩트 시 맥락 유실 방지
- **파일 위치**: 프로젝트 내 .ralph/notes.md 또는 ~/.claude/projects/{encoded}/notes.md

### [2026-03-12] 이식성 — install.sh / uninstall.sh
- **결정**: settings 레포를 clone + install.sh로 다른 환경에서 동일 셋업
- **근거**: 스킬/규칙이 ~/.claude/ 하위에 있어서 PC별로 설치 필요
- **설치 항목**: skills → ~/.claude/commands/wi/, rules → ~/.claude/rules/, Git UTF-8 설정

### [2026-03-12] UTF-8 전면 적용
- **결정**: 모든 스크립트, Git, 에디터에 UTF-8 강제
- **근거**: Windows 기본 cp949로 한글 깨짐
- **적용**: ralph.sh (chcp+env), install.sh (git config), .gitattributes, .editorconfig

### [2026-03-12] 커밋 규칙 (2026-03-13 업데이트: 번호 추가)
- **결정**: `WI-NNN-[type] 한글 작업명` 형식 (NNN = 3~4자리 순번)
- **타입**: feat, fix, docs, style, refactor, test, chore, perf, ci, revert
- **브랜치**: `{type}/WI-NNN-{type}-작업명-kebab`
- **예외**: 시스템 커밋은 번호 없이 `WI-chore ...` 허용

### [2026-03-12] 문서 계층구조
- **결정**: L0(비전) > L1(대분류/도메인) > L2(중분류/모듈) > L3(소분류/기능) > L4(상세/태스크=WI)
- **근거**: PRD 구조와 WI 체크리스트를 1:1 매핑

### [2026-03-12] 미완료 항목
- 실제 테스트 프로젝트에서 /wi:init → /wi:prd → /wi:start 풀 사이클 미검증
- MCP 설치 후 동작 검증 로직 미구현 (start.md에서 설치만 하고 검증 안 함)

### [2026-03-12] 완료된 항목 (감사 결과 수정)
- PR 자동 머지: PROMPT.md에 `gh pr merge --auto --squash` + CI 폴링 추가
- install.sh/uninstall.sh: 3개 규칙 파일 동적 탐색으로 개선
- 소스 ↔ 설치 동기화: init.md, wi-global.md 수정 후 재동기화
- 46개 감사 이슈 중 CRITICAL 4, HIGH 6, MEDIUM 12, LOW 5 전부 수정
