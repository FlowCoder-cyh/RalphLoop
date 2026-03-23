# Claude Code 공식 문서 참조 규칙

Claude Code 공식 기능을 활용하거나 hook/settings/skill/agent 관련 작업 시,
반드시 `.claude/docs/claude-code-official/` 디렉토리의 문서를 먼저 확인할 것.

## 참조 시점
- Hook 설정/수정 시 → 01-hooks-reference.md, 02-hooks-guide.md
- settings.json 수정 시 → 03-settings.md
- CLAUDE.md/rules 수정 시 → 04-memory.md
- 스킬 생성/수정 시 → 05-skills.md
- 팀/병렬 작업 설계 시 → 06-agent-teams.md
- 서브에이전트 설계 시 → 07-sub-agents.md
- 인덱스/우선순위 → 00-index.md

## 핵심 원칙
- 공식 스펙을 확인하지 않고 추측으로 구현하지 않는다
- 로컬 백업에 없는 문서는 `code.claude.com/docs/en/{page}.md`에서 WebFetch로 확인
- 새로운 공식 기능 발견 시 00-index.md에 추가
