---
name: prd
description: "대화형 PRD 생성 - 사용자와 대화하며 FlowSet 호환 PRD를 자동 작성"
category: workflow
complexity: advanced
mcp-servers: []
personas: [architect]
---

# /wi:prd - Interactive PRD Builder

> 사용자와 대화하며 프로젝트 요구사항을 추출하고, FlowSet이 바로 소화할 수 있는 PRD.md를 생성합니다.

## Triggers
- PRD 작성 요청
- 새 프로젝트 기획
- "PRD 만들어줘", "기획서 작성"

## Usage
```
/wi:prd [프로젝트에 대한 자유로운 설명]
```
인자가 없으면 처음부터 질문을 시작합니다.
인자가 있으면 해당 내용을 초기 컨텍스트로 활용하여 질문을 줄입니다.

## Behavioral Flow

### 원칙
- **한 번에 1~2개 질문만** (질문 폭격 금지)
- 사용자가 말한 내용에서 **최대한 유추** — 이미 파악된 건 다시 묻지 않음
- 애매한 건 **선택지를 제시**하여 골라받음
- 충분한 정보가 모이면 **즉시 PRD 초안 생성** → 피드백 받기
- **매 스텝 완료 시 `.flowset/prd-state.json`에 상태 자동 저장** (세션 중단 대비, 세션 메모리가 아닌 프로젝트 상태 파일)
- **모든 결정에 WHY를 기록** — `decisions[]`에 선택/기각/근거를 반드시 포함
- **사용자 원문 제약조건 보존** — `user_constraints[]`에 사용자 발언 그대로 기록
- 오토컴팩트가 발생해도 prd-state.json에서 전체 맥락 복원 가능해야 함

### Step 0: 이전 상태 복원 (세션 재개 시)

`.flowset/prd-state.json` 파일이 존재하면 읽어서 이전 대화 상태를 복원:

```json
{
  "step": 3,
  "project_name": "출퇴근 관리",
  "overview": { "name": "...", "goal": "...", "users": "...", "criteria": "..." },
  "tech_stack": {
    "language": "TypeScript",
    "framework": "Next.js",
    "db": "PostgreSQL",
    "reason": "프론트+백 통합, 30명 규모에 적합"
  },
  "L1": [
    {
      "name": "인증/계정",
      "confirmed": true,
      "L2": [...]
    }
  ],
  "decisions": [
    {
      "topic": "위치 검증 방식",
      "chosen": "IP 기반",
      "rejected": "GPS",
      "reason": "사용자 요청: GPS 불필요, IP만 사용",
      "turn": 5
    },
    {
      "topic": "기술 스택",
      "chosen": "Next.js + PostgreSQL",
      "rejected": null,
      "reason": "30명 규모, 프론트+백 통합 필요, 사용자가 스택 위임",
      "turn": 8
    }
  ],
  "user_constraints": [
    "GPS 미사용 (IP만)",
    "30명 규모"
  ],
  "draft_ready": false,
  "confirmed": false,
  "updated_at": "2026-03-12T15:30:00"
}
```

**필수 필드 설명:**
- `decisions[]`: 모든 결정의 선택/기각/근거를 기록 (컴팩트 후에도 WHY가 남음)
- `user_constraints[]`: 사용자가 명시한 제약조건 원문 기록
- `reason` 필드: 기술 스택, L1 구조 등 모든 선택에 근거 첨부

복원 후 중단된 스텝부터 이어서 진행.

### Step 1: 초기 컨텍스트 수집

사용자의 `$ARGUMENTS` 또는 첫 대화에서 아래를 파악:

```
파악 대상:
□ 무엇을 만드는가 (제품/서비스 한 줄 설명)
□ 누가 쓰는가 (대상 사용자)
□ 왜 만드는가 (해결하려는 문제)
□ 기술 스택 선호 (없으면 제안)
```

**첫 질문 예시** (인자가 없을 때):
```
어떤 프로젝트를 만들려고 하시나요?
자유롭게 설명해주세요. (예: "팀원 일정 관리 웹앱", "중고거래 API 서버" 등)
```

**인자가 있을 때**:
사용자가 제공한 설명을 분석하여 이미 파악된 항목을 체크하고,
빠진 것만 추가 질문.

### Step 2: 도메인 구조 탐색 (L1~L3)

파악된 프로젝트에서 자연스럽게 도출되는 도메인을 제안:

```
말씀하신 내용으로 보면 이런 구조가 될 것 같습니다:

L1 대분류:
  1. 인증/계정
  2. 상품 관리
  3. 주문/결제

맞나요? 빠진 영역이나 수정할 부분이 있으면 알려주세요.
```

사용자 확인 후, 각 L1에 대해 L2(모듈)와 L3(기능)를 제안:

```
"인증/계정" 영역을 좀 더 구체화하면:

L2 모듈:
  - 회원가입 → L3: 이메일 가입, 소셜 로그인
  - 로그인 → L3: JWT 인증, 토큰 갱신
  - 프로필 → L3: 정보 수정, 비밀번호 변경

추가하거나 빼야 할 게 있나요?
```

