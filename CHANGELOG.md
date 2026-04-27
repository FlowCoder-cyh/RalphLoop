# Changelog

## [v4.0.3] - 2026-04-27

**학습 37 일반화 — flowset.sh + lib/merge.sh + task-completed-eval.sh 영숫자 WI ID 통일 (WI-E3-ci)**

`v4.0.2` evaluator 회의적 검증에서 **POINT-NEW 3건 → 실제 8개 위치** 발굴. FlowSet 자체는 영문 ID(`WI-E1-ci`/`WI-A2a-feat`/`WI-C3code-fix`) 동작하면서 다운스트림에 배포되는 templates의 8개 위치가 영숫자 미지원 → 다운스트림 영숫자 WI 사용 시 silent fail. WI-E2가 commit-check 영역만 fix하고 잔존시킨 자기참조 결함 일괄 해소.

### Layer 1 — `templates/flowset.sh` 5개 위치 영숫자 ID + 서브넘버링 통일
- L262: `recover_completed_from_history()` prefix 추출 — `WI-[0-9]+` → `WI-[0-9A-Za-z]+(-[0-9]+)?`
- L271: git log 추출 정규식 동일 통일
- L371: PR rebase 실패 시 wi_prefix 추출 통일
- L467: `validate_post_iteration()` 정규식 + **`PATTERN_REVERT` 추가** (Revert 커밋 violation 방지)
- L932: domain 추출 sed → `sed -E` ERE + 영숫자 패턴

### Layer 2 — `templates/lib/merge.sh` 2개 위치 영숫자 ID 통일
- L161: 머지 추적 `wi_num` — `WI-[0-9]+` → `WI-[0-9A-Za-z]+`
- L445: regression issue 주입 `wi_num` 통일

### Layer 3 — `templates/.flowset/scripts/task-completed-eval.sh:20` 영숫자 ID + 서브넘버링
- 기존: `WI-[0-9]{3,4}` — 영숫자 WI silent skip → TaskCompleted hook 미동작
- 신규: `WI-[0-9A-Za-z]+(-[0-9]+)?` — evaluator gate 정상 발동

### Layer 4 — cross-check smoke (`tests/run-smoke-WI-E3.sh`, 36 assertion)
- 8개 위치 정규식 검증 + 잔존 `WI-[0-9]+` 차단
- 영숫자 WI commit/issue/머지 메시지 추출 시뮬레이션 (recover/wi_num/WI_NUM 6+4+5건)
- `validate_post_iteration()` bash regex 매칭 (영숫자 + 서브넘버링 + 시스템 + Merge/Revert 8건)
- domain 추출 sed -E 시뮬레이션

### Layer 5 — vault transcript PCRE + e2e JS regex 영숫자 통일 (evaluator 회의적 발굴)
- **CRITICAL** `templates/lib/vault.sh:396` PCRE — `WI-\d{3,4}(-\d+)?-\w+` → `WI-[0-9A-Za-z]+(-\d+)?-\w+` (다운스트림 vault state.md/daily.md에서 영숫자 WI 누락 차단)
- **CRITICAL** `.flowset/scripts/vault-helpers.sh:362` PCRE 동일 통일 — **루트 자기참조 결함** (FlowSet 본 저장소 vault transcript 추출에서 본인 작업(WI-E3 등) 누락 차단)
- **MEDIUM** `templates/.github/workflows/e2e.yml:90` JS regex — `/WI-\d+/` → `/WI-[0-9A-Za-z]+(-\d+)?/` (다운스트림 e2e regression issue 자동 생성에서 영숫자 WI 누락 차단)
- **LOW** `tests/test-vault-transcript.sh:141/145/154` 동일 PCRE 통일 + 영숫자 케이스 4건 추가 (35 assertion)

### Layer 6 — sentinel grep CI 게이트 (학습 38 영구 차단)
- WI-E3 smoke에 sentinel section 신설 (4 assertion):
  - `'WI-\d{3,4}'` literal (PCRE 코드 안)
  - `'WI-\d+'` literal (PCRE 코드 안)
  - `'WI-[0-9]+'` 단독 정규식
  - `'WI-[0-9]{3,4}'` 한정 정규식
- 영역: `templates/`, `.flowset/scripts/`, `.github/`, **`skills/`** (evaluator 3차 채점 반영)
- smoke 자체(WI-E2/E3 부정 케이스 포함)는 exclude
- 미래 회귀(영숫자 미지원 패턴 추가) PR CI에서 즉시 차단

### Layer 7 — evaluator 만점 채점 cleanup (9.15 → 10 도달)
- `skills/wi/start.md:736-737` 의사코드 정규식 영숫자 통일 (사용자 복붙 시 영숫자 WI silent skip 차단)
- `tests/run-smoke-WI-A4.sh:130` fixed-string 회귀 검증에 서브넘버링 그룹 `(-[0-9]+)?` 포함 (commit-check 정규식 변경 추적 정확화)
- Layer 6 sentinel 검사 영역에 `skills/` 추가 — "templates 전 영역 grep 필수" 학습 38 진정 일반화 완결

### CI 통합
- `flowset-ci.yml` smoke job: 1016 → **1070 assertion** (E3 50 + test-vault-transcript 31→35)
- 미래 회귀(template/.flowset/.github 영숫자 미지원 패턴) 즉시 차단

### 학습 37 → 38 일반화 완결
- **37**: FlowSet 자체와 templates 정규식 비일관 = 자기참조 결함
- **38** (본격 채택): "메이저 리팩토링 후 templates 전 영역 grep 필수" + sentinel CI 게이트로 영구 차단
- **self-violation 차단**: WI-E2/E3가 단계적 fix를 시도하면서 매 사이클 evaluator가 새 영역 발굴 → 본 PR이 sentinel grep으로 회귀 사이클 종결

