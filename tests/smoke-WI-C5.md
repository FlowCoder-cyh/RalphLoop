# Smoke Tests — WI-C5 (verify-requirements.sh 매트릭스 대조)

WI-C5는 `verify-requirements.sh`에 `matrix.json` 기반 정적 셀 대조 로직을 추가합니다. 기존 v3.0 LLM 검증은 그대로 보존되며 (하위 호환), `matrix.json` 부재 시 `HAS_MATRIX=false`로 매트릭스 대조를 skip합니다. PROJECT_CLASS(`code`/`content`/`hybrid`)에 따라 변경 파일을 entities/sections 영역에 매핑하고, 미완 셀(`status != "done"`)을 발견 시 `MATRIX_ISSUE: ...` 형식으로 보고하여 LLM 결과와 합산하여 exit code 결정.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-25
**대응 브랜치**: `feature/WI-C5-feat-verify-requirements-matrix`

---

## 변경 범위

1. **`templates/.flowset/scripts/verify-requirements.sh`** 확장 (90줄 → 195줄)
   - **HAS_MATRIX 플래그**: matrix.json 존재 여부로 매트릭스 대조 분기 — 부재 시 기존 v3.0 동작 완전 동일
   - **PROJECT_CLASS 로드**: `.flowsetrc` 기본값 `code` (하위 호환)
   - **`verify_matrix_against_diff()` 함수**: 변경 파일을 code/content 영역으로 분류 후 case 분기 — 알 수 없는 class → exit 1
   - **`_emit_missing_entities()` / `_emit_missing_sections()` 헬퍼**: jq pipeline으로 status != "done" 셀을 entity/section 단위 그룹화 후 `MATRIX_ISSUE: ...` 출력
   - **issue 합산**: `TOTAL_FAIL = LLM_MISSING + LLM_INCOMPLETE + MATRIX_ISSUES` → 1건 이상이면 exit 2
   - **vault 동기화 확장**: 매트릭스 결과도 vault 본문에 포함
2. **`tests/run-smoke-WI-C5.sh`** 신규 (29 assertion, 7 블록)
3. **`.github/workflows/flowset-ci.yml`** smoke job: 383 → 412 assertion

---

## 하위 호환

- `matrix.json` 부재 → `HAS_MATRIX=false` → 매트릭스 대조 skip → v3.0 LLM 검증만 실행 (기존 동작 완전 동일)
- `PROJECT_CLASS` 미설정 → 기본값 `code` (`.flowsetrc` 신설 안 한 v3.x 프로젝트도 정상)
- `requirements.md` 부재 → LLM 검증 skip — 단 매트릭스 issue가 있으면 그것만 보고하고 exit 2
- 기존 `exit 0/2` 인터페이스 보존 (Stop hook 호환)

---

## Smoke 1~7 블록별 요약

| 블록 | 주제 | Assertion |
|------|------|-----------|
| WI-C5-1 | 정적 구조 (set -euo / HAS_MATRIX / MATRIX_FILE / PROJECT_CLASS / 함수 3개 / case 분기 / 합산 / exit 2) | 10 |
| WI-C5-2 | 학습 전이 회귀 방지 (패턴 2/3/4/19/23 — jq pipeline 일관 2건) | 5 |
| WI-C5-3 | matrix.json 부재 → skip e2e (HAS_MATRIX=false) | 2 |
| WI-C5-4 | code class 분기 e2e (Leave 미완 검출 / Attendance done 미보고 / 변경 0건 skip / src 외 변경 skip) | 4 |
| WI-C5-5 | content class 분기 e2e (3.2-User-Flow 미완 / 4.1-API-Spec done 미보고 / code만 변경 skip) | 3 |
| WI-C5-6 | hybrid class 분기 e2e (양쪽 동시 / 코드만 / content만) | 3 |
| WI-C5-7 | 비정상 class 거부 e2e (ERROR 메시지 + return 1) | 2 |
| **합계** | | **29** |

### e2e 시나리오 매트릭스 (블록 3-7)

