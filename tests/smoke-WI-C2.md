# Smoke Tests — WI-C2 (sprint-template.md CRUD/Section 매트릭스 + Gherkin 강제)

WI-C2 변경이 기존 누적 smoke를 깨뜨리지 않고, `templates/.flowset/contracts/sprint-template.md`에 메타 PROJECT_CLASS 분기 + Gherkin 강제 + CRUD/Section 매트릭스 셀 + 평가 type 4종을 도입함을 실측 검증. WI-C1이 정의한 `matrix.json` 스키마 SSOT를 sprint-template이 소비하는 정합 관계도 검증 (entity/section 키 동일성).

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-25
**대응 브랜치**: `feature/WI-C2-feat-sprint-template-matrix-gherkin`

---

## 변경 범위

1. **`templates/.flowset/contracts/sprint-template.md` 전면 확장** (40줄 → 168줄)
   - 메타 섹션 신설: `PROJECT_CLASS` (code|content|hybrid) + matrix.json 경로 + WI-C1 SSOT 표지 + class 정합 안내
   - 수용 기준 Gherkin 강제: `Feature/Background/Scenario/Scenario Outline/Examples` + `Given/When/Then` 키워드 의무, 자유 텍스트 금지
   - code/content 두 종 Gherkin 예시 (Leave entity / 3.2-User-Flow section)
   - CRUD 매트릭스 (code/hybrid only): Entity × C/R/U/D + type_ssot + endpoints + Role × CRUD permission (employee/manager/admin)
   - Section 매트릭스 (content/hybrid only): Section × draft/review/approve + sources + completeness_checklist + Role × Action (writer/reviewer/approver)
   - 검증 방법 5건: parse-gherkin.sh 호출, jq matrix.json entities/sections 조회, .flowset/reviews/, .flowset/approvals/ 파일 존재
   - 제약 4건: 자유 텍스트 금지, matrix.json 외 entity/section 신설 금지, verify_matrix_cells 차단, sources 0건/reviewer 파일 부재 차단
   - 평가 type 4종: code | content | hybrid | visual (기존 code|visual 2종에서 확장 — WI-C4 evaluator type 신설 예약)
2. **`tests/run-smoke-WI-C2.sh`** 신규 (39 assertion, 7 블록)
3. **`.github/workflows/flowset-ci.yml`** smoke job: 341 → 380 assertion (`run-smoke-WI-C2.sh` 등록)

---

## 하위 호환

- 기존 sprint-{NNN}.md 파일은 `type: code (legacy)` 플래그 도입 검토 (설계 §8 :361 — 이 문서에서는 미적용, 후속 fix로 처리)
- 기존 `type: code | visual` 2종은 4종으로 확장 — `code`/`visual` 그대로 유지하므로 회귀 없음
- WI-B1/B2/B3가 생성한 sprint 계약은 본 변경 영향 없음 (template만 변경, 기존 인스턴스 자동 마이그레이션 안 함)
- v3.x sprint-template 사용자는 수동 업그레이드 또는 `/wi:start` 신규 실행 시에만 적용

---

## Smoke 1~7 블록별 요약

| 블록 | 주제 | Assertion |
|------|------|-----------|
| WI-C2-1 | 메타 PROJECT_CLASS + matrix.json 참조 (헤더 / 3종 / 경로 / WI-C1 SSOT 표지 / class 정합) | 5 |
| WI-C2-2 | 수용 기준 Gherkin 강제 (헤더 / 자유텍스트 금지 / 4 키워드 / GWT 6건 / code+content 예시 / 강제 규칙 4건 / parse-gherkin 참조 / Examples 합산) | 8 |
| WI-C2-3 | CRUD 매트릭스 code/hybrid (헤더 / 7컬럼 / Role 권한 3종 / pain point B1/B2/B3 / type_ssot 예시) | 5 |
| WI-C2-4 | Section 매트릭스 content/hybrid (헤더 / 6컬럼 / Role 3종 / 출처+style-guide / 익명 리뷰 금지 / SSOT 단일성) | 6 |
| WI-C2-5 | 평가 type 4종 + 검증 방법 + 제약 (4종 / WI-C4 예약 / content 가중치 5축 / 검증 5건 / 제약 3건) | 5 |
| WI-C2-6 | matrix.json (WI-C1 SSOT) 정합성 (파일 존재 / entity 키 정합 / section 키 정합 / 3-state 일관 / role 어휘 정합) | 5 |
| WI-C2-7 | 학습 전이 회귀 방지 (패턴 2/3/4/19/23 — Gherkin 어휘 일관) | 5 |
| **합계** | | **39** |

### 핵심 정합 검증 (WI-C2-6)