### 주요 파일 변경
- 갱신: `templates/flowset.sh` (5건), `templates/lib/merge.sh` (2건), `templates/.flowset/scripts/task-completed-eval.sh` (1건), `templates/lib/vault.sh` (1건, Layer 5), `templates/.github/workflows/e2e.yml` (1건, Layer 5), `.flowset/scripts/vault-helpers.sh` (1건, 루트 자기참조), `tests/test-vault-transcript.sh` (4건 영숫자 케이스 추가), `.github/workflows/flowset-ci.yml`, `CHANGELOG.md`
- 신규: `tests/run-smoke-WI-E3.sh` (50 assertion) — `tests/run-smoke-WI-*.sh` 25개 누적

## [v4.0.2] - 2026-04-27

**자기참조 결함 fix — template/hook commit-check regex 통일 (WI-E2-ci)**

`v4.0.1` evaluator 2차 회의적 검증에서 **POINT-NEW-2 시스템적 결함** 발굴: FlowSet 자체는 `WI-E1-ci`/`WI-A2a-feat`/`WI-C3code-fix` 같은 영문 ID로 동작하면서, 다운스트림 프로젝트에 배포되는 `templates/.github/workflows/commit-check.yml` + `templates/.flowset/hooks/commit-msg`는 숫자만 허용하는 엄격 regex(`^WI-[0-9]{3,4}(-[0-9]+)?-(type)`)였음 → 신규 사용자가 같은 패턴 쓰면 reject. **974 assertion + evaluator 회의적 검증으로 사전 발굴된 자기참조 결함**.

### Layer 1 — template commit-check + commit-msg regex 통일
- 기존: `^WI-[0-9]{3,4}(-[0-9]+)?-(type) .+` (숫자만, FlowSet 자체와 비일관)
- 신규: `^WI-[0-9A-Za-z]+(-[0-9]+)?-(type) .+` (영숫자, 루트 `flowset-ci.yml`과 일관)
- 다운스트림 프로젝트도 `WI-A2a-feat` / `WI-C3code-fix` / `WI-E1-ci` 같은 영문 시작 ID 사용 가능
- 서브넘버링(`WI-001-1-fix`) 보존 — `(-[0-9]+)?` 그룹 유지

### Layer 2 — REQUIRED_SCRIPTS 정합 (commit-msg)
- 12개 → **14개** (`parse-gherkin.sh` + `task-completed-eval.sh` 누락 보강)
- v4.0 신규 스크립트가 다운스트림 첫 커밋 시 누락 검증 통과하도록

### Layer 3 — PATTERN_REVERT 추가 (commit-msg + commit-check.yml)
- GitHub auto-Revert PR 머지 시 commit-msg reject 차단
- Merge / Revert 자동 skip 일관 처리

### Layer 4 — cross-check smoke (`tests/run-smoke-WI-E2.sh`, 42 assertion)
- 3곳 정규식 정합성 동적 검증 (root flowset-ci.yml ↔ template commit-check.yml ↔ template commit-msg)
- 영숫자 ID 매칭 (실 사용 케이스 6개)
- 서브넘버링 매칭 (3개)
- 부정 케이스 reject (5개)
- 시스템 커밋 + Merge/Revert auto-skip
- REQUIRED_SCRIPTS ↔ 실제 디렉토리 카운트 + 각 파일명 정합
- **root ↔ template 서브넘버링 양방향 정합** (evaluator POINT-MISSED 사전 발굴)

### Layer 5 — root flowset-ci.yml 서브넘버링 그룹 동시 fix (evaluator 발굴)
- 기존: `^(WI-[0-9A-Za-z]+-(type) .+|...)` — 서브넘버링 미지원 (templates와 비대칭)
- 신규: `^(WI-[0-9A-Za-z]+(-[0-9]+)?-(type) .+|...)` — `WI-001-1-fix` 형식 매칭
- evaluator 회의적 검증으로 사전 발굴: PR #47이 templates 영역만 fix하고 root에 동일 결함 잔존시 `WI-001-1-fix` 머지 시점 즉시 user-visible 회귀
- 학습 37 일반화 — "templates ↔ root 양방향 cross-check 의무"

### CI 통합
- `flowset-ci.yml` smoke job: 974 → **1016 assertion** (E2 42 신규, 서브넘버링 cross-check +3)

### 학습 패턴 (37개, +1)
- **37**: FlowSet 자체와 templates의 정규식/스크립트 카운트 비일관 = 자기참조 결함. 메이저 리팩토링 후 templates도 같은 evolution 적용 의무. cross-check smoke로 영구 차단

### 주요 파일 변경
- 갱신: `templates/.github/workflows/commit-check.yml`, `templates/.flowset/hooks/commit-msg`, `.github/workflows/flowset-ci.yml`, `CHANGELOG.md`
- 신규: `tests/run-smoke-WI-E2.sh` — `tests/run-smoke-WI-*.sh` 24개 누적 (v4.0.0 23개 → v4.0.2 +1)

## [v4.0.1] - 2026-04-27

**CI/CD 자동화 — CHANGELOG-driven release + README cross-check smoke (WI-E1-ci)**

`v4.0.0` 발행 직후 학습 — 릴리즈 발행과 README 정합성을 수동으로 유지하지 않도록 자동화. v3.0~v4.0 사이 GitHub Release가 v2.1.0에서 멈춰있던 문제 + WI-D3에서 발견된 README 누락 7건이 PR 머지 후에야 드러난 문제를 동시 해소.

