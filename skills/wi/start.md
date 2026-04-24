---
name: start
description: "PRD 분석 → MCP/스킬 자동 탐색·설치 → FlowSet 가동"
category: workflow
complexity: advanced
mcp-servers: []
personas: [architect, devops-engineer]
---

# /wi:start - PRD to FlowSet

> PRD를 분석하여 필요한 도구를 자동 설치하고 FlowSet을 시작합니다.

## Triggers
- PRD가 준비된 상태에서 자동 개발 시작
- FlowSet 가동 요청

## Usage
```
/wi:start [prd-file-path]
```
기본값: `./PRD.md`

## Behavioral Flow

### Phase 1: PRD 분석

1. PRD 파일 읽기
2. 문서 계층 추출:
   - L0 (비전/목표)
   - L1 (대분류/도메인)
   - L2 (중분류/모듈)
   - L3 (소분류/기능)
   - L4 (상세분류/태스크) → 각각 WI로 변환
3. 기술 스택 요구사항 파악:
   - 언어/프레임워크
   - DB 종류
   - 외부 API/서비스
   - UI/프론트엔드 프레임워크
   - 테스트 프레임워크
   - 인프라/배포 환경

### Phase 2: MCP/스킬 탐색 & 설치

PRD에서 파악한 기술 스택을 기반으로 필요한 MCP 서버를 검색하고 설치합니다.

#### 2-1. 기술 도메인 → MCP 매핑 테이블

| 도메인 | 검색 키워드 | 대표 MCP 예시 |
|--------|------------|---------------|
| DB/SQL | database, postgres, mysql, mongodb | @modelcontextprotocol/server-postgres |
| 파일시스템 | filesystem, file | @modelcontextprotocol/server-filesystem |
| Git/GitHub | github, git | @modelcontextprotocol/server-github |
| 웹 검색 | search, web | brave-search, tavily |
| UI/브라우저 | browser, playwright, puppeteer | @anthropic/mcp-playwright |
| API 문서 | openapi, swagger, api-docs | context7 |
| Docker/K8s | docker, kubernetes, container | docker-mcp |
| AWS/클라우드 | aws, gcp, azure | aws-mcp |
| 모니터링 | monitoring, logging, sentry | sentry-mcp |
| 디자인 | figma, design | figma-mcp |

#### 2-2. 검색 순서
```
1. 공식 레지스트리 검색 (무인증):
   curl "https://registry.modelcontextprotocol.io/v0/servers?search={keyword}&limit=5"

2. 결과 평가 기준:
   - 공식/검증된 서버 우선 (@modelcontextprotocol/* , @anthropic/*)
   - GitHub 스타 수 / 최근 업데이트
   - 프로젝트 타입과의 호환성

3. 사용자에게 설치 목록 제시 후 확인:
   "다음 MCP 서버를 설치합니다:
    - @modelcontextprotocol/server-postgres (DB 접근)
    - @anthropic/mcp-playwright (브라우저 테스트)
    설치할까요? (Y/n)"
```

#### 2-3. 설치
```bash
# 각 MCP 서버 설치 (프로젝트 스코프)
claude mcp add --scope project --transport stdio {name} -- npx -y {package}
# 또는 HTTP 전송
claude mcp add --scope project --transport http {name} {url}
```

#### 2-4. 플러그인 검색 (해당 시)
```bash
# 유용한 플러그인이 있으면 설치 제안
claude plugin install {plugin-name} --scope project
```

### Phase 3: fix_plan.md 생성

PRD의 L4 태스크를 WI 체크리스트로 변환:

```markdown
# Fix Plan (Work Items)

## L1: {대분류명}

### L2: {중분류명} > L3: {소분류명}
- [ ] WI-001-feat {기능명} | L1:{대분류} > L2:{중분류} > L3:{소분류}
- [ ] WI-002-feat {기능명} | L1:{대분류} > L2:{중분류} > L3:{소분류}
- [ ] WI-003-test {테스트명} | L1:{대분류} > L2:{중분류} > L3:{소분류}
```

**변환 규칙:**
- 의존성 순서대로 정렬 (인프라 → 데이터 → 백엔드 → 프론트엔드 → 테스트)
- 각 WI는 1개 컨텍스트 윈도우에서 완료 가능한 크기
- 너무 큰 태스크는 자동 분할
- WI 타입 자동 분류: feat(기능), fix(수정), test(테스트), docs(문서), chore(설정)
- **WI 번호 자동 부여**: 001부터 순차 증가, zero-padded (예: 001, 002, ..., 099, 100)
- 번호 자릿수: WI 총 개수에 따라 자동 결정 (99개 이하 → 3자리, 999개 이하 → 3자리, 1000개 이상 → 4자리)
- L4 태스크가 없으면 사용자에게 알림 후 중단 (flowset.sh preflight가 빈 fix_plan 감지)

**도메인 분리 분석 → PARALLEL_COUNT 자동 결정:**

