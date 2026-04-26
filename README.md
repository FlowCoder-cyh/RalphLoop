# FlowSet

**AI가 알아서 개발해주는 자동화 시스템**

> Autonomous AI development loop for Claude Code — describe what you want, and AI builds it automatically with full Git workflow (branch, implement, test, PR, merge).

FlowSet은 [Claude Code](https://claude.com/claude-code)를 활용하여 프로젝트를 자동으로 개발하는 시스템입니다.
요구사항(PRD)만 작성하면, AI가 코드 작성부터 테스트, PR 생성, 머지까지 전부 처리합니다.

**v4.0 (현재)**: 매트릭스 기반 검증 게이트웨이 + 4-class 시스템 (code/content/hybrid/visual) + Stop hook B1~B7 자동 차단. 코드 프로젝트(SaaS·앱)뿐 아니라 **content 프로젝트(문서·연구·기획)** 도 동일 워크플로우로 자동화.

**Keywords**: Claude Code automation, AI coding agent, autonomous development, AI pair programming, automated PR workflow, Claude API, Anthropic, AI software engineer, vibe coding, matrix-based validation, code-content hybrid

---

## 이런 분들에게 추천합니다

- 아이디어는 있는데 개발이 어려운 분
- 반복적인 개발 작업을 자동화하고 싶은 분
- Claude Code를 더 체계적으로 활용하고 싶은 개발자

## 어떻게 동작하나요?

```
1. 만들고 싶은 것을 설명합니다 (PRD 작성)
2. AI가 와이어프레임을 만들어 확인받습니다
3. AI가 작업 목록을 만듭니다 (WI: Work Item)
4. FlowSet이 자동으로 돌면서:
   브랜치 생성 → 코드 구현 → 테스트 → PR → 머지 대기 → 검증 → 다음 WI
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

1. 저장소를 다운로드합니다
```bash
git clone https://github.com/FlowCoder-cyh/FlowSet.git
```

2. Claude Code를 열고 클론받은 폴더로 이동합니다
```
"install.sh 실행해줘"
```

이것만 하면 설치 끝입니다.

> **터미널에서 직접 설치하려면** (참고용):
> ```bash
> cd FlowSet
> bash install.sh
> ```

### 제거

```bash
bash uninstall.sh
```

---

## 사용법

Claude Code를 열고 아래 명령어를 순서대로 입력하면 됩니다. AI가 알아서 필요한 것들을 물어봅니다.

### 1단계: 프로젝트 만들기

```
/wi:init
```

프로젝트 이름, 유형, GitHub 계정(조직 권장)을 AI가 물어봅니다. 답변만 하면 환경이 자동으로 셋업됩니다.

> 조직 계정을 사용하면 **Merge Queue**가 활성화되어 PR이 자동으로 순차 머지됩니다.

### 2단계: 만들고 싶은 것 설명하기

```
/wi:prd
```

AI가 "어떤 걸 만들고 싶으세요?"라고 물어봅니다. 편하게 설명하면 AI가 정리해서 문서(PRD)로 만들어줍니다.
**와이어프레임도 자동으로 생성**되어 브라우저에서 UI를 미리 확인할 수 있습니다.

> 어떻게 설명해야 할지 모르겠다면 `/wi:guide`를 먼저 실행해보세요.

### 3단계: 인프라 환경 구성

```
/wi:env
```

AI가 PRD를 분석해서 필요한 인프라(DB, 배포, 인증 등)를 파악하고, 단계별로 안내하며 설정합니다.
- Supabase MCP로 DB 자동 생성
- Vercel CLI로 배포 연결
- GitHub Secrets 자동 등록
- DB 연결 확인 시 mock 금지 자동 적용

### 4단계: 개발 시작

```
/wi:start
```

이것만 치면 AI가 알아서:
- 아키텍처 계약을 생성하고 (API 표준 + 데이터 흐름)
- RAG 체계를 초기화하고
- 작업 목록을 만들고 (도메인 분리 분석 → 병렬/순차 자동 권장)
- Smoke 테스트를 생성하고
- 별도 터미널에서 자동 개발을 시작합니다

이후 FlowSet이 작업이 끝날 때까지 자동으로 돌아갑니다.

### 진행 상황 확인

```
/wi:status
```

---

## 명령어 요약

| 명령어 | 설명 |
|--------|------|
| `/wi:init` | 프로젝트 환경 셋업 (Git, CI/CD, 템플릿, hooks) |
| `/wi:prd` | 요구사항(PRD) + 와이어프레임 작성 |
| `/wi:env` | 인프라 환경 구성 (DB, 배포, Secrets) |
| `/wi:start` | 개발 시작 (계약, RAG, smoke, FlowSet 가동) |
| `/wi:status` | 진행 상황 확인 |
| `/wi:guide` | PRD 작성 가이드 |
| `/wi:note` | 결정사항 기록 |

---

## 개발자 가이드

### 시스템 구조

```
FlowSet/
├── install.sh          # 설치 스크립트
├── uninstall.sh        # 제거 스크립트
├── CHANGELOG.md        # 릴리즈 노트
├── rules/              # Claude Code 글로벌 규칙
│   ├── wi-global.md    # 커밋/브랜치/PR/코드 규칙
│   ├── wi-flowset.md # FlowSet 실행 규칙
│   └── wi-utf8.md      # UTF-8 인코딩 규칙
├── skills/wi/          # Claude Code 스킬 (명령어)
│   ├── init.md         # /wi:init
│   ├── prd.md          # /wi:prd (와이어프레임 포함)
│   ├── env.md          # /wi:env
│   ├── start.md        # /wi:start (계약 + RAG 초기화)
│   ├── status.md       # /wi:status
│   ├── guide.md        # /wi:guide
│   └── note.md         # /wi:note
└── templates/          # 프로젝트 템플릿
    ├── flowset.sh        # FlowSet 엔진 (v3.4)
    ├── CLAUDE.md       # 프로젝트 규칙 (핵심 8개 + 자동 강제)
    ├── .flowset/
    │   ├── PROMPT.md   # AI 지시서 (TDD, 머지 대기, 와이어프레임 참조)
    │   ├── AGENT.md    # 빌드 명령 + 인프라 + 와이어프레임 + 계약
    │   ├── contracts/  # 팀 간 계약 + 스프린트 계약
    │   │   ├── api-standard.md    # API 응답 형식 계약
    │   │   ├── data-flow.md       # SSOT 데이터 흐름 계약
    │   │   └── sprint-template.md # 스프린트 계약 템플릿 (수용 기준 + 검증 방법)
    │   ├── guides/
    │   │   ├── team-worker-guide.md          # Agent Teams 팀원 초기화 가이드
    │   │   └── flowset-operations-guide.md   # FlowSet 운영 상세 가이드 (E2E 품질 기준 등)
    │   ├── ownership.json # 팀별 소유 디렉토리 매핑
    │   ├── tech-debt.md   # 기술부채 등록 (P0/P1/P2)
    │   ├── hooks/      # Git hooks (commit-msg + 필수 스크립트 검증, pre-push)
    │   └── scripts/    # vault-helpers, session-start-vault, stop-vault-sync, stop-rag-check, check-ownership, check-cross-team-impact, notify-contract-change, resolve-team, task-completed-eval, verify-requirements, enqueue-pr, launch-loop, rollback
    ├── .claude/
    │   ├── agents/
    │   │   ├── lead-workflow.md  # 리드 6단계 (TeamCreate→Agent Teams→evaluator→정리)
    │   │   └── evaluator.md     # 평가자 (채점 기반, few-shot, 안티패턴 감점)
    │   ├── rules/      # 핵심 운영 규칙 (경량화, 상세는 guides/ 참조)
    │   └── settings.json # SessionStart + PostCompact + PreToolUse + PostToolUse + TaskCompleted + Stop hook
    ├── .github/
    │   └── workflows/  # ci.yml, commit-check.yml, e2e.yml
    └── .flowsetrc        # 루프 설정 (+ vault 연동 [v3.0])
```

### v4.0 PROJECT_CLASS 시스템

`/wi:init` Step 1에서 `PROJECT_CLASS`를 선택 (기본값: `code`).

| PROJECT_CLASS | 매트릭스 영역 | Stop hook 차단 (B1~B7) | evaluator type |
|---------------|--------------|------------------------|---------------|
| `code` | `matrix.entities[]` (CRUD × status) | B1 미완 셀 / B2 auth / B3 타입중복 / B4 Gherkin↔테스트 | code (cell+scenario coverage) |
| `content` | `matrix.sections[]` (draft/review/approve × status) | B1 미완 / B6 sources / B7 completeness_checklist | content (출처/리뷰/형식) |
| `hybrid` | 양쪽 모두 (`ownership.json.teams[].class` 경로별) | B1~B7 전체 | hybrid (weighted/strict) |
| `visual` (legacy) | — | — | 비주얼 (디자인/독창성) |

**매트릭스 SSOT**: `.flowset/spec/matrix.json` — `/wi:prd` Step 4가 PROJECT_CLASS에 따라 동적 생성.

**자동 차단 메커니즘** (Stop hook `stop-rag-check.sh`, v4.0 §6/7/8/9/10):
- B1 (미완 셀): `matrix.status: "missing"` → evaluator FAIL
- B2 (auth_patterns): `src/api/**` 변경 시 등록 패턴 grep, 매칭 실패 → block
- B3 (타입 중복): 같은 interface/type 다른 파일 2개+ → block
- B4 (Gherkin↔테스트): 시나리오 수 + 이름 부분 매칭 검증, 실패 → block
- B6 (sources): `matrix.sections[].sources[]` 파일 존재 + URL 형식 검증
- B7 (completeness): `completeness_checklist` 항목이 본문(매핑된 paths)에 등장 검증

**hybrid 동시 변경**: 변경 파일을 class별로 분리 → 각 영역 검증 모두 실행 → 모든 issue 수집 후 한 번에 block.

### FlowSet 동작 원리 (v4.0)

```
bash flowset.sh
    │
    ├─ safe_sync_main (origin/main과 동기화)
    ├─ recover_completed_from_history (crash 복구)
    ├─ cleanup_stale_completed (충돌 close된 WI 재실행)
    ├─ resolve_conflicting_prs (충돌 PR 자동 rebase)
    ├─ inject_regression_wis (regression issue → fix WI 추가)
    │
    ├─ 다음 미완료 WI 선택 (completed_wis.txt 필터)
    ├─ claude -p 호출 (TDD: 테스트 먼저 → 구현)
    │   ├─ 브랜치 생성 (worktree)
    │   ├─ wireframes/ + contracts/ 참조
    │   ├─ RED → GREEN → lint → build → test
    │   ├─ 커밋 → push → PR → enqueue
    │   └─ 즉시 종료 (CI 폴링 없음)
    │
    ├─ validate_post_iteration (scope/TODO/API/RAG/requirements 검증)
    ├─ verify-requirements.sh (검증 에이전트 — requirements.md vs 구현 대조)
    ├─ wait_for_merge / wait_for_batch_merge (머지 완료 대기)
    ├─ safe_sync_main → mark_wi_done
    ├─ log_trace (trace.jsonl 기록)
    └─ 다음 WI로 반복

    루프 종료 시:
    └─ reconcile_fix_plan (fix_plan.md 일괄 동기화 → 단일 PR)
```

### 핵심 설계 원칙

- **요구사항 보호**: requirements.md에 사용자 원본 고정, 에이전트 수정 금지
- **생성자-평가자 분리**: 구현(team-worker)과 평가(evaluator)를 별도 에이전트로 분리. 자기 객관화 실패 방지.
- **스프린트 계약**: WI별 수용 기준 + 검증 방법을 사전 합의. 합의 전 구현 금지.
- **채점 기반 평가**: 0~10점, 4대 기준(기능/품질/테스트/계약 or 디자인/독창성/기술/정확성), few-shot 캘리브레이션, 안티패턴 감점
- **Agent Teams 상주 팀원**: TeamCreate → Agent(team_name)로 생성. 기존 팀원 재사용 필수, 중복 생성 금지.
- **소유권 hook 강제**: 팀별 디렉토리 제한 (PreToolUse), 계약/스키마 변경 차단 (cross-team)
- **vault 세션 연속성**: Obsidian vault에 state + 일별 세션 로그 + 팀 상태 자동 기록. SessionStart에서 state.md 포인터만 주입 (v3.4: 토큰 누적 방지, 상세는 on-demand 읽기).
- **머지 대기**: PR 머지 완료까지 대기 후 다음 WI (stale base 방지)
- **TDD 강제**: 테스트 먼저 작성 → 구현
- **RAG 강제**: Stop hook + validate로 자동 감지 + 업데이트 강제
- **fix_plan.md 읽기 전용**: completed_wis.txt가 SSOT
- **regression 자동화**: e2e 실패 → issue → WI-NNN-1-fix → 자동 재실행

### 커스터마이징

**루프 설정** (`.flowsetrc`):
```bash
MAX_ITERATIONS=50       # 최대 반복 횟수 (미설정 시 WI 수 × 1.2 자동 계산)
MAX_TURNS=40            # 워커당 최대 턴 수 (0=무제한)
PARALLEL_COUNT=1        # 병렬 워커 수 (1=순차, 2+=병렬 worktree)
RATE_LIMIT_PER_HOUR=80  # 시간당 API 호출 제한
COOLDOWN_SEC=5          # 반복 간 대기 시간
NO_PROGRESS_LIMIT=3     # 진행 없는 연속 반복 허용 횟수
CONTEXT_THRESHOLD=150000 # 세션 리셋 토큰 임계치
GITHUB_ACCOUNT_TYPE=""  # "org" 또는 "personal"
GITHUB_ORG=""           # 조직명 또는 사용자명
```

---

## 지원 환경

| OS | 상태 | 비고 |
|----|------|------|
| Windows (Git Bash) | 지원 | |
| macOS | 지원 | tmux 권장 (`brew install tmux`) |
| Linux | 지원 | |
| WSL | 지원 | Windows 경로 자동 감지 |

---

## 라이선스

MIT License
