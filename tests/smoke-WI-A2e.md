# Smoke Tests — WI-A2e (v4.0 lib/vault.sh 이관 + 이중 기록 제거)

WI-A2e 변경이 기존 동작을 깨뜨리지 않고, vault 19함수가 lib/vault.sh로 이관됨 + WI-A2a에서 약속한 이중 기록 제거가 완료됨을 검증.

**실행 환경**: jq 1.8.1, bash 5.2.37 (MSYS2 Git Bash, Windows 11)
**최초 실행일**: 2026-04-21
**대응 커밋**: WI-A2e 브랜치 (`refactor/WI-A2e-vault-sh`)

---

## 변경 범위

1. **`templates/lib/vault.sh` 신설 (452줄)** — `.flowset/scripts/vault-helpers.sh`의 19개 함수 본체 이관
2. **`templates/.flowset/scripts/vault-helpers.sh`** — shim으로 전환 (39줄). lib/vault.sh를 상대 경로 탐색 후 re-source
3. **`templates/flowset.sh`** — 4건 변경:
   - `.flowset/scripts/vault-helpers.sh` source 라인 제거 (:54-56)
   - `source lib/vault.sh` fail-fast 블록 추가 (WI-A2b/c/d와 동일)
   - **전역변수 선언 :135-146 + 이중 state_set 블록 :158-165 제거** → 단일 `state_init` + 8개 `state_set` 블록
   - **lib/state.sh shim(:64-68) 제거 → fail-fast 블록으로 전환** (WI-A2b/c/d/e 정책 일관)
4. **`templates/flowset.sh` / `templates/lib/worker.sh` / `templates/lib/merge.sh`** — 8개 RUNTIME_STATE_KEYS 직접 참조 전수 `state_get`/`state_set` 전환 (flowset.sh 약 30곳 + worker.sh 약 8곳 + merge.sh 약 5곳)
5. **`skills/wi/init.md`** — lib/ 복사 블록에 `cp lib/vault.sh` 추가

**이중 기록 제거 체크리스트** (smoke-WI-A2a.md:19 약속 이행):
- [x] flowset.sh 내 `$loop_count`/`$call_count` 등 8개 키 직접 참조 0건
- [x] flowset.sh 내 `loop_count=$((...))` 등 직접 할당 0건
- [x] lib/worker.sh / lib/merge.sh 내 동일 전환
- [x] restore_state() 내 `total_cost_usd=$prev_cost` + `state_set` 병행 → `state_set`만
- [x] 전역변수 :135-146 선언 제거 (set -u 영향 검증)
- [x] smoke A2e-8/9에 "직접 참조 0건" + "직접 할당 0건" 자동 검증 포함