fix_plan 생성 후 도메인 분리 가능 여부를 분석하여 사용자에게 안내합니다.

분석 기준:
- **L1 도메인 수**: 3개 이상이면 병렬 가능성 높음
- **공유 파일 수정 WI 비율**: page.tsx, layout.tsx 등을 수정하는 WI가 50% 이상이면 분리 불가
- **총 WI 수**: 20개 미만이면 병렬 시간 절약 대비 충돌 리스크가 큼

판정:
- **병렬 권장**: L1 도메인 3개 이상 + 공유 파일 WI 30% 미만 + WI 20개 이상
- **순차 권장**: 위 조건 미충족

```
📊 도메인 분리 분석 결과:
  - L1 도메인: {N}개
  - 공유 파일 수정 WI: {N}개 / {total}개 ({%})
  - 총 WI: {N}개

  ✅ 병렬 실행 권장 (PARALLEL_COUNT=2)
  또는
  ⚠️ 순차 실행 권장 (PARALLEL_COUNT=1)
     사유: 도메인 분리 불충분 — 충돌 위험

  병렬로 실행하시겠습니까? (Y/n)
  ※ 병렬 선택 시 충돌 발생하면 자동 rebase 후 재실행됩니다.
```

사용자 선택에 따라 `.flowsetrc`의 `PARALLEL_COUNT`를 설정합니다.

**병렬 배치 태깅 (PARALLEL_COUNT > 1 시 활성화):**
- `.flowsetrc`에 `PARALLEL_COUNT=2` 이상이면 batch 태그를 WI에 자동 부여
- 형식: `| batch:{영문라벨}` (L1 메타데이터 뒤에 추가)
- 배치 규칙:
  - **다른 L1 도메인** → 같은 batch (병렬 처리 가능)
  - **같은 L1 도메인** → 다른 batch (순차 처리, 파일 충돌 방지)
  - **L1:Shared** → 항상 단독 batch (공통 컴포넌트는 다른 WI와 병렬 불가)
  - **DB 스키마 (prisma/schema 등)** → 항상 단독 batch (공유 파일)
  - **패키지 설치 (package.json 변경)** → 항상 단독 batch
  - **공유 UI 파일 수정 (page.tsx, layout.tsx, globals.css 등)** → 같은 batch 또는 단독 batch (충돌 방지)
- 예시:
  ```markdown
  - [ ] WI-018-feat 근태 마감 | L1:Attendance > L2:마감 | batch:A
  - [ ] WI-020-feat 휴가 대시보드 | L1:Leave > L2:대시보드 | batch:A
  - [ ] WI-019-feat Leave DB 스키마 | L1:Leave > L2:DB | batch:B
  - [ ] WI-021-feat 공통 네비게이션 | L1:Shared > L2:레이아웃 | batch:C
  ```
- `PARALLEL_COUNT=1`이면 batch 태그 생략 (순차 실행이므로 불필요)

### Phase 4: AGENT.md 업데이트

PRD에서 파악한 기술 스택으로 `.flowset/AGENT.md`의 빌드/테스트 명령을 구체화.

#### 4-1. 인프라 환경 감지 및 주입

`prisma/schema.prisma`가 존재하면 DB 연결을 확인하고 AGENT.md에 인프라 정보를 주입합니다.

```
1. prisma/schema.prisma 존재 확인
   - 없음 → 스킵 (DB 없는 프로젝트)

2. DB 연결 테스트
   npx prisma db push --dry-run 2>/dev/null
   - 성공 → 3단계로
   - 실패 → "⚠️ DB 연결 실패 — /wi:env를 먼저 실행하세요" 안내
            AGENT.md "인프라 환경"을 비워둠 (mock 허용, 기존 동작)

3. 기존 mock 코드 감지
   프로젝트 소스에서 하드코딩 배열, mock API 패턴 검색:
   - grep -r "const.*=.*\[{" src/ app/ --include="*.ts" --include="*.tsx" -l
   - 감지됨 → "⚠️ 기존 mock 코드 발견 — 리팩토링 Phase 추가를 권장합니다" 안내
   - 감지 안 됨 → 정상 진행

4. AGENT.md "인프라 환경" 섹션 채우기
   ## 인프라 환경
   - **DB**: PostgreSQL (Prisma ORM)
   - **연결 상태**: 확인됨
   - **모델**: {schema에서 추출한 model 목록}
   - **⚠️ mock/하드코딩 데이터 사용 금지**: Prisma client로 CRUD 구현 필수
   - **사전 명령**: `npx prisma generate` (빌드 전 실행)
```

**핵심**: DB 연결이 확인된 경우에만 "mock 금지"가 주입됩니다. 연결 실패 시 기존 동작(mock 허용)을 유지하여 장점 상쇄를 방지합니다.

#### 4-2. 와이어프레임 경로 주입

