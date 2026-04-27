#!/usr/bin/env bash
set -euo pipefail

# run-smoke-readme-sync.sh — README ↔ 실제 코드 cross-check (WI-E1)
#
# 학습 34 (메타-건전성): smoke가 hardcode 카운트를 갖지 않고, 실제 디렉토리 ↔ README 표기를
# 동적으로 cross-check. v4.0 신규 산출물이 README에 반영되지 않으면 PR CI에서 자동 차단.
#
# 검증 영역:
#   1. templates/.flowset/scripts/  — 카운트 + 각 파일명 README 등장
#   2. templates/.flowset/contracts/ — 카운트 + 각 파일명 README 등장
#   3. templates/lib/                — 카운트 + 각 파일명 README 등장
#   4. skills/wi/                    — 카운트 + 각 명령 README 등장
#   5. templates/.claude/agents/     — 카운트 + 각 파일명 README 등장
#   6. templates/.claude/rules/      — 카운트 + 각 파일명 README 등장
#   7. templates/.flowset/guides/    — 각 파일명 README 등장
#
# 사용: bash tests/run-smoke-readme-sync.sh

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

README="README.md"
[[ ! -f "$README" ]] && { echo "ERROR: README.md not found"; exit 1; }

# ============================================================================
# 헬퍼: 디렉토리에서 파일명 목록 (확장자 제거 옵션) 추출
_list_basenames() {
  local dir="$1"
  local ext="$2"  # 비우면 확장자 보존, 값이 있으면 해당 확장자 제거
  local f base
  for f in "$dir"/*; do
    [[ ! -f "$f" ]] && continue
    base=$(basename "$f")
    if [[ -n "$ext" ]]; then
      echo "${base%.$ext}"
    else
      echo "$base"
    fi
  done
}

# 헬퍼: 카운트 + 파일명 cross-check
_check_dir_in_readme() {
  local label="$1"
  local dir="$2"
  local ext="$3"           # 확장자 (검증용 + basename 제거용)
  local readme_count_pattern="$4"  # README에서 카운트 추출할 정규식 (없으면 카운트 검증 skip)
  local items count

  if [[ ! -d "$dir" ]]; then
    fail "$label: 디렉토리 부재 ($dir)"
    return
  fi

  items=$(_list_basenames "$dir" "$ext")
  count=$(echo "$items" | grep -c . || true)

  # 카운트 검증 (패턴 있는 경우)
  if [[ -n "$readme_count_pattern" ]]; then
    local readme_count
    readme_count=$(grep -oE "$readme_count_pattern" "$README" | grep -oE '[0-9]+' | head -1 || echo "")
    if [[ -z "$readme_count" ]]; then
      fail "$label: README 카운트 표기 없음 (패턴: $readme_count_pattern)"
    elif [[ "$count" -eq "$readme_count" ]]; then
      pass "$label: 카운트 일치 (실제 ${count} = README ${readme_count})"
    else
      fail "$label: 카운트 불일치 (실제 ${count} ≠ README ${readme_count})"
    fi
  fi

  # 각 파일명 등장 검증
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if grep -qF "$name" "$README"; then
      pass "$label/$name README 표기"
    else
      fail "$label/$name README 미표기"
    fi
  done <<< "$items"
}

# ============================================================================
echo "=== readme-sync-1: templates/.flowset/scripts/ (운영 스크립트) ==="
_check_dir_in_readme "scripts" "templates/.flowset/scripts" "sh" '운영 스크립트 \([0-9]+개\)'

echo ""
echo "=== readme-sync-2: templates/.flowset/contracts/ (팀 간 계약) ==="
_check_dir_in_readme "contracts" "templates/.flowset/contracts" "" '팀 간 계약 \([0-9]+개\)'

echo ""
echo "=== readme-sync-3: templates/lib/ (v4.0 모듈) ==="
# lib는 README에 카운트 표기 없음 — 파일명 등장만 검증
_check_dir_in_readme "lib" "templates/lib" "" ''

echo ""
echo "=== readme-sync-4: skills/wi/ (Claude Code 명령어) ==="
# skills는 명령어 표 + 시스템 구조 트리 양쪽 등장
_check_dir_in_readme "skills/wi" "skills/wi" "" ''

# 추가: 명령어 표에 /wi:NAME 형식으로 등장하는지 검증
echo ""
echo "=== readme-sync-4b: skills/wi/ — /wi:NAME 명령 표기 ==="
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if grep -qF "/wi:$name" "$README"; then
    pass "skills/wi/$name → /wi:$name 표기"
  else
    fail "skills/wi/$name → /wi:$name 미표기"
  fi
done < <(_list_basenames "skills/wi" "md")

echo ""
echo "=== readme-sync-5: templates/.claude/agents/ (Agent Teams) ==="
_check_dir_in_readme "agents" "templates/.claude/agents" "" ''

echo ""
echo "=== readme-sync-6: templates/.claude/rules/ (운영 규칙) ==="
_check_dir_in_readme "rules" "templates/.claude/rules" "" ''

echo ""
echo "=== readme-sync-7: templates/.flowset/guides/ (가이드 문서) ==="
_check_dir_in_readme "guides" "templates/.flowset/guides" "" ''

# ============================================================================
echo ""
echo "=== readme-sync-7b: templates/.github/workflows/ (CI 워크플로우) ==="
_check_dir_in_readme "workflows" "templates/.github/workflows" "" ''

# ============================================================================
echo ""
echo "=== readme-sync-7c: templates/.flowset/hooks/ (Git hooks) ==="
_check_dir_in_readme "hooks" "templates/.flowset/hooks" "" ''

# ============================================================================
echo ""
echo "=== readme-sync-7d: templates/.claude/settings.json hook 6종 ==="
# WI-v4int 학습 — settings.json hook 등록 누락 차단 (B2~B7 무력화 방지)
settings_json="templates/.claude/settings.json"
if [[ -f "$settings_json" ]]; then
  # settings.json에 정의된 hook 이름 추출
  for hook_type in SessionStart PostCompact PreToolUse PostToolUse TaskCompleted Stop; do
    if jq -e ".hooks.${hook_type}" "$settings_json" >/dev/null 2>&1; then
      if grep -qF "$hook_type" "$README"; then
        pass "settings.json $hook_type → README 표기"
      else
        fail "settings.json $hook_type README 미표기"
      fi
    fi
  done
else
  fail "settings.json 부재 ($settings_json)"
fi

# ============================================================================
echo ""
echo "=== readme-sync-8: 매트릭스 SSOT + 신규 디렉토리 ==="

# spec/matrix.json 트리 표기
if grep -qE 'spec/.*matrix\.json|spec/$' "$README"; then
  pass "spec/matrix.json README 트리 표기"
else
  fail "spec/matrix.json README 트리 미표기"
fi

# reviews/ approvals/ (content class 동적 생성, README 표기 권장)
# 트리 노드 마커 "── " 뒤에 디렉토리명 등장 검증
for d in reviews approvals; do
  if grep -qE "── ${d}/" "$README"; then
    pass "$d/ README 트리 표기 (content class 디렉토리)"
  else
    fail "$d/ README 트리 미표기"
  fi
done

# ============================================================================
echo ""
echo "=== readme-sync-9: 버전 표기 정합성 ==="

# templates/flowset.sh 버전 표기 (트리에서 (v3.x) 잔재 차단)
if grep -qE 'flowset\.sh\s+#\s+FlowSet 엔진 \(v3\.' "$README"; then
  fail "README에 FlowSet 엔진 v3.x 잔재"
else
  pass "FlowSet 엔진 v3.x 잔재 없음"
fi

# CHANGELOG 최상단 버전이 README "v4.x (현재)" 형식과 정합
changelog_ver=$(grep -m1 -oE '^## \[v[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "")
changelog_major_minor=$(echo "$changelog_ver" | grep -oE 'v[0-9]+\.[0-9]+' | head -1 || echo "")
if [[ -n "$changelog_major_minor" ]]; then
  if grep -qE "\*\*${changelog_major_minor}.*\(현재\)\*\*" "$README"; then
    pass "README 현재 버전 표기 정합 ($changelog_major_minor — CHANGELOG 최상단과 일치)"
  else
    fail "README 현재 버전 표기 부정합 (CHANGELOG: $changelog_major_minor — README 헤더 확인)"
  fi
fi

# ============================================================================
echo ""
echo "=== 총 결과 ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"

if [[ $FAIL -eq 0 ]]; then
  echo "  ✅ readme-sync ALL SMOKE PASSED"
  exit 0
else
  echo "  ❌ readme-sync SMOKE FAILED"
  exit 1
fi
