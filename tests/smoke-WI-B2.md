# Smoke Tests — WI-B2 (/wi:start 3모드 분기)

WI-B2 변경이 기존 누적 smoke(SSOT = `.github/workflows/flowset-ci.yml` smoke job name)를 깨뜨리지 않고, `skills/wi/start.md` Phase 5.9 Ruleset class별 조건부 + Phase 5.95 실행 모드 선택 + Phase 6 재구성(루프/대화형/팀)을 실측 검증.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-24
**대응 브랜치**: `feature/WI-B2-feat-start-3mode-branch`

---

## 변경 범위

1. **`skills/wi/start.md` Phase 5.9** — Ruleset 설정을 `PROJECT_CLASS`별 조건부로 분기:
   - `content` → 최소 보호(non_fast_forward + deletion, CI/status checks 불필요)
   - `code` / `hybrid` → 기존 strict ruleset + merge queue (v3.x 동일)
2. **`skills/wi/start.md` Phase 5.95 (신설)** — 실행 모드 선택:
   - `PROJECT_CLASS` → 기본 모드 자동 매핑 (code→loop, content→interactive, hybrid→team, 설계 §3 축 Y)
   - 사용자 override (1/2/3 또는 loop/interactive/team 영문)
   - `EXECUTION_MODE` `.flowsetrc` 영속화 (필드 존재 시 대체, 없으면 append)
3. **`skills/wi/start.md` Phase 6 재구성** — 3모드 분기:
   - **모드 A (루프)**: 기존 flowset.sh 새 터미널 자동 실행 (find_windows_bash + 플랫폼 감지 v3.x 유지)
   - **모드 B (대화형)**: 세션 내 WI 1개씩 수동 승인 (mapfile로 fix_plan.md 미완 WI 추출)
   - **모드 C (팀)**: `lead-workflow` Agent spawn (disallowedTools: Edit/Write — v3.2 정의)
4. **`templates/.flowsetrc`** — `EXECUTION_MODE=""` 필드 신설 (하위 호환: 빈 값 → PROJECT_CLASS 매핑)
5. **`.github/workflows/flowset-ci.yml`** smoke job에 `run-smoke-WI-B2.sh` 추가
6. **`tests/run-smoke-WI-B2.sh`** 신규 (36 assertion, 10 실측 시나리오 + 18 정적 검증)

---

## 하위 호환

- `PROJECT_CLASS=code` + `EXECUTION_MODE=""` → `loop` 모드 자동 매핑 → **v3.x 동작 완전 동일** (Phase 6 기존 flowset.sh 새 터미널 실행 경로)
- `.flowsetrc`에 `EXECUTION_MODE` 필드가 없어도 `${EXECUTION_MODE:-loop}` 기본값으로 루프 진입
- content 프로젝트에서 `GITHUB_ACCOUNT_TYPE` 미설정 시 `git push` 건너뜀 (로컬 커밋만 — GitHub 없는 content 프로젝트 지원)
- lead-workflow 에이전트는 v3.2 그대로 유지(설계 §5 :245 명시) — WI-B2는 `/wi:start` 호출 경로만 추가

---

## Smoke 1~6 블록별 요약

| 블록 | 주제 | Assertion |
|------|------|-----------|
| WI-B2-1 | Phase 5.9 Ruleset class별 조건부 (content 분기 / ruleset 이름 / 최소 보호 / else 분기 / class 라벨) | 5 |
| WI-B2-2 | Phase 5.95 모드 선택 블록 (제목 / DEFAULT_MODE 3종 / 사용자 case / 잘못 모드 / 잘못 class / 영속화) | 6 |
| WI-B2-3 | Phase 6 재구성 (6.0 공통 / GITHUB 조건 push / 6.1 case + 기본값 / 3모드 제목 / 팀 spawn / 대화형 PENDING / 루프 find_windows_bash) | 7 |
| WI-B2-4 | `.flowsetrc` EXECUTION_MODE 필드 (선언 / 기본값 빈 문자열 / 3모드 주석) | 3 |
| WI-B2-5 | 학습 전이 회귀 방지 (패턴 2 `((var++))` / 패턴 3 `${arr[@]/pat}` / 패턴 19 `local x=$(cmd)` / 패턴 4 `\|\| echo 0`) | 4 |
| WI-B2-6 | Phase 5.95 블록 awk 추출 + bash 실측 (10 시나리오) | 11 |
| **합계** | | **36** |