`wireframes/` 디렉토리가 존재하면 AGENT.md에 와이어프레임 정보를 주입합니다.

```
1. wireframes/ 존재 확인
   - 없음 → 스킵

2. AGENT.md "와이어프레임" 섹션 채우기:
   ## 와이어프레임
   - **위치**: wireframes/
   - **페이지 목록**:
     {wireframes/*.html 파일 목록}
   - **⚠️ UI 구현 시 와이어프레임의 구조 + data-testid를 따를 것**
```

### Phase 4.6: 아키텍처 계약 생성

프로젝트의 API 표준과 데이터 흐름 규칙을 자동 생성합니다.

```
1. .flowset/contracts/ 디렉토리 생성

2. api-standard.md 생성 (PRD 기술 스택 기반):
   - 성공 응답 형식: { data: T | T[], total?, page?, pageSize? }
   - 에러 응답 형식: { error: { code, message } }
   - HTTP Status 규칙 (200/201/400/401/403/404/500)
   - 공통 규칙 (try-catch, 날짜 ISO 8601, 페이지네이션, 인증)

3. data-flow.md 생성 (PRD 도메인 + 역할 기반):
   - 모델별 SSOT API 정의
   - 역할별 읽기/쓰기 권한 매핑
   - SSOT 규칙:
     a. 각 모델은 하나의 SSOT API만 가짐
     b. 다른 역할 페이지에서도 같은 API 호출
     c. 역할별 필터링은 API 내부에서 session.role 기반 처리
     d. 프론트에서 데이터 복사/캐시 금지

4. AGENT.md에 계약 참조 추가:
   ## 아키텍처 계약
   - API 표준: .flowset/contracts/api-standard.md
   - 데이터 흐름: .flowset/contracts/data-flow.md
   - ⚠️ 모든 API는 api-standard.md 형식 준수 필수
   - ⚠️ 데이터 접근은 data-flow.md의 SSOT 엔드포인트 사용 필수
```

### Phase 4.5: RAG 초기화

프로젝트의 RAG 체계를 자동으로 설정합니다.

```
1. .claude/memory/rag/ 디렉토리 생성

2. 기본 RAG 파일 생성:
   - 00-timeline.md (빈 타임라인 — 세션 기록용)
   - pages-map.md (PRD에서 페이지/API 목록 추출)
   - decisions-log.md (빈 의사결정 로그)

3. PRD L1 도메인별 RAG 파일 생성:
   - {NN}-{domain-kebab}.md (각 L1 도메인)
   - 예: 01-auth.md, 02-attendance.md, 03-leave.md

4. .claude/rules/rag-context.md 생성:
   주제-파일 매핑 테이블 + 실시간 업데이트 트리거 + /mem:save 동기화 규칙
   (wi-test의 rag-context.md 패턴 기반)

5. .claude/memory/MEMORY.md 생성:
   RAG 파일 인덱스 + 현재 상태
```

**rag-context.md 템플릿:**
```markdown
# RAG Context Management Rules

이 프로젝트에는 주제별 RAG 참조 문서가 있습니다.
위치: `.claude/memory/rag/`

## 1. 세션 시작 시 자동 로드
작업 시작 전 작업 주제에 해당하는 RAG 파일을 반드시 로드.

### 주제-파일 매핑
| 작업 주제 | 로드할 RAG 파일 |
|-----------|----------------|
{PRD L1 도메인에서 자동 생성}
| 페이지/라우트 추가 | pages-map.md |
| 설계 판단/전략 변경 | decisions-log.md |
| 전체 맥락 파악 | 00-timeline.md |

복수 해당 시 전부 로드.

## 2. 실시간 업데이트 트리거
| 이벤트 | 업데이트 파일 |
|--------|-------------|
| 새 API 생성/수정 | 해당 도메인 RAG + pages-map.md |
| 새 페이지 생성 | pages-map.md |
| 아키텍처/전략 결정 | decisions-log.md |
| PR 머지 완료 | 00-timeline.md |

## 3. /mem:save 시 RAG 동기화
세션 중 변경사항이 RAG에 반영되었는지 검증 → 미반영 시 즉시 반영.
```

### Phase 4.7: Vault 연동 설정 (v3.0)

Obsidian + Local REST API가 설치된 환경에서 vault 연동을 설정합니다.

```
1. Obsidian vault 접근 가능 여부 확인:
   curl -s -k "https://localhost:27124/vault/" -H "Authorization: Bearer {API_KEY}" 2>/dev/null

2. 접근 가능하면 .flowsetrc에 설정:
   VAULT_ENABLED=true
   VAULT_URL="https://localhost:27124"
   VAULT_API_KEY="{API_KEY}"
   VAULT_PROJECT_NAME="{PROJECT_NAME}"

3. vault에 프로젝트 폴더 초기화:
   curl -s -k "${VAULT_URL}/vault/${PROJECT_NAME}/state.md" \
     -H "Authorization: Bearer ${VAULT_API_KEY}" \
     -X PUT -H "Content-Type: text/markdown" \
     -d "# ${PROJECT_NAME} State\n- Status: initialized\n- Updated: $(date)"

4. 접근 불가능하면:
   VAULT_ENABLED=false
   (파일 기반 RAG만 사용 — v2.x 호환)
```

