# {PROJECT_NAME}

## 프로젝트 정보
- **이름**: {PROJECT_NAME}
- **타입**: {PROJECT_TYPE}
- **설명**: {PROJECT_DESCRIPTION}

## 빌드/테스트
```bash
# /wi:init에서 프로젝트 타입에 따라 자동 채워짐
```

## 구조
```
src/                    → 소스 코드
wireframes/             → 와이어프레임 HTML (PRD 확정 시 생성)
docs/                   → 문서 계층구조 (L0~L4)
.ralph/                 → Ralph Loop 설정
.github/                → CI/CD 워크플로우
.claude/rules/          → 프로젝트 규칙
.claude/memory/rag/     → RAG 참조 문서
```

## 규칙
- 글로벌 규칙: `~/.claude/rules/wi-*.md` 자동 적용
- 프로젝트 규칙: `.claude/rules/project.md`
- **RAG 규칙: `.claude/rules/rag-context.md`** — 작업 시 관련 RAG 자동 로드
- 커밋: `WI-NNN-[type] 한글 작업명` 형식
- main 직접 push 금지 → PR 필수

## 개발 프로세스 (반드시 준수)
1. **브랜치 먼저**: git 추적 파일 변경 시 무조건 브랜치 생성 후 작업
2. **커밋 전 확인**: `git status`로 빠진 파일 없는지 확인
3. **로컬 검증**: lint + build + test 전부 통과 후 push
4. **PR → enqueue**: `gh pr create` → `bash .ralph/scripts/enqueue-pr.sh <PR번호>`
5. **머지 확인 후 다음**: PR 머지 완료 확인 → `git checkout main && git pull` → 다음 브랜치
6. **순서 준수**: 이전 PR 머지 전 다음 브랜치 작업 금지 (stale base 방지)
7. **짜잘한 변경 단독 PR 금지**: 설정 변경은 다음 기능 브랜치에 포함
8. **main에서 직접 작업 금지**: reset --hard 시 변경 유실

## 구현 원칙 (모든 작업에 적용)
1. **코드 숙지 먼저**: 수정 대상 + 관련 파일을 전문 읽고 파악
2. **영향도 평가**: 변경이 영향을 미치는 모든 파일/API/페이지 사전 파악
3. **전수 조사**: 동일 패턴이 다른 곳에도 있는지 전수 검색
4. **사이드이펙트 사전 분석**: 깨질 수 있는 기존 기능 미리 식별
5. **장점 상쇄 없는 해결**: 한쪽 고치면서 다른 쪽 깨지는 해결 금지
6. **검증 후 커밋**: lint → build → test 통과 확인 후에만
