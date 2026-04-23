# Smoke Tests — WI-B1 (/wi:init content/hybrid 분기)

WI-B1 변경이 기존 누적 smoke(221 assertion)를 깨뜨리지 않고, `skills/wi/init.md` Step 3.5에 신설된
class별 ownership.json 분기(설계 §5 :214 4단계 흐름)와 `mkdir -p .flowset/reviews .flowset/approvals`(§7 :302)를 실측 검증.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-23
**대응 브랜치**: `feature/WI-B1-feat-init-content-hybrid-branch`

---

## 변경 범위

1. **`skills/wi/init.md` Step 3.5** — 기존 "validation only" case 블록을 제거하고 전체 `build_team_names()` 의사코드로 대체:
   - (a) `skip_dup_check` 가드: hybrid에서만 중복 감지 활성
   - (b) code/hybrid 시 frontend/backend/qa/devops/planning 누적 + hybrid는 동적 확장 질문
   - (c) content/hybrid 시 writer/reviewer/approver/designer/shared 5역 누적
   - (d) content/hybrid 시 `.flowset/reviews` + `.flowset/approvals` mkdir (§7 :302)
   - (e) hybrid 전용: `sort | uniq -d` 중복 감지 + 재시도 루프(max_retry=3) + 방어 2종(빈 입력 + 새 이름 자체 중복) + filter-rebuild 배열 조작
   - (f) 3회 연속 실패 시 `exit 1` (무한 루프 방어)
2. **content class 매핑 테이블 신설** (writer/reviewer/approver/designer/shared)
3. **hybrid class 매핑 JSON 예시 신설** (`ownership.json.teams[].class` 필드로 경로별 class 태깅)
4. **`.github/workflows/flowset-ci.yml`** smoke job에 `run-smoke-WI-B1.sh` 추가
5. **`tests/run-smoke-WI-B1.sh`** 신규 (27 assertion, 8 시나리오 실측)

---

## 하위 호환

- `PROJECT_CLASS=code` (기본) → frontend/backend/qa/devops/planning 5역만. reviews/approvals mkdir 미실행. **v3.x 동작 완전 동일**.
- WI-001의 validation 게이트(알 수 없는 class → exit 1) 유지.
- 기존 프로젝트(PROJECT_CLASS 미설정) → `${PROJECT_CLASS:-code}` 기본값 → v3.x 경로.

---

## Smoke 1~4 블록별 요약

| 블록 | 주제 | Assertion |
|------|------|-----------|
| WI-B1-1 | init.md 정적 확인 (validation 유지 / skip_dup_check / code 5역 / content 5역 / mkdir) | 5 |
| WI-B1-2 | hybrid 중복 감지 루프 구조 (max_retry / sort\|uniq / 방어1 / 방어2 / 3회 exit / filter-rebuild / retry=$((n+1))) | 7 |
| WI-B1-3 | 학습 전이 회귀 방지 (패턴 2 `((var++))` / 패턴 3 `${arr[@]/pat}` / 패턴 19 `local x=$(cmd)`) | 3 |
| WI-B1-4 | init.md 블록 awk 추출 + 실측 (8 시나리오) | 12 |
| **합계** | | **27** |

### 실측 시나리오 (WI-B1-4, 설계 §5 :235 8종 전수)

- **1 — code**: frontend/backend/qa/devops/planning 생성 + reviews/approvals 미생성 (하위 호환)
- **2 — content**: writer/reviewer/approver/designer/shared 5역 + reviews/approvals mkdir
- **3 — hybrid 기본**: code 5역 + content 5역 공존 (designer 1건 — extra 없음이면 중복 없음)
- **4 — hybrid designer 중복 재입력 성공**: extra로 `designer` 추가 → designer 중복 → `designer-code designer-content` 재입력 → 최종 배열 정상
- **5 — hybrid 3회 연속 중복 → exit 1**: 무한 루프 방어 (각 재입력이 `designer designer` 자체 중복 반복)
- **6 — 방어 1(빈 입력)**: 재입력에서 엔터만 → "최소 1개 이상의 새 이름 입력 필요" + retry 증가 + 다음 입력 대기
- **7 — 방어 2(새 이름 자체 중복)**: 재입력에서 `designer-code designer-code` → "새 이름 자체에 중복" + retry 증가
- **8 — filter-rebuild**: 중복 해결 후 team_names에 빈 요소 0건 + 원본 `designer` 완전 제거 (패턴 3 회귀 방지)

### 블록 추출 방식

init.md는 markdown이므로, smoke는 awk로 `source .flowsetrc` 줄을 시작점으로 첫 ``` ``` ``` 닫힘까지 블록을 추출. 추출된 블록에 `ownership_save()` stub + `PROJECT_CLASS` 인자 주입 + `mkdir -p` 격리 cwd 준비 후 bash 서브셸로 실행. init.md 편집 시 smoke가 최신 의사코드를 자동 검증.

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-B1.sh
```

**예상 출력 요약**:
```
  PASS: 27
  FAIL: 0
  ✅ WI-B1 ALL SMOKE PASSED
```

**전체 누적**: 기존 220 + WI-B1 smoke 27 = **247 assertion** + bats 16 @test.
(내역: test-vault 31 + A1 14 + A2a-e 81 + A3 17 + A4 21 + 001 40 + B1 27 / WI-001은 WI-B1에서 41→40 재캘리브레이션)

---

## 이 smoke의 역할 (후속 WI에서 깨뜨리지 말아야 할 것)

| 검증 대상 | 회귀 시 차단 시점 |
|----------|-----------------|
| code 5역 구성 | 기본 경로 손상 시 시나리오 1 실패 |
| content 5역 + mkdir | §7 :302 누락 시 시나리오 2 실패 |
| hybrid designer 중복 재입력 | filter-rebuild 깨짐 시 시나리오 4/8 실패 |
| 3회 연속 중복 방어 | 무한 루프 발생 시 시나리오 5 실패 |
| 방어 1/2 (빈 입력 / 자체 중복) | silent data loss 발생 시 시나리오 6/7 실패 |
| bash gotcha 회피(`retry=$((n+1))`) | `((retry++))` 도입 시 WI-B1-2 실패 |

---

## Group β 진행 상황

- ✅ **WI-B1** — `/wi:init` content/hybrid 분기 (본 smoke)
- ⏳ WI-B2 — `/wi:start` 3모드 분기 (Phase 6 재구성) — 병렬 진입 가능
- ⏳ WI-B3 — contracts 템플릿 (`style-guide.md`, `review-rubric.md` 신설) — 병렬 진입 가능

WI-B1 완료 후 WI-B2/B3는 파일 분리되어 병렬 세션 진입 가능.
