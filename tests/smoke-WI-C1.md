# Smoke Tests — WI-C1 (/wi:prd Role 추출 + 매트릭스 스키마 SSOT 수립)

WI-C1 변경이 기존 누적 smoke(SSOT = `.github/workflows/flowset-ci.yml` smoke job name)를 깨뜨리지 않고, `/wi:prd` Step 2.5 (Role 추출)와 Step 4 확장(매트릭스 셀 의무화), `templates/.flowset/spec/matrix.json` 신설(3-class schema reference SSOT), v3 다운그레이드 방어(WI-001 이월 적용)를 실측 검증.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-25
**대응 브랜치**: `feature/WI-C1-feat-prd-role-matrix-schema`

---

## 변경 범위

1. **`skills/wi/prd.md` Step 2.5 신설** — Role 추출 + auth_patterns 자동 매핑
   - Step 2.5.a: PRD 본문에서 한글 6 + 영문 6 keyword grep 후 사용자 확인
   - Step 2.5.b: `package.json` 기반 auth_framework 자동 감지 (next-auth/clerk/supabase/lucia/passport 5종) + 정규식 패턴 매핑
   - Step 2.5.c: 커스텀 auth 수동 추가 (5종 외 자체 구현)
   - Step 2.5.d: prd-state.json에 roles + auth_framework + auth_patterns jq atomic 저장
   - Step 2.5.e: content class에서 auth_patterns skip 분기
2. **`skills/wi/prd.md` Step 4 확장** — 매트릭스 셀 의무화
   - `generate_code_matrix()` — Entity × CRUD × Role × Permission, 모든 셀 status `missing` 초기화
   - `generate_content_matrix()` — Section × Role × Action(draft/review/approve), 출처 + completeness_checklist 의무
   - `generate_hybrid_merge_content()` 진입점 (case 분기에서 호출)
   - `verify_matrix_cells()` 생성 직후 self-check (CRUD 4셀 / draft·review·approve 3셀 누락 시 exit 1)
   - SSOT 단일성: rubric 가중치는 review-rubric.md만 SSOT (matrix.json에 직접 직렬화 거부)
3. **`skills/wi/prd.md` Step 0.1 v3 다운그레이드 방어** (WI-001 이월)
   - `[[ "$schema_version" == "v2" ]]` → `[[ "$schema_version" =~ ^v[2-9]$ ]]`로 확장
   - 미래 v3 도입 시 v3 → v2 다운그레이드 차단 (설계 §8 :377)
4. **`templates/.flowset/spec/matrix.json` 신설** — 3-class schema reference SSOT (98줄)
   - `_schema_code` / `_schema_content` / `_schema_hybrid` 3-class 예시 + 필드 명세
   - 기본값 `class=code`, `schema_version=v2` (하위 호환)
   - 후속 6 WI(C2/C3-code/C3-content/C4/C5/C6) consumers 명시
   - `install.sh`가 cp하지 않음 — `/wi:prd`가 PROJECT_CLASS에 따라 동적 생성
5. **`.github/workflows/flowset-ci.yml`** smoke job에 `run-smoke-WI-C1.sh` 추가
6. **`tests/run-smoke-WI-C1.sh`** 신규 (46 assertion, 정적 + 4 idempotency 실측 시나리오)

---

## 하위 호환

- 기존 v1 prd-state.json은 WI-001의 `migrate_prd_state_v1_to_v2()`가 v2로 이행 (변경 없음)
- 기존 v2 prd-state.json은 idempotent skip (변경 없음)
- 미래 v3 prd-state.json도 정규식 매칭으로 skip (다운그레이드 방어)
- `templates/.flowset/spec/matrix.json`은 `install.sh`가 직접 복사하지 않음 — `/wi:prd` 미실행 프로젝트는 영향 없음
- Step 2.5는 `PROJECT_CLASS=content`일 때 auth 매핑을 skip하므로 content 단일 class도 정상 동작
- Step 4 확장은 case 분기에서 PROJECT_CLASS에 따라 분기되어 미설정 시 `code` 기본값으로 동작 (기존 v3.x와 동일)

---

## Smoke 1~6 블록별 요약

| 블록 | 주제 | Assertion |
|------|------|-----------|
| WI-C1-1 | prd.md Step 2.5 Role 추출 (헤더 / Step 시퀀스 / 한글·영문 키워드 / detect_auth_framework / 5 framework / content 분기) | 7 |
| WI-C1-2 | prd.md Step 4 매트릭스 셀 의무화 (확장 헤더 / 3개 generate 함수 / verify_matrix_cells / CRUD 4셀 / 3셀 / case 분기 / SSOT 단일성 / pain point) | 9 |
| WI-C1-3 | v3 다운그레이드 방어 (정규식 v2-v9 / 기존 == "v2" 잔존 없음 / 주석 근거) | 3 |
| WI-C1-4 | matrix.json 템플릿 SSOT (파일 존재 / 유효 JSON / schema_version / class / 3-class schema / CRUD 4셀 / status / draft·review·approve / 5 framework / consumers / v3 주석 / 동적 생성) | 12 |
| WI-C1-5 | migrate 함수 v2~v9 idempotency 실측 (함수 추출 / v2 idempotent / v3 방어 / .v1.bak 미생성 / 미래 필드 보존 / v9 경계 / v10 경계) | 10 |
| WI-C1-6 | 학습 전이 회귀 방지 (패턴 2/3/4/19/23) | 5 |
| **합계** | | **46** |

