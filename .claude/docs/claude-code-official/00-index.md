# Claude Code 공식 문서 인덱스

총 67개 문서. 핵심 문서는 로컬 백업 완료, 나머지는 URL 참조.

## 로컬 백업 완료 (핵심 7개)
| 파일 | 공식 URL | 내용 |
|------|---------|------|
| 01-hooks-reference.md | code.claude.com/docs/en/hooks | Hook 이벤트 전체, JSON 스키마, exit code, stdin/stdout |
| 02-hooks-guide.md | code.claude.com/docs/en/hooks-guide | 실전 예제, 워크플로우 자동화 패턴 |
| 03-settings.md | code.claude.com/docs/en/settings | settings.json 구조, 전역/프로젝트 설정 |
| 04-memory.md | code.claude.com/docs/en/memory | CLAUDE.md, auto memory, .claude/rules/ |
| 05-skills.md | code.claude.com/docs/en/skills | 스킬 생성, frontmatter, context:fork |
| 06-agent-teams.md | code.claude.com/docs/en/agent-teams | 팀 구성, task list, messaging, hooks |
| 07-sub-agents.md | code.claude.com/docs/en/sub-agents | 서브에이전트, isolation, memory, hooks |

## URL 참조 (나머지 60개)
| 카테고리 | 문서 |
|---------|------|
| 코어 | overview, quickstart, how-claude-code-works, cli-reference, commands, tools-reference |
| 설정 | permissions, env-vars, model-config, keybindings, output-styles, statusline |
| 확장 | features-overview, plugins, plugins-reference, discover-plugins, plugin-marketplaces |
| CI/CD | github-actions, gitlab-ci-cd, code-review |
| 플랫폼 | vs-code, jetbrains, desktop, desktop-quickstart, chrome |
| 클라우드 | claude-code-on-the-web, amazon-bedrock, google-vertex-ai, microsoft-foundry |
| 운영 | costs, analytics, monitoring-usage, security, sandboxing, checkpointing |
| 네트워크 | authentication, network-config, llm-gateway, server-managed-settings |
| 기타 | channels, channels-reference, remote-control, scheduled-tasks, voice-dictation, fast-mode |
| 법률 | legal-and-compliance, data-usage, zero-data-retention |
| 참고 | best-practices, common-workflows, terminal-config, setup, troubleshooting, changelog |
| 팀 | third-party-integrations, slack, headless, devcontainer, interactive-mode, agent-teams |

## RalphLoop 적용 가능 기능 (우선순위)

### P0 — 즉시 적용 (v2.2.0 이후)
1. `type: "agent"` hook → verify-requirements.sh 대체
2. `type: "prompt"` hook → 경량 검증 (yes/no 판정)
3. `PostToolUse` Edit|Write → 파일 수정 후 실시간 검증
4. `PreToolUse` Bash → 위험 명령 사전 차단
5. `SessionStart` compact → 컨텍스트 압축 후 재주입

### P1 — 테스트 후 적용
6. Agent Teams → execute_parallel 대체 (실험 기능)
7. Subagent `isolation: worktree` → 병렬 워커 격리
8. Subagent `memory: project` → patterns.md/guardrails.md 대체
9. Skill `context: fork` → 검증 에이전트 격리 실행
10. `TaskCompleted` hook → WI 완료 전 검증 게이트

### P2 — 장기 로드맵
11. Agent SDK (Python/TypeScript) → ralph.sh bash 대체
12. Channels → 외부 웹훅 연동
13. Scheduled Tasks → 주기적 실행
14. Plugins → RalphLoop을 플러그인으로 배포