### Layer 1 — Release 자동 발행 (`.github/workflows/release.yml`)
- 트리거: `main` push에 `CHANGELOG.md` 변경 포함 시
- 로직: CHANGELOG 최상단 `## [vX.Y.Z]` 헤더 추출 → 해당 tag/release 미존재 시 자동 발행
- idempotent: tag/release 둘 다 있으면 skip, 부분만 있으면 누락 부분만 생성
- 섹션 추출: `grep -F` (literal) + `sed` line-number 기반 (학습 36 — awk dynamic regex의 char-class 오해석 회피)
- 빈 노트 방어 + 헤더 라인 자동 제목화 (`**...**` 추출 → `vX.Y.Z — ...` 형식)
- `concurrency` 제어: 같은 ref에서 release job 1개만 실행 (race 방지)

### Layer 2 — README cross-check smoke (`tests/run-smoke-readme-sync.sh`, 63 assertion)
- 학습 34 (메타-건전성) 적용: hardcode 카운트 없이 실제 디렉토리 ↔ README 표기 동적 비교
- 검증 영역:
  1. `templates/.flowset/scripts/` — 카운트 + 14개 파일명 README 등장
  2. `templates/.flowset/contracts/` — 카운트 + 5개 파일명 등장
  3. `templates/lib/` — 5개 모듈 등장
  4. `skills/wi/` — 7개 명령 + `/wi:NAME` 표기
  5. `templates/.claude/agents/` — 2개
  6. `templates/.claude/rules/` — 3개
  7. `templates/.flowset/guides/` — 2개
  8. `templates/.github/workflows/` — 3개 (ci/commit-check/e2e)
  9. `templates/.flowset/hooks/` — 2개 (commit-msg/pre-push)
  10. `templates/.claude/settings.json` 6종 hook (SessionStart/PostCompact/PreToolUse/PostToolUse/TaskCompleted/Stop) → README 표기 검증 (WI-v4int 같은 settings.json 결함 재발 차단)
  11. `spec/matrix.json` + `reviews/` + `approvals/` 트리 표기
  12. v3.x 잔재 차단 (`flowset.sh # ... (v3.x)` 형식 등장 시 fail)
  13. README 현재 버전 표기 vs CHANGELOG 최상단 버전 정합

### Layer 1.5 — release.yml dry-run smoke (`tests/run-smoke-release-yml.sh`, 13 assertion)
- release.yml은 `main` push에만 trigger되어 PR CI에서 동작 검증 안 됨 → 머지 후 첫 동작이 production
- 이 smoke가 release.yml과 동일 추출 로직을 로컬에서 dry-run하여 사전 차단
- v4.0.0 / v4.0.1 / v3.x 모든 헤더에 대해 추출 동작 검증 + 존재하지 않는 버전 → 빈 출력 방어 검증
- release.yml 자체 정합성 검증 (grep -F 기반, concurrency, permissions, trigger paths)

### CI 통합
- `flowset-ci.yml` smoke job: 895 → **974 assertion** (readme-sync 63 + release-yml 13 + WI-D1 99→102 갱신)
- 새 PR이 v4.0 산출물 추가/변경 시 README/settings.json/workflows/hooks 등에 반영하지 않으면 자동 차단 (WI-D3·WI-v4int 같은 누락 사전 차단)

### 학습 패턴 (36개, +2)
- **35**: 자동화 3-layer는 CHANGELOG.md를 SSOT로 통일 — release notes / 버전 정합 / README cross-check 모두 CHANGELOG 최상단을 단일 진실로 참조
- **36**: awk dynamic regex (`"^## \\[" v "\\]"`)는 char-class로 오해석 — 4 backslash 보강도 환경/컨텍스트에 silent fail 가능. `grep -F` (literal) + `sed` line-number 기반으로 escape 의존성 완전 제거가 안전 (evaluator 회의적 검증으로 사전 발굴)

### 주요 파일 변경
- 신규: `.github/workflows/release.yml`, `tests/run-smoke-readme-sync.sh`, `tests/run-smoke-release-yml.sh`
- 갱신: `.github/workflows/flowset-ci.yml` (smoke 974 + readme-sync + release-yml 호출 추가)

## [v4.0.0] - 2026-04-27

**매트릭스 기반 검증 게이트웨이 + 4-class 시스템 (code/content/hybrid/visual)**

23 WI 머지 (Group α/β/γ/δ + WI-001) + 사전 정비 1건(WI-001-fix) + 통합 fix 1건(WI-v4int-fix) = **25 PR** — 코드 프로젝트뿐 아니라 **content 프로젝트(문서·연구·기획)** 도 동일 워크플로우로 자동화.

### Group α (shell 품질, 8 WI)
- **WI-A1**: jq 전환 + `set -euo pipefail` 통일 (전체 22 shell)
- **WI-A2a**: `lib/state.sh` 모듈 분리 (8개 전역변수 이관, flock/mkdir 양쪽 지원)
- **WI-A2b**: `lib/preflight.sh` 모듈 분리 (`flowset.sh:385-508` 이관)
- **WI-A2c**: `lib/worker.sh` 모듈 분리 (`execute_claude()` + 관련 함수)
- **WI-A2d**: `lib/merge.sh` 모듈 분리 (`wait_for_merge` + `wait_for_batch_merge` + `inject_regression_wis`)
- **WI-A2e**: `lib/vault.sh` 모듈 분리 (vault-helpers.sh 통합)
- **WI-A3**: bats-core 핵심 테스트 16 @test (state, vault-helpers shim)
- **WI-A4**: FlowSet 자체 CI (`shellcheck` + `bats` + `bash smoke` + `commit-check`)