### 실측 시나리오 (WI-C1-5)

- **v2 idempotent**: 기존 v2 파일에 대해 함수 호출 시 md5 동일 (변화 없음, WI-001 회귀 검증)
- **v3 방어**: `schema_version: "v3"` + `future_v3_field` 파일에 대해 return 0 / md5 동일 / `.v1.bak` 미생성 / 미래 필드 보존
- **v9 경계**: 정규식 `^v[2-9]$` 상한 — `v9` 파일도 skip / `.v1.bak` 미생성
- **v10 경계**: 정규식 매칭 실패 → migration 진입 → schema_version이 `v2`로 덮어써짐 (의도된 동작 — v10 도입 시 별도 마이그레이션 함수 신설 신호)

### Step 시퀀스 검증

`grep '^### Step' skills/wi/prd.md` 결과가 정확히 `0 1 2 2.5 3 3.5 4 5 6` 순서여야 함. Step 2.5는 Step 2(도메인 구조)와 Step 3(기술 스택) 사이, 기존 Step 3.5(와이어프레임)는 그대로 유지.

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-C1.sh
```

**예상 출력 요약**:
```
  PASS: 46
  FAIL: 0
  ✅ WI-C1 ALL SMOKE PASSED
```

**전체 누적 (SSOT = `.github/workflows/flowset-ci.yml` smoke job name)**:
- **CI SSOT**: test-vault 31 + A1 14 + A2a-e 81 (13+13+15+16+24) + A3 17 + 001 40 + B1 27 + B2 36 + B3 35 + **C1 46** = **327 assertion** (A4는 CI 미호출, 순수 meta-smoke)
- **로컬 regression (A4 포함)**: 327 + 21 = **348 assertion**
- **bats core.bats**: 16 @test (class 무관)

---

## 이 smoke의 역할 (후속 WI에서 깨뜨리지 말아야 할 것)

| 검증 대상 | 회귀 시 차단 시점 |
|----------|-----------------|
| Step 시퀀스 0→1→2→2.5→3→3.5→4→5→6 | 순서 어긋남 시 WI-C1-1 실패 |
| Role 키워드 한글·영문 6+6 | 키워드 누락 시 WI-C1-1 실패 |
| auth_framework 5종 매핑 | 1종 누락 시 WI-C1-1 + WI-C1-4 실패 |
| Step 4 매트릭스 진입점 case 분기 | 3-class 분기 손상 시 WI-C1-2 실패 |
| v3 다운그레이드 방어 정규식 | `== "v2"` 회귀 시 WI-C1-3 + WI-C1-5 실패 |
| matrix.json 3-class schema reference | 스키마 단순화/누락 시 WI-C1-4 실패 |
| migrate 함수 v2~v9 idempotency | jq 함수 손상 시 WI-C1-5 실패 |
| SSOT 단일성 (rubric 가중치 직접 직렬화 거부) | matrix.json에 가중치 잘못 추가 시 WI-C1-2 실패 |
| 후속 WI 연계 (C2/C3-code/C3-content/C4/C5/C6 consumers) | Group γ 진입 경로 손상 시 WI-C1-4 실패 |
| 학습 전이 패턴 2/3/4/19/23 | 신규 코드에서 회귀 발생 시 WI-C1-6 실패 |

---

## Group γ 진행 상황 (선행 1/N)

- 🎯 **WI-C1** — /wi:prd Role 추출 + 매트릭스 스키마 SSOT 수립 (본 smoke, Group γ 선행)
- ⏳ WI-C2 — sprint-template.md CRUD/Section 매트릭스 + Gherkin 강제 (C1 스키마 참조)
- ⏳ WI-C3-code — stop-rag-check.sh code 분기 (auth_patterns grep + 타입 중복 + Gherkin↔테스트 매핑)
- ⏳ WI-C3-content — stop-rag-check.sh content 분기 (출처 URL + completeness_checklist done grep)
- ⏳ WI-C4 — evaluator.md type: content + cell/scenario coverage 채점 (rubric 5축 차용)
- ⏳ WI-C5 — verify-requirements.sh 매트릭스 대조
- ⏳ WI-C6 — session-start-vault.sh 미완 셀 주입

WI-C1 완결 후 후속 {C2, C5, C6} 병렬 진입 잠금 해제 → C3-code ∥ C3-content → C4.
