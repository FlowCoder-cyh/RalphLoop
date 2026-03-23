---
name: RalphLoop v3.0 설계 — Obsidian + 회사 부서 구조
description: Obsidian+벡터 통합, 회사형 에이전트 팀, 충돌 방지 5원칙, 상세 정책 13개 전부 포함
type: project
---

# RalphLoop v3.0 설계

## 핵심 전환
- v2.x: 품질 감시 중심 (메모리 불안정 → Guardian/Verifier/Judge/DocOps 6명 고정)
- v3.0: 회사 부서 구조 (메모리 안정 → 기획/프론트/백엔드/QA/DevOps 유동적)

### 전환 근거
현재 팀 구성이 품질에 치우친 이유는 메모리 불안정 때문:
```
v2.x: 6명 중 1명만 생산(Implementer), 5명이 감시/검증/메모리
  ├── Guardian      — 리드가 요구사항 빼먹는지 감시
  ├── Verifier      — 구현이 껍데기인지 검증
  ├── Judge         — Verifier를 재검증
  ├── DocOps        — 메모리 수동 동기화
  ├── Tester        — 결과물 테스트
  └── Implementer   — 유일한 생산자

v3.0: 전원이 생산자, 품질은 메모리 + hook이 자동 보장
  ├── 기획팀        — PRD, 와이어프레임, 요구사항
  ├── 프론트팀      — UI/UX 구현
  ├── 백엔드팀      — API, DB, 비즈니스 로직
  ├── QA팀          — 테스트 (E2E, 통합, 단위)
  ├── DevOps팀      — CI/CD, 배포, 인프라
  └── 디자인팀      — 컴포넌트, 스타일 시스템
```

메모리가 안정되면 모든 에이전트가 requirements를 정확히 기억하고 참조 → 감시 전담이 아니라 각자 역할 안에서 자체 검증.

## 1. Obsidian + Smart Connections + MCP

### 도입 이유
현재 파일 기반 knowledge/의 7개 약점 해결:
- 동기화 신선도 → Smart Connections 자동 인덱싱
- 유지보수 비용 → 플러그인이 처리 (DocOps 불필요)
- 커버리지 → vault 전체 자동 임베딩
- 토큰 효율 → 시맨틱 검색으로 관련만 로드
- 시간 인식 → 파일 mtime + 메타데이터
- 과거 이력 → git 히스토리 + 임베딩
- 확장성 → 로컬 디스크 한도 (실용적 충분)

### 통합 구조
```
Claude Code ←→ MCP ←→ Obsidian vault
                      ├── Smart Connections (벡터 검색)
                      ├── Local REST API (CRUD)
                      └── obsidian-claude-code-mcp (네이티브)
```

### 기존 시스템과의 호환
- knowledge/ 파일 → Obsidian vault로 열기만 하면 됨
- hook → curl로 REST API 호출 (또는 기존 cat 유지)
- 사용자 → Obsidian 앱에서 직접 보고 편집

### DocOps가 필요 없어지는 이유
DocOps의 역할:
1. knowledge/ 파일 업데이트 → Smart Connections 자동 인덱싱으로 대체
2. state.md 갱신 → hook이 자동 갱신 or 에이전트 자체가 MCP로 직접 쓰기
3. 세션 JSONL 읽고 맥락 추출 → Smart Connections 시맨틱 검색으로 대체
4. PR 상태 추적 → 각 팀이 자체 관리

DocOps가 빠지면 팀 구성이 작업에 맞게 유연해짐:
| 작업 | 필요한 팀원만 |
|------|------------|
| 단순 버그 수정 | Implementer + QA |
| 기능 구현 | 기획 + 프론트/백엔드 + QA |
| E2E 포함 | + Tester |
| 복잡한 설계 | + 디자인 |
| .claude/ 설정만 | DevOps만 |

## 2. 회사 부서 구조

### 팀 구성 (유동적)
| 팀 | 소유 디렉토리 | 역할 |
|---|------------|------|
| 기획팀 | docs/, wireframes/, requirements.md | PRD, 와이어프레임, 요구사항 |
| 프론트팀 | src/app/, src/components/ | UI/UX |
| 백엔드팀 | src/api/, src/lib/ | API, DB, 비즈니스 로직 |
| QA팀 | e2e/, tests/ | 테스트 |
| DevOps | .github/, .claude/ | CI/CD, 인프라, 배포 |
| 디자인팀 | src/styles/, src/design-system/ | 컴포넌트, 스타일 |

### 작업 규모별 팀 구성
- 단순 (버그, 설정): 2명
- 중간 (기능 추가): 3~4명
- 복잡 (시스템 변경): 5명+
- 리드가 작업 복잡도 판단 → 팀 규모 결정

## 3. 정책 1: 소유권 분리 (hook 강제)

