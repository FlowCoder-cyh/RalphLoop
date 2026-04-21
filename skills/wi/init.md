---
name: init
description: "프로젝트 개발 환경 전체 셋업 (Git, CI/CD, FlowSet, 문서 계층구조)"
category: workflow
complexity: advanced
mcp-servers: []
personas: [devops-engineer, architect]
---

# /wi:init - Project Environment Setup

> 새 프로젝트에 Git, GitHub CI/CD, PR 규칙, FlowSet, 문서 계층구조를 한번에 셋업합니다.

## Triggers
- 새 프로젝트 초기 환경 구성
- 개발 인프라 셋업 요청

## Usage
```
/wi:init [project-name] [--type typescript|python|rust|go|java] [--org github-org] [--private]
```

## Behavioral Flow

### Step 1: 인자 파싱 & 사전 검증
- `$ARGUMENTS`에서 프로젝트명, 타입, GitHub org 추출
- 누락된 필수 정보는 사용자에게 질문
- 필수 도구 확인: `git`, `gh` (GitHub CLI). 미설치 시 설치 안내 후 중단
- `gh auth status`로 인증 상태 확인. 미인증 시 `gh auth login` 안내 후 중단

### Step 2: Git 초기화
```bash
git init
git checkout -b main
```

### Step 3: 프로젝트 구조 생성
**1단계: `~/.claude/templates/flowset/`에서 템플릿 복사** (flowset.sh, PROMPT.md, hooks, workflows, .gitignore 등)
**2단계: 아래 중 템플릿에 없는 파일만 직접 생성** (.claude/rules/, docs/, fix_plan.md, guardrails.md, AGENT.md)

최종 구조:
```
.github/
  workflows/
    ci.yml              # lint → build → test (프로젝트 타입에 맞게)
    commit-check.yml    # WI-NNN-[type] 커밋 메시지 검증
  PULL_REQUEST_TEMPLATE.md
.claude/
  rules/
    project.md          # 프로젝트 규칙 (글로벌 규칙 상속)
.flowset/
  PROMPT.md             # FlowSet 반복 프롬프트 (절차만, 규칙은 rules/ 참조)
  AGENT.md              # 빌드/테스트 명령 (프로젝트 타입에 맞게)
  fix_plan.md           # WI 체크리스트 (PRD 투입 시 채워짐)
  guardrails.md         # 프로젝트별 실패 방지 규칙
  hooks/
    commit-msg          # 커밋 메시지 형식 강제
    pre-push            # main 직접 push 방지
  specs/
  logs/
docs/
  L0-vision/            # 비전/목표/OKR
  L1-domain/            # 대분류 (비즈니스 도메인)
  L2-module/            # 중분류 (기능 모듈)
  L3-feature/           # 소분류 (개별 기능)
  L4-task/              # 상세분류 (WI 단위)
flowset.sh                # FlowSet 스크립트
.flowsetrc                # FlowSet 설정
.gitattributes          # UTF-8 + LF 강제
.editorconfig           # 에디터 설정
CLAUDE.md               # 프로젝트 정보 (규칙은 rules/ 참조)
```

**파일 내용은 아래 명세를 기반으로 직접 생성. 템플릿 경로에 의존하지 않음.**
단, 아래는 프로젝트 타입에 맞게 커스터마이징:

#### ci.yml (프로젝트 타입별)
- **typescript/javascript**: Node.js 20, `npm ci`, `npm run lint`, `npm run build`, `npm test`
- **python**: Python 3.12, `pip install -r requirements.txt`, `ruff check .`, `pytest`
- **rust**: stable toolchain, `cargo clippy`, `cargo build`, `cargo test`
- **go**: Go 1.22, `golangci-lint run`, `go build ./...`, `go test ./...`
- **java**: JDK 21, Gradle/Maven, `./gradlew check`, `./gradlew build`, `./gradlew test`

#### AGENT.md (프로젝트 타입별)
프로젝트 타입에 맞는 lint/build/test 명령 기입.

