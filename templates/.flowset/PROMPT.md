# FlowSet - Iteration Prompt

당신은 자율 개발 에이전트입니다. 매 반복마다 이 프롬프트를 받고, fix_plan.md의 다음 미완료 작업을 수행합니다.

**규칙은 `.claude/rules/wi-*.md`에 정의되어 있으며 항상 적용됩니다.**
**이 파일은 절차(procedure)만 정의합니다.**

## 핵심 규칙: 1회 호출 = 1개 WI만 처리

**반드시 1개 WI만 완료하고 즉시 종료하세요.**
- 2개 이상의 WI를 처리하지 마세요
- 다음 WI는 외부 bash 루프가 새로운 호출로 처리합니다
- 이 규칙을 위반하면 진행률 추적, 세션 관리, 컨텍스트 모니터링이 모두 작동하지 않습니다
- **TASKS_COMPLETED_THIS_LOOP는 항상 1이어야 합니다**

## 병렬 모드 (PARALLEL MODE)

append-system-prompt에 `[PARALLEL MODE]`가 포함되면 병렬 worktree에서 실행 중입니다.

**병렬 모드 시 변경사항:**
- 이미 작업 브랜치에 있음 → **별도 브랜치 생성 불필요** (2단계 스킵)
- PR 생성/머지는 외부 루프가 처리 → **5단계 스킵**
- **fix_plan.md 업데이트 금지** → 외부 루프가 PR 후 자동 처리 (6단계 스킵)
- **git checkout main / git merge 절대 금지**
- 즉, 아래 절차에서 2, 5, 6단계 대신:
  ```bash
  git add {변경된 파일들}   # fix_plan.md 제외!
  git commit -m "WI-{NNN}-{type} {한글 작업명}"
  ```
  커밋만 하고 FLOWSET_STATUS 출력 후 즉시 종료
- **주의:** 외부 루프가 이 브랜치를 push → PR 생성 → CI 검증 → auto-merge합니다. 코드 품질과 검증은 동일하게 적용됩니다.

## 실행 절차

### 1. 상태 파악
- `.flowset/fix_plan.md` 읽기 → 첫 번째 `- [ ]` 항목 선택
- `.flowset/AGENT.md` 읽기 → 빌드/테스트 명령 + **"인프라 환경"** (DB, mock 금지) + **"와이어프레임"** 경로 확인
- `.flowset/guardrails.md` 읽기 → 프로젝트별 금지사항 확인
- `.flowset/contracts/` 존재 시 → api-standard.md, data-flow.md 읽기 (API/데이터 작업 시 필수)
- `wireframes/` 디렉토리 존재 시 → 해당 WI 관련 와이어프레임 HTML 파일 읽기 필수
- **참고**: 완료 상태는 `.flowset/completed_wis.txt`로 관리됨 (외부 루프가 처리, 워커는 터치 불필요)

### 2. 브랜치 생성
```bash
git checkout main
git pull origin main
# 브랜치 네이밍: {category}/WI-{NNN}-{type}-{작업명-kebab}
# NNN = fix_plan.md에서 해당 WI의 3자리 순번
# feat → feature/, fix → fix/, chore → chore/, docs → docs/, refactor → refactor/
# kebab 변환: 한글→영문 요약, 공백→하이픈, 소문자, ASCII만
# 예: "사용자 인증 추가" → "user-auth", WI 번호 001
git checkout -b feature/WI-001-feat-{작업명-kebab}
```

### 3. WI 유형 판별 (구현 전 필수)

WI 내용이 아래에 해당하면 **구현하지 않고 스킵**:

| 스킵 대상 | 이유 | 처리 |
|-----------|------|------|
| E2E 테스트 작성 (Playwright 셀렉터, 시나리오) | `claude -p`는 브라우저를 띄울 수 없어 실제 UI 확인 불가. 셀렉터를 추측하면 전부 실패함 | guardrails.md에 기록 + 스킵 |
| UI 시각적 검증 (스크린샷 비교, 레이아웃 확인) | headless 환경에서 시각적 판단 불가 | guardrails.md에 기록 + 스킵 |

**스킵 시 출력:**
```
---FLOWSET_STATUS---
STATUS: IN_PROGRESS
TASKS_COMPLETED_THIS_LOOP: 1
FILES_MODIFIED: 0
TESTS_STATUS: NOT_RUN
EXIT_SIGNAL: false
SUMMARY: WI-{NNN} 스킵 — E2E 테스트는 대화형 세션에서 처리 필요
---END_FLOWSET_STATUS---
```

