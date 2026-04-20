# Smoke Tests — WI-A2a (v4.0 lib/state.sh 신설)

WI-A2a 변경사항이 기존 동작을 깨뜨리지 않고, 새로 추가된 `lib/state.sh` 인프라가 정확히 동작하는지 수동 재현 가능한 형태로 기록.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-20
**대응 커밋**: WI-A2a 브랜치 (`refactor/WI-A2a-state-sh`)

---

## 변경 범위

1. **`templates/lib/state.sh` 신설** — 설계 §11 의사코드 구현. 8개 런타임 전역변수 파일 기반 격리
2. **`templates/flowset.sh`** — `source lib/state.sh` + shim fallback + `state_init` + `save_state()` / `restore_state()` state_get/set 전환
3. **`skills/wi/init.md`** — 템플릿 복사 블록에 `lib/state.sh` 추가

**범위 한정**: 나머지 61개 `$loop_count` 등 직접 참조는 **WI-A2b~e 각 모듈 분리 시점**에 점진 전환 예정. WI-A2a는 "인프라 + save/restore_state 연동"으로 좁힘.

**이중 기록 제거 시점**: 현 `restore_state()`는 전역변수 할당과 `state_set` 호출을 병행(이중 기록). 이는 `$var` 직접 참조 함수들(A2b~e 작업 대상)이 WI-A2a 시점에도 동작하도록 보장하는 **과도기적 타협**. **WI-A2e 완료 시점**에 61건 직접 참조가 전부 state_get으로 전환되면 이중 기록을 제거(전역변수 할당 라인 삭제 + state_set만 유지). 현 ISSUE로 인식하고 WI-A2e PR 본문에 "이중 기록 제거 체크리스트" 포함 필수.

**iteration_cost / total_context_tokens 제외 근거**: 설계 §11 line 441에 따라 이 두 변수는 `execute_claude()`의 **지역 변수**(:1662, :1667의 `local` 선언). 함수 호출 범위에서만 존재하고 세션 간 영속성 필요 없음 → `RUNTIME_STATE_KEYS`에 포함하지 않음. Smoke A2a-11이 `local` 선언 존재를 자동 검증하여 이 근거를 회귀 방지.

---

## Smoke 1~9 시나리오

`tests/run-smoke-WI-A2a.sh`에 완전한 실행 스크립트 존재. 수동 재현 시 아래 각 블록을 순차 실행.

### A2a-1 — state_init 8개 키 초기화
```bash
source templates/lib/state.sh
state_init
grep -cE "^(call_count|loop_count|consecutive_no_progress|last_git_sha|last_commit_msg|rate_limit_start|current_session_id|total_cost_usd)=" "$RUNTIME_STATE_FILE"
# 기대: 8
```

### A2a-2 — state_set / state_get 기본 동작
```bash
state_set loop_count 42
state_set current_session_id "sess-abc-123"
state_set total_cost_usd "1.23"
state_get loop_count           # 42
state_get current_session_id   # sess-abc-123
state_get total_cost_usd       # 1.23
```

### A2a-3 — newline escape (multi-line 값)
```bash
state_set last_commit_msg "첫 줄
둘째 줄"
state_get last_commit_msg
# 기대: "첫 줄 둘째 줄" (newline → 공백 정규화, 한글 보존)
```

### A2a-4 — state_snapshot 파일 생성
```bash
state_set loop_count 99
snap=$(state_snapshot)
[[ -f "$snap" ]] && grep -q "^loop_count=99$" "$snap" && echo OK
# 기대: OK
```

### A2a-5 — 값에 `=` 포함 처리
```bash
state_set last_commit_msg "fix: url=https://foo?a=b&c=d"
state_get last_commit_msg
# 기대: "fix: url=https://foo?a=b&c=d" (전체 보존, awk substr 방식)
```

### A2a-6 — Lock 연속 set 무결성 (100회)
```bash
for i in $(seq 1 100); do state_set call_count "$i"; done
state_get call_count
# 기대: 100
```