#### flowset.sh, PROMPT.md, hooks, workflows 등 (템플릿에서 복사)
**직접 생성하지 않음.** `~/.claude/templates/flowset/`에서 복사합니다.

```bash
# 템플릿 디렉토리 확인
TEMPLATE_DIR="$HOME/.claude/templates/flowset"
if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "ERROR: 템플릿이 설치되지 않았습니다."
  echo "  settings 저장소에서 설치하세요:"
  echo "  git clone https://github.com/FlowCoder-cyh/FlowSet.git /tmp/flowset-templates"
  echo "  cp -r /tmp/flowset-templates/templates/ ~/.claude/templates/flowset/"
  exit 1
fi

# 템플릿 복사 (중첩 방지: 개별 파일 단위)
cp "$TEMPLATE_DIR/flowset.sh" ./flowset.sh
cp "$TEMPLATE_DIR/.gitignore" ./.gitignore
cp "$TEMPLATE_DIR/.gitattributes" ./.gitattributes
cp "$TEMPLATE_DIR/.editorconfig" ./.editorconfig
cp "$TEMPLATE_DIR/CLAUDE.md" ./CLAUDE.md

# v4.0 WI-A2a~e: lib/ 런타임 라이브러리 복사
# state.sh (WI-A2a) + preflight.sh (WI-A2b) + worker.sh (WI-A2c) + merge.sh (WI-A2d) + vault.sh (WI-A2e)
mkdir -p ./lib
cp "$TEMPLATE_DIR/lib/state.sh" ./lib/state.sh
cp "$TEMPLATE_DIR/lib/preflight.sh" ./lib/preflight.sh
cp "$TEMPLATE_DIR/lib/worker.sh" ./lib/worker.sh
cp "$TEMPLATE_DIR/lib/merge.sh" ./lib/merge.sh
cp "$TEMPLATE_DIR/lib/vault.sh" ./lib/vault.sh

# .flowset/ 내부 파일 복사 (디렉토리는 이미 Step 3에서 생성됨)
cp "$TEMPLATE_DIR/.flowset/PROMPT.md" ./.flowset/PROMPT.md
cp "$TEMPLATE_DIR/.flowset/hooks/commit-msg" ./.flowset/hooks/commit-msg
cp "$TEMPLATE_DIR/.flowset/hooks/pre-push" ./.flowset/hooks/pre-push
mkdir -p ./.flowset/scripts
cp "$TEMPLATE_DIR/.flowset/scripts/enqueue-pr.sh" ./.flowset/scripts/enqueue-pr.sh
cp "$TEMPLATE_DIR/.flowset/scripts/launch-loop.sh" ./.flowset/scripts/launch-loop.sh
cp "$TEMPLATE_DIR/.flowset/scripts/verify-requirements.sh" ./.flowset/scripts/verify-requirements.sh

# .github/ 내부 파일 복사
mkdir -p ./.github/workflows
cp "$TEMPLATE_DIR/.github/PULL_REQUEST_TEMPLATE.md" ./.github/PULL_REQUEST_TEMPLATE.md
cp "$TEMPLATE_DIR/.github/workflows/ci.yml" ./.github/workflows/ci.yml
cp "$TEMPLATE_DIR/.github/workflows/commit-check.yml" ./.github/workflows/commit-check.yml
cp "$TEMPLATE_DIR/.github/workflows/e2e.yml" ./.github/workflows/e2e.yml

# .claude/rules/ 운영 규칙 복사
mkdir -p ./.claude/rules
cp "$TEMPLATE_DIR/.claude/rules/flowset-operations.md" ./.claude/rules/flowset-operations.md
cp "$TEMPLATE_DIR/.claude/rules/project.md" ./.claude/rules/project.md
cp "$TEMPLATE_DIR/.claude/rules/team-roles.md" ./.claude/rules/team-roles.md 2>/dev/null || true

# .claude/settings.json (PreToolUse 소유권 hook + Stop hook)
cp "$TEMPLATE_DIR/.claude/settings.json" ./.claude/settings.json

# Stop hook 스크립트 (v3.4: stop-vault-sync.sh가 메인)
cp "$TEMPLATE_DIR/.flowset/scripts/stop-vault-sync.sh" ./.flowset/scripts/stop-vault-sync.sh
cp "$TEMPLATE_DIR/.flowset/scripts/stop-rag-check.sh" ./.flowset/scripts/stop-rag-check.sh
cp "$TEMPLATE_DIR/.flowset/scripts/session-start-vault.sh" ./.flowset/scripts/session-start-vault.sh
cp "$TEMPLATE_DIR/.flowset/scripts/notify-contract-change.sh" ./.flowset/scripts/notify-contract-change.sh
cp "$TEMPLATE_DIR/.flowset/scripts/check-cross-team-impact.sh" ./.flowset/scripts/check-cross-team-impact.sh
cp "$TEMPLATE_DIR/.flowset/scripts/rollback.sh" ./.flowset/scripts/rollback.sh
cp "$TEMPLATE_DIR/.flowset/tech-debt.md" ./.flowset/tech-debt.md 2>/dev/null || true

# v3.0: 소유권 hook + vault helpers + 계약 템플릿
cp "$TEMPLATE_DIR/.flowset/scripts/check-ownership.sh" ./.flowset/scripts/check-ownership.sh
cp "$TEMPLATE_DIR/.flowset/scripts/vault-helpers.sh" ./.flowset/scripts/vault-helpers.sh
cp "$TEMPLATE_DIR/.flowset/scripts/resolve-team.sh" ./.flowset/scripts/resolve-team.sh
# ownership.json은 프로젝트 타입에 맞게 동적 생성 (아래 Step 3.5)
mkdir -p ./.flowset/contracts
cp "$TEMPLATE_DIR/.flowset/contracts/api-standard.md" ./.flowset/contracts/api-standard.md
cp "$TEMPLATE_DIR/.flowset/contracts/data-flow.md" ./.flowset/contracts/data-flow.md
cp "$TEMPLATE_DIR/.flowset/contracts/sprint-template.md" ./.flowset/contracts/sprint-template.md
cp "$TEMPLATE_DIR/.flowset/scripts/task-completed-eval.sh" ./.flowset/scripts/task-completed-eval.sh
mkdir -p ./.flowset/eval-results

# v3.0: Agent Teams (서브에이전트 정의: evaluator만. team-worker는 가이드 문서)
if [[ -d "$TEMPLATE_DIR/.claude/agents" ]]; then
  mkdir -p ./.claude/agents
  cp "$TEMPLATE_DIR/.claude/agents/"*.md ./.claude/agents/ 2>/dev/null || true
fi
# 팀원 가이드 (Agent Teams 팀원 초기화 참조 문서)
mkdir -p ./.flowset/guides
cp "$TEMPLATE_DIR/.flowset/guides/"*.md ./.flowset/guides/ 2>/dev/null || true

chmod +x flowset.sh .flowset/hooks/* .flowset/scripts/*.sh 2>/dev/null || true
```