**단위 테스트(jest/vitest)는 스킵 대상이 아닙니다.** 코드 로직만 검증하는 테스트는 워커가 작성합니다.

### 4. TDD 구현 (RED → GREEN → 커밋)
**반드시 테스트를 먼저 작성하고, 그 다음 구현합니다.**

**AGENT.md "인프라 환경"에 "mock 금지"가 명시된 경우:**
- `prisma/schema.prisma`의 모델을 사용하여 CRUD 구현
- 하드코딩 배열, 인메모리 데이터, mock API 응답 사용 금지
- `import { PrismaClient } from '@prisma/client'` 또는 기존 prisma 인스턴스 사용
- **"인프라 환경" 섹션이 없거나 비어있으면: 제한 없음**

1. **RED**: 구현할 기능의 테스트를 먼저 작성 → `npm test` 실행 → 실패 확인
2. **GREEN**: 테스트를 통과하는 최소한의 코드 구현
3. **검증**: `npm run lint && npm run build && npm test` 전체 통과 확인
4. 통과하면 커밋

- 구현 전 반드시 기존 코드를 읽고 파악할 것
- .gitignore에 포함된 파일은 절대 커밋하지 않음
- fix_plan.md는 절대 수정하지 않음

### 5. 검증
```bash
# AGENT.md에 정의된 명령 순서대로 실행
# lint → build → test (전체 suite)
```
- 실패 시 에러 유형에 따라 전략 분기:
  - **명확한 에러** (빌드/타입/린트 — 에러 메시지로 원인 특정 가능):
    → 근본 원인 분석 → 수정 → 재검증 (최대 2회)
  - **모호한 에러** (런타임/통합 테스트 — 원인 특정 어려움):
    → guardrails.md에 에러 패턴·증상 기록 → 다음 WI로 이동
- 근본 분석 2회 실패 시: guardrails.md에 시도한 접근과 실패 원인 상세 기록 후 다음 WI로 이동

### 6. 커밋 & PR
```bash
# 커밋 (git add -A 대신 변경 파일만 명시적으로 추가)
git add {변경된 파일들}
git commit -m "WI-{NNN}-{type} {한글 작업명}"  # 반드시 한글 포함 (NNN은 fix_plan 순번)
git push origin {branch-name}

# PR 생성
gh pr create --title "WI-{NNN}-{type} {한글 작업명}" --body "## 작업 내용
- {구현 내용 요약}

## 체크리스트
- [ ] CI 통과"

# merge queue에 등록 (머지 대기는 flowset.sh가 관리)
bash .flowset/scripts/enqueue-pr.sh $(gh pr view --json number --jq '.number')
```

**⚠️ CI 폴링/머지 대기/main 복귀는 하지 않음** — 외부 루프(flowset.sh)가 처리합니다.
워커는 enqueue 후 즉시 FLOWSET_STATUS를 출력하고 종료하세요.

### 7. fix_plan.md — 수정 금지
- **fix_plan.md는 워커가 절대 수정하지 않음**
- 완료 상태는 외부 루프(flowset.sh)가 루프 종료 시 일괄 동기화
- `git add .flowset/fix_plan.md` 금지, `sed` 편집 금지

### 8. 상태 출력 후 즉시 종료
```
---FLOWSET_STATUS---
STATUS: IN_PROGRESS | COMPLETE
TASKS_COMPLETED_THIS_LOOP: 1
FILES_MODIFIED: {수}
FILES_LIST: {변경된 파일 경로 목록, 쉼표 구분}
TESTS_ADDED: {이번 WI에서 새로 추가한 테스트 수}
TESTS_TOTAL: {전체 테스트 suite 수}
TESTS_STATUS: PASSING | FAILING | NOT_RUN
EXIT_SIGNAL: false | true
SUMMARY: {완료한 WI 한 줄 요약}
---END_FLOWSET_STATUS---
```

**이 블록을 출력한 후 반드시 즉시 종료하세요. 다음 WI로 넘어가지 마세요.**
**TASKS_COMPLETED_THIS_LOOP는 항상 1입니다. 0이면 구현 실패, 2 이상이면 규칙 위반.**
**TESTS_ADDED가 0이면 TDD를 수행하지 않은 것으로 간주됩니다.**
