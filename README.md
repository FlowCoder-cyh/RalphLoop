# RalphLoop

**AI가 알아서 개발해주는 자동화 시스템**

RalphLoop은 [Claude Code](https://claude.com/claude-code)를 활용하여 프로젝트를 자동으로 개발하는 시스템입니다.
요구사항(PRD)만 작성하면, AI가 코드 작성부터 테스트, PR 생성, 머지까지 전부 처리합니다.

---

## 이런 분들에게 추천합니다

- 아이디어는 있는데 개발이 어려운 분
- 반복적인 개발 작업을 자동화하고 싶은 분
- Claude Code를 더 체계적으로 활용하고 싶은 개발자

## 어떻게 동작하나요?

```
1. 만들고 싶은 것을 설명합니다 (PRD 작성)
2. AI가 작업 목록을 만듭니다 (WI: Work Item)
3. Ralph Loop이 자동으로 돌면서:
   브랜치 생성 → 코드 구현 → 테스트 → PR → CI 통과 → 머지
   이 과정을 작업이 끝날 때까지 반복합니다
```

사람이 할 일은 **"무엇을 만들지 설명하는 것"** 뿐입니다.

---

## 설치

### 사전 준비

| 필수 | 설치 방법 |
|------|-----------|
| [Claude Code](https://claude.com/claude-code) | `npm install -g @anthropic-ai/claude-code` |
| [GitHub CLI](https://cli.github.com/) | `winget install GitHub.cli` (Windows) / `brew install gh` (Mac) |
| [Git](https://git-scm.com/) | 대부분 이미 설치되어 있음 |
| Git Bash | Windows: Git 설치 시 포함 / Mac·Linux: 터미널 그대로 사용 |

### 설치 방법

```bash
git clone https://github.com/FlowCoder-cyh/RalphLoop.git
cd RalphLoop
bash install.sh
```

설치가 완료되면 Claude Code에서 `/wi:` 명령어를 사용할 수 있습니다.

### 제거

```bash
bash uninstall.sh
```

---

## 사용법

### 1단계: 프로젝트 만들기

Claude Code를 열고 프로젝트 폴더에서 실행합니다.

```
/wi:init my-project --type typescript --org my-github-org
```

- `my-project`: 프로젝트 이름
- `--type`: 프로젝트 유형 (typescript, python, go 등)
- `--org`: GitHub 조직 또는 사용자명

### 2단계: 요구사항 작성 (PRD)

AI와 대화하면서 만들고 싶은 것을 설명합니다.

```
/wi:prd 직원 근태관리 웹 서비스를 만들고 싶어
```

AI가 질문하면 답변하면 됩니다. 대화가 끝나면 PRD 문서가 자동 생성됩니다.

> PRD 작성이 어려우면 `/wi:guide`를 먼저 실행하면 가이드를 볼 수 있습니다.

### 3단계: 개발 시작

```
/wi:start
```

이 명령 하나로:
1. PRD를 분석하여 작업 목록(WI)을 자동 생성
2. 필요한 도구(MCP)를 탐색하고 설치
3. 별도 터미널에서 Ralph Loop 실행

이후 Ralph Loop이 자동으로 돌면서 작업을 처리합니다.

### 진행 상황 확인

```
/wi:status
```

터미널에서도 실시간으로 진행 상태를 볼 수 있습니다:
```
[2026-03-13 10:30:15] --- Iteration 5/94 ---
[2026-03-13 10:30:15] WI #8/78: WI-008-feat People DB 스키마
[2026-03-13 10:30:15] 진행률: 7/78 (8%)
[2026-03-13 10:30:15] 세션 재활용: 5843321b...
  ⠹ 2m 30s | feature/WI-008-feat-people-db-schema | 파일: 5개
```

### 결정사항 기록

개발 중 중요한 결정을 내렸다면:
```
/wi:note 인증은 NextAuth 대신 Supabase Auth를 사용하기로 결정
```

---

## 명령어 요약

| 명령어 | 설명 |
|--------|------|
| `/wi:init` | 프로젝트 환경 셋업 |
| `/wi:prd` | 요구사항(PRD) 작성 |
| `/wi:start` | 개발 시작 (Ralph Loop 가동) |
| `/wi:status` | 진행 상황 확인 |
| `/wi:guide` | PRD 작성 가이드 |
| `/wi:note` | 결정사항 기록 |

---

## 개발자 가이드

### 시스템 구조

```
RalphLoop/
├── install.sh          # 설치 스크립트
├── uninstall.sh        # 제거 스크립트
├── rules/              # Claude Code 글로벌 규칙
│   ├── wi-global.md    # 커밋/브랜치/PR/코드 규칙
│   ├── wi-ralph-loop.md # Ralph Loop 실행 규칙
│   └── wi-utf8.md      # UTF-8 인코딩 규칙
├── skills/wi/          # Claude Code 스킬 (명령어)
│   ├── init.md         # /wi:init
│   ├── start.md        # /wi:start
│   ├── prd.md          # /wi:prd
│   ├── status.md       # /wi:status
│   ├── guide.md        # /wi:guide
│   └── note.md         # /wi:note
└── templates/          # 프로젝트 템플릿
    ├── ralph.sh        # Ralph Loop 엔진
    ├── .ralph/         # 상태 관리 파일
    │   ├── PROMPT.md   # AI에게 전달되는 지시서
    │   ├── AGENT.md    # 빌드/테스트 명령 정의
    │   ├── fix_plan.md # 작업 목록 (WI)
    │   ├── guardrails.md # 실패 방지 규칙
    │   └── hooks/      # Git hooks
    ├── .github/        # CI/CD + PR 템플릿
    ├── .ralphrc        # 루프 설정
    └── CLAUDE.md       # 프로젝트 정보
```

### Ralph Loop 동작 원리

```
bash ralph.sh
    │
    ├─ fix_plan.md에서 다음 미완료 WI 선택
    ├─ claude -p 호출 (1개 WI만 처리)
    │   ├─ 브랜치 생성
    │   ├─ 코드 구현
    │   ├─ lint → build → test 검증
    │   ├─ 커밋 → push → PR 생성
    │   ├─ CI 통과 → 자동 머지
    │   └─ RALPH_STATUS 출력 후 종료
    ├─ 세션 ID 및 토큰 사용량 파싱
    ├─ 컨텍스트 임계치 체크 (150k tokens)
    ├─ fix_plan.md 진행률 확인
    └─ 다음 WI로 반복
```

### 핵심 설계 원칙

- **1 iteration = 1 WI**: `claude -p` 한 번 호출에 하나의 작업만 처리
- **세션 재활용**: `--resume`으로 이전 컨텍스트 재사용, 토큰 절약
- **컨텍스트 모니터링**: 150k tokens 초과 시 자동으로 새 세션
- **크래시 복구**: `loop_state.json`에 상태 저장, 비정상 종료 후 자동 재개
- **에러 전략**: 명확한 에러(빌드/타입)는 근본 분석 + 재시도, 모호한 에러는 기록 후 스킵
- **circuit breaker**: 3회 연속 진행 없으면 자동 중지

### WI 커밋 규칙

```
형식: WI-NNN-[type] 한글 작업명

타입: feat, fix, docs, style, refactor, test, chore, perf, ci, revert
번호: fix_plan.md 기준 3자리 순번 (001, 002, ...)
예시: WI-001-feat 사용자 인증 추가
      WI-015-fix 로그인 토큰 만료 처리

시스템 커밋 (번호 없음): WI-chore, WI-docs
```

### 브랜치 규칙

```
feat:     feature/WI-NNN-feat-작업명-kebab
fix:      fix/WI-NNN-fix-작업명-kebab
chore:    chore/WI-NNN-chore-작업명-kebab
docs:     docs/WI-NNN-docs-작업명-kebab
refactor: refactor/WI-NNN-refactor-작업명-kebab
```

### 커스터마이징

**루프 설정** (`.ralphrc`):
```bash
MAX_ITERATIONS=50       # 최대 반복 횟수 (미설정 시 WI 수 × 1.2 자동 계산)
RATE_LIMIT_PER_HOUR=80  # 시간당 API 호출 제한
COOLDOWN_SEC=5          # 반복 간 대기 시간
NO_PROGRESS_LIMIT=3     # 진행 없는 연속 반복 허용 횟수
CONTEXT_THRESHOLD=150000 # 세션 리셋 토큰 임계치
```

**빌드/테스트 명령** (`.ralph/AGENT.md`):
프로젝트 유형에 따라 lint, build, test 명령을 정의합니다.

**실패 방지 규칙** (`.ralph/guardrails.md`):
루프 실행 중 발견된 실패 패턴이 자동으로 누적됩니다. 다음 WI에서 이를 참고하여 동일 실패를 방지합니다.

---

## 지원 환경

| OS | 상태 |
|----|------|
| Windows (Git Bash) | 지원 |
| macOS | 지원 |
| Linux | 지원 |
| WSL | 지원 (Windows 경로 자동 감지) |

---

## 라이선스

MIT License
