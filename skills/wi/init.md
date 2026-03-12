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

#### ralph.sh (필수 기능 — 간소화 금지)
Ralph Loop의 핵심 스크립트. 아래 기능을 **모두** 포함해야 함:

1. **UTF-8 설정**: LANG, LC_ALL, PYTHONUTF8, PYTHONIOENCODING + Windows chcp 감지
2. **.ralphrc 로드**: 존재 시 source
3. **설정 변수**: MAX_ITERATIONS(기본 50), RATE_LIMIT_PER_HOUR(기본 80), COOLDOWN_SEC(기본 5), ERROR_COOLDOWN_SEC(기본 30), ALLOWED_TOOLS(기본 "Edit,Write,Read,Bash,Glob,Grep")
4. **preflight()**: claude CLI 존재, gh CLI 존재 + 인증(`gh auth status`), git 저장소, 필수 파일(PROMPT.md, fix_plan.md, AGENT.md, .ralphrc, guardrails.md), fix_plan에 미완료 WI 존재 확인
5. **count_tasks()**: 코드블록(`\`\`\``) 내부 체크박스 제외, awk로 unchecked/completed 카운트
6. **check_all_done()**: completed=0 && unchecked=0 → 빈 상태(완료 아님) 구분
7. **check_progress()**: git SHA + `git diff --quiet` 로 uncommitted 변경 감지, 연속 무진행 시 circuit breaker (NO_PROGRESS_LIMIT 기본 3)
8. **check_rate_limit()**: 시간 기반 rate limiting (경과 시간 계산)
9. **execute_claude()**: `claude -p "$prompt" --output-format json --append-system-prompt "$context" --allowedTools "$ALLOWED_TOOLS"`, EXIT_SIGNAL/에러 감지
10. **validate_post_iteration()**: 커밋 메시지 WI-NNN-[type] 형식 검증, .ralph/ 파일 삭제 감지, 위반 시 guardrails.md 기록
11. **main()**: preflight → while 루프(integrity→all_done→progress→rate_limit→execute→validate→cooldown)
12. **종료 시**: 미머지 PR 확인 (`gh pr list --state open`), 최종 통계 출력

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

### Step 5: GitHub 레포 생성 & 설정
```bash
# 레포 생성
gh repo create {org}/{project-name} --private --source=. --remote=origin
# 또는 --public (--private 플래그 여부에 따라)

# 초기 커밋 & 푸시
git add -A
git commit -m "WI-chore 프로젝트 초기 환경 셋업"
git push -u origin main

# 머지 시 브랜치 자동 삭제 활성화
gh api -X PATCH "repos/{org}/{project-name}" -f delete_branch_on_merge=true

# 브랜치 보호 규칙 (main) — 플랜별 자동 분기
#
# 1. Rulesets API 시도 (Pro/Team/Enterprise)
# 2. 실패 시 Branch Protection API fallback (Free public)
# 3. 둘 다 실패 시 로컬 hooks만으로 보호 (Free private)

# 먼저 Rulesets API 시도
ruleset_ok=false
gh api --method POST "repos/{org}/{project-name}/rulesets" --input - <<'RULES' 2>/dev/null && ruleset_ok=true
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
      "type": "pull_request",
      "parameters": {
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": false,
        "required_approving_review_count": 0,
        "required_review_thread_resolution": false
      }
    },
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
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
RULES

# Rulesets 실패 시 → Branch Protection API (Free public repos)
if [[ "$ruleset_ok" != "true" ]]; then
  echo "Rulesets API 미지원 — Branch Protection API로 대체합니다."
  gh api --method PUT "repos/{org}/{project-name}/branches/main/protection" \
    --input - <<'PROTECT' 2>/dev/null || {
    echo "Branch Protection API도 미지원 (Free private). 로컬 Git hooks로만 보호합니다."
  }
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["lint", "build", "test", "check-commits"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
PROTECT
fi
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

📋 다음 단계: /wi:prd 로 PRD 생성
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