### Step 3: 기술 스택 확정

사용자의 선호가 없으면 프로젝트 특성에 맞게 제안:

```
이 프로젝트에 적합한 스택을 제안합니다:

- 언어: TypeScript
- 프레임워크: Next.js (프론트+백 통합)
- DB: PostgreSQL (Prisma ORM)
- 인프라: Vercel
- 테스트: Vitest + Playwright

이대로 갈까요? 변경하고 싶은 부분이 있으면 말씀해주세요.
```

### Step 3.5: 와이어프레임 생성 (필수)

L1 도메인별 핵심 페이지의 HTML 와이어프레임을 생성합니다. **스킵 불가.**

```
절차:
1. L1 도메인별 핵심 페이지 목록 추출 (L2/L3 기반)
   - 각 도메인의 메인 페이지 + CRUD 화면 식별
   - 네비게이션 구조 (사이드바, 탑바, 라우팅) 설계

2. 페이지별 HTML 와이어프레임 생성:
   - 시맨틱 HTML + 최소 inline 스타일 (레이아웃 확인용)
   - data-testid 속성 필수 포함 (향후 E2E 테스트 연동)
   - 주요 UI 요소: 테이블, 폼, 버튼, 모달, 탭
   - 네비게이션 링크 연결

3. wireframes/{page-name}.html 로 저장

4. 사용자에게 와이어프레임 제시:
   "와이어프레임을 생성했습니다. 브라우저에서 확인해주세요:
    wireframes/index.html (전체 목록)
    wireframes/{page}.html (개별 페이지)

    수정할 부분이 있으면 말씀해주세요."

5. 피드백 → 수정 반복 (확정까지)

6. 확정 후 prd-state.json에 wireframe_confirmed: true 기록
```

**와이어프레임 규칙:**
- 각 페이지에 `data-testid` 속성 필수 (E2E 셀렉터 기준)
- 레이아웃/구조만 정의, 스타일링은 개발 시 적용
- index.html에 전체 페이지 목록 + 링크 포함
- 워커가 구현 시 와이어프레임의 구조를 따라야 함

### Step 4: L4 태스크 생성

L3까지 확정되면 각 기능별 구체적 태스크를 자동 생성.
이 단계는 사용자에게 일일이 묻지 않고 **자동 도출**:

```
자동 생성 규칙:
- 각 L3 기능 → 1~5개 L4 태스크로 분해
- 순서: 스키마/모델 → API → UI → 단위 테스트
- 1태스크 = 파일 5개 이내 수정, 1컨텍스트 윈도우 완료 가능
- 각 태스크에 수용 기준 포함
- UI 태스크는 해당 와이어프레임 참조: "(wireframes/{page}.html 참조)" 포함
```

**⚠️ E2E 테스트는 WI로 포함하지 않음:**
- `claude -p` 워커는 브라우저를 띄울 수 없어 실제 UI 셀렉터를 확인할 수 없음
- PRD/코드에서 셀렉터를 추측하면 거의 전부 실패함 (wi-test WI-088~096 사례)
- E2E 테스트는 대화형 세션에서 Playwright로 실제 화면을 보며 작성해야 함
- **단위 테스트(jest/vitest)는 WI에 포함** — 코드 로직 검증은 워커가 TDD로 처리
- smoke 테스트는 `/wi:start` Phase 5.5에서 대화형으로 자동 생성

**⚠️ DB 기술 스택이 있으면 WI 설명에 Prisma 모델 명시:**
- 기술 스택에 DB(PostgreSQL/MySQL 등 + Prisma ORM)가 포함된 경우:
  - WI 설명에 `(Prisma {모델명} CRUD)` 자동 포함
  - 예: "출근 기록 API 구현" → "출근 기록 API 구현 (Prisma AttendanceRecord CRUD)"
- 워커가 WI 설명만 보고도 Prisma를 사용해야 함을 인지할 수 있어야 함
- DB가 없는 프로젝트는 해당 없음

**⚠️ WI 설명에 데이터 흐름 + 수용 기준 포함:**
- API 태스크: SSOT 엔드포인트 명시 + HTTP 메서드 + 응답 형식
  - 예: "출근 기록 API (SSOT: /api/attendance, GET+POST, api-standard.md 준수)"
- UI 태스크: 호출할 API + 성공 시 동작 명시
  - 예: "출근 폼 UI → POST /api/attendance → 성공 시 목록 리프레시 (wireframes/attendance.html 참조)"
- 수용 기준: 검증 가능한 1줄
  - 예: "수용 기준: POST 호출 시 DB에 레코드 생성 + 에러 시 400 반환"
- `/wi:start`에서 .flowset/contracts/data-flow.md가 있으면 SSOT 엔드포인트 자동 참조

### Step 5: PRD 초안 생성 & 피드백

