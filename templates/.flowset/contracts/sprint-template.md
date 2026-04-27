# Sprint Contract — WI-{ID}-{type} {작업명}     (ID = 영숫자, 예: 001, A2a, C3code, E1, 001-1)

## 메타 (WI-C2, v4.0)
<!--
  PROJECT_CLASS는 본 sprint의 평가 기준을 결정합니다 (설계 §3 :48-52).
  - code:    Entity × CRUD × Role × Permission 매트릭스 + Gherkin 강제
  - content: Section × Role × Action 매트릭스 + 출처/완결성 강제
  - hybrid:  code + content 동시 보유, 경로별 분기
  matrix.json `class` 필드와 정확히 일치해야 함 (jq 비교 가능).
-->
- **PROJECT_CLASS**: `code` | `content` | `hybrid`
- **matrix.json 참조**: `.flowset/spec/matrix.json` (WI-C1이 생성한 SSOT)
- **본 sprint가 다루는 entity/section**:
  - code/hybrid: `entities[]` 키 (예: `Leave`, `Attendance`)
  - content/hybrid: `sections[]` 키 (예: `3.2-User-Flow`)

## 계약 상태 (리드가 관리)
- [ ] 리드 초안 작성
- [ ] 팀원에게 메시지로 전달 → OK 또는 수정 요청 받음
- [ ] 리드가 최종 확정

> 리드가 팀원의 OK를 받은 후 체크. 합의 전 구현 시작 금지.
> 체크박스는 리드만 관리한다. 팀원은 메시지로 OK/수정 요청만.

## 수용 기준 (Acceptance Criteria) — Gherkin 강제

> **자유 텍스트 금지** (WI-C2, 설계 §5 :218). 모든 수용 기준은 Gherkin 형식 (`Given/When/Then`)으로 기술합니다.
> - **Background**: 모든 시나리오 공통 사전 조건 (선택)
> - **Scenario**: 단일 동작 시나리오 (필수, 1개 이상)
> - **Scenario Outline + Examples**: 매개변수화 시나리오 (선택, Examples 데이터 행 수가 시나리오 수에 합산됨 — 설계 §4 :183-204 정규화 규칙)
> - 각 Scenario의 `name`은 대응 테스트(`describe`/`it` 또는 `test()` 블록)의 이름에 포함되어야 함 (이름 매칭 + 정규화 후 부분 문자열 — 설계 §4 :199-204).

```gherkin
# code 예시 (entity Leave)
Feature: Leave Request Management
  Background:
    Given a user with role "employee" is logged in

  Scenario: Create leave request as employee
    When the employee submits a leave request with valid dates
    Then the system creates a Leave record
    And returns HTTP 201

  Scenario: Manager approves leave request
    Given a leave request exists in "pending" status
    When a manager approves the request
    Then the Leave record status becomes "approved"

  Scenario Outline: Reject invalid date range
    When the user submits a leave request with <start_date> and <end_date>
    Then the system returns HTTP <status>
    And the response message is "<message>"
    Examples:
      | start_date | end_date   | status | message              |
      | 2026-12-01 | 2026-11-30 | 400    | end before start     |
      | 2026-13-01 | 2026-12-31 | 400    | invalid month        |
      | 2026-12-01 | 2026-12-32 | 400    | invalid day          |
```

```gherkin
# content 예시 (section 3.2-User-Flow)
Feature: User Flow section completeness

  Scenario: Writer completes draft
    Given the writer "alice" is editing section "3.2-User-Flow"
    When the writer marks the section as "ready for review"
    Then the matrix.sections["3.2-User-Flow"].status.draft becomes "done"
    And .flowset/reviews/3.2-User-Flow-* file is required for review status

  Scenario: Approver final approval
    Given the section "3.2-User-Flow" has review.status = "done"
    When approver "bob" creates .flowset/approvals/3.2-User-Flow-bob.md
    Then matrix.sections["3.2-User-Flow"].status.approve becomes "done"
```

**Gherkin 강제 규칙** (설계 §4 :116, :183-204):
- `Feature:` 헤더 1개 필수
- `Scenario:` 또는 `Scenario Outline:` 1개 이상 필수
- `Given` / `When` / `Then` 키워드 각 1개 이상 (Scenario당)
- 자유 텍스트 수용 기준 (체크박스 `- [ ]` 만 단순 나열) 금지 — Stop hook이 차단 (WI-C3-code 예약)
- Scenario name은 대응 테스트와 이름 매칭 — `parse-gherkin.sh` (설계 §4 :183) 출력의 `scenarios[].name`이 `describe`/`it`/`test()` 블록 이름에 포함되어야 PASS

## CRUD 매트릭스 (code | hybrid only) — matrix.json 셀 참조

<!--
  PROJECT_CLASS=code 또는 hybrid에서만 채움 (content는 행 비워둠).
  각 entity는 matrix.json `entities[]`의 동일 키에 연결되어야 함 (이름 정확 일치).
  status 컬럼은 matrix.json의 status 값을 복사 (missing | pending | done).
  WI-C1 verify_matrix_cells가 sprint-template ↔ matrix.json 키 정합을 차후 검증 (WI-C5 verify-requirements 예약).
-->

| Entity | C 셀 | R 셀 | U 셀 | D 셀 | type_ssot | endpoints |
|--------|------|------|------|------|-----------|-----------|
| {Leave} | missing | missing | missing | missing | prisma/schema.prisma#Leave | POST /api/leaves, GET /api/leaves, PATCH /api/leaves/:id, DELETE /api/leaves/:id |

