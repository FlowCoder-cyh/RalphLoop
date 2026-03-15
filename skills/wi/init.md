---
name: init
description: "프로젝트 개발 환경 전체 셋업 (Git, CI/CD, Ralph Loop, 문서 계층구조)"
category: workflow
complexity: advanced
mcp-servers: []
personas: [devops-engineer, architect]
---

# /wi:init - Project Environment Setup

> 새 프로젝트에 Git, GitHub CI/CD, PR 규칙, Ralph Loop, 문서 계층구조를 한번에 셋업합니다.

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
아래 구조를 현재 디렉토리에 생성:
```
.github/
  workflows/
    ci.yml              # lint → build → test (프로젝트 타입에 맞게)
    commit-check.yml    # WI-NNN-[type] 커밋 메시지 검증
  PULL_REQUEST_TEMPLATE.md
.claude/
  rules/
    project.md          # 프로젝트 규칙 (글로벌 규칙 상속)
.ralph/
  PROMPT.md             # Ralph Loop 반복 프롬프트 (절차만, 규칙은 rules/ 참조)
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
ralph.sh                # Ralph Loop 스크립트
.ralphrc                # Ralph 설정
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

#### ralph.sh, PROMPT.md, hooks, workflows 등 (템플릿에서 복사)
**직접 생성하지 않음.** `~/.claude/templates/ralph/`에서 복사합니다.

```bash
# 템플릿 디렉토리 확인
TEMPLATE_DIR="$HOME/.claude/templates/ralph"
if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "ERROR: 템플릿이 설치되지 않았습니다."
  echo "  settings 저장소에서 설치하세요:"
  echo "  git clone https://github.com/FlowCoder-cyh/RalphLoop.git /tmp/ralph-templates"
  echo "  cp -r /tmp/ralph-templates/templates/ ~/.claude/templates/ralph/"
  exit 1
fi

# 템플릿 복사 (기존 파일 덮어쓰기)
cp "$TEMPLATE_DIR/ralph.sh" ./ralph.sh
cp "$TEMPLATE_DIR/.gitignore" ./.gitignore
cp "$TEMPLATE_DIR/.gitattributes" ./.gitattributes
cp "$TEMPLATE_DIR/.editorconfig" ./.editorconfig
cp "$TEMPLATE_DIR/CLAUDE.md" ./CLAUDE.md
cp -r "$TEMPLATE_DIR/.ralph/" ./.ralph/
cp -r "$TEMPLATE_DIR/.github/" ./.github/
chmod +x ralph.sh .ralph/scripts/*.sh 2>/dev/null || true
```

**복사 후 프로젝트별 커스터마이징만 수행:**

#### .ralphrc
`PROJECT_NAME`, `PROJECT_TYPE` 필드를 인자 값으로 채움.

#### CLAUDE.md
`{PROJECT_NAME}`, `{PROJECT_TYPE}`, `{PROJECT_DESCRIPTION}` 플레이스홀더를 실제 값으로 치환.

#### .claude/rules/project.md
`{PROJECT_NAME}`, `{PROJECT_TYPE}` 플레이스홀더를 실제 값으로 치환.

### Step 4: Git Hooks 설치
```bash
# commit-msg hook (커밋 메시지 형식 강제)
cp .ralph/hooks/commit-msg .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg

# pre-push hook (main 직접 push 방지, 초기셋업/PRD/fix_plan 예외)
cp .ralph/hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

### Step 4.5: GitHub 계정 유형 안내

레포 생성 전, 사용자에게 계정 유형을 안내합니다:

```
📋 GitHub 계정 유형 선택

Ralph Loop은 PR 기반 자동 머지를 사용합니다.
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

**사용자 선택을 `.ralphrc`에 기록:**
```bash
# .ralphrc에 계정 유형 저장 (wi:start에서 ruleset 설정 시 참조)
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

📁 구조:
  .github/        → CI/CD + PR 템플릿
  .claude/rules/  → 프로젝트 규칙 (글로벌 규칙 상속)
  .ralph/         → Ralph Loop 설정 + Git Hooks
  docs/           → 문서 계층구조 (L0~L4)
  ralph.sh        → Ralph Loop 실행 스크립트
  .gitattributes  → UTF-8 + LF 강제
  .editorconfig   → 에디터 설정
  CLAUDE.md       → 프로젝트 정보

🔒 규칙 강제:
  Git Hook (commit-msg) → WI-NNN-[type] 형식 로컬 검증
  Git Hook (pre-push)   → main 직접 push 차단
  CI (commit-check)     → WI-NNN-[type] 형식 원격 검증
  CI (ci.yml)           → lint + build + test
  ralph.sh              → 매 반복 후 규칙 준수 검증

🔗 GitHub: https://github.com/{org}/{project-name}

📋 다음 단계: /wi:prd → /wi:env → /wi:start
```

## Boundaries

**Will:**
- 프로젝트 타입에 맞는 CI/CD 워크플로우 생성
- GitHub 레포 생성 및 브랜치 보호 설정
- Ralph Loop 전체 환경 구성
- 문서 계층구조 디렉토리 생성

**Will Not:**
- 실제 비즈니스 코드 작성 (그건 Ralph Loop이 함)
- PRD 생성 (별도로 `/wi:prd`를 사용)
- MCP 서버 설치 (그건 /wi:start가 함)
