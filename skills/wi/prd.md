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

#### Step 0.1: prd-state.json v1 → v2 migration (WI-001, v4.0)

`.flowset/prd-state.json` 읽기 **전**에 아래 함수를 실행하여 스키마를 v2로 승격합니다.
**idempotent**(v2면 즉시 return), **atomic**(tmp → mv), **rollback**(실패 시 `.v1.bak` 복원) 보장.

v2 신규 필드(entities/roles/crud_matrix/permission_matrix/auth_patterns/auth_framework)는 Group γ(WI-C1~)에서 사용되며, 미존재 시 기본값으로 채워집니다. 기존 v1 파일은 `schema_version` 필드 자체가 없으며, migration 후에는 `"schema_version": "v2"`가 추가됩니다.

```bash
migrate_prd_state_v1_to_v2() {
  local state_file=".flowset/prd-state.json"
  [[ ! -f "$state_file" ]] && return 0  # 파일 없으면 skip (신규 프로젝트)
  [[ ! -s "$state_file" ]] && return 0  # 빈 파일(0바이트) skip — /wi:prd 비정상 종료 후 잔존 파일 방어

  # idempotent: 이미 v2 이상이면 즉시 return (v3 다운그레이드 방어)
  # WI-001 1차 평가 이월 항목 (WI-C1 동반 수정, 설계 §8 :377):
  # `== "v2"` 비교는 미래 v3 도입 시 v3 → v2 다운그레이드 발생.
  # `=~ ^v[2-9]$`로 v2~v9 전수 skip — v10+는 별도 migration 함수로 분기 예정.
  local schema_version
  schema_version=$(jq -r '.schema_version // "v1"' "$state_file" 2>/dev/null || echo "v1")
  [[ "$schema_version" =~ ^v[2-9]$ ]] && return 0

  # 원본 백업 (실패 시 복원용 스냅샷)
  cp "$state_file" "${state_file}.v1.bak" || return 1

  # v2 필드 병합 (기존 필드 전부 보존 — jq `. +` 우측이 좌측을 덮어씀, `//` 기본값 적용)
  local tmp="${state_file}.tmp"
  if jq '. + {
    schema_version: "v2",
    entities: (.entities // []),
    roles: (.roles // []),
    crud_matrix: (.crud_matrix // {}),
    permission_matrix: (.permission_matrix // {}),
    auth_patterns: (.auth_patterns // []),
    auth_framework: (.auth_framework // "")
  }' "$state_file" > "$tmp"; then
    # atomic: tmp → 원본 교체
    if ! mv "$tmp" "$state_file"; then
      # 교체 실패 → 백업에서 복원
      mv "${state_file}.v1.bak" "$state_file"
      rm -f "$tmp"
      return 1
    fi
  else
    # jq 변환 실패 → 백업에서 복원
    mv "${state_file}.v1.bak" "$state_file"
    rm -f "$tmp"
    return 1
  fi
  return 0
}

# Step 0 진입점에서 최초 1회 실행
migrate_prd_state_v1_to_v2 || {
  echo "ERROR: prd-state.json migration 실패. .v1.bak에서 복원 확인 후 재시도 필요." >&2
  exit 1
}
```

**하위 호환** (설계 §8):
- `prd-state.json` 없음 → skip (신규 프로젝트 정상 흐름)
- `schema_version=v2` → skip (재실행 안전)
- 기존 v1 필드(`step`/`project_name`/`overview`/`tech_stack`/`L1`/`decisions`/`user_constraints`/...) 는 **전부 보존**
- migration 후 원본은 `.v1.bak`로 영구 보존 (수동 복구 시 사용)

#### Step 0.2: 상태 복원

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

### Step 2.5: Role 추출 + auth_patterns 자동 매핑 (WI-C1, v4.0 신설)

**목적**: PRD 본문에서 역할(role)을 자동 추출하고, 기존 코드베이스의 auth 스택을 감지해 `auth_patterns[]`를 매핑합니다. Step 4(매트릭스 셀 의무)와 Stop hook의 auth middleware 검사(WI-C3-code 예약)에서 SSOT로 소비됩니다.

**적용 대상**: `PROJECT_CLASS=code` 또는 `PROJECT_CLASS=hybrid`. content는 Section×Role×Action 매트릭스를 사용하므로 Step 2.5에서도 role 추출은 동일하게 실행되며, auth_patterns 매핑은 skip됩니다.

**Step 2.5.a: PRD 본문 기반 Role 추출**

L1~L3 도메인 설명에서 다음 키워드를 grep하여 role 후보를 추출:

```
역할 키워드 (한글):  관리자 | 매니저 | 팀장 | 직원 | 사용자 | 작성자 | 리뷰어 | 승인자
역할 키워드 (영문):  admin | manager | lead | employee | user | writer | reviewer | approver
권한 키워드:        권한 | 접근 | 승인 | 거부 | 401 | 403 | role | permission | RBAC
```

후보 추출 후 사용자에게 확인:

```
PRD에서 다음 역할이 감지되었습니다:
  1. admin (관리자)
  2. manager (매니저/팀장)
  3. employee (직원)

이대로 확정할까요?
- 추가 역할이 있으면: "역할 추가: {이름}"
- 빠진 역할이 있으면: "역할 제거: {이름}"
- 매핑 변경이 있으면: "이름 변경: {old} → {new}"
```

확정된 role 목록을 `prd-state.json.roles[]`에 저장:

```json
{
  "roles": ["admin", "manager", "employee"]
}
```

**Step 2.5.b: auth_framework 감지 (PROJECT_CLASS=code | hybrid only)**

기존 코드베이스가 있는 경우 (`/wi:init` 후 재실행 시), 다음 파일을 grep하여 auth 스택 자동 감지:

| 감지 파일 | 패턴 | auth_framework |
|---------|------|---------------|
| `package.json` | `"next-auth"` | `next-auth` |
| `package.json` | `"@clerk/"` | `clerk` |
| `package.json` | `"@supabase/auth-helpers"` | `supabase` |
| `package.json` | `"lucia-auth"` \| `"lucia"` | `lucia` |
| `package.json` | `"passport"` | `passport` |
| `requirements.txt` / `pyproject.toml` | `flask-login` \| `django.contrib.auth` | `python-{name}` |

매핑 후 `auth_patterns[]`에 정규식 패턴 자동 채움 (설계 §4 :98-107):

```bash
detect_auth_framework() {
  local fw="" patterns=()
  if [[ -f "package.json" ]]; then
    if jq -e '.dependencies."next-auth" // .devDependencies."next-auth"' package.json >/dev/null 2>&1; then
      fw="next-auth"
      patterns=('getServerSession\(' 'auth\(\)')
    elif jq -e '.dependencies | to_entries[] | select(.key | startswith("@clerk/"))' package.json >/dev/null 2>&1; then
      fw="clerk"
      patterns=('currentUser\(' 'auth\(\)')
    elif jq -e '.dependencies | to_entries[] | select(.key | startswith("@supabase/auth-helpers"))' package.json >/dev/null 2>&1; then
      fw="supabase"
      patterns=('getUser\(' 'createServerClient\(')
    elif jq -e '.dependencies."lucia-auth" // .dependencies."lucia"' package.json >/dev/null 2>&1; then
      fw="lucia"
      patterns=('validateRequest\(')
    elif jq -e '.dependencies."passport"' package.json >/dev/null 2>&1; then
      fw="passport"
      patterns=('req\.isAuthenticated\(')
    fi
  fi
  printf '%s\n' "$fw"
  printf '%s\n' "${patterns[@]}"
}
```

**Step 2.5.c: 커스텀 auth 수동 추가**

자체 구현 auth (위 5개 프레임워크에 매칭 안 됨)인 경우:

```
package.json에서 auth 스택을 감지하지 못했습니다.
커스텀 auth 함수가 있으면 패턴(정규식)을 입력해주세요.
예: "requireRole\(", "checkAuth\(", "getCurrentUser\("

여러 개는 쉼표로 구분: "requireRole\(, checkAuth\("

없으면 엔터 (auth_patterns 비워두기 — Stop hook 검사 skip).
```

**Step 2.5.d: prd-state.json 저장**

확정된 값을 prd-state.json에 병합 (jq atomic write):

```bash
# .flowset/prd-state.json에 roles + auth_framework + auth_patterns 저장
# WI-001 migrate 함수가 이미 v2 필드를 보장하므로 단순 .roles = ... 로 덮어쓰기
jq --argjson roles "$roles_json" \
   --arg fw "$auth_framework" \
   --argjson patterns "$auth_patterns_json" \
   '.roles = $roles | .auth_framework = $fw | .auth_patterns = $patterns' \
   .flowset/prd-state.json > .flowset/prd-state.json.tmp \
   && mv .flowset/prd-state.json.tmp .flowset/prd-state.json
```

**Step 2.5.e: content class 분기 (PROJECT_CLASS=content)**

content 단일 class에서는 auth_framework / auth_patterns 매핑을 skip하고 role만 추출. content 매트릭스는 `writer/reviewer/approver/designer` 같은 워크플로우 role을 사용 (설계 §4 :126-138).

```bash
if [[ "${PROJECT_CLASS:-code}" == "content" ]]; then
  # content는 auth 검사 대상 아님 — Stop hook도 auth_patterns 검사 skip
  auth_framework=""
  auth_patterns_json="[]"
fi
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

#### Step 4 확장: 매트릭스 셀 의무화 (WI-C1, v4.0 신설)

L4 태스크 생성과 동시에 **`.flowset/spec/matrix.json`**을 생성하고 모든 셀을 `status: "missing"`으로 초기화합니다. 셀이 하나라도 매트릭스에 누락되면 후속 검증(WI-C5 verify-requirements + Stop hook + WI-C4 evaluator coverage)이 FAIL을 강제합니다 — pain point B1/B2/B5 직접 차단(설계 §4 :109-117).

**적용 대상**: 모든 PROJECT_CLASS. 단 스키마는 class별로 다름 (template SSOT는 `templates/.flowset/spec/matrix.json`).

**Step 4.M.a: code 매트릭스 생성 (`PROJECT_CLASS=code | hybrid`)**

각 Entity × CRUD × Role 조합에 대해 셀을 생성:

```bash
generate_code_matrix() {
  # 입력: prd-state.json의 entities[], roles[], crud_matrix{}, permission_matrix{}, auth_patterns[], auth_framework
  # 출력: .flowset/spec/matrix.json (class=code 스키마)
  local roles_json entities_json auth_patterns_json auth_framework
  roles_json=$(jq '.roles' .flowset/prd-state.json)
  entities_json=$(jq '.entities' .flowset/prd-state.json)
  auth_patterns_json=$(jq '.auth_patterns' .flowset/prd-state.json)
  auth_framework=$(jq -r '.auth_framework' .flowset/prd-state.json)

  # 각 entity에 대해 CRUD 4셀 + role별 permission 셀 + status="missing" 초기화
  jq -n \
    --argjson roles "$roles_json" \
    --argjson entities "$entities_json" \
    --argjson auth_patterns "$auth_patterns_json" \
    --arg auth_framework "$auth_framework" '
    {
      schema_version: "v2",
      class: "code",
      auth_framework: $auth_framework,
      auth_patterns: $auth_patterns,
      entities: ($entities | map({
        (.name): {
          crud: {C: {}, R: {}, U: {}, D: {}},
          permissions: ($roles | map({(.): {C: false, R: false, U: false, D: false}}) | add),
          type_ssot: ((.type_ssot // "")),
          endpoints: {C: "", R: "", U: "", D: ""},
          gherkin: [],
          tests: [],
          status: {C: "missing", R: "missing", U: "missing", D: "missing"}
        }
      }) | add)
    }' > .flowset/spec/matrix.json.tmp \
    && mv .flowset/spec/matrix.json.tmp .flowset/spec/matrix.json
}
```

**code 매트릭스 셀 의무 규칙** (설계 §4 :68-95):
- **CRUD 4셀** 모두 존재해야 함 (C/R/U/D 누락 금지) — pain point B1
- **role × CRUD 권한 셀** 모두 존재해야 함 (`employee/manager/admin × C/R/U/D` = N×4 셀) — pain point B2
- **type_ssot** 필드 1개 (예: `prisma/schema.prisma#Leave`) — 타입 중복 SSOT — pain point B3
- **endpoints** 4셀 (HTTP 메서드 + 경로) — Stop hook이 변경 파일 path 매칭에 사용
- **gherkin[] / tests[]** 배열 (초기 빈 배열, WI-C2에서 채움) — pain point B4
- **status[C/R/U/D]**: `missing` | `pending` | `done` 3-state

**Step 4.M.b: content 매트릭스 생성 (`PROJECT_CLASS=content | hybrid`)**

각 Section × Role × Action 조합에 대해 셀 생성:

```bash
generate_content_matrix() {
  # 입력: prd-state.json의 sections[], roles[], completeness_checklist[]
  # 출력: .flowset/spec/matrix.json (class=content 스키마)
  local roles_json sections_json
  roles_json=$(jq '.roles' .flowset/prd-state.json)
  sections_json=$(jq '.sections // []' .flowset/prd-state.json)

  jq -n \
    --argjson roles "$roles_json" \
    --argjson sections "$sections_json" '
    {
      schema_version: "v2",
      class: "content",
      sections: ($sections | map({
        (.name): {
          roles: ($roles | map({(.): {draft: false, review: false, approve: false}}) | add),
          sources: (.sources // []),
          completeness_checklist: (.completeness_checklist // []),
          status: {draft: "missing", review: "missing", approve: "missing"}
        }
      }) | add)
    }' > .flowset/spec/matrix.json.tmp \
    && mv .flowset/spec/matrix.json.tmp .flowset/spec/matrix.json
}
```

**content 매트릭스 셀 의무 규칙** (설계 §4 :119-138 + §3 :143-146):
- **Section × draft/review/approve 3셀** 모두 존재 — pain point B1 변형 (섹션 단계 누락 금지)
- **role 권한 매핑** (writer→draft, reviewer→review, approver→approve)
- **sources[]** 배열 (출처 URL 1개 이상 — WI-B3 style-guide.md `섹션당 출처 URL 최소 1개` 규칙 SSOT 참조)
- **completeness_checklist[]** 배열 (목표/흐름/예외케이스 등 — 모든 항목 done이어야 PASS)
- **status[draft/review/approve]**: `missing` | `pending` | `done` 3-state
- **rubric scoring_weights**: WI-B3 review-rubric.md 5축 가중치(25/25/20/15/15)는 본 매트릭스에 직접 직렬화하지 않고 SSOT 단일성 원칙에 따라 review-rubric.md만 참조 (WI-C4 evaluator가 두 파일을 동시 로드)

**Step 4.M.c: hybrid 매트릭스 생성 (`PROJECT_CLASS=hybrid`)**

hybrid는 단일 `matrix.json` 파일에 두 스키마를 분리하여 저장 — `entities[]`(code 영역) + `sections[]`(content 영역) 동시 보유:

```json
{
  "schema_version": "v2",
  "class": "hybrid",
  "auth_framework": "next-auth",
  "auth_patterns": ["getServerSession\\(", "auth\\(\\)"],
  "entities": { "Leave": { ... } },
  "sections": { "3.2-User-Flow": { ... } }
}
```

Stop hook은 변경 파일 경로를 `ownership.json.teams[].class`로 분류해 `entities` 또는 `sections` 검증 분기에 라우팅 (설계 §4 :158-181).

**Step 4.M.d: matrix.json 생성 진입점**

`/wi:prd` Step 4 마지막에 PROJECT_CLASS에 따라 분기:

```bash
mkdir -p .flowset/spec
case "${PROJECT_CLASS:-code}" in
  code)    generate_code_matrix ;;
  content) generate_content_matrix ;;
  hybrid)  generate_code_matrix; generate_hybrid_merge_content ;;
  *)       echo "ERROR: 알 수 없는 PROJECT_CLASS: ${PROJECT_CLASS}" >&2; exit 1 ;;
esac
```

**셀 의무 검증 (생성 직후 self-check)**:

```bash
verify_matrix_cells() {
  local matrix=".flowset/spec/matrix.json"
  local class
  class=$(jq -r '.class' "$matrix")

  case "$class" in
    code|hybrid)
      # 모든 entity가 CRUD 4셀 + status 4셀 보유 확인
      local missing
      missing=$(jq -r '.entities | to_entries[] |
        select((.value.crud | keys | sort) != ["C","D","R","U"] or
               (.value.status | keys | sort) != ["C","D","R","U"]) |
        .key' "$matrix")
      [[ -n "$missing" ]] && { echo "ERROR: CRUD 셀 누락 entity: $missing" >&2; return 1; }
      ;;
    content)
      # 모든 section이 draft/review/approve 3셀 보유 확인
      local missing
      missing=$(jq -r '.sections | to_entries[] |
        select((.value.status | keys | sort) != ["approve","draft","review"]) |
        .key' "$matrix")
      [[ -n "$missing" ]] && { echo "ERROR: Section status 셀 누락: $missing" >&2; return 1; }
      ;;
  esac
  return 0
}
```

생성 직후 `verify_matrix_cells` 호출이 실패하면 `/wi:prd`가 즉시 종료(`exit 1`)하여 미완성 매트릭스가 다음 단계(WI 생성)로 흘러가는 것을 차단합니다.

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