**Role × CRUD 권한 (Permission 매트릭스)**:

| Role / Action | C | R | U | D |
|---------------|---|---|---|---|
| employee | true | own | own | false |
| manager | true | team | team | false |
| admin | true | all | all | true |

**셀 의무 규칙** (설계 §4 :109-117):
- CRUD 4셀 모두 채움 (누락 금지) — `matrix.entities[].status` 미완 셀 차단 (**B1**)
- Role × CRUD 권한 셀 모두 채움 (`employee/manager/admin × C/R/U/D` = N×4) — sprint contract 자체 의무 (auth_patterns **B2**는 별개, Stop hook §7에서 src/api 변경 시 검증)
- `type_ssot` 단일 SSOT 명시 (예: `prisma/schema.prisma#Leave`) — sprint contract 자체 의무 (타입 중복 **B3**은 별개, Stop hook §6에서 같은 이름 다른 파일 2개+ 검증)
- Gherkin 시나리오는 별도 .feature 파일로 분리, `matrix.entities[].gherkin[]`에 등록 — Gherkin↔테스트 매핑 (**B4**)은 Stop hook §8에서 검증

## Section 매트릭스 (content | hybrid only) — matrix.json 셀 참조

<!--
  PROJECT_CLASS=content 또는 hybrid에서만 채움 (code는 행 비워둠).
  각 section은 matrix.json `sections[]`의 동일 키에 연결되어야 함 (이름 정확 일치).
  status 컬럼은 matrix.json의 status 값 (missing | pending | done).
-->

| Section | draft | review | approve | sources (URL/path) | completeness_checklist |
|---------|-------|--------|---------|--------------------|------------------------|
| {3.2-User-Flow} | missing | missing | missing | research/user-interviews/2026-03-01.md | 목표, 흐름, 예외케이스 |

**Role × Action 권한 매핑**:

| Role / Action | draft | review | approve |
|---------------|-------|--------|---------|
| writer | true | false | false |
| reviewer | false | true | false |
| approver | false | false | true |

**셀 의무 규칙** (설계 §4 :119-138 + WI-B3 review-rubric.md):
- Section × draft/review/approve 3셀 모두 채움
- `sources[]` 1개 이상 (WI-B3 style-guide.md "섹션당 출처 URL 최소 1개" SSOT)
- `completeness_checklist[]` 모든 항목 done이어야 PASS (WI-C3-content 예약)
- review 단계 통과: `.flowset/reviews/{section}-{reviewer}.md` 파일 존재 (설계 §4 :143, 익명 리뷰 금지)
- approve 단계 통과: `.flowset/approvals/{section}-{approver}.md` 파일 존재 (설계 §4 :146)
- 평가 가중치 5축 (사실성/완결성/명료성/일관성/출처)는 WI-B3 `review-rubric.md`만 SSOT — 본 매트릭스에 직렬화하지 않음 (SSOT 단일성)

## 검증 방법 (Verification Method)
<!-- 평가자가 수용 기준을 어떻게 확인하는지. -->
<!-- 코드: 어떤 테스트, 어떤 명령 실행 -->
<!-- 비주얼/콘텐츠: 어떤 파일 확인, 어떤 기준으로 비교 -->
1. `bash .flowset/scripts/parse-gherkin.sh <feature_file>` — Scenario 수 산출 (설계 §4 :183)
2. 대응 테스트(`describe`/`it`/`test()`)가 Scenario name과 이름 매칭 (정규화 §4 :199-204)
3. `jq '.entities["{Entity}"].status' .flowset/spec/matrix.json` — code/hybrid CRUD status `done` 확인
4. `jq '.sections["{Section}"].status' .flowset/spec/matrix.json` — content/hybrid 3셀 status `done` 확인
5. content/hybrid review/approve: `ls .flowset/reviews/{section}-*` / `ls .flowset/approvals/{section}-*` 파일 존재

## 산출물 (Deliverables)
<!-- 이 WI가 완료되면 존재해야 할 파일/결과물. 경로 명시. -->
| # | 파일 경로 | 설명 |
|---|---------|------|
| 1 | | |

## 제약 (Constraints)
<!-- 이 WI에서 하면 안 되는 것 -->
- 자유 텍스트 수용 기준 작성 금지 — Gherkin 형식만 허용 (위 수용 기준 섹션 참조)
- matrix.json에 없는 entity/section을 sprint-template에 새로 만들지 않음 — `/wi:prd` Step 4가 신설하는 SSOT를 sprint-template은 소비만
- code/hybrid가 CRUD 4셀 미완 상태로 sprint 종료 금지 — `verify_matrix_cells || exit 1`이 차단
- content/hybrid가 sources[] 0건 또는 reviewer 파일 부재로 review 단계 통과 금지

## 평가 기준 유형
<!--
  type 4종 (WI-C2, v4.0):
  - code:    code class 또는 hybrid 코드 영역 — 기능완성도(30%) / 코드품질(25%) / 테스트(25%) / 계약준수(20%)
  - content: content class 또는 hybrid 콘텐츠 영역 — review-rubric.md 5축 SSOT (사실성 25 / 완결성 25 / 명료성 20 / 일관성 15 / 출처 15) — WI-C4 evaluator type 신설 예약
  - hybrid:  code + content 동시 평가, 경로별 자동 분기 (설계 §4 :158-181)
  - visual:  비주얼/디자인 산출물 — 디자인품질(25%) / 독창성(30%) / 기술완성도(25%) / 정확성(20%)
-->
type: code | content | hybrid | visual
