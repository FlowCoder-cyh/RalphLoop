# Data Flow Contract

데이터의 흐름과 SSOT(Single Source of Truth) 엔드포인트 합의.
이 파일은 `/wi:start`에서 프로젝트 구조에 맞게 자동 채워집니다.

## SSOT 원칙
- 각 데이터 엔티티는 하나의 API 엔드포인트에서만 생성/수정
- 다른 팀은 해당 엔드포인트를 통해서만 데이터 접근
- 직접 DB 쿼리로 다른 팀 데이터에 접근 금지

## 데이터 흐름
```
사용자 입력 → 프론트엔드 → API 요청 → 백엔드 → DB
                                              ↓
프론트엔드 ← API 응답 ← 백엔드 ← DB 결과
```

## 엔티티별 SSOT
<!-- /wi:start에서 prisma/schema.prisma 분석 후 자동 채워짐 -->
| 엔티티 | SSOT 엔드포인트 | 소유 팀 |
|--------|----------------|---------|
| (예시) User | /api/users | backend |
| (예시) Auth | /api/auth | backend |

## 팀 간 데이터 공유
- 프론트엔드는 API 응답의 `data` 필드만 사용
- 백엔드는 prisma 모델을 통해서만 DB 접근
- QA는 seed 스크립트로 테스트 데이터 생성

## 변경 규칙
- 이 파일 수정 시 관련 팀 전원 확인 필수
- SSOT 엔드포인트 변경은 사용하는 모든 팀에 영향