**복사 후 프로젝트별 커스터마이징만 수행:**

#### .flowsetrc
`PROJECT_NAME`, `PROJECT_TYPE` 필드를 인자 값으로 채움.

#### CLAUDE.md
`{PROJECT_NAME}`, `{PROJECT_TYPE}`, `{PROJECT_DESCRIPTION}` 플레이스홀더를 실제 값으로 치환.

#### .claude/rules/project.md
`{PROJECT_NAME}`, `{PROJECT_TYPE}` 플레이스홀더를 실제 값으로 치환.

### Step 3.5: ownership.json 동적 생성 (프로젝트 타입별)

`.flowsetrc`의 `PROJECT_TYPE`을 기반으로 `.flowset/ownership.json`을 생성합니다.
프로젝트 구조에 맞는 팀 소유 디렉토리를 매핑합니다.

| PROJECT_TYPE | frontend | backend | qa | shared |
|---|---|---|---|---|
| typescript (Next.js) | src/app/**, src/components/** | src/api/**, src/lib/** | e2e/**, tests/**, __tests__/** | package.json, tsconfig.json, prisma/schema.prisma |
| python | templates/**, static/** | app/**, src/** | tests/**, test_** | requirements.txt, pyproject.toml, alembic/ |
| rust | src/bin/**, src/ui/** | src/lib/**, src/api/** | tests/**, benches/** | Cargo.toml, Cargo.lock |
| go | cmd/**, web/** | internal/**, pkg/** | *_test.go (동일 디렉토리) | go.mod, go.sum |
| java | src/main/resources/** | src/main/java/** | src/test/** | build.gradle, pom.xml |

**생성 절차:**
1. `PROJECT_TYPE` 확인
2. 위 매핑에 따라 JSON 생성
3. `crossTeamReview`는 계약 파일 + 스키마 파일 + 공유 컴포넌트 경로 자동 매핑
4. `.flowset/ownership.json`에 저장

**devops**는 항상 `.github/**`, `.claude/**`, `.flowset/**`
**planning**은 항상 `docs/**`, `wireframes/**`

프로젝트 실제 디렉토리 구조를 `tree -L 2` 또는 `ls`로 확인한 후, 존재하는 디렉토리만 포함합니다. 매핑 테이블에 없는 구조면 사용자에게 질문합니다.

### Step 3.6: Obsidian + Vault 환경 셋업

FlowSet v3.0은 Obsidian vault를 세션 간 기억 저장소로 사용합니다.

#### 1. Obsidian 설치 확인

```bash
# Obsidian 설치 확인 (프로세스 또는 실행 파일)
obsidian_installed=false
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    [[ -d "$LOCALAPPDATA/Obsidian" || -d "$APPDATA/obsidian" ]] && obsidian_installed=true
    ;;
  Darwin*)
    [[ -d "/Applications/Obsidian.app" ]] && obsidian_installed=true
    ;;
  Linux*)
    command -v obsidian &>/dev/null && obsidian_installed=true
    [[ -d "$HOME/.config/obsidian" ]] && obsidian_installed=true
    ;;
esac
```

미설치 시 안내:
```
Obsidian이 설치되어 있지 않습니다.

FlowSet v3.0은 Obsidian vault로 세션 간 기억을 유지합니다.
설치하면 이전 세션 맥락 자동 복원, 시맨틱 검색, 패턴 학습이 활성화됩니다.

설치 방법:
  https://obsidian.md/download

설치 후 필요한 플러그인:
  1. Smart Connections — 벡터 임베딩 + 시맨틱 검색
  2. Local REST API — HTTP API (Claude Code 연동)

지금 설치하시겠습니까? (Y/n)
  Y → 브라우저에서 다운로드 페이지 열기
  n → vault 없이 진행 (파일 기반 RAG만 사용)
```

#### 2. Vault 디렉토리 확인

```bash
VAULT_DIR="$HOME/.claude/knowledge"

# vault 디렉토리 존재 확인
if [[ ! -d "$VAULT_DIR" ]]; then
  mkdir -p "$VAULT_DIR"
  echo "vault 디렉토리 생성: $VAULT_DIR"
  echo "Obsidian에서 이 폴더를 vault로 열어주세요."
fi
```

#### 3. Local REST API 플러그인 확인

```bash
# REST API 응답 확인 (플러그인 활성화 여부)
vault_api_ok=false
VAULT_API_KEY=""

# 기존 API key가 있으면 확인
if [[ -f "$VAULT_DIR/.obsidian/plugins/obsidian-local-rest-api/data.json" ]]; then
  VAULT_API_KEY=$(jq -r '.apiKey // empty' "$VAULT_DIR/.obsidian/plugins/obsidian-local-rest-api/data.json" 2>/dev/null)
fi

if [[ -n "$VAULT_API_KEY" ]]; then
  response=$(curl -s -k --max-time 3 "https://localhost:27124/vault/" -H "Authorization: Bearer $VAULT_API_KEY" 2>/dev/null)
  [[ -n "$response" ]] && vault_api_ok=true
fi
```

미연결 시 안내:
```
Local REST API 플러그인이 응답하지 않습니다.

확인 사항:
  1. Obsidian이 실행 중인가? → Obsidian 앱 열기
  2. Local REST API 플러그인 설치됨? → Settings > Community plugins > "Local REST API" 검색
  3. 플러그인 활성화됨? → 토글 ON 확인
  4. HTTPS 활성화됨? → 플러그인 설정에서 "Enable HTTPS" ON

플러그인 설치: https://github.com/coddingtonbear/obsidian-local-rest-api

설정 완료 후 다시 확인하시겠습니까? (Y/n)
```

#### 4. Smart Connections 플러그인 확인

```bash
if [[ -d "$VAULT_DIR/.obsidian/plugins/smart-connections" ]]; then
  echo "Smart Connections 설치 확인"
else
  echo "Smart Connections 미설치"
  echo "  Obsidian > Settings > Community plugins > 'Smart Connections' 검색 > Install > Enable"
fi
```

#### 5. MCP 서버 등록

```bash
# obsidian-rest MCP 서버 등록 (이미 있으면 스킵)
if ! claude mcp get obsidian-rest &>/dev/null; then
  claude mcp add --scope user obsidian-rest -- npx -y mcp-obsidian "$VAULT_DIR"
  echo "MCP 서버 등록: obsidian-rest"
fi
```

#### 6. .flowsetrc에 vault 설정 기록

```bash
# .flowsetrc 업데이트
if [[ "$vault_api_ok" == true ]]; then
  # VAULT_ENABLED=true (기본값이므로 변경 불필요)
  # VAULT_API_KEY 설정
  sed -i "s|^VAULT_API_KEY=.*|VAULT_API_KEY=\"$VAULT_API_KEY\"|" .flowsetrc
  sed -i "s|^VAULT_PROJECT_NAME=.*|VAULT_PROJECT_NAME=\"$PROJECT_NAME\"|" .flowsetrc

  # vault에 프로젝트 폴더 초기화
  curl -s -k --max-time 3 \
    "https://localhost:27124/vault/${PROJECT_NAME}/state.md" \
    -H "Authorization: Bearer $VAULT_API_KEY" \
    -X PUT -H "Content-Type: text/markdown" \
    -d "# ${PROJECT_NAME} State
- Status: initialized
- Updated: $(date '+%Y-%m-%d %H:%M:%S')" > /dev/null 2>&1

  echo "vault 연동 완료: ${PROJECT_NAME}/"
else
  echo "vault 미연결 — 파일 기반 RAG로 진행"
fi
```

#### 셋업 완료 후 요약

```
Obsidian Vault 상태:
  Obsidian:           {설치됨/미설치}
  Local REST API:     {연결됨/미연결}
  Smart Connections:  {설치됨/미설치}
  MCP obsidian-rest:  {등록됨/미등록}
  Vault 경로:         ~/.claude/knowledge/
  프로젝트 폴더:      ~/.claude/knowledge/{PROJECT_NAME}/
```

### Step 4: Git Hooks 설치
```bash
# commit-msg hook (커밋 메시지 형식 강제)
cp .flowset/hooks/commit-msg .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg

# pre-push hook (main 직접 push 방지, 초기셋업/PRD/fix_plan 예외)
cp .flowset/hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

### Step 4.5: GitHub 계정 유형 안내

레포 생성 전, 사용자에게 계정 유형을 안내합니다:

```
📋 GitHub 계정 유형 선택

FlowSet은 PR 기반 자동 머지를 사용합니다.
계정 유형에 따라 머지 방식이 달라집니다:

🏢 조직(Organization) 계정 — 권장
  - Merge Queue 사용 가능 (자동 rebase + CI + 머지)
  - PR 충돌 자동 해소, 병렬 실행 시 안정적
  - 조직이 없으면: https://github.com/organizations/plan 에서 무료 생성

👤 개인(Personal) 계정
  - Merge Queue 미지원
  - strict: false로 설정 (CI 통과 시 즉시 머지)
  - 같은 파일을 수정하는 WI가 충돌할 수 있음 (batch 설계로 최소화)

어떤 계정을 사용하시겠습니까?
  1) 조직 계정 (권장)
  2) 개인 계정
```

사용자 선택에 따라:
- **조직**: `gh repo create {org}/{project-name}` + (ruleset은 `/wi:start`에서 설정)
- **개인**: `gh repo create {user}/{project-name}` + (ruleset은 `/wi:start`에서 설정)

**사용자 선택을 `.flowsetrc`에 기록:**
```bash
# .flowsetrc에 계정 유형 저장 (wi:start에서 ruleset 설정 시 참조)
GITHUB_ACCOUNT_TYPE="org"  # 또는 "personal"
GITHUB_ORG="{org}"         # 조직명 또는 사용자명
```

### Step 5: GitHub 레포 생성 & 설정
```bash
# 레포 생성
gh repo create {org}/{project-name} --private --source=. --remote=origin
# 또는 --public (--private 플래그 여부에 따라)

# 초기 커밋 & 푸시 (ruleset 없이 — 자유롭게 push 가능)
git add -A
git commit -m "WI-chore 프로젝트 초기 환경 셋업"
git push -u origin main

# 머지 시 브랜치 자동 삭제 활성화
gh api -X PATCH "repos/{org}/{project-name}" -f delete_branch_on_merge=true
gh api -X PATCH "repos/{org}/{project-name}" -f allow_auto_merge=true

# ⚠️ ruleset/branch protection은 여기서 설정하지 않음
# /wi:prd, /wi:env 단계에서 main에 직접 push가 필요하므로
# /wi:start 실행 시 ruleset이 자동 적용됩니다
```

### Step 6: 완료 안내
셋업 완료 후 아래 안내 출력:

```
✅ 프로젝트 환경 셋업 완료

구조:
  .github/          → CI/CD + PR 템플릿
  .claude/rules/    → 프로젝트 규칙 (글로벌 규칙 상속)
  .claude/agents/   → Agent Teams 팀 역할 정의 (v3.0)
  .flowset/           → FlowSet 설정 + Git Hooks
  .flowset/contracts/ → 팀 간 계약 (API 표준, 데이터 흐름) (v3.0)
  docs/             → 문서 계층구조 (L0~L4)
  flowset.sh          → FlowSet 실행 스크립트
  .gitattributes    → UTF-8 + LF 강제
  .editorconfig     → 에디터 설정
  CLAUDE.md         → 프로젝트 정보

🔒 규칙 강제:
  Git Hook (commit-msg) → WI-NNN-[type] 형식 로컬 검증
  Git Hook (pre-push)   → main 직접 push 차단
  CI (commit-check)     → WI-NNN-[type] 형식 원격 검증
  CI (ci.yml)           → lint + build + test
  flowset.sh              → 매 반복 후 규칙 준수 검증

🔗 GitHub: https://github.com/{org}/{project-name}

📓 Vault: {연결됨 — ~/.claude/knowledge/{project-name}/ | 미연결 — 파일 기반 RAG}

📋 다음 단계: /wi:prd → /wi:env → /wi:start
```

## Boundaries

**Will:**
- 프로젝트 타입에 맞는 CI/CD 워크플로우 생성
- GitHub 레포 생성 및 브랜치 보호 설정
- FlowSet 전체 환경 구성
- 문서 계층구조 디렉토리 생성

**Will Not:**
- 실제 비즈니스 코드 작성 (그건 FlowSet이 함)
- PRD 생성 (별도로 `/wi:prd`를 사용)
- MCP 서버 설치 (그건 /wi:start가 함)