### Phase 5: docs/ 계층 문서 내용 채우기

`/wi:init`이 생성한 빈 docs/ 디렉토리에 PRD 내용을 분배합니다.
(디렉토리가 없으면 생성):
```
docs/L0-vision/README.md   ← PRD의 비전/목표 섹션
docs/L1-domain/{name}.md   ← 각 대분류별 문서
docs/L2-module/{name}.md   ← 각 중분류별 문서
docs/L3-feature/{name}.md  ← 각 소분류별 문서
docs/L4-task/               ← fix_plan.md가 마스터, 개별 문서는 필요 시만
```

### Phase 5.5: Smoke 테스트 생성

PRD의 L1 도메인별 smoke 테스트를 자동 생성합니다.

**절차:**
1. fix_plan.md에서 L1 도메인 목록 추출
2. 도메인별 웹리서치: `"{PROJECT_TYPE} {L1 domain} smoke test best practice {year}"`
3. PRD + 리서치 결과 기반 smoke 테스트 설계
4. 사용자 확인: "이 smoke 테스트로 진행할까요?" (Y/N)
5. Playwright 기반 smoke 테스트 코드 생성

**규칙:**
- 각 테스트의 `describe` 블록에 WI 번호 포함: `describe('WI-063: 휴가 신청 폼', () => {...})`
- e2e 실패 시 WI 번호 추출에 사용됨 (GitHub Actions e2e.yml 연동)
- 도메인별 핵심 경로만 (페이지 접근 → 주요 요소 렌더링 확인)
- 전체 도메인 커버 (누락 시 404/렌더링 깨짐 미감지)

**생성 위치:**
```
tests/
  smoke/
    auth.spec.ts          ← 로그인 → 세션 유지
    people.spec.ts        ← 직원 목록 → 상세
    attendance.spec.ts    ← 대시보드 → 출결 기록
    leave.spec.ts         ← 대시보드 → 휴가 신청
    ...
  e2e/
    (추후 워커가 구현 시 자동 추가)
```

### Phase 5.9: Ruleset 설정 (루프 시작 전 보호 활성화)

`.flowsetrc`에서 `GITHUB_ACCOUNT_TYPE`과 `GITHUB_ORG`를 읽어 ruleset을 설정합니다.
**v4.0 PROJECT_CLASS 조건부**:
- `code` — 기존 strict ruleset (status checks + merge queue)
- `content` — 최소 보호만 (CI 없음, non_fast_forward + deletion). status checks 불필요
- `hybrid` — code 경로 보호 기준 strict ruleset (code + content 동시 운영이지만 main 보호는 code 기준으로 엄격)

```bash
# .flowsetrc에서 계정 유형 + class 읽기
source .flowsetrc
PROJECT_CLASS="${PROJECT_CLASS:-code}"

REPO_FULL="${GITHUB_ORG}/${PROJECT_NAME}"

# v4.0: PROJECT_CLASS별 조건부 분기
# content class는 CI/PR 엄격성 없음 → status checks 불필요, non_fast_forward + deletion만
if [[ "$PROJECT_CLASS" == "content" ]]; then
  echo "ℹ️ content 프로젝트 — 최소 Ruleset (CI 없음, PR 선택)"
  gh api --method POST "repos/${REPO_FULL}/rulesets" --input - <<'RULES' 2>/dev/null || {
    echo "⚠️ Ruleset 설정 실패 — 로컬 Git hooks로만 보호합니다."
  }
{
  "name": "Protect main (content)",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
RULES
  echo "🔒 content Ruleset (간소화) 설정 완료"
else
  # code 또는 hybrid — 기존 strict ruleset (hybrid는 code 경로 보호 기준)
  # 브랜치 보호 규칙 (main) — 계정 유형별 자동 분기
  # 참고: heredoc(<<'RULES')의 종료 마커는 bash 문법상 반드시 column 0에 있어야 하므로,
  #       else 블록 내부라도 `RULES`만 0-space 유지. 그 외 실행 라인은 +2-space로 일관화.
  ruleset_ok=false

  # 1. Rulesets API 시도 (조직 계정)
  if [[ "${GITHUB_ACCOUNT_TYPE:-}" == "org" ]]; then
    gh api --method POST "repos/${REPO_FULL}/rulesets" --input - <<'RULES' 2>/dev/null && ruleset_ok=true
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "lint" },
          { "context": "build" },
          { "context": "test" },
          { "context": "check-commits" }
        ]
      }
    },
    {
      "type": "merge_queue",
      "parameters": {
        "check_response_timeout_minutes": 10,
        "grouping_strategy": "ALLGREEN",
        "max_entries_to_build": 5,
        "max_entries_to_merge": 5,
        "merge_method": "SQUASH",
        "min_entries_to_merge": 1,
        "min_entries_to_merge_wait_minutes": 1
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
RULES
  fi

  # 2. 개인 계정 또는 Rulesets 실패 시 → strict: false
  if [[ "$ruleset_ok" != "true" ]]; then
    gh api --method POST "repos/${REPO_FULL}/rulesets" --input - <<'RULES' 2>/dev/null || {
      echo "⚠️ Ruleset 설정 실패 — 로컬 Git hooks로만 보호합니다."
    }
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "lint" },
          { "context": "build" },
          { "context": "test" },
          { "context": "check-commits" }
        ]
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
RULES
  fi

  echo "🔒 Ruleset 설정 완료 (class=$PROJECT_CLASS)"
fi
```