| 시나리오 | PROJECT_CLASS | matrix.json | CHANGED | 기대 출력 |
|----------|---------------|-------------|---------|-----------|
| A | (any) | 부재 | (any) | 빈 출력 (skip) |
| B | code | Leave U/D missing + Attendance all done | src/api/leaves/route.ts | `entity=Leave 미완 셀 [U,D]`, Attendance 미보고 |
| C | code | (B와 동일) | (빈 문자열) | 빈 출력 (변경 0건) |
| D | code | (B와 동일) | README.md | 빈 출력 (src 외) |
| E | content | 3.2 review/approve missing + 4.1 all done | docs/3.2-user-flow.md | `section=3.2-User-Flow 미완 셀 [review,approve]` 또는 [approve,review] |
| F | content | (E와 동일) | src/api/route.ts | 빈 출력 (content 변경 없음) |
| G | hybrid | Leave U/R/D missing + 3.2 review/approve missing | src + docs 동시 | entity + section 둘 다 보고 |
| H | hybrid | (G와 동일) | src만 | entity만 보고 |
| I | hybrid | (G와 동일) | docs만 | section만 보고 |
| J | unknown | class=unknown_class | src | `ERROR: 알 수 없는 PROJECT_CLASS` + return 1 |

### jq pipeline 일관성 (패턴 23)

`_emit_missing_entities`와 `_emit_missing_sections`는 동일한 jq 추출 패턴을 사용:
```jq
.X | to_entries[] |
[.key, ([.value.status | to_entries[] | select(.value != "done") | .key] | join(","))] | @tsv
```
status에서 `done`이 아닌 셀(missing/pending)만 추출 → comma join → TSV 출력. 후처리에서 `read -r entity missing_cells` 로 분리. WI-C1 status 3-state(missing/pending/done) 어휘 정합 유지.

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-C5.sh
```

**예상 출력 요약**:
```
  PASS: 29
  FAIL: 0
  ✅ WI-C5 ALL SMOKE PASSED
```

**전체 누적 (SSOT = `.github/workflows/flowset-ci.yml` smoke job name)**:
- **CI SSOT**: test-vault 31 + A1 14 + A2a-e 81 (13+13+15+16+24) + A3 17 + 001 40 + B1 27 + B2 36 + B3 35 + C1 60 + C2 42 + **C5 29** = **412 assertion**
- **로컬 regression (A4 포함)**: 412 + 21 = **433 assertion**
- **bats core.bats**: 16 @test (class 무관)

---

## 이 smoke의 역할 (후속 WI에서 깨뜨리지 말아야 할 것)

| 검증 대상 | 회귀 시 차단 시점 |
|----------|-----------------|
| HAS_MATRIX 플래그 + matrix.json 부재 시 skip | 무조건 매트릭스 대조 시도 시 WI-C5-3 실패 |
| PROJECT_CLASS 기본값 code (하위 호환) | 기본값 변경 시 WI-C5-1 실패 |
| 3-class case 분기 (code/content/hybrid) | 분기 누락 시 WI-C5-1 + WI-C5-{4,5,6} 실패 |
| _emit_missing_entities/sections jq pipeline | jq 패턴 변경 시 WI-C5-2 + 해당 e2e 실패 |
| 알 수 없는 class → ERROR + return 1 | fall-through 회귀 시 WI-C5-7 실패 |
| TOTAL_FAIL 합산 (LLM + MATRIX) | 합산 누락 시 WI-C5-1 실패 |
| exit 2 (Stop hook 호환) | 인터페이스 변경 시 WI-C5-1 실패 |
| 학습 전이 패턴 2/3/4/19/23 | 신규 코드 회귀 시 WI-C5-2 실패 |

---

## Group γ 진행 상황 (3/N)

- ✅ WI-C1 — `/wi:prd` Role 추출 + 매트릭스 스키마 SSOT (matrix.json 신설)
- ✅ WI-C2 — sprint-template.md CRUD/Section 매트릭스 + Gherkin 강제
- 🎯 **WI-C5** — verify-requirements.sh 매트릭스 대조 (본 smoke)
- ⏳ WI-C6 — session-start-vault.sh 미완 셀 주입 (status missing/pending 추출 패턴 차용 가능)
- ⏳ WI-C3-code/C3-content — stop-rag-check.sh class 분기 (parse-gherkin.sh 신설 후 진입)
- ⏳ WI-C4 — evaluator.md type=content + cell/scenario coverage (rubric 5축 차용)

WI-C5 완결 후 후속 WI-C6 진입 가능. C3/C4는 parse-gherkin.sh 신설 후.
