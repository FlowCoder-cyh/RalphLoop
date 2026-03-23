---
name: note
description: "대화 중 결정사항/맥락을 디스크에 즉시 기록 (오토컴팩트 대비)"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /wi:note - Decision Recorder

> 대화 중 중요한 결정, 맥락, 제약조건을 디스크에 즉시 기록합니다.
> 오토컴팩트가 발생해도 이 파일의 내용은 보존됩니다.

## Triggers
- "이거 기록해", "메모해둬", "잊지마"
- 중요한 설계 결정이 내려졌을 때 자동 판단하여 기록 제안
- `/wi:note 내용`

## Usage
```
/wi:note 결정사항이나 맥락을 자유롭게 기술
/wi:note --list          (기록된 내용 조회)
/wi:note --clear         (전체 삭제, 확인 필요)
```

## Behavioral Flow

### 기록
`.flowset/notes.md`에 append:

```markdown
### [YYYY-MM-DD HH:MM] {요약}
- **결정**: {무엇을 결정했는가}
- **근거**: {왜 이렇게 결정했는가}
- **기각**: {다른 후보와 기각 사유} (해당 시)
- **맥락**: {사용자 원문 또는 배경}
```

### 자동 기록 트리거
아래 상황에서 사용자에게 기록을 제안:
- 기술 스택 결정
- 아키텍처 방향 결정
- 기존 방안 폐기 후 새 방안 채택
- 사용자가 명시적 제약조건 언급

제안 형식:
```
이 결정을 기록해둘까요? (오토컴팩트 대비)
  결정: {요약}
  근거: {이유}
```

### 조회
`/wi:note --list` → `.flowset/notes.md` 전체 출력

### /wi:status 연동
`/wi:status`에서 notes.md 내용도 함께 표시

## 파일 위치 (우선순위)

1. **프로젝트 내** (우선): `.flowset/notes.md` — `.flowset/` 디렉토리가 있으면 여기에 기록
2. **프로젝트 외** (fallback): `~/.claude/projects/{project-encoded}/notes.md` — git 미연결이거나 .flowset/가 없을 때

조회 시 두 곳 모두 확인하되, 프로젝트 로컬 파일을 먼저 표시합니다.
**git이 없어도 동작합니다.**

## Boundaries

**Will:**
- 결정사항과 맥락을 디스크에 즉시 저장
- 자동 기록 제안

**Will Not:**
- 대화 전체를 통째로 저장 (요약만)
- 기존 notes 임의 수정 (append only)