모든 정보가 모이면 **PRD.md 초안을 즉시 생성**하여 보여줌:

```
PRD 초안을 생성했습니다. 확인해주세요:

[PRD 전문 출력]

수정할 부분이 있으면 말씀해주세요.
"확정"이라고 하시면 PRD.md로 저장합니다.
```

### Step 6: 확정 & 저장

사용자가 확정하면:

```bash
# PRD.md 저장
Write PRD.md (프로젝트 루트)

# docs/ 계층에 분배
Write docs/L0-vision/README.md
Write docs/L1-domain/{name}.md (각 대분류별)
Write docs/L2-module/{name}.md (각 중분류별)
Write docs/L3-feature/{name}.md (각 소분류별)
```

확정 후:
```bash
# prd-state.json 업데이트
{ "step": 6, "confirmed": true, "updated_at": "..." }

# prd-state.json은 삭제하지 않음 (wi:status에서 참조)
```

**사용자 원본 요구사항 고정 (에이전트 수정 금지):**
```bash
# .flowset/requirements.md 생성
# prd-state.json의 user_constraints[] + decisions[]에서 추출
# 이 파일은 사용자 원본이며, 에이전트가 절대 수정하지 않음
# 매 커밋 시 이 파일 기준으로 구현 누락 여부 검증됨
```

`.flowset/requirements.md` 형식:
```markdown
# 사용자 원본 요구사항 (수정 금지)
# 이 파일은 /wi:prd 확정 시 자동 생성됩니다.
# 에이전트가 이 파일을 수정하면 validate_post_iteration에서 위반으로 감지됩니다.

## 사용자 제약조건
{user_constraints[] 각 항목을 그대로 기록}

## 사용자 결정사항
{decisions[] 각 항목: chosen + reason}

## 기능 요구사항 (L3 기준)
{PRD의 L3 기능별 1줄 요약 — 검증 키워드 포함}
예:
- 출근/퇴근 기록: IP 기반 검증, 실시간 기록, API 연동
- 휴가 신청: 잔여 연차 계산, 승인 워크플로우, 이메일 알림
- 고용지원금: 외부 API 연동(고용24), 자동 매칭
```

안내 출력:
```
PRD가 확정되었습니다.

📄 PRD.md 저장 완료
📁 docs/ 계층 문서 생성 완료
🔒 .flowset/requirements.md 생성 (사용자 원본 — 수정 금지)

다음 단계: /wi:start 로 FlowSet을 시작하세요.
```

## PRD 출력 형식

생성되는 PRD.md는 반드시 아래 구조를 따름:

```markdown
# {프로젝트명} PRD

## 프로젝트 개요
- **이름**: {프로젝트명}
- **목표**: {한 줄 목표}
- **대상 사용자**: {사용자 정의}
- **성공 기준**: {측정 가능한 목표}

## 기술 스택
- **언어**: {언어}
- **프레임워크**: {프레임워크}
- **DB**: {DB}
- **인프라**: {인프라}
- **테스트**: {테스트 프레임워크}
- **기타**: {추가 도구}

## L1: {대분류명}

### L2: {중분류명}

#### L3: {소분류명}
{기능 설명}

##### 태스크 (L4)
1. **{태스크명}**
   - {구현 내용}
   - 수용 기준: {검증 방법}

## 비기능 요구사항
- {항목}

## 외부 연동
- {서비스}: {용도}
```

## 대화 예시

```
사용자: /wi:prd 팀원들 출퇴근 관리하는 웹앱 만들려고

Claude: 출퇴근 관리 웹앱이군요.
        몇 가지만 확인하겠습니다:

        1. 팀 규모가 어느 정도인가요? (5명? 50명? 500명?)
        2. 기술 스택 선호가 있나요? (없으면 제가 제안합니다)

사용자: 30명 정도, 스택은 알아서

Claude: 30명 규모면 이런 구조가 될 것 같습니다:

        L1 대분류:
          1. 인증/계정 - 직원 로그인, 관리자 권한
          2. 출퇴근 기록 - 출근/퇴근 체크, GPS/IP 검증
          3. 근태 관리 - 휴가/연차, 초과근무
          4. 대시보드 - 팀 현황, 통계, 리포트

        기술 스택 제안:
          Next.js + PostgreSQL + Vercel

        맞는 방향인가요?

사용자: GPS는 필요없고 IP만. 나머지는 좋아

Claude: 확인했습니다. 각 영역을 좀 더 구체화하면:
        ...
        (L2, L3 제안 → 확인 → L4 자동 생성 → PRD 초안 → 확정)
```

## Boundaries

**Will:**
- 대화를 통해 요구사항 추출
- 구조화된 PRD.md 자동 생성
- L4 태스크까지 자동 분해
- docs/ 계층 문서 자동 생성

**Will Not:**
- 사용자 확인 없이 PRD 확정
- 기술적으로 불가능한 요구사항 무비판 수용 (대안 제시)
- 코드 구현 (FlowSet이 담당)
