---
name: start
description: "PRD 분석 → MCP/스킬 자동 탐색·설치 → Ralph Loop 가동"
category: workflow
complexity: advanced
mcp-servers: []
personas: [architect, devops-engineer]
---

# /wi:start - PRD to Ralph Loop

> PRD를 분석하여 필요한 도구를 자동 설치하고 Ralph Loop을 시작합니다.

## Triggers
- PRD가 준비된 상태에서 자동 개발 시작
- Ralph Loop 가동 요청

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
- L4 태스크가 없으면 사용자에게 알림 후 중단 (ralph.sh preflight가 빈 fix_plan 감지)

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

사용자 선택에 따라 `.ralphrc`의 `PARALLEL_COUNT`를 설정합니다.

**병렬 배치 태깅 (PARALLEL_COUNT > 1 시 활성화):**
- `.ralphrc`에 `PARALLEL_COUNT=2` 이상이면 batch 태그를 WI에 자동 부여
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

PRD에서 파악한 기술 스택으로 `.ralph/AGENT.md`의 빌드/테스트 명령을 구체화.

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

`.ralphrc`에서 `GITHUB_ACCOUNT_TYPE`과 `GITHUB_ORG`를 읽어 ruleset을 설정합니다.

```bash
# .ralphrc에서 계정 유형 읽기
source .ralphrc

REPO_FULL="${GITHUB_ORG}/${PROJECT_NAME}"

# 브랜치 보호 규칙 (main) — 계정 유형별 자동 분기
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

echo "🔒 Ruleset 설정 완료"
```

### Phase 6: 커밋 & Ralph Loop 시작 안내

```bash
# 생성된 파일 커밋
git add -A
git commit -m "WI-chore PRD 기반 작업 계획 생성"
git push origin main
```

**⚠️ ralph.sh는 절대 이 세션에서 `bash ralph.sh`로 직접 실행하지 않는다.**
`claude -p`는 Claude Code 세션 안에서 중첩 실행이 불가능하므로,
**플랫폼을 감지하여 새 터미널 창을 자동으로 열고 ralph.sh를 실행**한다:

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

# 플랫폼별 새 터미널에서 ralph.sh 실행
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    # Windows — bash.exe 동적 탐색
    BASH_EXE=$(find_windows_bash)
    if [[ -n "$BASH_EXE" ]]; then
      start "" "$BASH_EXE" -c "cd '$PROJECT_DIR' && bash ralph.sh; read -p 'Press Enter to close...'"
    else
      # Git Bash 없음 — WSL 시도
      if command -v wsl &>/dev/null; then
        wsl_path=$(wslpath "$PROJECT_DIR" 2>/dev/null || echo "/mnt/c${PROJECT_DIR:2}")
        start "" wsl bash -c "cd '$wsl_path' && bash ralph.sh; read -p 'Press Enter to close...'"
      else
        echo "⚠️ bash를 찾을 수 없습니다."
        echo "  다음 중 하나를 설치하세요:"
        echo "  1. Git for Windows (https://git-scm.com) — Git Bash 포함"
        echo "  2. WSL (wsl --install)"
        echo ""
        echo "  설치 후 수동 실행:"
        echo "  cd $PROJECT_DIR && bash ralph.sh"
      fi
    fi
    ;;
  Linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      # WSL — WSL 내부에서 직접 새 터미널
      if command -v wslview &>/dev/null; then
        # wslu 설치된 경우 Windows 터미널 활용
        wslview "wt.exe" -d "$PROJECT_DIR" bash -c "bash ralph.sh; read -p 'Press Enter...'"
      else
        # 새 bash 프로세스로 실행
        setsid bash -c "cd '$PROJECT_DIR' && bash ralph.sh" &>/dev/null &
        echo "Ralph Loop이 백그라운드에서 시작되었습니다."
        echo "  로그 확인: tail -f .ralph/logs/ralph.log"
      fi
    else
      # Native Linux — 터미널 에뮬레이터 탐색
      if command -v gnome-terminal &>/dev/null; then
        gnome-terminal -- bash -c "cd '$PROJECT_DIR' && bash ralph.sh; read -p 'Press Enter to close...'"
      elif command -v konsole &>/dev/null; then
        konsole -e bash -c "cd '$PROJECT_DIR' && bash ralph.sh; read -p 'Press Enter to close...'" &
      elif command -v xfce4-terminal &>/dev/null; then
        xfce4-terminal -e "bash -c \"cd '$PROJECT_DIR' && bash ralph.sh; read -p 'Press Enter to close...'\"" &
      elif command -v xterm &>/dev/null; then
        xterm -e "cd '$PROJECT_DIR' && bash ralph.sh; read -p 'Press Enter to close...'" &
      else
        setsid bash -c "cd '$PROJECT_DIR' && bash ralph.sh" &>/dev/null &
        echo "Ralph Loop이 백그라운드에서 시작되었습니다."
        echo "  로그 확인: tail -f .ralph/logs/ralph.log"
      fi
    fi
    ;;
  Darwin*)
    # macOS — Terminal.app 또는 iTerm2
    if osascript -e 'exists application "iTerm"' 2>/dev/null; then
      osascript -e "tell application \"iTerm\" to create window with default profile command \"cd '$PROJECT_DIR' && bash ralph.sh\""
    else
      osascript -e "tell application \"Terminal\" to do script \"cd '$PROJECT_DIR' && bash ralph.sh\""
    fi
    ;;
esac
```

실행 후 안내 출력:
```
🚀 Ralph Loop이 새 터미널 창에서 시작되었습니다!
   열린 터미널 창에서 진행 상황을 확인하세요.

💡 수동 실행이 필요한 경우:
   cd {project-path} && bash ralph.sh
```

**bash를 찾을 수 없는 경우 (Windows):**
```
⚠️ bash를 찾을 수 없습니다.
  다음 중 하나를 설치하세요:
  1. Git for Windows (https://git-scm.com) — Git Bash 포함
  2. WSL (wsl --install)
```

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

🚀 Ralph Loop이 새 터미널 창에서 시작되었습니다!
   열린 터미널 창에서 진행 상황을 확인하세요.
```

## Boundaries

**Will:**
- PRD를 분석하여 WI 체크리스트 자동 생성
- 기술 스택에 맞는 MCP 서버 검색 및 설치 제안
- 문서 계층구조에 PRD 내용 분배
- Ralph Loop 실행 준비

**Will Not:**
- 사용자 확인 없이 MCP 서버 설치
- 실제 코드 구현 (Ralph Loop이 담당)
- PRD 내용 임의 수정
- `--dangerously-skip-permissions` 사용 (보안상 --allowedTools 사용)
- **ralph.sh를 `bash ralph.sh`로 이 세션에서 직접 실행** (claude -p 중첩 불가 → 새 터미널 창 자동 오픈)
