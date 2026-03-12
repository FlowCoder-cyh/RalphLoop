# Ralph Loop - Iteration Prompt

당신은 자율 개발 에이전트입니다. 매 반복마다 이 프롬프트를 받고, fix_plan.md의 다음 미완료 작업을 수행합니다.

**규칙은 `.claude/rules/wi-*.md`에 정의되어 있으며 항상 적용됩니다.**
**이 파일은 절차(procedure)만 정의합니다.**

## 핵심 규칙: 1회 호출 = 1개 WI만 처리

**반드시 1개 WI만 완료하고 즉시 종료하세요.**
- 2개 이상의 WI를 처리하지 마세요
- 다음 WI는 외부 bash 루프가 새로운 호출로 처리합니다
- 이 규칙을 위반하면 진행률 추적, 세션 관리, 컨텍스트 모니터링이 모두 작동하지 않습니다
- **TASKS_COMPLETED_THIS_LOOP는 항상 1이어야 합니다**

## 실행 절차

### 1. 상태 파악
- `.ralph/fix_plan.md` 읽기 → 첫 번째 `- [ ]` 항목 선택
- `.ralph/AGENT.md` 읽기 → 빌드/테스트 명령 확인
- `.ralph/guardrails.md` 읽기 → 프로젝트별 금지사항 확인

### 2. 브랜치 생성
```bash
git checkout main
git pull origin main
# 브랜치 네이밍: {category}/WI-{NNN}-{type}-{작업명-kebab}
# NNN = fix_plan.md에서 해당 WI의 3자리 순번
# feat → feature/, fix → fix/, chore → chore/, docs → docs/, refactor → refactor/
# kebab 변환: 한글→영문 요약, 공백→하이픈, 소문자, ASCII만
# 예: "사용자 인증 추가" → "user-auth", WI 번호 001
git checkout -b feature/WI-001-feat-{작업명-kebab}
```

### 3. 구현
- 선택한 WI 항목을 완전히 구현
- 구현 전 반드시 기존 코드를 읽고 파악할 것
- .gitignore에 포함된 파일은 절대 커밋하지 않음

### 4. 검증
```bash
# AGENT.md에 정의된 명령 순서대로 실행
# lint → build → test
```
- 실패 시 에러 유형에 따라 전략 분기:
  - **명확한 에러** (빌드/타입/린트 — 에러 메시지로 원인 특정 가능):
    → 근본 원인 분석 → 수정 → 재검증 (최대 2회)
  - **모호한 에러** (런타임/통합 테스트 — 원인 특정 어려움):
    → guardrails.md에 에러 패턴·증상 기록 → 다음 WI로 이동
- 근본 분석 2회 실패 시: guardrails.md에 시도한 접근과 실패 원인 상세 기록 후 다음 WI로 이동

### 5. 커밋 & PR & 머지
```bash
# 커밋 (git add -A 대신 변경 파일만 명시적으로 추가)
git add {변경된 파일들}
git commit -m "WI-{NNN}-{type} {한글 작업명}"  # 반드시 한글 포함 (NNN은 fix_plan 순번)
git push origin {branch-name}

# PR 생성
gh pr create --title "WI-{NNN}-{type} {한글 작업명}" --body "## 작업 내용
- {구현 내용 요약}

## 체크리스트
- [ ] CI 통과"

# auto-merge 활성화 (CI 통과 시 자동 머지)
gh pr merge --auto --squash

# CI 상태 폴링 (최대 5분)
for i in $(seq 1 10); do
  sleep 30
  status=$(gh pr checks --json state --jq '.[].state' 2>/dev/null | sort -u)
  if echo "$status" | grep -q "FAILURE"; then
    # CI 실패 → 로그 확인 후 수정 시도
    echo "CI FAILED - 수정 시도"
    # 실패 로그를 읽고 수정 후 push (최대 2회 재시도)
    # 재시도 실패 시 guardrails.md에 기록, PR 닫기, 다음 WI로 이동
    pr_url=$(gh pr view --json url --jq '.url' 2>/dev/null || echo "")
    if [[ -n "$pr_url" ]]; then
      gh pr close --comment "CI 실패로 인한 자동 닫기"
    fi
    git checkout main && git pull origin main
    break
  fi
  if echo "$status" | grep -q "SUCCESS\|COMPLETED"; then
    echo "CI PASSED"
    break
  fi
done

# 머지 완료 확인 후 main으로 복귀
git checkout main
git pull origin main
```

**CI 실패 시 대응 절차:**
1. `gh run view --log-failed`로 실패 로그 확인
2. 에러 유형 판단:
   - **명확한 에러** (빌드/타입/린트): 근본 원인 분석 → 수정 → push (최대 2회 재시도)
   - **모호한 에러** (런타임/통합): guardrails.md에 기록 → PR 닫기 → 다음 WI
3. 2회 재시도 실패 시: guardrails.md에 시도한 접근과 실패 원인 상세 기록, PR 닫기, 다음 WI로 이동

**레이스 컨디션 방지:**
- 다음 WI 브랜치 생성 전 반드시 `git pull origin main`으로 최신 상태 동기화
- 이전 PR이 아직 머지 대기 중이면 머지 완료까지 대기

### 6. fix_plan.md 업데이트
- 완료한 항목: `- [ ]` → `- [x]`
- 커밋: `git add .ralph/fix_plan.md && git commit -m "WI-chore fix_plan 업데이트" && git push origin main`
  - 주의: fix_plan 업데이트 등 시스템 커밋은 번호 없이 `WI-chore` 사용
  - 주의: fix_plan 업데이트는 main에 직접 push 허용 (pre-push hook이 WI-chore 허용)

### 7. 상태 출력 후 즉시 종료
```
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE
TASKS_COMPLETED_THIS_LOOP: 1
FILES_MODIFIED: {수}
TESTS_STATUS: PASSING | FAILING | NOT_RUN
EXIT_SIGNAL: false | true
SUMMARY: {완료한 WI 한 줄 요약}
---END_RALPH_STATUS---
```

**이 블록을 출력한 후 반드시 즉시 종료하세요. 다음 WI로 넘어가지 마세요.**
**TASKS_COMPLETED_THIS_LOOP는 항상 1입니다. 0이면 구현 실패, 2 이상이면 규칙 위반.**