### WI-001 (게이트웨이)
- **WI-001**: `.flowsetrc`에 `PROJECT_CLASS` 필드 신설 (기본값 `code`, 후속 모든 class 분기 잠금 해제)

### Group β (class 분기, 3 WI)
- **WI-B1**: `/wi:init` content/hybrid 분기 — CI/PR/hook/ownership 선택적 적용, `mkdir -p .flowset/reviews .flowset/approvals` 포함
- **WI-B2**: `/wi:start` 3모드 분기 (Phase 6 재구성: 루프/대화형/팀)
- **WI-B3**: contracts class별 템플릿 — `style-guide.md` + `review-rubric.md` 신설

### Group γ (매트릭스 SSOT, 9 WI)
- **WI-C1**: `/wi:prd` Step 2.5 Role 추출 + 매트릭스 셀 의무 + `prd-state.json` v2 확장 (entities/roles/crud_matrix/permission_matrix)
- **WI-C2**: `sprint-template.md` CRUD/Section 매트릭스 + Gherkin 강제 (자유 텍스트 금지)
- **WI-C3-parse**: `parse-gherkin.sh` 신설 (cucumber CLI 미설치 환경 fallback, JSON 출력 계약)
- **WI-C3-code**: `stop-rag-check.sh` 섹션 6/7/8 신설 — **B2/B3/B4 차단**
  - B2: `src/api/**` 변경 시 `auth_patterns[]` grep, 매칭 실패 → block
  - B3: 같은 interface/type 다른 파일 2개+ → block
  - B4: Gherkin 시나리오 ↔ tests 개수 + 이름 부분 매칭, 실패 → block
- **WI-C3code-fix**: WI-C3-code 평가자 [MEDIUM/LOW] 즉시 해소 — `decision JSON jq -nc --arg` 의무 (학습 32 도출) + 학습 31 누락 4곳 보강
- **WI-C3-content**: `stop-rag-check.sh` 섹션 9/10 신설 — **B6/B7 차단**
  - B6: `matrix.sections[].sources[]` 파일 존재 + URL 형식 검증
  - B7: `completeness_checklist` 항목이 변경된 content 파일 본문에 등장 (paths 매핑 옵션)
- **WI-C4**: `evaluator.md` v3.3 → v4.0 — **type=content/hybrid 신설** + cell_coverage/scenario_coverage 채점 축
- **WI-C5**: `verify-requirements.sh` 매트릭스 대조 (git diff ↔ matrix.json 셀, class별 분기)
- **WI-C6**: `session-start-vault.sh` 미완 셀 우선 주입 (B5)

### Group δ (문서, 2 WI)
- **WI-D1**: `templates/CLAUDE.md` 핵심 규칙 → 4-class 분화 (code/content/hybrid) + 9번 "증거 기반 완료 보고" 신설 + 자동 강제 class별 분기. `README.md` v4.0 PROJECT_CLASS 시스템 표 + B1~B7 차단 매핑 + Stop hook §6/7/8/9/10
- **WI-D2**: 본 CHANGELOG v4.0 항목

