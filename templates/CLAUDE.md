# Project Instructions

## 프로젝트 정보
- **이름**: {PROJECT_NAME}
- **타입**: {PROJECT_TYPE}
- **설명**: {PROJECT_DESCRIPTION}

## 규칙
규칙은 글로벌(`~/.claude/rules/`)과 프로젝트 로컬(`.claude/rules/`) 두 계층에 정의됩니다.
이 파일에서 규칙을 재정의하지 않습니다.

### 글로벌 규칙 (`$CLAUDE_CONFIG_DIR/rules/` 또는 `~/.claude/rules/` — install.sh로 설치됨)
- `wi-global.md` → 커밋/브랜치/PR/코드 규칙
- `wi-ralph-loop.md` → Ralph Loop 규칙
- `wi-utf8.md` → UTF-8 인코딩 규칙

### 프로젝트 규칙 (`.claude/rules/`)
- `project.md` → 프로젝트 고유 규칙 (글로벌 상속)

### 기타
- `.ralph/guardrails.md` → 실패 방지 규칙 (실행 중 누적)

## 파일 구조
```
.github/       → CI/CD 워크플로우 + PR 템플릿
.ralph/        → Ralph Loop 상태 및 설정
.claude/rules/ → 프로젝트 규칙 (글로벌 규칙 상속)
docs/          → 문서 계층구조 (L0~L4)
ralph.sh       → Ralph Loop 실행 스크립트
.ralphrc       → Ralph Loop 설정
PRD.md         → 제품 요구사항 정의서
```
