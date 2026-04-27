# WI System - Core Rules (Canonical Source)

이 파일은 wi:* 시스템의 **유일한 규칙 원본**입니다.
다른 파일(CLAUDE.md, PROMPT.md, 스킬)은 이 규칙을 참조만 하며 재정의하지 않습니다.

## 1. 커밋 규칙
- 형식: `WI-NNN-[type] 한글 작업명` (NNN = 영숫자 ID, fix_plan.md 기준)
- NNN 허용 패턴: `[0-9A-Za-z]+(-[0-9]+)?` — 숫자(`001`/`015`) / 영숫자(`A2a`/`C3code`/`E1`) / 서브넘버링(`001-1`/`A2a-1`)
- 허용 타입: feat, fix, docs, style, refactor, test, chore, perf, ci, revert
- 예시:
  - 숫자 ID: `WI-001-feat 사용자 인증 추가`, `WI-015-fix 로그인 토큰 만료 처리`
  - 영숫자 ID: `WI-A2a-refactor lib/state.sh 모듈 분리`, `WI-C3code-fix evaluator MEDIUM 즉시 해소`
  - 서브넘버링: `WI-001-1-fix 후속 핫픽스`
- 번호 없는 예외: `WI-chore`, `WI-docs` (환경 셋업, PRD 문서 등 시스템 커밋)
- 학습 29 — `-` 추가 분절 금지: `WI-C3-content` ❌ → `WI-C3content` ✓ (NNN 자리는 한 분절)
- main/master 직접 push 절대 금지 — 반드시 PR을 통해서만 머지
- 커밋 메시지는 반드시 한글 작업명 포함

## 2. 브랜치 규칙
- feat: `feature/WI-NNN-feat-작업명-kebab`
- fix: `fix/WI-NNN-fix-작업명-kebab`
- chore: `chore/WI-NNN-chore-작업명-kebab`
- docs: `docs/WI-NNN-docs-작업명-kebab`
- refactor: `refactor/WI-NNN-refactor-작업명-kebab`
- 브랜치는 main에서 분기, 머지 후 자동 삭제

## 3. PR 규칙
- CI 게이트 전체 통과 필수 (lint, build, test, commit-check)
- `.github/PULL_REQUEST_TEMPLATE.md` 양식 준수
- PR 제목도 `WI-NNN-[type] 한글 작업명` 형식

## 4. 코드 규칙
- 플레이스홀더, TODO, stub 코드 절대 금지 — 완전한 구현만
- 기존 코드 스타일 및 패턴 준수
- 새 파일 생성 최소화 — 기존 파일 수정 우선
- 보안 취약점 금지 (OWASP Top 10)

## 5. 상태 관리
- 모든 상태는 파일 기반으로 관리 (mem:* 사용하지 않음)
- 프로젝트 상태 확인: `/wi:status`
- 상태 파일 위치: `.flowset/` 디렉토리
- 세션 간 상태 복원: `.flowset/prd-state.json`, `.flowset/fix_plan.md`, git history

## 6. 워크플로우
- `/wi:init` → 환경 셋업
- `/wi:prd` → PRD 생성 (대화형)
- `/wi:start` → MCP 탐색·설치 + FlowSet 가동
- `/wi:status` → 상태 확인
- `/wi:note` → 결정사항 즉시 기록
- `/wi:guide` → PRD 작성 가이드

## 7. 규칙 우선순위 (충돌 시)
```
1순위: .claude/rules/wi-*.md (이 파일들)
2순위: {project}/.claude/rules/project.md
3순위: .flowset/guardrails.md (프로젝트별 누적 규칙)
4순위: CLAUDE.md (프로젝트 정보 참조)
```
상위 규칙과 하위 규칙이 충돌하면 **상위를 따른다**.