**lib/state.sh shim 제거 근거**: WI-A2a 도입 당시 shim(:64-68)은 lib/state.sh 미존재 환경의 과도기 호환용이었다. WI-A2b/c/d에서 preflight/worker/merge.sh는 전부 fail-fast(`exit 1`) 적용. WI-A2e에서 lib/*.sh 전체가 전역변수 직접 참조 0건이 되었으므로 shim 폴백은 더 이상 의미가 없다. lib/vault.sh fail-fast와 함께 state.sh shim도 제거하여 5개 lib 모듈 정책 완전 일관.

---

## Smoke 1~16 시나리오

`tests/run-smoke-WI-A2e.sh`에 완전한 실행 스크립트 존재. 수동 재현 시 아래 각 블록을 순차 실행.

### A2e-1 — lib/vault.sh 존재 + 문법 (2 assertion)
```bash
test -f templates/lib/vault.sh
bash -n templates/lib/vault.sh
```

### A2e-2 — 19개 vault_* 함수 정의 이관 확인 (1 assertion)
```bash
for fn in _vault_curl vault_check vault_read vault_write vault_delete \
          vault_search vault_init_project vault_detect_mode vault_sync_state \
          vault_save_session_log vault_save_daily_session_log vault_read_latest_session \
          vault_sync_team_state vault_read_team_state vault_record vault_check_tech_debt \
          vault_extract_transcript vault_build_transcript_summary vault_build_state_content; do
  grep -qE "^${fn}\(\)" templates/lib/vault.sh || echo "MISSING: $fn"
done
# 기대: 출력 없음 (19/19 정의)
```

### A2e-3 — vault-helpers.sh shim 구조 (2 assertion)
```bash
# 본체 이관됐으므로 shim은 50줄 미만
[[ $(wc -l < templates/.flowset/scripts/vault-helpers.sh) -lt 50 ]]
# shim이 lib/vault.sh를 source
grep -qE 'source.*lib/vault\.sh' templates/.flowset/scripts/vault-helpers.sh
```

### A2e-4 — shim source 시 19함수 declare (1 assertion)
```bash
cd templates
source .flowset/scripts/vault-helpers.sh
for fn in _vault_curl vault_check ...; do declare -F "$fn" &>/dev/null || echo MISSING; done
# 기대: 누락 0
```

### A2e-5 — flowset.sh source 블록에 lib/vault.sh 포함 (1 assertion)
```bash
grep -q '^  source lib/vault.sh' templates/flowset.sh
# 기대: 매칭
```

### A2e-6 — lib/vault.sh 없을 때 fail-fast (1 assertion)
```bash
grep -q "ERROR: lib/vault.sh 없음" templates/flowset.sh
# 기대: 매칭 (WI-A2b/c/d와 동일 패턴)
```

### A2e-7 — init.md에 lib/vault.sh 복사 라인 추가 (1 assertion)
```bash
grep -qE 'cp "\$TEMPLATE_DIR/lib/vault\.sh"' skills/wi/init.md
```

### A2e-8 — [핵심] 이중 기록 제거: 8개 키 직접 참조 0건 (1 assertion)
```bash
# flowset.sh + lib/state.sh + lib/preflight.sh + lib/worker.sh + lib/merge.sh
keys='\$\{?(call_count|loop_count|consecutive_no_progress|last_git_sha|last_commit_msg|rate_limit_start|current_session_id|total_cost_usd)\}?'
for f in templates/flowset.sh templates/lib/{state,preflight,worker,merge}.sh; do
  grep -cE "$keys" "$f"
done | paste -sd+ | bc
# 기대: 0
```
**WI-A2a smoke-WI-A2a.md:19 약속 이행**. lib/vault.sh 내 `local loop_count`(파라미터)는 제외.

### A2e-9 — 전역변수 직접 할당 0건 (1 assertion)
```bash
pat='^(call_count|loop_count|consecutive_no_progress|last_git_sha|last_commit_msg|rate_limit_start|current_session_id|total_cost_usd)='
for f in templates/flowset.sh templates/lib/worker.sh templates/lib/merge.sh; do
  grep -cE "$pat" "$f"
done | paste -sd+ | bc
# 기대: 0
```

### A2e-10 — state_init 후 state_set 8개 키 초기화 (1 assertion)
```bash
for key in call_count loop_count consecutive_no_progress last_git_sha last_commit_msg rate_limit_start current_session_id total_cost_usd; do
  grep -qE "^state_set $key " templates/flowset.sh || echo MISSING: $key
done
# 기대: 출력 없음 (8/8 존재)
```

### A2e-11 — lib/state.sh shim 제거 검증 (2 assertion)
```bash
# 과거 shim 패턴 (eval 기반 state_get/set 정의) 0건
grep -cE '^  state_get\(\)\s*\{.*eval|^  state_set\(\)\s*\{.*eval' templates/flowset.sh  # 기대: 0
# fail-fast 에러 메시지 존재
grep -q "ERROR: lib/state.sh 없음" templates/flowset.sh  # 기대: 매칭
```
**근거**: WI-A2a 당시 shim은 "lib/state.sh 미존재 시 전역변수로 폴백" 과도기 호환. WI-A2e에서 전역 참조 0건 달성 후 더 이상 의미 없음. preflight/worker/merge/vault와 동일 fail-fast로 통일.

### A2e-12 — flowset.sh 라인 수 (1 assertion)
WI-A2d 후 1308 → WI-A2e 후 약 1306 (이중 기록 블록 제거 약 -22줄 + vault source 추가 +10 + 지역변수 추가 +소량). 임계치: `<= 1318` (유지 또는 감소).

### A2e-13 — bash -n 전체 shell 통과 (1 assertion)

### A2e-14 — lib/vault.sh 학습 전이 보존 (1 assertion)
sed JSON 파싱 / `((var++))` / `${arr[@]/pattern}` 0건

### A2e-15 — state.sh API 불변 (1 assertion)
state_init / state_get / state_set / state_snapshot / state_restore 5함수 존재.

### A2e-16 — 누적 비회귀 (6 assertion)
test-vault(31) + WI-A1(14) + A2a(13) + A2b(13) + A2c(15) + A2d(16) 전수 PASS

---

## 자동 실행 스크립트

```bash
bash tests/run-smoke-WI-A2e.sh
```

**예상 출력 요약**:
```
  Smoke Total: 22
  PASS: 22
  FAIL: 0
  ✅ WI-A2e ALL SMOKE PASSED
```

assertion 계수:
- A2e-1: 2 (존재 + bash -n)
- A2e-2: 1 (19함수 정의)
- A2e-3: 2 (shim 줄수 + source)
- A2e-4: 1 (shim source 후 declare)
- A2e-5: 1 (source 블록)
- A2e-6: 1 (fail-fast 메시지)
- A2e-7: 1 (init.md 복사)
- A2e-8: 1 **(이중 기록 제거 — 핵심)**
- A2e-9: 1 **(전역 할당 제거 — 핵심)**
- A2e-10: 1 (state_set 초기화)
- A2e-11: 2 (shim 제거 + fail-fast)
- A2e-12: 1 (라인 수)
- A2e-13: 1 (bash -n 전체)
- A2e-14: 1 (학습 전이)
- A2e-15: 1 (state API 불변)
- A2e-16: 6 (비회귀 × 6파일)
- **합계: 24 assertion**

`exit 1` 반환 시 WI-A2e 회귀. `exit 0`이 릴리즈 조건.

---

## 후속 WI 연계

- **WI-A3 (bats-core 테스트)**: run-smoke-WI-A* 6개 파일(71 + test-vault 31 = 102 assertion + A2e 24 = **126 assertion**)을 bats로 정식 변환. 현재 bash 기반 smoke는 A3에서 단계적 폐기.
- **WI-A4 (FlowSet 자체 CI)**: shellcheck + bats on CI. WI-A2e에서 도달한 lib/*.sh 5개 모듈 + 전역 참조 0건 구조가 CI 테스트 대상.

## 이 smoke의 역할 (후속 WI에서 깨뜨리지 말아야 할 것)

| 검증 대상 | 회귀 시 차단 시점 |
|----------|-----------------|
| lib/vault.sh 19함수 정의 | 함수 삭제·rename 시 A2e-2 실패 |
| vault-helpers.sh shim 구조 | shim 경로 재작성 시 A2e-3/4 실패 |
| 이중 기록 0건 | 누군가 `$loop_count` 직접 참조 재도입 시 A2e-8 실패 |
| 전역변수 shim 0건 | state.sh fail-fast 정책 위반 시 A2e-11 실패 |
| state.sh 5 API | state 공개 API 변경 시 A2e-15 실패 |

`WI-A3(bats)`에서 정식 회귀 테스트로 변환 예정.