```
프론트팀:   src/app/**  src/components/**
백엔드팀:   src/api/**  src/lib/**
QA팀:      e2e/**  tests/**
DevOps:    .github/**  .claude/**
기획팀:    docs/**  wireframes/**  requirements.md
```
각 팀은 자기 디렉토리만 수정 가능. 경계 넘으면 hook 차단.
PreToolUse hook에서 Write/Edit 대상 파일의 경로를 확인 → 팀 소유 디렉토리가 아니면 exit 2.

## 4. 정책 2: 계약 기반 소통

```
프론트 ←→ 백엔드:
  contracts/api-standard.md     → 응답 형식 합의
  contracts/data-flow.md        → SSOT 엔드포인트 합의

프론트 ←→ 기획:
  wireframes/{page}.html        → UI 구조 합의
  requirements.md               → 기능 범위 합의

백엔드 ←→ DevOps:
  prisma/schema.prisma          → DB 스키마 합의
  .env.example                  → 환경변수 합의
```

계약 파일을 수정하면 관련 팀 전원에게 알림. 일방적 변경 불가.

## 5. 정책 3: 공유 기억 (Obsidian vault)

```
모든 팀이 같은 vault 접근:
├── state.md          → 현재 진행 상태 (모든 팀이 읽음)
├── decisions/        → 합의된 결정 (변경 시 전팀 동의)
├── issues/           → 알려진 이슈 (발견한 팀이 등록)
└── 각 팀별 노트/     → 팀 내부 메모 (다른 팀 참조 가능)

Smart Connections가 자동 임베딩 → 관련 정보 검색
MCP로 Claude Code에서 직접 읽기/쓰기/검색
사용자는 Obsidian 앱에서 직접 보고 편집
```

## 6. 정책 4: 자체 검증 + hook 게이트

```
각 팀 자체:
  ├── 단위 테스트 작성 (TDD) → 자체
  ├── lint/build 통과 → hook 자동
  ├── 계약 준수 확인 → hook 자동
  └── PR 생성 → CI 게이트

팀 간 검증:
  ├── API 계약 변경 → 관련 팀 리뷰 필수 (hook)
  └── 통합 테스트 → QA팀 담당
```

## 7. 정책 5: 팀 간 의존성 관리

```
프론트가 백엔드 API 필요 → 태스크 의존성 설정
  #12 프론트 UI (blocked by #11)
  #11 백엔드 API

Agent Teams shared task list에서 자동 관리:
  #11 완료 → #12 자동 unblock → 프론트팀 시작

교착 방지:
  A팀이 B팀 대기 + B팀이 A팀 대기 → 감지 → 리드에게 보고
  리드가 의존성 재설계 또는 인터페이스 mock으로 unblock
```

## 8. 정책 6: 에스컬레이션 경로

```
팀 내 해결 불가 → 리드에게 에스컬레이션
리드 판단 불가 → 사용자에게 에스컬레이션

명확한 기준:
  - 계약 변경이 필요한 경우 → 리드
  - 요구사항 해석이 다른 경우 → 사용자
  - 기술적 막힘 (2회 재시도 실패) → 리드 + 다른 팀 협력
  - 팀 간 충돌 (소유권 경계 분쟁) → 리드
  - 우선순위 충돌 (어떤 팀 먼저?) → 기획팀이 결정
```

## 9. 정책 7: 긴급 핫픽스 프로세스

```
프로덕션 장애 시:
  정상 프로세스 (5단계 워크플로우) 대신:
  1. DevOps가 장애 감지
  2. 리드가 "핫픽스 모드" 선언 → 소유권 제한 완화
  3. 해당 팀이 즉시 수정 + 최소 테스트
  4. 배포 후 정상 프로세스로 후속 PR

hook에서 "hotfix/" 브랜치는 소유권 체크 완화
핫픽스 후 반드시 정상 PR로 후속 정리 (기술 부채 방지)
```

## 10. 정책 8: 세션 간 연속성

```
Agent Teams는 세션 끝나면 팀 소멸.

연속성 보장:
  - Obsidian vault에 모든 맥락 자동 저장 (Smart Connections)
  - 다음 세션에서 같은 vault 접근 → 맥락 즉시 복원
  - 태스크 상태는 state.md에 기록
  - 진행 중이던 작업은 issues/에 "중단됨" 표시
  - 새 세션에서 MCP로 vault 검색 → 이전 맥락 자동 파악
  - 별도 온보딩 과정 불필요 — vault가 온보딩 자료
```

## 11. 정책 9: 비용/토큰 관리

```
팀 수가 늘면 토큰 소비 비례 증가.

관리:
  - 작업 규모에 맞는 팀만 spawn (고정 6명 → 유동적)
  - 단순 작업: 2명 (Implementer + QA)
  - 복잡 작업: 5명 (기획 + 프론트 + 백엔드 + QA + DevOps)
  - 리드가 작업 복잡도 판단 → 팀 규모 결정
  - trace.jsonl로 팀별 토큰 소비 추적
  - 세션 내 팀 유지 (매 작업마다 해체/재생성 하지 않음)
  - 5-6 tasks per teammate 권장 (공식 문서)
```

