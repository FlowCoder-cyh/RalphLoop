# Team Roles (v3.0)

팀 역할 참조 문서 — 서브에이전트(lead-workflow, team-worker)가 참조합니다.

## 역할 매핑

| TEAM_NAME | 역할 | 소유 디렉토리 | 책임 |
|-----------|------|-------------|------|
| frontend | 프론트엔드 | src/app/**, src/components/** | UI/UX 구현, 페이지, 컴포넌트 |
| backend | 백엔드 | src/api/**, src/lib/** | API, DB 연동, 비즈니스 로직 |
| qa | QA | e2e/**, tests/** | E2E 테스트, 통합 테스트, 단위 테스트 |
| devops | DevOps | .github/**, .claude/**, .flowset/** | CI/CD, 인프라, 배포, 설정 |
| planning | 기획 | docs/**, wireframes/** | PRD, 와이어프레임, 요구사항 정리 |

## 공유 파일 (전팀 수정 가능)
- `package.json`, `package-lock.json`
- `tsconfig.json`
- `.gitignore`
- `CLAUDE.md`
- `prisma/schema.prisma`

상세 매핑은 `.flowset/ownership.json` 참조.

## 팀별 검증 책임

| TEAM_NAME | 자체 검증 |
|-----------|----------|
| frontend | lint + build + 컴포넌트 렌더링 |
| backend | lint + build + API 단위 테스트 |
| qa | 전체 테스트 suite 실행 |
| devops | CI 파이프라인 + 배포 설정 |
| planning | 요구사항 완전성, 와이어프레임 정합성 |

## 팀 간 소통
- 프론트 ↔ 백엔드: `.flowset/contracts/api-standard.md`
- 프론트 ↔ 기획: `wireframes/`, `.flowset/requirements.md`
- 백엔드 ↔ DevOps: `prisma/schema.prisma`, `.env.example`
- 전체: `.flowset/guardrails.md` (공유 제약)

## 동적 확장
프로젝트에 따라 역할 추가 가능:
- `design`: 디자인 시스템, 스타일 (src/styles/**, src/design-system/**)
- `data`: 데이터 파이프라인, 분석 (src/data/**)
- `mobile`: 모바일 전용 (src/mobile/**)

추가 시 `ownership.json`에 팀 + 디렉토리 매핑 등록.