### Phase 5.95: 실행 모드 선택 (v4.0 신설)

PROJECT_CLASS에 따라 기본 실행 모드를 매핑하고, 사용자가 override할 수 있는 선택지를 제공합니다.
**3모드 (설계 §3 축 Y)**:

| 모드 | 동작 | 기본값이 되는 class |
|------|------|---------------------|
| 루프 (loop) | `flowset.sh` 새 터미널 자동 반복 | code |
| 대화형 (interactive) | 이 세션에서 WI 1개씩 수동 승인 | content |
| 팀 (team) | `lead-workflow` spawn, 6단계 | hybrid 또는 복잡한 code |

```bash
source .flowsetrc
PROJECT_CLASS="${PROJECT_CLASS:-code}"

# PROJECT_CLASS → 기본 모드 자동 매핑 (설계 §3 축 Y)
case "$PROJECT_CLASS" in
  code)    DEFAULT_MODE="loop" ;;
  content) DEFAULT_MODE="interactive" ;;
  hybrid)  DEFAULT_MODE="team" ;;
  *)
    echo "ERROR: 알 수 없는 PROJECT_CLASS='$PROJECT_CLASS' (code|content|hybrid 중 선택)" >&2
    exit 1
    ;;
esac

echo "📋 PROJECT_CLASS=$PROJECT_CLASS → 기본 실행 모드: $DEFAULT_MODE"
echo ""
echo "실행 모드 선택:"
echo "  1) loop        — flowset.sh 새 터미널 자동 반복 (code 기본)"
echo "  2) interactive — 이 세션에서 WI 1개씩 수동 승인 (content 기본)"
echo "  3) team        — lead-workflow spawn, 6단계 (hybrid 기본, 복잡한 code도 가능)"
read -r -p "선택 [Enter=$DEFAULT_MODE]: " MODE_CHOICE

case "${MODE_CHOICE:-}" in
  1|loop)        EXECUTION_MODE="loop" ;;
  2|interactive) EXECUTION_MODE="interactive" ;;
  3|team)        EXECUTION_MODE="team" ;;
  "")            EXECUTION_MODE="$DEFAULT_MODE" ;;
  *)
    echo "ERROR: 알 수 없는 모드 '$MODE_CHOICE' (loop|interactive|team 중 선택)" >&2
    exit 1
    ;;
esac

# 모드 영속화 (Phase 6에서 참조)
# 필드 존재 시 대체, 없으면 append — 빈 .flowsetrc에서도 정상 동작 (sed만 쓰면 match 없어 조용히 no-op)
if grep -qE '^EXECUTION_MODE=' .flowsetrc 2>/dev/null; then
  sed -i.bak -E "s|^EXECUTION_MODE=.*|EXECUTION_MODE=\"${EXECUTION_MODE}\"|" .flowsetrc
  rm -f .flowsetrc.bak
else
  echo "EXECUTION_MODE=\"${EXECUTION_MODE}\"" >> .flowsetrc
fi

echo "✅ 실행 모드 확정: $EXECUTION_MODE"
```

**하위 호환**: `.flowsetrc`에 `EXECUTION_MODE` 필드가 없거나 PROJECT_CLASS 미설정 시 자동으로 `code`/`loop`으로 매핑 — 기존 동작 완전 동일.

### Phase 6: 커밋 & 실행 모드별 분기 (v4.0 재구성)

Phase 5.95에서 확정한 `EXECUTION_MODE`에 따라 3가지 경로 중 하나로 진입합니다.

#### 6.0: 공통 커밋 (모든 모드 공통)

```bash
# 생성된 파일 커밋
git add -A
git commit -m "WI-chore PRD 기반 작업 계획 생성"

# content class는 GitHub이 선택적 — GITHUB_ACCOUNT_TYPE 있을 때만 push
source .flowsetrc
if [[ -n "${GITHUB_ACCOUNT_TYPE:-}" ]]; then
  git push origin main
else
  echo "ℹ️ GITHUB_ACCOUNT_TYPE 미설정 — push 건너뜀 (로컬 커밋만)"
fi
```

