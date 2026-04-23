# Smoke Tests — WI-001 (v4.0 PROJECT_CLASS 게이트웨이)

WI-001 변경이 기존 누적 smoke(180 assertion) + bats(16 @test) 전수를 깨뜨리지 않고,
`.flowsetrc` / `skills/wi/init.md` / `skills/wi/prd.md`에 신설된 PROJECT_CLASS 플로우와
`migrate_prd_state_v1_to_v2()` 함수의 계약(idempotent / atomic / rollback)을 실측 검증.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-23
**대응 브랜치**: `feature/WI-001-feat-project-class-gateway`

---

## 변경 범위

1. **`templates/.flowsetrc`**: `PROJECT_CLASS="code"` 필드 신설 (기본값 code — 하위 호환 보장)
2. **`skills/wi/init.md`**:
   - Step 1에 `--class` 플래그 + 대화형 질문 추가
   - Usage 라인에 `[--class code|content|hybrid]` 표기
   - Step 3 `.flowsetrc` 커스터마이징 블록에 `PROJECT_CLASS` 채움 로직 추가
   - Step 3.5 ownership.json 생성 헤더에 `case "$PROJECT_CLASS" in` 분기 추가 (content/hybrid는 WI-B1로 위임)
3. **`skills/wi/prd.md`**:
   - Step 0 최상단에 `migrate_prd_state_v1_to_v2()` 함수 배치 (설계 §8 :368)
   - idempotent(v2 skip) / atomic(tmp→mv) / rollback(.v1.bak 복원) 전부 구현
4. **`.github/workflows/flowset-ci.yml`**: smoke job에 `bash tests/run-smoke-WI-001.sh` 추가
5. **`tests/run-smoke-WI-001.sh`** 신규: 38 assertion

---

## 하위 호환 원칙 (설계 §8 :359)

- 기존 `.flowsetrc`에 `PROJECT_CLASS` 없음 → 로드 시 `${PROJECT_CLASS:-code}` 기본값 적용 → 기존 동작 완전 동일
- 기존 `prd-state.json`에 `schema_version` 없음 → migration이 v2로 승격, 기존 필드 전부 보존
- 기존 `.v1.bak` 존재 → migration은 영구 백업 유지 (수동 복구 경로)

---

## Smoke 1~6 시나리오 요약

`tests/run-smoke-WI-001.sh`에 전체 실행 스크립트.

| 블록 | 주제 | Assertion |
|------|------|-----------|
| WI-001-1 | `.flowsetrc` PROJECT_CLASS 필드 + 기본값 code + 3종 옵션 주석 | 3 |
| WI-001-2 | `init.md` 질문 단계 (플래그 문서화 / Usage / 대화형 프롬프트) | 3 |
| WI-001-3 | `init.md` Step 3.5 `case "$PROJECT_CLASS" in` 분기 3종 + 미지정 값 exit 1 | 4 |
| WI-001-4 | `prd.md` migrate 함수 정의 / Step 0 내부 배치 / v2 필드 6종 / schema_version | 9 |
| WI-001-5 | migrate 함수 실측 (awk 추출 후 source): 파일 없음 / v1→v2 / idempotent / 손상→rollback / **빈 파일** / 하위 호환 / 3종 class 수용 | 19 |
| WI-001-6 | 학습 전이 회귀 방지 (패턴 2 `((var++))` / 패턴 4 `\|\| echo 0` / 패턴 19 `local x=$(cmd)`) | 3 |
| **합계** | | **41** |

### 핵심 실측 시나리오 (WI-001-5)

- **A — 파일 없음**: `migrate_prd_state_v1_to_v2()` → return 0, 파일 신규 생성 없음
- **B — v1→v2**: 기존 필드(step/project_name/overview/user_constraints) 전수 보존 + v2 필드 6종 기본값 주입 + `.v1.bak` 생성
- **C — idempotent**: v2 상태에서 재실행 시 md5 무변화
- **D — rollback**: 손상 JSON 입력 시 return 1 + 원본 파일 복원 (`.v1.bak`에서)
- **G — 빈 파일(0바이트) 엣지**: `[[ -s ]]` 선체크로 migration 진입 차단 → return 0 + `.v1.bak` 미생성 + 원본 유지 (evaluator 1차 평가 피드백 반영)
- **E — 하위 호환**: PROJECT_CLASS 없는 `.flowsetrc` 로드 시 code 기본값
- **F — 3종 수용**: code/content/hybrid 각각 로드 성공

### 함수 추출 방식

prd.md는 markdown 파일이므로, smoke는 awk로 `migrate_prd_state_v1_to_v2() {` ~ 첫 `^}` 라인 사이의 함수 본문을 추출하여 source → 실제 함수로 실행. 이 방식은 prd.md 편집 시 smoke가 자동으로 최신 버전을 검증하도록 보장 (중복 정의 없음).

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-001.sh
```

**예상 출력 요약**:
```
  PASS: 41
  FAIL: 0
  ✅ WI-001 ALL SMOKE PASSED
```

**전체 누적**: 기존 180 + WI-001 smoke 41 = **221 assertion**
bats core.bats는 v4.0 Group α 종료 시점 그대로 **16 @test** (WI-001은 bats 대상 아님 — 후속 WI에서 필요 시 추가).

---

## 회의적 검증 포인트 (evaluator 선제 관측)

HANDOFF.md §3 evaluator 가이드 4건 전수 기계 검증 포함:

1. **하위 호환 완전성** → 시나리오 E (WI-001-5)
2. **migration idempotency + atomicity + rollback** → 시나리오 B/C/D (WI-001-5)
3. **`/wi:init` 분기 정확성** → WI-001-3 case 분기 + 미지정 값 거부
4. **smoke의 3중 검증**(기본값 / 3종 class 실측 / migration 재실행) → WI-001-1/-3/-5/-6 전체

---

## 이 smoke의 역할 (후속 WI에서 깨뜨리지 말아야 할 것)

| 검증 대상 | 회귀 시 차단 시점 |
|----------|-----------------|
| `.flowsetrc`의 PROJECT_CLASS 기본값 code | 필드 삭제/변경 시 WI-001-1 실패 |
| `init.md`의 PROJECT_CLASS 질문 | 질문 단계 제거 시 WI-001-2 실패 |
| `init.md` Step 3.5 case 분기 | 분기 구조 변경 시 WI-001-3 실패 |
| `prd.md`의 migrate 함수 계약 | 함수 본문 변경 시 WI-001-4/5 실패 |
| v2 필드 6종 기본값 타입 | 스키마 확장 시 기존 타입 유지 여부 확인 |

---

## Group β/γ/δ 잠금 해제

WI-001 머지 시점에 FlowSet v4.0 **Group β/γ/δ 진입 가능**:
- Group β (class 분기): WI-B1 / WI-B2 / WI-B3 (병렬 가능)
- Group γ (매트릭스): WI-C1 선행 → C2/C5/C6 병렬 → C3 → C4
- Group δ (문서): WI-D1 / WI-D2 최종