### A2a-7 — Shim fallback (lib/state.sh 없을 때)
기존 v3.x 프로젝트에서 `lib/state.sh` 없이 flowset.sh를 source하면 내부 shim이 `state_get`/`state_set`을 전역변수 래퍼로 정의. 기능 동등성 유지.

```bash
# flowset.sh:58-73의 shim 직접 정의
state_get() { local k="${1:-}"; eval "printf \"%s\" \"\${$k:-}\""; }
state_set() { local k="${1:-}" v="${2:-}"; eval "$k=\"\$v\""; }

state_set loop_count 77
state_get loop_count   # 기대: 77
```

### A2a-8 — bash -n 문법 검증
```bash
bash -n templates/flowset.sh
bash -n templates/lib/state.sh
# 기대: 둘 다 에러 없이 통과
```

### A2a-10 — 설계 §11 체크리스트: flowset.sh 변수 ↔ RUNTIME_STATE_KEYS 대조
설계 §11 line 617-620의 "이관 누락 방지 체크리스트" 자동 실행.
```bash
# flowset.sh `# State` 섹션에서 전역변수 추출
awk '/^# State$/,/^COMPLETED_FILE=/' templates/flowset.sh | grep -oE '^[a-z_]+=' | sed 's/=$//' | sort -u
# 기대: 8개 = RUNTIME_STATE_KEYS 내용과 일치
#   call_count, consecutive_no_progress, current_session_id, last_commit_msg,
#   last_git_sha, loop_count, rate_limit_start, total_cost_usd
```
상수(NO_PROGRESS_LIMIT, CONTEXT_THRESHOLD, STATE_FILE, COMPLETED_FILE)는 state 이관 대상 아니므로 비교에서 제외.

### A2a-11 — iteration_cost / total_context_tokens 제외 근거
```bash
grep -E '^\s+local\s+(iteration_cost|new_session_id\s+iteration_cost|total_context_tokens)' templates/flowset.sh
# 기대: execute_claude() 내부 `local` 선언 매칭 → 지역변수 확인
```
이 두 변수가 `local` 선언이라는 사실이 "RUNTIME_STATE_KEYS에 포함하지 않는 근거"임을 자동 검증.

### A2a-9 — WI-A1 기준선 비회귀
```bash
bash tests/test-vault-transcript.sh | grep "^ALL TESTS PASSED$"
bash tests/run-smoke-WI-A1.sh       | grep "WI-A1 ALL SMOKE PASSED"
# 기대: 두 줄 모두 매칭
```

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-A2a.sh
```

**예상 출력 요약**:
```
  Smoke Total: 13
  PASS: 13
  FAIL: 0
  ✅ WI-A2a ALL SMOKE PASSED
```

- A2a-1: 1 assertion (state_init 8개 키 초기화)
- A2a-2: 1 assertion (set/get 기본)
- A2a-3: 1 assertion (newline escape)
- A2a-4: 1 assertion (snapshot 파일 생성)
- A2a-5: 1 assertion (`=` 포함 값)
- A2a-6: 1 assertion (100회 연속 set)
- A2a-7: 1 assertion (shim fallback)
- A2a-8: 2 assertion (flowset.sh + state.sh bash -n)
- A2a-9: 2 assertion (WI-A1 기준선 비회귀)
- A2a-10: 1 assertion (설계 §11 체크리스트: 변수 ↔ KEYS 대조)
- A2a-11: 1 assertion (iteration_cost 지역변수 근거)
- **합계: 13 assertion**

`exit 1` 반환 시 WI-A2a 회귀. `exit 0`이 릴리즈 조건.

이 문서는 WI-A2a 회귀 감지용 기준선. 후속 WI-A2b~e(preflight/worker/merge/vault lib 분리)가 WI-A1+WI-A2a 기준선을 깨뜨리지 않는지 매 릴리즈 전 `run-smoke-WI-A2a.sh`로 확인.

**WI-A3(bats 테스트)에서 정식 회귀 테스트로 변환 예정.**