#### 6.1: 모드별 분기 (loop / interactive / team)

```bash
source .flowsetrc
case "${EXECUTION_MODE:-loop}" in
  loop)        echo "🔁 루프 모드 — flowset.sh 새 터미널에서 자동 반복 시작" ;;
  interactive) echo "💬 대화형 모드 — 이 세션에서 WI 1개씩 수동 승인 진행" ;;
  team)        echo "👥 팀 모드 — lead-workflow 에이전트로 6단계 위임 진행" ;;
esac
```

---

### 모드 A: 루프 (loop) — 기존 v3.x 동작 유지

**⚠️ flowset.sh는 절대 이 세션에서 `bash flowset.sh`로 직접 실행하지 않는다.**
`claude -p`는 Claude Code 세션 안에서 중첩 실행이 불가능하므로,
**플랫폼을 감지하여 새 터미널 창을 자동으로 열고 flowset.sh를 실행**한다:

```bash
# 프로젝트 경로
PROJECT_DIR="$(pwd)"

# Windows에서 bash.exe 경로를 동적으로 탐색하는 함수
find_windows_bash() {
  # 1. PATH에서 bash 탐색
  local bash_path
  bash_path=$(which bash 2>/dev/null || where bash 2>/dev/null | head -1)
  if [[ -n "$bash_path" && -x "$bash_path" ]]; then
    echo "$bash_path"; return
  fi
  # 2. Git for Windows 기본 경로들
  for candidate in \
    "C:/Program Files/Git/bin/bash.exe" \
    "C:/Program Files (x86)/Git/bin/bash.exe" \
    "$LOCALAPPDATA/Programs/Git/bin/bash.exe" \
    "$PROGRAMFILES/Git/bin/bash.exe"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"; return
    fi
  done
  # 3. 못 찾음
  return 1
}

# 플랫폼별 새 터미널에서 flowset.sh 실행
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    # Windows — bash.exe 동적 탐색
    BASH_EXE=$(find_windows_bash)
    if [[ -n "$BASH_EXE" ]]; then
      start "" "$BASH_EXE" -c "cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter to close...'"
    else
      # Git Bash 없음 — WSL 시도
      if command -v wsl &>/dev/null; then
        wsl_path=$(wslpath "$PROJECT_DIR" 2>/dev/null || echo "/mnt/c${PROJECT_DIR:2}")
        start "" wsl bash -c "cd '$wsl_path' && bash flowset.sh; read -p 'Press Enter to close...'"
      else
        echo "⚠️ bash를 찾을 수 없습니다."
        echo "  다음 중 하나를 설치하세요:"
        echo "  1. Git for Windows (https://git-scm.com) — Git Bash 포함"
        echo "  2. WSL (wsl --install)"
        echo ""
        echo "  설치 후 수동 실행:"
        echo "  cd $PROJECT_DIR && bash flowset.sh"
      fi
    fi
    ;;
  Linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      # WSL — WSL 내부에서 직접 새 터미널
      if command -v wslview &>/dev/null; then
        # wslu 설치된 경우 Windows 터미널 활용
        wslview "wt.exe" -d "$PROJECT_DIR" bash -c "bash flowset.sh; read -p 'Press Enter...'"
      else
        # 새 bash 프로세스로 실행
        setsid bash -c "cd '$PROJECT_DIR' && bash flowset.sh" &>/dev/null &
        echo "FlowSet이 백그라운드에서 시작되었습니다."
        echo "  로그 확인: tail -f .flowset/logs/flowset.log"
      fi
    else
      # Native Linux — 터미널 에뮬레이터 탐색
      if command -v gnome-terminal &>/dev/null; then
        gnome-terminal -- bash -c "cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter to close...'"
      elif command -v konsole &>/dev/null; then
        konsole -e bash -c "cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter to close...'" &
      elif command -v xfce4-terminal &>/dev/null; then
        xfce4-terminal -e "bash -c \"cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter to close...'\"" &
      elif command -v xterm &>/dev/null; then
        xterm -e "cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter to close...'" &
      else
        setsid bash -c "cd '$PROJECT_DIR' && bash flowset.sh" &>/dev/null &
        echo "FlowSet이 백그라운드에서 시작되었습니다."
        echo "  로그 확인: tail -f .flowset/logs/flowset.log"
      fi
    fi
    ;;
  Darwin*)
    # macOS — Terminal.app 또는 iTerm2
    if osascript -e 'exists application "iTerm"' 2>/dev/null; then
      osascript -e "tell application \"iTerm\" to create window with default profile command \"cd '$PROJECT_DIR' && bash flowset.sh\""
    else
      osascript -e "tell application \"Terminal\" to do script \"cd '$PROJECT_DIR' && bash flowset.sh\""
    fi
    ;;
esac
```

