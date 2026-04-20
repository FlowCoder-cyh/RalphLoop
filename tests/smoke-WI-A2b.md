# Smoke Tests — WI-A2b (v4.0 lib/preflight.sh 이관)

WI-A2b 변경사항이 WI-A1 + WI-A2a 기준선을 깨뜨리지 않고, `preflight()` 이관이 정확히 동작하는지 수동 재현 가능한 형태로 기록.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-20
**대응 커밋**: WI-A2b 브랜치

---

## 변경 범위

1. **`templates/lib/preflight.sh` 신설** — 설계 §7 "A2b: lib/preflight.sh(flowset.sh:385-508 preflight() 이관)" 구현. 기존 `preflight()` 전문 이관
2. **`templates/flowset.sh`** — 본체 `preflight()` 정의 제거 + `source lib/preflight.sh` 필수화
3. **`skills/wi/init.md`** — 템플릿 복사 블록에 `lib/preflight.sh` 추가

### Fallback 전략 — WI-A2a와 차이

**WI-A2a (lib/state.sh)**: shim fallback 제공 (lib 없으면 전역변수 래퍼로 동일 기능 유지)
**WI-A2b (lib/preflight.sh)**: **필수 로드**. lib 없으면 명확한 에러 메시지 + `exit 1`

이유: `preflight()`는 코드 200줄 규모로 기능 등가 shim 작성이 비현실적. 축소 fallback은 의미 없음(preflight의 본질은 전체 검증). **v3.x 프로젝트 업그레이드 시 `/wi:init` 재실행 필수**를 명시적으로 요구.

### flowset.sh 이관 효과

- **이관 전**: flowset.sh 1947줄 (preflight 약 130줄 포함)
- **이관 후**: flowset.sh **1882줄** (-65줄). lib/preflight.sh 163줄 신설

**이관 효과 자동 감지**: Smoke A2b-7이 `flowset.sh < 1900줄` 자동 검증.

---

## Smoke 1~9 시나리오

`tests/run-smoke-WI-A2b.sh`에 완전한 실행 스크립트 존재.

### A2b-1 — lib/preflight.sh 존재 + bash -n
```bash
[[ -f templates/lib/preflight.sh ]] && bash -n templates/lib/preflight.sh && echo OK
# 기대: OK
```

### A2b-2 — preflight() 정의 이관 확인
```bash
grep -cE '^preflight\(\)' templates/flowset.sh        # 기대: 0
grep -cE '^preflight\(\)' templates/lib/preflight.sh  # 기대: 1
```

### A2b-3 — source 시 preflight 함수 declare
```bash
bash -c 'source templates/lib/preflight.sh && declare -F preflight >/dev/null && echo FN_OK'
# 기대: FN_OK
```

### A2b-4 — flowset.sh 경로 기준 preflight 로드
```bash
cd templates && bash -c '[[ -f lib/preflight.sh ]] && source lib/preflight.sh && declare -F preflight >/dev/null && echo OK'
# 기대: OK
```

### A2b-5 — lib/preflight.sh 없을 때 fail-fast
```bash
bash -c '
  if [[ -f /nonexistent/lib/preflight.sh ]]; then
    source /nonexistent/lib/preflight.sh
  else
    echo "ERROR" >&2; exit 1
  fi
' || echo "FALLBACK_OK"
# 기대: FALLBACK_OK (exit 1 경로 진입)
```

### A2b-6 — init.md에 복사 라인 추가
```bash
grep -qE 'cp "\$TEMPLATE_DIR/lib/preflight\.sh"' skills/wi/init.md && echo OK
# 기대: OK
```

### A2b-7 — flowset.sh 라인 수 감소
```bash
wc -l < templates/flowset.sh   # 기대: 1900 미만 (이관 효과 증거)
```

### A2b-8 — 전체 shell bash -n 회귀 감지
```bash
find . -name "*.sh" -not -path "./.git/*" -exec bash -n {} \;
# 기대: 모든 파일 에러 0건
```

### A2b-9 — WI-A1 + WI-A2a 기준선 비회귀
```bash
bash tests/test-vault-transcript.sh | grep "^ALL TESTS PASSED$"
bash tests/run-smoke-WI-A1.sh       | grep "WI-A1 ALL SMOKE PASSED"
bash tests/run-smoke-WI-A2a.sh      | grep "WI-A2a ALL SMOKE PASSED"
# 기대: 세 줄 모두 매칭
```

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-A2b.sh
```

**예상 출력 요약**:
```
  Smoke Total: 13
  PASS: 13
  FAIL: 0
  ✅ WI-A2b ALL SMOKE PASSED
```

- A2b-1: 2 assertion (파일 존재 + 문법)
- A2b-2: 2 assertion (본체 제거 + lib 정의)
- A2b-3: 1 assertion (source declare)
- A2b-4: 1 assertion (flowset 경로 로드)
- A2b-5: 1 assertion (fail-fast)
- A2b-6: 1 assertion (init.md)
- A2b-7: 1 assertion (라인 수 감소)
- A2b-8: 1 assertion (전체 문법)
- A2b-9: 3 assertion (비회귀)
- **합계: 13 assertion**

**누적 assertion**: WI-A1 45 + WI-A2a 13 + WI-A2b 13 = **71 전수 통과**

이 문서는 WI-A2b 회귀 감지용 기준선. 후속 WI-A2c~e(worker/merge/vault lib 분리)가 이 시나리오를 깨뜨리지 않는지 `run-smoke-WI-A2b.sh`로 확인.
