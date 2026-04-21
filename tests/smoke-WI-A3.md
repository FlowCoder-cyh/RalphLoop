# Smoke Tests — WI-A3 (v4.0 bats-core 테스트 인프라)

WI-A3 변경이 기존 bash smoke(126 assertion)를 깨뜨리지 않고, bats-core 기반 회귀 테스트 14개가 정확히 동작하는지 검증.

**실행 환경**: jq 1.8.1, bash 5.2.37, Bats 1.13.0 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-21
**대응 커밋**: WI-A3 브랜치 (`refactor/WI-A3-bats-tests`)

---

## 변경 범위

1. **`tests/bats/` (git submodule)** — bats-core 공식 저장소 (v1.13.0)
   - `.gitmodules`에 `[submodule "tests/bats"]` 등록 + `branch = v1.13.0` 태그 고정 (드리프트 방지)
   - `git submodule update --init --recursive`으로 초기화
   - 버전 업그레이드 절차: `git -C tests/bats fetch --tags && git -C tests/bats checkout vX.Y.Z && git add tests/bats && git commit`
2. **`tests/bats_tests/core.bats` 신설** — 16개 `@test` 블록 (설계 §7 "10~20개 핵심 테스트" 준수)
   - WI-A1 × 2 (set -euo + jq)
   - WI-A2a × 4 (state_init + '=' 값 무결성 + snapshot/restore 라운드트립 + lock 동작)
   - WI-A2b × 2 (preflight declare + fail-fast)
   - WI-A2c × 2 (execute_claude declare + 본체 제거)
   - WI-A2d × 2 (7함수 declare + 본체 제거)
   - WI-A2e × 2 (19함수 + 이중 기록 제거)
   - vault-helpers × 2 (shim source + re-source 확인)
3. **`install.sh`** — `[0/6]` 의존성 체크에 tests/bats submodule 자동 초기화 로직 추가 (네트워크 실패 시 경고만)
4. **`tests/run-smoke-WI-A3.sh` 신설** — 메타 smoke (bats 실행 + 14 PASS + 기존 6개 smoke 비회귀)

**HANDOFF R8 리스크 해소**: "bats-core가 Windows Git Bash에서 호환 불가 가능성"을 실측으로 확인 → Bats 1.13.0이 Windows에서 정상 실행됨 (A3-2 기계 검증).

**기존 bash smoke와 bats의 관계**:
- bash smoke(126 assertion): **상세 회귀 방어선**. 각 WI의 세부 기능·엣지 케이스·환경 특이사항 모두 커버
- bats core(14 assertion): **핵심 회귀 요약**. 각 WI의 "건드리면 안 되는 1~2가지" 압축. WI-A4(CI) 진입 시 ubuntu runner의 첫 번째 gate
- 이중 검증 구조: bats만 있으면 상세성 손실, bash만 있으면 CI 통합성 손실 → 둘 다 유지

---

## Smoke 1~9 시나리오

`tests/run-smoke-WI-A3.sh`에 전체 실행 스크립트. 수동 재현:

### A3-1 — bats submodule 경로 + .gitmodules 등록 (2 assertion)
```bash
test -f tests/bats/bin/bats
grep -q 'tests/bats' .gitmodules
```

### A3-2 — bats 실행 가능 (Windows 호환 실측, 1 assertion)
```bash
bash tests/bats/bin/bats --version
# 기대: "Bats 1.13.0"
```
HANDOFF R8 리스크 해소 기준.

### A3-3 — core.bats 존재 + 테스트 개수 10~20 (2 assertion)
```bash
test -f tests/bats_tests/core.bats
bash tests/bats/bin/bats --count tests/bats_tests/core.bats
# 기대: 16 (10~20 범위 준수)
```

### A3-4 — core.bats 전수 PASS (1 assertion)
```bash
bash tests/bats/bin/bats tests/bats_tests/core.bats
# 기대: 16/16 ok
```

### A3-5 — WI 커버리지 정합 (1 assertion)
```bash
grep -cE '^@test "(WI-A1|WI-A2a|WI-A2b|WI-A2c|WI-A2d|WI-A2e|vault-helpers):' tests/bats_tests/core.bats
# 기대: ≥ 14 (실제 16, WI-A2a에 snapshot/restore + lock 추가로 확장)
```

### A3-6 — install.sh에 submodule 로직 추가 (1 assertion)
```bash
grep -q 'tests/bats submodule' install.sh
```

### A3-7 — bash -n 전체 shell (1 assertion)
tests/bats/ 내부는 제외 (submodule이므로 상류 관리).

### A3-8 — 학습 전이 보존 (1 assertion)
```bash
# tests/bats_tests/*.bats 내부에 sed JSON / ((var++)) / ${arr[@]/pattern} 0건
```

### A3-9 — WI-A1~A2e 기준선 전수 비회귀 (7 assertion)
test-vault + A1 + A2a + A2b + A2c + A2d + A2e

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-A3.sh
```

**예상 출력 요약**:
```
  Smoke Total: 17
  PASS: 17
  FAIL: 0
  ✅ WI-A3 ALL SMOKE PASSED
```

assertion 계수:
- A3-1: 2 (submodule 경로 + .gitmodules)
- A3-2: 1 (bats 실행 가능)
- A3-3: 2 (core.bats 존재 + 테스트 개수)
- A3-4: 1 (전수 PASS)
- A3-5: 1 (WI 커버리지)
- A3-6: 1 (install.sh)
- A3-7: 1 (bash -n 전체)
- A3-8: 1 (학습 전이)
- A3-9: 7 (비회귀 × 7개 smoke)
- **합계: 17 assertion (smoke 레벨) + 16 bats 테스트 = 33 신규 assertion**

**전체 누적**: 기존 126 + WI-A3 smoke 17 + bats 16 = **159 assertion**

---

## 후속 WI 연계

### WI-A4 (FlowSet 자체 CI) — 직후 진입
- `.github/workflows/`에 GitHub Actions 워크플로우 추가
- shellcheck + bats core.bats + bash smoke 전체 실행
- Ubuntu runner에서 bats 실행 (Windows 로컬 + Linux CI 이중 환경 검증)
- PR 머지 게이트화

### bash smoke의 운명
- WI-A3 시점: **유지** (상세 회귀 방어선)
- WI-A4 시점: CI는 bats 우선 + bash smoke 병행
- 장기 (Group β~δ 후): bash smoke 일부를 bats로 점진 이관 고려. 단 WI-A3에서 "설계 §7 10~20개 핵심"을 이미 만족했으므로 서두르지 않음

---

## 이 smoke의 역할 (후속 WI에서 깨뜨리지 말아야 할 것)

| 검증 대상 | 회귀 시 차단 시점 |
|----------|-----------------|
| tests/bats submodule 경로 | submodule 제거·이동 시 A3-1 실패 |
| bats 실행 가능성 | bats 경로 변경 / 버전 문제 시 A3-2 실패 |
| core.bats 14 테스트 | WI별 핵심 invariant 깨짐 시 A3-4 실패 |
| WI 커버리지 비율 | `@test` 블록 누락 시 A3-5 실패 |
| 기존 6개 bash smoke | WI-A1~A2e 회귀 시 A3-9 실패 |

`WI-A4(CI)`에서 위 9개 smoke assertion이 **PR 머지 게이트**가 됨.
