---
name: status
description: "프로젝트 상태 확인 - 파일 기반 상태 조회 (mem:load/resume 대체)"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /wi:status - Project Status

> 프로젝트의 현재 상태를 파일에서 읽어 한눈에 보여줍니다.
> mem:load, mem:resume을 대체합니다.

## Triggers
- 세션 시작 시 현재 상태 확인
- "어디까지 했지?", "현재 상태", "이어서 하자"
- 컨텍스트 압축(compaction) 후 복원

## Usage
```
/wi:status
```

## Behavioral Flow

### 1. 프로젝트 상태 파일 수집

아래 파일들을 순서대로 읽는다:

```
읽기 대상:
1. CLAUDE.md              → 프로젝트 정보 (이름, 타입, 규칙)
2. .ralph/fix_plan.md     → WI 진행 상태 (완료/미완료 수)
3. .ralph/guardrails.md   → 누적된 실패 방지 규칙
4. .ralph/notes.md        → 수동 메모 (있으면)
5. .ralph/prd-state.json  → PRD 작성 진행 상태 (있으면)
6. .ralph/logs/ralph.log  → 마지막 10줄 (Ralph Loop 실행 이력)
7. PRD.md                 → PRD 확정 여부
8. git log --oneline -10  → 최근 커밋 이력
9. gh pr list             → 열린 PR 목록
```

### 2. 현재 단계 판별

파일 존재 여부로 현재 단계를 자동 판별:

```
CLAUDE.md 없음          → "환경 미셋업. /wi:init 실행 필요"
CLAUDE.md 있고 PRD 없음 → "환경 셋업 완료. /wi:prd 로 PRD 생성 필요"
prd-state.json 있음     → "PRD 작성 중 (진행률 표시)"
PRD.md 있고 fix_plan 비어있음 → "PRD 확정됨. /wi:start 실행 필요"
fix_plan에 [ ] 있음     → "Ralph Loop 진행 중 (N/M 완료)"
fix_plan 전부 [x]       → "전체 완료"
```

### 3. 출력 형식

```
📍 프로젝트 상태: {프로젝트명}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 단계: {현재 단계}
   환경 셋업 [✅] → PRD 작성 [✅] → WI 생성 [✅] → Ralph Loop [🔄] → 완료 [ ]

📊 진행률: {완료}/{전체} WI ({퍼센트}%)
   - feat: {N}개 완료 / {M}개
   - test: {N}개 완료 / {M}개
   - chore: {N}개 완료 / {M}개

📝 최근 완료:
   - [x] WI-001-feat 사용자 인증 API
   - [x] WI-002-feat 회원가입 폼 UI

⏭️ 다음 작업:
   - [ ] WI-003-feat 로그인 토큰 갱신

🔴 가드레일 ({N}개):
   - {최근 추가된 규칙}

🔗 열린 PR: {N}개
   - #12 WI-001-feat 사용자 인증 API (CI 통과)

💡 다음 단계: {권장 액션}
```

### 4. 컨텍스트 압축 후 자동 복원

컨텍스트 압축(compaction)이 감지되면:
1. 위 상태 파일을 전부 읽기
2. 이전 세션의 JSONL 로드 **대신** 파일 상태만으로 복원
3. "파일 기반 상태를 로드했습니다. 이전 작업을 이어갑니다." 출력

## Boundaries

**Will:**
- 파일에서 프로젝트 상태 읽기
- 현재 단계 자동 판별
- 다음 액션 안내

**Will Not:**
- 파일 수정 (읽기 전용)
- Ralph Loop 실행 (그건 /wi:start)
- 상태 추측 (파일에 없는 정보는 "알 수 없음" 표시)