WI-C1이 정의한 matrix.json `_schema_code.entities_example.Leave`와 `_schema_content.sections_example."3.2-User-Flow"` 키를 sprint-template이 그대로 인용 (jq로 키 추출 후 sprint-template grep). matrix.json이 미래에 entity 이름을 변경하면 sprint-template도 동시에 업데이트해야 회귀 차단 통과 — SSOT 단일성 보장.

### Gherkin 강제 규칙 (WI-C2-2)

- `Feature:` 헤더 1개 필수
- `Scenario:` 또는 `Scenario Outline:` 1개 이상 필수
- `Given/When/Then` 키워드 각 1개 이상 (Scenario당)
- `Scenario Outline + Examples`의 데이터 행 수가 시나리오 수에 합산 (설계 §4 :195-196)
- Scenario name과 대응 테스트 이름 매칭 (정규화 §4 :199-204)
- 자유 텍스트 수용 기준 (체크박스 단순 나열) 금지 — Stop hook이 차단 (WI-C3-code 예약)
- `parse-gherkin.sh` 출력의 `scenarios[].name`이 SSOT (WI-C3 호출 예약)

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-C2.sh
```

**예상 출력 요약**:
```
  PASS: 39
  FAIL: 0
  ✅ WI-C2 ALL SMOKE PASSED
```

**전체 누적 (SSOT = `.github/workflows/flowset-ci.yml` smoke job name)**:
- **CI SSOT**: test-vault 31 + A1 14 + A2a-e 81 (13+13+15+16+24) + A3 17 + 001 40 + B1 27 + B2 36 + B3 35 + C1 60 + **C2 39** = **380 assertion**
- **로컬 regression (A4 포함)**: 380 + 21 = **401 assertion**
- **bats core.bats**: 16 @test (class 무관)

---

## 이 smoke의 역할 (후속 WI에서 깨뜨리지 말아야 할 것)

| 검증 대상 | 회귀 시 차단 시점 |
|----------|-----------------|
| 메타 PROJECT_CLASS 3종 (code/content/hybrid) | 메타 누락/축소 시 WI-C2-1 실패 |
| matrix.json 경로 + WI-C1 SSOT 표지 | sprint↔matrix 연결 끊김 시 WI-C2-1 실패 |
| Gherkin 4 키워드 + GWT + 자유텍스트 금지 | 수용 기준 형식 회귀 시 WI-C2-2 실패 |
| CRUD 매트릭스 7컬럼 + pain point B1/B2/B3 | 매트릭스 컬럼 축소 시 WI-C2-3 실패 |
| Section 매트릭스 6컬럼 + WI-B3 출처 SSOT | 콘텐츠 매트릭스 축소 시 WI-C2-4 실패 |
| 평가 type 4종 (WI-C4 evaluator type 예약) | content type 누락 시 WI-C2-5 실패 |
| **matrix.json entity/section 키 정합** (Leave / 3.2-User-Flow) | WI-C1 matrix.json과 sprint-template 키 어긋남 시 WI-C2-6 실패 |
| status 3-state 일관 (missing/pending/done) | 어휘 불일치 시 WI-C2-6 실패 |
| Gherkin 어휘 일관 (Scenario Outline 표준) | ScenarioOutline 등 변형 시 WI-C2-7 실패 |
| 학습 전이 패턴 2/3/4/19/23 | 신규 코드에서 회귀 발생 시 WI-C2-7 실패 |

---

## Group γ 진행 상황 (3/N)

- ✅ **WI-C1** — `/wi:prd` Role 추출 + 매트릭스 스키마 SSOT 수립 (matrix.json 신설)
- 🎯 **WI-C2** — sprint-template.md CRUD/Section 매트릭스 + Gherkin 강제 (본 smoke)
- ⏳ WI-C3-code — stop-rag-check.sh code 분기 (auth_patterns + 타입 중복 + Gherkin↔테스트 매칭) ← parse-gherkin.sh 신설 + 호출
- ⏳ WI-C3-content — stop-rag-check.sh content 분기 (출처 URL + completeness done grep)
- ⏳ WI-C4 — evaluator.md type: content + cell/scenario coverage 채점 (rubric 5축 차용)
- ⏳ WI-C5 — verify-requirements.sh 매트릭스 대조 (sprint-template 매트릭스 ↔ 구현 비교)
- ⏳ WI-C6 — session-start-vault.sh 미완 셀 주입

WI-C2 완결 후 후속 {C5, C6} 추가 잠금 해제 (C1 + C2 둘 다 의존). C3/C4는 C1+C2+parse-gherkin.sh가 함께 갖춰진 후 진입.
