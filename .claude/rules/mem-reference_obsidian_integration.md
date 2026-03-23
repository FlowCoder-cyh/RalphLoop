---
name: Obsidian 통합 레퍼런스
description: Obsidian vs Supabase vs 현재 비교, 플러그인 목록, MCP 연동 방법, ASMR 참고
type: reference
---

# Obsidian 통합 레퍼런스

## 비교 결과 (현재 vs Supabase vs Obsidian)

Obsidian이 14개 차원 중 12개에서 우위:
- 현재 시스템 장점(파일 기반, git, 로컬, 교차 추론) 유지
- 7개 약점(동기화, 유지보수, 커버리지, 토큰효율, 시간인식, 이력, 확장성) 해결
- Supabase는 무제한 확장성에서만 우위

## 설치된 구성

| 구성요소 | 버전 | 역할 |
|---------|------|------|
| Obsidian | 1.12.4 | vault 관리 + 사용자 편집 |
| Smart Connections | 4.1.8 (Smart Env 2.2.8) | 로컬 벡터 임베딩 + 시맨틱 검색 |
| Local REST API | 3.5.0 | HTTP API (CRUD + 검색) |
| MCP obsidian-rest | mcp-obsidian | Claude Code ↔ vault 연동 |

## vault 구조
```
~/.claude/knowledge/ (Obsidian vault)
├── global/          전역 메모리
├── settings/        RalphLoop 프로젝트 (14파일)
├── wi-test/         ralph_FlowHR 프로젝트 (21파일)
└── {새 프로젝트}/    자동 추가
```

## API 접근
```bash
# 읽기
curl -s "https://localhost:27124/vault/{path}" -k -H "Authorization: Bearer {API_KEY}"

# 쓰기
curl -s "https://localhost:27124/vault/{path}" -k -H "Authorization: Bearer {API_KEY}" -X PUT -H "Content-Type: text/markdown" -d "{content}"

# 검색
curl -s "https://localhost:27124/search/simple/?query={query}" -k -H "Authorization: Bearer {API_KEY}" -X POST
```
API Key: 20fb6f5e46cbfc7f7514fd5015997896647179dc73eb82b41282f1a9ad8ac6d2

## MCP 서버
```bash
claude mcp add --scope user obsidian-rest -- npx -y mcp-obsidian "C:/Users/User/.claude/knowledge"
```

## 관련 GitHub 저장소
- [obsidian-claude-code-mcp](https://github.com/iansinnott/obsidian-claude-code-mcp) — Obsidian 내 MCP 서버
- [Smart Connections](https://github.com/brianpetro/obsidian-smart-connections) — 벡터 검색 플러그인
- [Smart Connections MCP](https://github.com/msdanyg/smart-connections-mcp) — SC 임베딩을 MCP로 노출
- [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) — REST API 플러그인
- [obsidian-cli](https://github.com/davidpp/obsidian-cli) — AI 에이전트용 CLI

## ASMR (Supermemory) — 향후 참고
- 벡터 DB 없이 관찰자+검색 에이전트로 99% 기억 정확도
- 오픈소스 공개 예정 (2026-03 기준 11일 후)
- 공개되면 Obsidian 시스템과 비교 검증 필요