### 통합 무결성 (1 fix)
- **WI-v4int-fix** (PR #44): 통합 평가에서 발견된 hook chain 결함 7건 즉시 해소 (학습 34 도출). 분리 평가 23/23 10.00이었으나 통합 평가 5.20 FAIL → fix 후 10.00 회복.
  - [CRITICAL-1] `templates/.claude/settings.json` Stop hook에 `stop-rag-check.sh` 미등록 → B2~B7 차단 무력화 회복
  - [CRITICAL-2] `verify-requirements.sh`의 `verify_output || true` 마스킹 패턴 제거 → B1 stop hook 경로 복원
  - [MEDIUM-3/4/5] sprint-template B 정의 충돌 + README B5 누락 + 학습 31 누락 4곳 보강
  - [LOW-6/7] evaluator null guard + CHANGELOG 카운트 자기참조 cross-check
  - **재발 방지**: smoke가 settings.json ↔ 실재 파일, `_emit_missing_*` SSOT 일관, masking 패턴 cross-check를 영구 차단

### Stop hook 자동 차단 (B1~B7)

| ID | 차단 대상 | hook 위치 | 영역 |
|----|----------|---------|------|
| B1 | `matrix.status` 미완 셀 | evaluator FAIL | code/content |
| B2 | `auth_patterns[]` 매칭 실패 | stop-rag-check.sh §7 | code |
| B3 | 같은 interface/type 다른 파일 2개+ | stop-rag-check.sh §6 | code |
| B4 | Gherkin↔테스트 개수/이름 매핑 실패 | stop-rag-check.sh §8 | code |
| B5 | 미완 셀 우선 주입 | session-start-vault.sh | code/content |
| B6 | `matrix.sections[].sources[]` 깨진 파일/URL | stop-rag-check.sh §9 | content |
| B7 | `completeness_checklist` 본문 미등장 | stop-rag-check.sh §10 | content |

### evaluator 4-class 채점 (WI-C4)

- **type: code**: 기능+cell_coverage / 코드품질 / 테스트+scenario_coverage / 계약+auth_patterns
- **type: content** (신설): 완결성+cell_coverage / 출처무결성 / 리뷰증적 / 형식일관성
- **type: hybrid** (신설): code 영역 + content 영역 변경량(line) 가중 평균 또는 strict mode (`coverage_mode: strict`)
- **type: 비주얼** (legacy 보존)

### 누적 학습 패턴 (34개)

본 v4.0 사이클에서 도출된 신규 패턴 (이전 29개 + 본 사이클 +5):

- **30**: bash heredoc backslash escape 함정 — `cat -A` 또는 `awk | tr -d -c '\\' | wc -c`로 검증
- **31**: Windows jq.exe stdout CRLF — 모든 `jq -r` 결과에 `| tr -d '\r'` 의무 (SSOT 패턴)
- **32**: decision JSON은 `jq -nc --arg` 의무 — `printf+sed` escape 회귀 차단
- **33**: 헬퍼 함수 분리 시 `verify-requirements.sh`의 `_underscore_prefix` + `local _x="$1"` + `while IFS= read` 컨벤션 차용
- **34**: 분리 평가 ≠ 통합 검증 — 메이저 리팩토링 마무리 시 통합 평가 별도 사이클 필수 (cross-WI hook chain 결함은 분리 평가가 못 잡음)

### 마이그레이션 (v3.x → v4.0)

기존 프로젝트는 **자동 덮어쓰기 금지** — 사용자 커스터마이징 보존:

1. **`.flowsetrc`**: `PROJECT_CLASS=code` 기본값 → 기존 동작 그대로 (jq 의존성만 추가 — `install.sh`가 자동 안내)
2. **`prd-state.json`**: `migrate_prd_state_v1_to_v2()` idempotent 자동 실행 (`/wi:prd` Step 0)
3. **`stop-rag-check.sh`**: `HAS_MATRIX` 플래그 — `matrix.json` 부재 시 신규 섹션 6~10 모두 skip → 기존 프로젝트 무영향
4. **`CLAUDE.md`**: 수동 업그레이드 권장 — 기존 `## 핵심 규칙`은 그대로 유지(암묵적 code class 해석), 신규 `/wi:init` 시에만 4-class 분화 적용
5. **`team-roles.md`**: `class` 필드 없어도 `check-ownership.sh`는 paths 매칭만 수행 → 기존 동작 그대로
6. **기존 `sprint-{NNN}.md`**: `type: code (legacy)` 플래그로 evaluator가 구버전 채점 (Gherkin 강제 안 함)

### CI

- smoke: 126 → **895 assertion** (20개 그룹 — A1/A2a~e/A3/A4/001/B1~B3/C1/C2/C3p/C3code/C3content/C4/C5/C6/D1/D2/v4int)
- bats: 16 @test
- shellcheck severity=warning 전체 .sh 통과
- commit-check: `WI-NNN-[type] 한글 작업명` 정규식 (영숫자 포함 허용 — WI-A2a, WI-C3code 등)

### 의존성 (신규)
- **jq**: 필수 (matrix.json 처리, parse-gherkin.sh JSON 출력, evaluator coverage 산출)
- **shellcheck**: 개발용 (CI에서 자동 검증)
- **bats**: 개발용 (CI에서 자동 검증, submodule 관리)
- **cucumber CLI**: 옵션 (npm 환경에서 1순위, 미설치 시 `parse-gherkin.sh` fallback)

### 주요 파일 변경
- 신규: `templates/.flowset/spec/matrix.json` (SSOT 스키마), `parse-gherkin.sh`, `verify-requirements.sh` (매트릭스 대조), `templates/lib/state.sh` + 4 모듈 (preflight/worker/merge/vault), `templates/.flowset/contracts/style-guide.md` + `review-rubric.md`, `tests/bats_tests/core.bats`, `tests/run-smoke-WI-*.sh` 23개, `.github/workflows/flowset-ci.yml`
- 확장: `templates/.claude/agents/evaluator.md` (186→371줄, 4-class), `templates/CLAUDE.md` (48→97줄, class 분화), `templates/.flowset/scripts/stop-rag-check.sh` (155→434줄, 섹션 6~10 + 통합 fix), `session-start-vault.sh` (130→229줄, 미완 셀 주입 + 학습 31)

## [v3.4.0] - 2026-04-03

### 토큰 최적화 — vault 누적 방지 + rules 경량화
- `vault-helpers.sh`: state.md Last Activity를 응답 원문 300자 → `sessions/{날짜}-daily.md 참조` 포인터로 변경
- `session-start-vault.sh`: 세션 로그 자동 주입 제거 (토큰 누적 방지, 필요 시 on-demand 읽기)
- `flowset-operations.md`: rules → guides 분리 (6.1KB → 1.0KB, 상세는 `flowset-operations-guide.md`)
- `flowset-operations-guide.md`: v3.0 기능 개요, completed_wis.txt SSOT, 루프 실행, E2E 테스트 품질 기준 (코드 예시 포함)
- PostCompact hook 추가 (autoCompact 후 vault 컨텍스트 복원)
- 글로벌 `inject-knowledge.sh` 레거시 제거 → 프로젝트별 hook 이관
- `vibe-extras` 서드파티 플러그인 제거 (스킬 8개 + 에이전트 3개 매 메시지 로드 제거)
- ComfyUI MCP 글로벌 → 프로젝트별 설치로 전환

### transcript 기반 vault 저장 (v3.4 초기)
- `stop-vault-sync.sh`: transcript_path에서 커밋/PR/도구 호출 수 기계적 추출
- `vault-helpers.sh`: `vault_extract_transcript()`, `vault_build_transcript_summary()`, `vault_build_state_content()` 추가
- state.md: 구조화된 Commits/PRs/Changed Files 섹션
- daily.md: 세션별 branch + commits + tool calls 요약
- rules에서 memory 파일 5개 제거 (mem-lessons, mem-project, mem-reference → auto memory로 이관)

## [v3.3.0] - 2026-04-02

### evaluator 채점 정밀화 (8.8 → 9.0+)
- `evaluator.md`: few-shot 캘리브레이션 예시 추가, 안티패턴 감점 항목 세분화
- 리드 오인식 버그 수정: 소유권 hook이 리드를 팀원으로 오판하는 문제 해결
- `check-ownership.sh`: 리드/evaluator 역할 식별 로직 보강

### 팀 관련 수정
- `resolve-team.sh`: PID 필터링 + 빈 파일 skip + mtime 기반 최신 등록 우선
- 팀 등록 키를 PID → 팀명으로 변경 (구조적 결함 수정)
- `lead-workflow.md`: TeamCreate → Agent(team_name) 순서 명시, 팀 등록 명령 필수 포함

### 세션 로그 폭증 방지
- `vault_save_daily_session_log()`: 하루 1파일에 append (세션별 파일 생성 → 일별 통합)

### 템플릿 감사 12건 수정
- lead-workflow, evaluator, team-worker 간 참조 정합성 교정

## [v3.0.0] - 2026-03-23

### Obsidian Vault 통합
- `vault-helpers.sh`: Obsidian Local REST API 연동 (읽기/쓰기/검색)
- `flowset.sh`: save_state()에서 vault state.md 자동 동기화
- `flowset.sh`: preflight()에서 vault 연결 확인 + graceful degradation
- `flowset.sh`: build_rag_context()에서 vault 시맨틱 검색 추가 (이전 세션 지식)
- `flowset.sh`: record_pattern()에서 vault에 패턴 기록
- `stop-rag-check.sh`: 세션 종료 시 vault에 변경사항 기록
- `.flowsetrc`: VAULT_ENABLED, VAULT_URL, VAULT_API_KEY, VAULT_PROJECT_NAME 추가
- VAULT_ENABLED=false 기본값 — v2.x 호환, vault 없이도 동작

### 소유권 기반 파일 수정 제한
- `check-ownership.sh`: PreToolUse hook (Edit|Write 매칭)
- `ownership.json`: 팀별 소유 디렉토리 매핑 템플릿
- TEAM_NAME 미설정 시 무동작 (solo 모드 호환)
- hotfix/ 브랜치에서 소유권 제한 완화
- settings.json: PreToolUse + Stop hook 구성

### 계약 기반 팀 간 소통
- `.flowset/contracts/api-standard.md`: API 응답 형식, HTTP 상태 코드, 변경 규칙
- `.flowset/contracts/data-flow.md`: SSOT 엔드포인트, 팀 간 데이터 공유 규칙

### Agent Teams 템플릿
- `.claude/agents/lead-workflow.md`: 리드 5단계 워크플로우 (요구사항→복잡도→태스크→spawn→통합)
- `.claude/agents/spawn-template.md`: 팀원 초기화 절차
- `.claude/agents/team-roles.md`: 5개 기본 역할 (frontend/backend/qa/devops/planning)
- Agent Teams 없이도 전체 시스템 동작 — 선택적 활성화

### 스킬 업데이트
- `wi:init`: vault-helpers, check-ownership, ownership.json, contracts, agents 복사 추가
- `wi:start`: Phase 4.7 Vault 연동 설정 추가

### SessionStart hook + 컨텍스트 자동 주입
- `session-start-vault.sh`: startup/resume/clear/compact 모두에서 vault state.md 주입
- PostCompact은 additionalContext 미지원 (공식 스펙) → SessionStart(source:compact)가 대체

### 팀간 리뷰 차단 (PreToolUse)
- `check-cross-team-impact.sh`: contracts/, prisma/schema, requirements.md 변경 시 차단
- devops/planning 팀은 허용 (알림만), 일반 팀원은 리드 경유 필수

### 기술부채 관리
- `.flowset/tech-debt.md`: 부채 등록 템플릿 (P0/P1/P2 우선순위)
- `vault-helpers.sh`: vault_check_tech_debt() 임계치 경고
- `flowset.sh`: preflight에서 open 부채 10건 초과 시 경고

### 롤백/복구
- `rollback.sh`: code (git revert → PR), db (prisma migrate resolve), deploy (vercel rollback)
- 롤백도 정상 PR 프로세스 유지 (hotfix 제외)

### 계약 변경 알림 (PostToolUse)
- `notify-contract-change.sh`: contracts/ 변경 시 관련 팀 알림

### Agent 정의 공식 스펙 준수
- `lead-workflow.md`: name 필드, disallowedTools 적용
- `spawn-template.md` → `team-worker.md`: 정식 서브에이전트
- `team-roles.md`: agents/ → rules/ 이동 (참조 문서)

### Vault 연동 범용화 (루프/대화형/팀 전체)
- `vault_detect_mode()`: loop_state.json mtime 기반 루프 감지, TEAM_NAME 팀 감지, 나머지 대화형
- `vault_sync_state()`: 5인자(루프) 하위 호환 + 7인자(범용) 확장
- `vault_save_session_log()`: sessions/{timestamp}.md에 세션 작업 로그 저장 (전 모드)
- `vault_read_latest_session()`: 시맨틱 검색으로 최근 세션 로그 읽기
- `vault_sync_team_state()`/`vault_read_team_state()`: teams/{team}.md CRUD
- `session-start-vault.sh` 전면 재작성: state.md + 최근 세션 + 팀 state + resume 이슈
- `stop-rag-check.sh` vault 섹션 교체: `last_assistant_message` 처음 500자로 세션 요약 저장
- 루프 모드 Stop hook은 state.md skip (flowset.sh가 관리)
- `resolve-team.sh`: TEAM_NAME 해소 (환경변수 → .flowset/teams/{session_id}.team 폴백)

### RalphLoop → FlowSet 리네임
- 디렉토리: .ralph/ → .flowset/, 파일: ralph.sh → flowset.sh, .ralphrc → .flowsetrc
- 변수: RALPH_VERSION → FLOWSET_VERSION, RALPH_STATUS → FLOWSET_STATUS
- 전체 410건 치환, 잔여 0건

### 설계 원칙
- VAULT_ENABLED=true 기본값 (Obsidian 미설치 시 graceful degradation)
- TEAM_NAME 미설정 시 소유권/계약 hook 무동작 (solo 모드 호환)
- vault 연결 실패 시 파일 기반 RAG 폴백
- flowset.sh 메인 루프(Section 9) 구조 변경 없음
- 리드/팀원 모델 전부 opus 고정

---

## [v2.2.0] - 2026-03-21

### 머지 대기 — stale base 완전 제거
- `enqueue-pr.sh --wait`: PR 머지 완료까지 15초 간격 폴링 (timeout 15분)
- Exit codes: 0=머지완료, 1=CI실패/PR닫힘, 2=timeout
- flowset.sh 순차 모드: `wait_for_merge()` — 워커 종료 후 머지 대기 → safe_sync_main
- flowset.sh 병렬 모드: `wait_for_batch_merge()` — batch 전체 머지 대기 → safe_sync_main
- PROMPT.md: 워커 CI 폴링 제거 — 머지 대기는 flowset.sh가 관리 (워커 턴 12~30% 절약)

### 와이어프레임 필수
- `/wi:prd` Step 3.5: HTML 와이어프레임 생성 (스킵 불가)
- data-testid 속성 필수 (E2E 셀렉터 기준)
- wireframes/{page}.html 저장, 사용자 피드백 → 확정
- PROMPT.md/AGENT.md: 와이어프레임 참조 규칙

### RAG 강제 매커니즘
- Stop hook (`stop-rag-check.sh`): 파일 변경 시 RAG 업데이트 자동 알림
- `.claude/settings.json`: Stop hook 등록
- flowset.sh `validate_post_iteration`: API/페이지/스키마 변경 시 RAG 미업데이트 감지
- `/wi:start` Phase 4.5: RAG 초기화 (PRD 도메인별 RAG 파일 + rag-context.md 자동 생성)

### 아키텍처 계약
- `/wi:start` Phase 4.6: `.flowset/contracts/` 자동 생성
  - `api-standard.md`: API 응답/에러 형식 표준
  - `data-flow.md`: 모델별 SSOT + 역할별 접근 경로
- PROMPT.md/AGENT.md: contracts/ 참조 규칙

### 검증 강화 (validate_post_iteration 확장)
- scope creep 감지 (변경 파일 10개 초과)
- 금지 파일 수정 감지 (.env, package-lock)
- 빈 구현 감지 (TODO/placeholder/stub)
- API 형식 검증 (contracts/ 존재 시)
- WI 수용 기준 자동 검증 (GET/POST 핸들러 매칭)
- requirements.md 수정 차단 + 자동 복원

### FLOWSET_STATUS 확장
- FILES_LIST, TESTS_ADDED, TESTS_TOTAL 필드 추가
- TESTS_ADDED=0 시 TDD 미수행 경고

### trace 구조화
- `log_trace()`: `.flowset/logs/trace.jsonl` (JSON Lines, 200건 rotation)
- iteration별: wi, result, files, elapsed, cost 기록

### 사용자 원본 요구사항 보호
- `/wi:prd` Step 6: `.flowset/requirements.md` 자동 생성 (사용자 원본 고정)
- 에이전트 수정 금지 — validate에서 변경 감지 시 위반 처리 + 자동 복원
- flowset-operations.md Section 0: requirements.md 수정 절대 금지

### 검증 에이전트 분리
- `verify-requirements.sh`: 별도 `claude -p` 실행 (Read/Grep/Glob만 허용)
- requirements.md vs git diff 대조 → 누락/불완전/미구현 판정
- flowset.sh 순차/병렬 모드: validate 후 자동 실행
- Stop hook: 소스 3파일+ 변경 시 자동 트리거

### E2E 테스트 품질 강제
- flowset-operations.md Section 7.1: E2E 품질 기준
  - 필수: page.goto + click/fill + data-testid
  - 금지: request.get/post (seed/setup 제외)
- Stop hook: E2E 파일에 API shortcut / UI 미사용 감지 → 경고

### 템플릿 강화
- CLAUDE.md: 핵심 규칙 8개 + 자동 강제 항목 명시
- project.md: 코드 품질 체크리스트 (경계분리/모듈화/캡슐화/재사용/하드코딩 금지)
- flowset-operations.md: v2.2.0 운영 규칙 (머지 대기, RAG, requirements 보호)

### 신규 파일
- `verify-requirements.sh`: 검증 전용 에이전트 스크립트
- `stop-rag-check.sh`: Stop hook (RAG + E2E + requirements + 검증 에이전트 트리거)
- `.claude/settings.json`: Stop hook 등록

---

## [v2.1.0] - 2026-03-16

### 워커 CRUD 강제
- `/wi:env` 후 DB 연결 확인되면 AGENT.md에 "mock 금지" 자동 주입
- PROMPT.md: Prisma 존재 시 하드코딩/mock 데이터 사용 금지 규칙 추가
- `/wi:prd`: DB 기술 스택 있으면 WI 설명에 `(Prisma {모델} CRUD)` 자동 명시
- `/wi:start` Phase 4-1: Prisma 스키마 감지 → DB 연결 테스트 → 조건부 주입
- 3중 방어: WI 설명 + AGENT.md + PROMPT.md (하나 무시해도 나머지에서 잡힘)
- DB 연결 실패 시 mock 금지 미주입 (기존 동작 유지, 장점 상쇄 방지)

### E2E 테스트 워커 작성 금지
- PROMPT.md: Step 3 "WI 유형 판별" 추가 — E2E WI는 스킵 + guardrails 기록
- `/wi:prd`: E2E 테스트를 WI로 포함하지 않도록 경고 추가
- `/wi:guide`: L4 규칙 테이블에 "E2E 금지" 행 추가
- `flowset-operations.md`: Section 7 "E2E 테스트 — 워커 작성 금지" 추가
- 근거: wi-test WI-088~096에서 111개 E2E 테스트 전멸 (셀렉터 추측 실패)

### enqueue-pr.sh 버그 수정
- grep 패턴 매칭 → merge queue API 존재 확인 방식으로 변경
- `gh api repos/.../rulesets`에서 merge_queue 타입 확인
- merge queue 있는데 enqueue 실패 → `--auto` (squash 없이) + 에러 메시지 출력
- merge queue 없음 → `--auto --squash` fallback (기존 동작)
- "merge queue 미지원" 오탐 문제 해결

### macOS 호환성
- flowset.sh: `sedi()` 래퍼 추가 (macOS BSD `sed -i ''` 호환)
- launch-loop.sh: macOS에서 tmux 우선 사용 (osascript fallback)
- tmux로 Claude Code 세션과 완전 독립 실행 (stdout 리다이렉트 문제 해결)

### 순차 모드 mark_wi_done 누락 수정
- 순차 모드에서 SHA 변경 시 `mark_wi_done()` 호출 추가
- 기존: `execute_parallel`에서만 호출 → 순차 모드에서 completed_wis.txt 미기록
- WI 머지 후 재실행되는 문제 해결

---

## [v2.0.0] - 2026-03-15

### 핵심 변경
- **flowset.sh v2.0.0**: 전면 리팩토링
  - fix_plan.md 읽기 전용 (루프 중 수정 금지)
  - completed_wis.txt = 단일 진실 원천 (SSOT)
  - safe_sync_main: 로컬 main에 커밋 없음 → reset --hard 안전
  - reconcile_fix_plan: 루프 종료 시 fix_plan 일괄 동기화 → 단일 PR
  - recover_completed_from_history: crash 후 git log에서 자동 복구
  - cleanup_stale_completed: PR 충돌 close 시 자동 재실행
  - resolve_conflicting_prs: 충돌 PR 자동 rebase → 실패 시 close + 재실행

### CI gate 강화
- TDD 강제 (PROMPT.md: RED → GREEN → 커밋)
- e2e.yml: 머지 후 Playwright 실행 → 실패 시 regression issue 자동 생성
- smoke 테스트: /wi:start Phase 5.5에서 도메인별 자동 생성
- WI-NNN-1 서브넘버링: regression fix WI 자동 추가

### GH Issue Regression
- CI/e2e 실패 → `gh issue create --label regression`
- inject_regression_wis: open issue → fix_plan에 WI-NNN-1-fix 추가
- closed issue → guardrails.md RAG 흡수

### Merge Queue
- 조직 계정: merge queue ruleset 자동 설정 (/wi:init)
- 개인 계정: strict: false fallback
- enqueuePullRequest GraphQL 연동
- enqueue-pr.sh 래퍼 스크립트

### 신규 스킬
- `/wi:env`: 인프라 환경 구성 (DB, 배포, Secrets 등록)

### 신규 스크립트
- `.flowset/scripts/enqueue-pr.sh`: merge queue PR 등록
- `.flowset/scripts/launch-loop.sh`: 새 터미널에서 루프 실행

### 운영 규칙
- `.claude/rules/flowset-operations.md`: 모든 세션에 자동 적용
  - fix_plan 수정 금지, enqueue-pr.sh 사용, completed_wis SSOT 등

### 도메인 분리 분석
- /wi:start에서 WI 수 + L1 도메인 분리 분석 → 병렬/순차 자동 권장

### 템플릿 복사 방식 변경
- init 스킬: flowset.sh 직접 생성 → `~/.claude/templates/flowset/`에서 복사
- 모든 프로젝트에서 동일한 v2.0.0 보장

### 기타
- commit-msg hook: WI-NNN-N-fix 서브넘버링 허용
- commit-check.yml: 동일 패턴
- pre-push hook: push 대상 ref 기반 판단 + merge queue 브랜치 예외
- .gitignore: completed_wis.txt, loop_state.json 추가
- MAX_TURNS: 25 → 40
- 429 false positive 수정 ("status":\s*429 패턴)

### 검증
- wi-test (FlowHR): 99 WI 완료, 중복 0회, fix_plan 충돌 0개
- MakeLanding: 소규모 프로젝트 테스트

---

## [v1.0.0] - 2026-03-14

### 초기 릴리즈
- FlowSet 기본 구조 (순차 + 병렬 worktree)
- RAG 시스템 (codebase-map, wi-history, patterns, guardrails)
- WI 기반 자동 개발 루프
- /wi:init, /wi:prd, /wi:start, /wi:status, /wi:guide, /wi:note 스킬
- CI/CD (lint, build, test, commit-check)
- Git hooks (commit-msg, pre-push)