## 12. 정책 10: 기술 부채 관리

```
issues/tech-debt.md에 누적:
  - 각 팀이 발견한 부채 등록
  - 우선순위: 장애 위험 > 성능 > 코드 품질
  - 스프린트마다 기술 부채 해소 시간 확보
  - Obsidian에서 부채 ↔ 기능 연결 ([[위키링크]])
  - 부채가 일정 수준 넘으면 리드에게 자동 경고
```

## 13. 정책 11: 팀 간 리뷰

```
단일 팀 범위: 자체 CI로 충분
팀 간 영향: 리뷰 필수

자동 감지 (hook):
  - contracts/ 파일 변경 → 관련 팀 전원 리뷰
  - prisma/schema 변경 → 프론트+백엔드 리뷰
  - 공유 컴포넌트 변경 → 사용하는 팀 리뷰
  - requirements.md 변경 → 전팀 리뷰 (사용자 승인 필수)
```

## 14. 정책 12: 온보딩 (새 팀원 spawn)

```
새 에이전트 spawn 시:
  1. Obsidian vault에서 관련 knowledge 자동 로드 (MCP 시맨틱 검색)
  2. 자기 팀의 소유 디렉토리 코드 읽기
  3. contracts/ 읽기 (다른 팀과의 인터페이스)
  4. issues/ 읽기 (현재 알려진 문제)
  5. state.md 읽기 (전체 진행 상태)

별도 온보딩 과정 불필요 — vault가 온보딩 자료
새 프로젝트 추가 시 vault에 {프로젝트명}/ 폴더만 생성
```

## 15. 정책 13: 롤백/복구

```
배포 후 장애:
  1. DevOps가 이전 버전으로 롤백 (vercel rollback)
  2. 원인 팀이 수정
  3. regression 테스트 후 재배포

코드 롤백:
  git revert → PR → CI → merge queue
  롤백도 정상 프로세스를 따름 (핫픽스 모드 제외)

데이터 롤백:
  DB 마이그레이션 실패 시 → prisma migrate resolve
  데이터 유실 시 → Supabase 백업에서 복원
```

## 16. 충돌 시나리오별 방어

| 충돌 | 방어 | 매커니즘 |
|------|------|---------|
| 프론트+백엔드 같은 파일 수정 | 디렉토리 소유권 | hook 차단 |
| API 응답 형식 불일치 | api-standard.md 계약 | 양팀 참조 필수 |
| DB 스키마 변경 → 프론트 깨짐 | schema 변경 알림 | hook이 관련 팀에 통지 |
| 우선순위 충돌 (어떤 팀 먼저?) | state.md 우선순위 | 기획팀이 결정 |
| 머지 충돌 | 순차 merge queue | 자동 rebase |
| 요구사항 해석 차이 | requirements.md SSOT | Obsidian에서 전팀 접근 |
| 교착 (A→B 대기 + B→A 대기) | 의존성 감지 | 리드가 재설계 |

## 17. 전체 구조도

```
사용자: "~해줘"
  ↓
리드 (PM):
  ├── 요구사항 → requirements.md (Obsidian vault)
  ├── 복잡도 판단 → 팀 규모 결정
  ├── 태스크 분해 → 의존성 설정
  └── 팀 spawn
  ↓
┌─────────┬──────────┬─────────┬──────────┐
│ 기획팀   │ 프론트팀  │ 백엔드팀 │ QA팀     │
│ docs/   │ src/app/ │ src/api/│ e2e/     │
│ wire/   │ src/comp/│ src/lib/│ tests/   │
└────┬────┴────┬─────┴────┬────┴────┬─────┘
     │    contracts/로 소통    │         │
     └─────────┴──────────────┘         │
                    ↓                    │
              merge queue ← CI 게이트 ←──┘
                    ↓
              Obsidian vault 자동 업데이트
              (Smart Connections 인덱싱)
                    ↓
              사용자: Obsidian에서 확인
```

## 18. 충돌 방지 5원칙 (최종)

```
1. 소유권 분리    → "내 영역만 수정" (hook 강제)
2. 계약 기반 소통  → "인터페이스로 대화" (파일 기반)
3. 공유 기억      → "같은 정보를 봄" (Obsidian vault)
4. 의존성 관리    → "순서대로 작업" (태스크 blocking)
5. 에스컬레이션   → "막히면 올린다" (팀→리드→사용자)
```

## 19. 전제 조건
- Obsidian + Smart Connections + MCP 통합 완료 ✅
- ASMR 오픈소스 공개 시 비교 검토 (향후)

## 20. 참고 기술
- [obsidian-claude-code-mcp](https://github.com/iansinnott/obsidian-claude-code-mcp)
- [Smart Connections](https://smartconnections.app/smart-connections/)
- [Smart Connections MCP](https://github.com/msdanyg/smart-connections-mcp)
- [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api)
- [obsidian-cli](https://github.com/davidpp/obsidian-cli)
- ASMR (Supermemory — 오픈소스 공개 예정)
