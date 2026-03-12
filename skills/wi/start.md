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

### Phase 4: AGENT.md 업데이트

PRD에서 파악한 기술 스택으로 `.ralph/AGENT.md`의 빌드/테스트 명령을 구체화.

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
