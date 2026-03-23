---
name: Ralph Loop 현재 상태 (2026-03-23)
description: settings/wi-test 프로젝트 현재 상태와 다음 작업
type: project
---

# 현재 상태 (2026-03-23)

## Obsidian + Smart Connections 통합 완료
- vault: ~/.claude/knowledge/
- Smart Connections: 벡터 임베딩 동작 확인
- Local REST API: 읽기/쓰기/검색 동작 확인
- MCP 서버: obsidian-rest Connected
- 마이그레이션: global(1) + settings(14) + wi-test(21) = 36파일

## settings 저장소 (FlowCoder-cyh/RalphLoop)
- PR #3: v2.2.0 (14커밋) — 코워크 이전 설계
- v3.0 설계 확정: Obsidian+벡터 + 회사 부서 구조 + 충돌 방지 5원칙
- v2.2.0은 코워크 기반 → v3.0에서 Obsidian 기반으로 전환

## wi-test 코워크 실전 테스트 — 중단
- PR #185~229 (코워크 시스템 + 외부 API 연동)
- 중단 사유: 메모리 불안정 → 품질 감시 중심 설계 → Obsidian으로 근본 해결
- 코워크 자체는 유지하되, DocOps/Guardian/Verifier 의존도 대폭 감소

## 다음 작업
1. /clear → 새 세션에서 MCP obsidian-rest 동작 확인
2. Obsidian vault 기반 knowledge 시스템으로 hook/agent 연동 테스트
3. v3.0 구현 시작 (회사 부서 구조 + Obsidian 통합)
