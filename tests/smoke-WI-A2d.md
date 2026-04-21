# Smoke Tests — WI-A2d (v4.0 lib/merge.sh 이관)

WI-A2d 변경사항이 WI-A1 + WI-A2a + WI-A2b + WI-A2c 기준선을 깨뜨리지 않고, 7개 merge 함수 이관이 정확히 동작하는지 수동 재현 가능한 형태로 기록.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-21
**대응 커밋**: WI-A2d 브랜치

---

## 변경 범위

1. **`templates/lib/merge.sh` 신설** (514줄) — 설계 §7 "A2d: lib/merge.sh (wait_for_merge + wait_for_batch_merge + inject_regression_wis 이관)" + 연속 블록 이관을 위한 4개 함수 추가 포함
2. **`templates/flowset.sh`** — 본체 7개 함수 전면 제거 (Section 6.5~Section 8 블록) + `source lib/merge.sh` 필수
3. **`skills/wi/init.md`** — 템플릿 복사 블록에 `lib/merge.sh` 추가

### 이관된 7개 함수

| # | 함수 | 줄 수 | 역할 |
|---|------|------|------|
| 1 | `wait_for_merge` | 32 | 단일 PR 머지 대기 (순차 모드) |
| 2 | `wait_for_batch_merge` | 67 | batch PR 머지 대기 (병렬 모드) |
| 3 | `inject_regression_wis` | 45 | regression issue → fix_plan WI 주입 |
| 4 | `safe_sync_main` | 8 | main 동기화 (state 파일 보호) |
| 5 | `reconcile_fix_plan` | 34 | 루프 종료 시 fix_plan 체크박스 동기화 |
| 6 | `setup_worktree` | 33 | 병렬 워커 worktree + 브랜치 생성 |
| 7 | `execute_parallel` | 247 | 병렬 워커 실행 + PR + merge queue |
|   | **합계** | **466줄** | |

### 설계 §7 범위 확장 선언

설계 §7: "A2d: lib/merge.sh (wait_for_merge + wait_for_batch_merge + inject_regression_wis)"

**실제 이관 범위**: 7개 함수 (설계 3개 + `safe_sync_main`/`reconcile_fix_plan`/`setup_worktree`/`execute_parallel` 4개 추가)

**범위 확장 이유**:
1. **연속 블록 이관**: `safe_sync_main`/`reconcile_fix_plan`은 merge 3함수와 인접(:1211/:1220). 분리하면 비연속 이관 필요
2. **execute_parallel/setup_worktree는 WI-A2c에서 이월**: WI-A2c smoke-WI-A2c.md에 "merge 영역과 결합이므로 WI-A2d 포함 자연스러움" 명시
3. **의미상 통합**: 7개 함수 전부 "머지 + 병렬 실행 + 동기화" 주제

---

## flowset.sh 이관 효과 (누적 추적)

| 시점 | 라인 | 변동 | 사유 |
|------|-----|------|------|
| 설계 원본 (v3.4) | 1947 | — | 기준선 |
| WI-A2a 후 | 1998 | +51 | state.sh + shim + state_init |
| WI-A2b 후 | 1882 | -116 | preflight 이관 |
| WI-A2c 후 | 1782 | -100 | execute_claude 이관 |
| **WI-A2d 후** | **1308** | **-474** | **merge 7함수(466줄) + 주석 이관** |
| WI-A2e 예상 | ~1150 | -158 | vault 함수 + 이중 기록 제거 |

**A2d-7 임계치**: delta ≥ 400 (merge 블록이 대형이므로 엄격한 기준)

---

## Smoke 1~10 시나리오

`tests/run-smoke-WI-A2d.sh`에 완전한 실행 스크립트 존재.

### A2d-1 — lib/merge.sh 존재 + bash -n
### A2d-2 — 7개 함수 정의 이관 (본체 0건, lib 1건씩)
### A2d-3 — source 시 7개 함수 전부 declare
### A2d-4 — flowset.sh source 블록에 lib/merge.sh 포함
### A2d-5 — lib/merge.sh 없을 때 fail-fast
### A2d-6 — init.md에 복사 라인 추가
### A2d-7 — flowset.sh 라인 수 감소 (WI-A2c 1782 대비 delta ≥ 400)
### A2d-8 — 전체 shell bash -n 회귀 감지
### A2d-9 — WI-A1 + WI-A2a + WI-A2b + WI-A2c 기준선 비회귀 (5건)
### A2d-10 — merge.sh 학습 전이 보존 (sed/((var++))/arr pattern 0건)

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-A2d.sh
```

**예상 출력 요약**:
```
  Smoke Total: 16
  PASS: 16
  FAIL: 0
  ✅ WI-A2d ALL SMOKE PASSED
```

- A2d-1: 2 assertion (파일 + 문법)
- A2d-2: 2 assertion (본체 제거 + lib 정의)
- A2d-3: 1 assertion (7함수 declare)
- A2d-4: 1 assertion (source 블록)
- A2d-5: 1 assertion (fail-fast)
- A2d-6: 1 assertion (init.md)
- A2d-7: 1 assertion (라인 수)
- A2d-8: 1 assertion (전체 문법)
- A2d-9: 5 assertion (비회귀 5종)
- A2d-10: 1 assertion (학습 전이)
- **합계: 16 assertion**

**누적 assertion**: WI-A1 45 + WI-A2a 13 + WI-A2b 13 + WI-A2c 15 + WI-A2d 16 = **102 전수 통과**

이 문서는 WI-A2d 회귀 감지용 기준선. 후속 WI-A2e(vault.sh + 이중 기록 제거)가 이 시나리오를 깨뜨리지 않는지 `run-smoke-WI-A2d.sh`로 확인.