### 실측 시나리오 (WI-B2-6)

- **1 — class=code + Enter**: DEFAULT_MODE=loop 자동 매핑 (하위 호환)
- **2 — class=content + Enter**: DEFAULT_MODE=interactive 자동 매핑
- **3 — class=hybrid + Enter**: DEFAULT_MODE=team 자동 매핑
- **4 — class=code + "interactive"**: 사용자 override (영문 입력)
- **5 — 숫자 "1"**: 숫자 선택지 매핑 → loop
- **6 — 숫자 "3"**: 숫자 선택지 매핑 → team
- **7 — 잘못된 모드 "foobar"**: exit ≠ 0 (validation)
- **8 — 잘못된 PROJECT_CLASS "weird"**: exit ≠ 0 (validation)
- **9 — 빈 `.flowsetrc`**: EXECUTION_MODE append (sed no-op 회피)
- **10 — 기존 EXECUTION_MODE="loop"**: sed로 덮어쓰기 (중복 append 없음)

### 블록 추출 방식

start.md는 markdown이므로, smoke는 awk로 `### Phase 5.95:` 섹션 안의 첫 ` ```bash ` 블록을 추출. 추출된 블록에 `PROJECT_CLASS` 인자 주입 + stdin으로 `MODE_CHOICE` 제공 + 격리 cwd로 실행. 각 시나리오마다 `FINAL_MODE=...`를 echo하여 결과 대조. start.md 편집 시 smoke가 최신 의사코드를 자동 검증.

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-B2.sh
```

**예상 출력 요약**:
```
  PASS: 36
  FAIL: 0
  ✅ WI-B2 ALL SMOKE PASSED
```

**전체 누적 (SSOT = `.github/workflows/flowset-ci.yml` smoke job name)**:
- **CI SSOT**: test-vault 31 + A1 14 + A2a-e 81 (13+13+15+16+24) + A3 17 + 001 40 + B1 27 + **B2 36** = **246 assertion** (A4는 CI 미호출, 순수 meta-smoke)
- **로컬 regression (A4 포함)**: 246 + 21 = **267 assertion**
- **bats core.bats**: 16 @test (class 무관)

---

## 이 smoke의 역할 (후속 WI에서 깨뜨리지 말아야 할 것)

| 검증 대상 | 회귀 시 차단 시점 |
|----------|-----------------|
| Phase 5.9 content 최소 보호 (status checks 없음) | content 프로젝트 무리한 CI 강제 시 WI-B2-1 실패 |
| Phase 5.95 DEFAULT_MODE 3종 매핑 | 축 Y 매핑 손상 시 WI-B2-2, 실측 1/2/3 실패 |
| 사용자 override (1/2/3 + 영문) | UX 손상 시 실측 4~6 실패 |
| 잘못 입력 validation | exit 1 누락 시 실측 7/8 실패 |
| EXECUTION_MODE 영속화 (빈 파일 append) | sed no-op 시 실측 9 실패 |
| find_windows_bash 함수 유지 (루프 모드) | v3.x Windows 호환 손상 시 WI-B2-3 실패 |
| lead-workflow subagent_type 참조 | 팀 모드 spawn 경로 손상 시 WI-B2-3 실패 |

---

## Group β 진행 상황

- ✅ WI-B1 — `/wi:init` content/hybrid 분기
- ✅ **WI-B2** — `/wi:start` 3모드 분기 (본 smoke)
- ⏳ WI-B3 — contracts 템플릿 (`style-guide.md`, `review-rubric.md` 신설) — 순차 진행

WI-B2 완료 후 WI-B3 단독 진입 (contracts 템플릿 신설 — 파일 분리되어 충돌 없음).
