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
src/                    → 소스 코드 (code class)
docs/                   → 문서 계층구조 (L0~L4, content class)
content/                → content 본문 (content class — 옵션)
research/               → 출처 자료 (content class — 옵션)
wireframes/             → 와이어프레임 HTML (PRD 확정 시 생성)
.flowset/                 → FlowSet 설정
.flowset/requirements.md  → 사용자 원본 요구사항 (수정 금지)
.flowset/contracts/       → 팀 간 API 표준 + 데이터 흐름 계약 + 스프린트 계약
.flowset/spec/matrix.json → v4.0 매트릭스 SSOT (entities × CRUD / sections × draft·review·approve)
.flowset/ownership.json   → 팀별 소유 디렉토리 매핑 (teams[].class로 경로별 분류 — v4.0)
.flowset/reviews/         → content class 리뷰 증적 ({section}-{reviewer}.md)
.flowset/approvals/       → content class 최종 승인 증적 ({section}-{approver}.md)
.github/                → CI/CD 워크플로우
.claude/rules/          → 프로젝트 규칙 (자동 로드)
.claude/agents/         → Agent Teams 팀 역할 정의 + evaluator (v4.0 type=content/hybrid)
.claude/memory/rag/     → RAG 참조 문서
```

## v4.0 PROJECT_CLASS 시스템

`.flowsetrc`의 `PROJECT_CLASS` 값에 따라 본 CLAUDE.md의 적용 섹션이 결정됩니다 (기본값: `code`).

| PROJECT_CLASS | 적용 섹션 | 매트릭스 영역 | Stop hook 차단 |
|---------------|----------|--------------|---------------|
| `code` | "핵심 규칙 (code class)" | `matrix.entities[]` (CRUD × status) | B1/B2/B3/B4 |
| `content` | "핵심 규칙 (content class)" | `matrix.sections[]` (draft/review/approve × status) | B1/B6/B7 |
| `hybrid` | "핵심 규칙 (hybrid class)" — code 9개 + content 7개 전부 | 양쪽 모두 (`ownership.json.teams[].class`로 경로별 분류) | B1~B7 전체 |

## 핵심 규칙 (code class) — PROJECT_CLASS=code

(hook으로 강제 불가능한 판단 영역 — 반드시 숙지)

1. **requirements.md 수정 금지**: 사용자 원본 요구사항. 범위 축소 시 사용자 승인 필수.
2. **요구사항 충실 이행**: "나중에", "Phase 2로", "일단 빼고" 금지. 어려우면 확인을 구할 것.
3. **머지 확인 후 다음**: PR 머지 완료 → `git pull` → 다음 브랜치. 이전 PR 머지 전 다음 작업 금지.
4. **코드 숙지 먼저**: 수정 전 관련 파일 전문 읽기. 추측으로 구현 금지.
5. **영향도 평가**: 변경이 영향을 미치는 모든 파일/API/페이지 사전 파악.
6. **전수 조사**: 동일 패턴이 다른 곳에도 있는지 전수 검색. 부분 수정 금지.
7. **사이드이펙트 사전 분석**: 깨질 수 있는 기존 기능 미리 식별. 한쪽 고치면서 다른 쪽 깨지는 해결 금지.
8. **E2E = 브라우저 UI 조작**: `request.get/post`는 E2E가 아님. `page.goto → fill → click → 검증` 필수.
9. **증거 기반 완료 보고** (v4.0 신설): `matrix.entities[].status` 미완 셀 0 + Gherkin 시나리오 대응 테스트 존재 + auth 패턴 grep 통과 전까지 "완료" 보고 금지. Stop hook (stop-rag-check.sh §6/7/8) + verify-requirements.sh + evaluator (cell_coverage/scenario_coverage)가 자동 강제.

## 핵심 규칙 (content class) — PROJECT_CLASS=content (v4.0 신설)

1. **출처 URL 필수**: `matrix.sections[].sources[]` 모든 항목이 파일 존재 또는 URL 형식 OK여야 함. 깨진 링크 금지 (B6).
2. **completeness_checklist 전체 done**: section의 모든 checklist 항목이 본문에 등장. 미등장 시 Stop hook block (B7).
3. **단일 섹션당 reviewer ≥ 1 확인**: `.flowset/reviews/{section}-{reviewer}.md` 파일 1개 이상 존재. 익명 리뷰 차단.
4. **approver 최종 승인 증적**: `.flowset/approvals/{section}-{approver}.md` 파일 존재 + `matrix.sections[].status.approve == done`.
5. **포맷 일관성**: heading 위계 정확 (## 직후 #### 건너뜀 금지), 코드블록 언어 명시 (\`\`\`bash 등), 표/링크 정상.
6. **CHANGELOG 업데이트**: content 변경 시 `CHANGELOG.md`에 항목 추가 (publish 추적).
7. **matrix.status 미완 셀 없음**: section의 draft/review/approve 모두 done 상태. evaluator FAIL 강제 (B1).

## 핵심 규칙 (hybrid class) — PROJECT_CLASS=hybrid (v4.0 신설)

- **code class 9개 + content class 7개 전부 적용** — 변경 파일이 어느 영역에 속하는지에 따라 해당 규칙 적용.
- **경로별 class 태깅 준수**: `ownership.json.teams[].class` 필드로 경로 → class 매핑. 위반 시 PreToolUse hook block.
- **양쪽 영역 동시 변경 시**: 각 영역의 규칙을 모두 만족해야 함. evaluator hybrid 채점 (weighted 또는 strict mode — `coverage_mode: strict` sprint contract frontmatter로 발동).

## 자동 강제 (hook/validate/검증 에이전트 — 사람 개입 없이 동작)

### 모든 class 공통
- **검증 에이전트**: 소스 3파일+ 변경 시 자동 실행 — requirements.md vs 구현 대조, 누락/불완전 감지
- requirements.md 수정 → validate 차단 + 자동 복원
- RAG 미업데이트 → Stop hook 경고
- scope creep (10파일 초과) → validate 경고
- TODO/placeholder/stub → validate 경고
- .env/package-lock 수정 → validate 경고
- matrix.status 미완 셀 → evaluator FAIL (B1)

### code class 전용
- E2E API shortcut → Stop hook 경고
- TDD 미수행 (TESTS_ADDED=0) → validate 경고
- API 형식 미준수 → validate 경고
- GET/POST 수용 기준 미충족 → validate 경고
- 타입 중복 (interface/type 다른 파일 2개+) → Stop hook block (B3)
- auth_patterns 매칭 실패 → Stop hook block (B2)
- Gherkin↔테스트 매핑 실패 → Stop hook block (B4)

### content class 전용 (v4.0 신설)
- 출처 누락 (sources[] 깨진 파일/URL) → Stop hook block (B6)
- completeness_checklist 본문 미등장 → Stop hook block (B7)
- 리뷰 증적 부재 (.flowset/reviews/) → evaluator FAIL
- approver 승인 증적 부재 → evaluator FAIL