실행 후 안내 출력:
```
🚀 FlowSet이 새 터미널 창에서 시작되었습니다!
   열린 터미널 창에서 진행 상황을 확인하세요.

💡 수동 실행이 필요한 경우:
   cd {project-path} && bash flowset.sh
```

**bash를 찾을 수 없는 경우 (Windows):**
```
⚠️ bash를 찾을 수 없습니다.
  다음 중 하나를 설치하세요:
  1. Git for Windows (https://git-scm.com) — Git Bash 포함
  2. WSL (wsl --install)
```

---

### 모드 B: 대화형 (interactive) — v4.0 신설

이 세션에서 WI를 **1개씩 수동 승인하며 순차 진행**합니다.
content 프로젝트 기본값. code 프로젝트에서도 "꼼꼼히 보며 진행하고 싶은 경우" 선택 가능.

**동작 흐름** (리드 Claude가 직접 실행):

1. `fix_plan.md` 미완 WI 목록 로드
2. 각 WI마다 다음 루프 반복:
   - a. WI 메타데이터 읽기 (L1/L2/L3 + 타입)
   - b. 사용자에게 질문: "WI-NNN {작업명} 진행할까요? [Y/n/s=skip/q=quit]"
   - c. 동의 시 브랜치 생성 → 구현 → 검증 → 커밋 → PR 생성 (또는 로컬 커밋만)
   - d. 완료 후 사용자 승인 요청 (diff 보여주고 머지 여부 확인)
   - e. 승인 시 fix_plan.md 체크박스 업데이트 → main으로 복귀 → 다음 WI
3. 전체 완료 또는 사용자가 q 입력 시 종료

**content 프로젝트 특화 동작**:
- PR 생성 선택적 (GITHUB_ACCOUNT_TYPE 미설정 시 로컬 커밋만)
- 검증은 content contracts(style-guide.md, review-rubric.md — WI-B3에서 추가) 기준
- reviewer≥1 파일 증거(`.flowset/reviews/{section}-{reviewer}.md`) 확인

**의사코드 (셸 루프 골격)**:
```bash
source .flowsetrc
PROJECT_CLASS="${PROJECT_CLASS:-code}"

# fix_plan.md에서 미완 WI 추출
mapfile -t PENDING < <(grep -E '^- \[ \] WI-' .flowset/fix_plan.md)

for wi_line in "${PENDING[@]}"; do
  wi_id=$(echo "$wi_line" | sed -E 's/^- \[ \] (WI-[0-9]+).*/\1/')
  wi_desc=$(echo "$wi_line" | sed -E 's/^- \[ \] WI-[0-9]+-[a-z]+ ([^|]+).*/\1/')

  read -r -p "${wi_id} ${wi_desc} 진행할까요? [Y/n/s/q]: " ans
  case "${ans:-Y}" in
    [Nn]|[Nn][Oo]) echo "  → 건너뜀"; continue ;;
    [Ss]|[Ss][Kk][Ii][Pp]) echo "  → 건너뜀"; continue ;;
    [Qq]|[Qq][Uu][Ii][Tt]) echo "  → 종료"; break ;;
  esac

  # 실제 구현은 리드 Claude가 아래 도구 체인으로 직접 수행 (아래 상세)
  echo "  ✅ $wi_id 완료 (브랜치 머지 후 다음 WI)"
done

echo "💬 대화형 모드 종료 — fix_plan.md 상태를 확인하세요"
```

**WI 1개당 실행 도구 체인 (리드 Claude 직접 수행, class별 분기)**:

