# Project Rules

이 파일은 글로벌 규칙(Claude Code 설정 디렉토리 `rules/wi-*.md`, install.sh로 설치)을 상속하며,
프로젝트 고유 규칙만 추가로 정의합니다.

**글로벌 규칙과 충돌 시 글로벌 규칙이 우선합니다.**

## 프로젝트 정보
- 이름: {PROJECT_NAME}
- 타입: {PROJECT_TYPE}

## 워크플로우
- `/wi:init` → `/wi:prd` → `/wi:start` → `/wi:status`

## CI/CD
- PR 생성 시 자동 실행: lint → build → test → commit-check
- 모든 체크 통과 필수
- 머지 후 브랜치 자동 삭제

## 파일 구조
- `.ralph/`: Ralph Loop 상태 및 설정
- `docs/L0~L4`: 문서 계층구조
- `.github/`: CI/CD 워크플로우 및 PR 템플릿

## 프로젝트 고유 규칙
<!-- /wi:init 시 프로젝트 타입에 맞게 추가 -->
