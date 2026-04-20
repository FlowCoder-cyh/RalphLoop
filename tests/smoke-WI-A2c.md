# Smoke Tests — WI-A2c (v4.0 lib/worker.sh 이관)

WI-A2c 변경사항이 WI-A1 + WI-A2a + WI-A2b 기준선을 깨뜨리지 않고, `execute_claude()` 이관이 정확히 동작하는지 수동 재현 가능한 형태로 기록.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-20
**대응 커밋**: WI-A2c 브랜치

---

## 변경 범위

1. **`templates/lib/worker.sh` 신설** — 설계 §7 "A2c: lib/worker.sh (execute_claude() + 관련 함수 이관)" 구현. execute_claude 전문 이관
2. **`templates/flowset.sh`** — 본체 execute_claude() 제거 + `source lib/worker.sh` 필수 (preflight.sh 패턴)
3. **`skills/wi/init.md`** — 템플릿 복사 블록에 `lib/worker.sh` 추가
4. **`tests/run-smoke-WI-A2a.sh` A2a-11 검색 범위 확장** — `templates/flowset.sh + templates/lib/` 전체로 grep 대상 확대 (execute_claude 위치 이동 대응)

### 설계 §7 라인 범위 stale 대응

설계 §7: "A2c: lib/worker.sh (flowset.sh:1603-1710 execute_claude() + 관련 함수)"
**실제 위치 (WI-A2b 직후)**: `:1533-1645` (113줄)
WI-A2b에서 확립한 "설계 §7 라인 범위 stale 가이드"(smoke-WI-A2b.md)를 따라 **실제 위치를 재확인 후 이관**.

---

## flowset.sh 이관 효과 (누적 추적)

| 시점 | 라인 | 변동 | 사유 |
|------|-----|------|-----|
| 설계 원본 (v3.4) | 1947 | — | 기준선 |
| WI-A2a 후 | 1998 | +51 | state.sh + shim + state_init |
| WI-A2b 후 | 1882 | -116 | preflight 이관 |
| **WI-A2c 후** | **1782** | **-100** | execute_claude 이관 |
| WI-A2d 예상 | ~1550 | -230 | wait_for_merge + wait_for_batch_merge + inject_regression 이관 |
| WI-A2e 예상 | ~1400 | -150 | vault 함수 + 이중 기록 제거 |

**A2c-7 회귀 방지**: `WI-A2b 후 1882 대비 감소량 ≥ 80줄` 엄격 검증.

---

## Smoke 1~10 시나리오

`tests/run-smoke-WI-A2c.sh`에 완전한 실행 스크립트 존재.

### A2c-1 — lib/worker.sh 존재 + bash -n
### A2c-2 — execute_claude() 정의 이관 (본체 0건, lib 1건)
### A2c-3 — source 시 execute_claude declare 확인
### A2c-4 — flowset.sh 경로 기준 worker 로드
### A2c-5 — lib/worker.sh 없을 때 fail-fast (preflight.sh 패턴)
### A2c-6 — init.md에 복사 라인 추가
### A2c-7 — flowset.sh 라인 수 감소 (이관 효과, delta ≥ 80)
### A2c-8 — 전체 shell bash -n 회귀 감지
### A2c-9 — WI-A1 + WI-A2a + WI-A2b 기준선 비회귀
### A2c-10 — execute_claude jq 파싱 3개 키 보존 (WI-A1 학습 전이 회귀 방지)
```bash
for k in session_id total_cost_usd cache_creation_input_tokens; do
  grep -q "$k" templates/lib/worker.sh
done
# 기대: 모두 매칭 (WI-A1의 sed→jq 전환이 worker.sh에서 유지됨)
```

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-A2c.sh
```

**예상 출력 요약**:
```
  Smoke Total: 15
  PASS: 15
  FAIL: 0
  ✅ WI-A2c ALL SMOKE PASSED
```

- A2c-1: 2 assertion (파일 + 문법)
- A2c-2: 2 assertion (본체 제거 + lib 정의)
- A2c-3: 1 assertion (source declare)
- A2c-4: 1 assertion (flowset 경로)
- A2c-5: 1 assertion (fail-fast)
- A2c-6: 1 assertion (init.md)
- A2c-7: 1 assertion (라인 수 감소)
- A2c-8: 1 assertion (전체 문법)
- A2c-9: 4 assertion (비회귀 4종)
- A2c-10: 1 assertion (jq 파싱 보존)
- **합계: 15 assertion**

**누적 assertion**: WI-A1 45 + WI-A2a 13 + WI-A2b 13 + WI-A2c 15 = **86 전수 통과**

---

## WI-A2a smoke 업데이트 (정당한 기준선 이동)

A2a-11 smoke가 원래 `templates/flowset.sh`에서 `local iteration_cost` 선언을 검색. WI-A2c에서 execute_claude가 `lib/worker.sh`로 이관되면서 검색 대상 확장 필요.

**수정 전**:
```bash
grep -qE '^\s+local\s+(iteration_cost|total_context_tokens|...)' templates/flowset.sh
```

**수정 후**:
```bash
grep -rqE '^\s+local\s+(iteration_cost|total_context_tokens|...)' templates/flowset.sh templates/lib/
```

**의미**: execute_claude 함수 자체의 local 선언은 그대로 유지(기능 동등). 단지 파일 위치만 이동. A2a-11의 설계 §11 line 441 근거 검증은 어느 파일에 있든 작동하도록 확장.

이는 "후속 WI가 이전 WI smoke를 수정하는 예외 케이스" — lib 분리에 따른 기준선 이동으로 정당화됨. WI 격리 원칙의 일반적 예외.

이 문서는 WI-A2c 회귀 감지용 기준선. 후속 WI-A2d/e가 이 시나리오를 깨뜨리지 않는지 `run-smoke-WI-A2c.sh`로 확인.