| 단계 | 도구 | code/hybrid class | content class |
|------|------|------------------|---------------|
| a. 브랜치 생성 | `Bash` | `git checkout main && git pull && git checkout -b feature/{WI}-{type}-{kebab}` | 동일 (GITHUB_ACCOUNT_TYPE 미설정이면 push만 생략) |
| b. 관련 파일 읽기 | `Read` / `Grep` | src/** 관련 코드 | docs/** 관련 문서 + 출처 URL |
| c. 구현 | `Edit` / `Write` | 코드 변경 + 타입 동기화 | 문서 초안 + 참고자료 링크 |
| d. 검증 | `Bash` | `npm test` / `cargo test` / `pytest` + 린트 | `.flowset/reviews/{section}-{reviewer}.md` 작성 + completeness_checklist 전체 done 확인 |
| e. 커밋 | `Bash` | `git add -A && git commit -m "WI-NNN-type 한글 작업명"` | 동일 |
| f. PR 생성 | `Bash` | `gh pr create --base main --title "..." --body "..."` | GITHUB_ACCOUNT_TYPE 있을 때만. 없으면 로컬 커밋만 |
| g. 사용자 승인 | `AskUserQuestion` | diff 요약 제시 후 머지 여부 확인 | 동일 |
| h. 머지 | `Bash` | `gh pr merge --squash --delete-branch` 또는 `bash .flowset/scripts/enqueue-pr.sh` | GITHUB 없으면 `git checkout main && git merge --ff-only {branch}` |
| i. fix_plan 업데이트 | `Edit` | `- [ ] WI-NNN` → `- [x] WI-NNN` | 동일 |
| j. 다음 WI | (루프) | main으로 복귀 후 다음 WI | 동일 |

**content class 검증 상세 (d단계)**:
- `.flowset/reviews/{section}-{reviewer}.md` 파일 존재 확인 (1차 판정 — 파일 방식 필수)
- `.flowset/approvals/{section}-{approver}.md` 파일 확인 (approver 승인 WI인 경우)
- 출처 URL 누락 감지 (Stop hook의 `stop-rag-check.sh` content 분기 — WI-C3-content 이후)

**code class 검증 상세 (d단계)**:
- lint + build + test (AGENT.md에 정의된 명령)
- API 수정 시 api-standard.md 응답 형식 준수 확인
- 테스트 커버리지(검증 에이전트가 자동 감지)

---

### 모드 C: 팀 (team) — v4.0 신설

`lead-workflow` 에이전트를 spawn하여 **6단계 위임 워크플로우**로 진행합니다.
hybrid 프로젝트 기본값. 복잡한 code 프로젝트에서도 선택 가능.

**사전 조건**:
- `.claude/agents/lead-workflow.md` 존재 (v3.2 그대로 유지 — 3모드 호출 주체 이미 정의됨)
- `.flowset/ownership.json` 존재 (WI-B1 Step 3.5에서 생성됨)
- `.claude/rules/team-roles.md` 존재 (class별 역할 매핑)

**동작**:

```
Agent(
  subagent_type: "lead-workflow",
  description: "Lead orchestrates team for PRD WIs",
  prompt: "프로젝트: {PROJECT_NAME} (class=${PROJECT_CLASS})

  .flowset/fix_plan.md의 미완 WI 전체를 6단계 워크플로우로 진행하세요:
  1. 요구사항 파악 (.flowset/requirements.md + contracts/)
  2. 복잡도 분석 + 팀 규모 결정
  3. 태스크 분해 + 의존성 설정
  3.5. 스프린트 계약 협상
  4. 팀 관리 (생성 또는 재사용)
  5. 구현 위임 (SendMessage)
  6. 결과 통합 + PR 생성

  class=${PROJECT_CLASS}에 따라:
  - code: frontend/backend/qa/devops/planning 팀 구성
  - content: writer/reviewer/approver/designer/shared 팀 구성
  - hybrid: 양쪽 혼합 (ownership.json.teams[].class 참조)"
)
```

**주의**: `lead-workflow` 에이전트는 `Edit`/`Write` disallowed — 직접 코드 수정하지 않고 팀원(`Agent`)에 위임합니다.

---

## 출력 형식

```
📋 PRD 분석 완료
  - L1 대분류: {N}개
  - L2 중분류: {N}개
  - L3 소분류: {N}개
  - L4 태스크 → WI: {N}개

🔧 MCP 서버 설치:
  ✅ {name} - {용도}
  ✅ {name} - {용도}

📝 fix_plan.md: {N}개 WI 생성
  - feat: {N}개
  - test: {N}개
  - chore: {N}개

📋 PROJECT_CLASS={code|content|hybrid} → 기본 실행 모드: {loop|interactive|team}
✅ 실행 모드 확정: {EXECUTION_MODE}

# 모드별 출력 분기:
# — loop 모드:
🚀 FlowSet이 새 터미널 창에서 시작되었습니다!
   열린 터미널 창에서 진행 상황을 확인하세요.

# — interactive 모드:
💬 대화형 모드 시작 — WI 1개씩 승인하며 진행합니다.

# — team 모드:
👥 팀 모드 시작 — lead-workflow 에이전트를 spawn합니다.
```

## Boundaries

**Will:**
- PRD를 분석하여 WI 체크리스트 자동 생성
- 기술 스택에 맞는 MCP 서버 검색 및 설치 제안
- 문서 계층구조에 PRD 내용 분배
- FlowSet 실행 준비

**Will Not:**
- 사용자 확인 없이 MCP 서버 설치
- 실제 코드 구현 (loop/interactive/team 각 모드별 주체가 담당)
- PRD 내용 임의 수정
- `--dangerously-skip-permissions` 사용 (보안상 --allowedTools 사용)
- **flowset.sh를 `bash flowset.sh`로 이 세션에서 직접 실행** (claude -p 중첩 불가 → 새 터미널 창 자동 오픈. 단 loop 모드에서만 flowset.sh 호출)
- content 프로젝트에 무조건 CI/merge queue 강제 (Phase 5.9 class별 분기로 해소)
- PROJECT_CLASS 무시하고 기본 모드 자동 매핑 없이 항상 loop 강제 (v3.x 경직성 C1 해소)
