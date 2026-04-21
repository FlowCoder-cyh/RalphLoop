#!/usr/bin/env bash
set -euo pipefail

#==============================
# WI System Installer
# 다른 환경에서 동일한 wi:* 시스템을 셋업합니다.
#
# 사용법:
#   git clone <settings-repo-url>
#   cd settings
#   bash install.sh
#
# 환경변수:
#   CLAUDE_CONFIG_DIR  Claude Code 설정 디렉토리 (기본: ~/.claude)
#==============================

# UTF-8 강제 (Windows 한글 깨짐 방지)
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
  chcp.com 65001 > /dev/null 2>&1 || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#--- Claude Code 설정 디렉토리 탐지 ---
detect_claude_dir() {
  # 1순위: CLAUDE_CONFIG_DIR 환경변수 (Claude Code 공식)
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    echo "$CLAUDE_CONFIG_DIR"
    return
  fi

  # 2순위: 레거시 CLAUDE_HOME 환경변수 (하위 호환)
  if [[ -n "${CLAUDE_HOME:-}" ]]; then
    echo "$CLAUDE_HOME"
    return
  fi

  # 3순위: 플랫폼별 기본 경로
  local os_type
  os_type="$(uname -s)"

  case "$os_type" in
    Linux*)
      # WSL 감지: WSL에서 실행 중이면 Windows 사용자 홈 사용
      if grep -qi microsoft /proc/version 2>/dev/null; then
        local win_home
        win_home=$(cmd.exe /C "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' | sed 's|\\|/|g' | sed 's|^\([A-Z]\):|/mnt/\L\1|')
        if [[ -n "$win_home" && -d "$win_home" ]]; then
          echo "$win_home/.claude"
          return
        fi
        echo ""
        echo "  WARNING: WSL 감지됨. Windows의 Claude Code는 Windows 경로를 사용합니다."
        echo "  Windows 홈 디렉토리를 자동 감지할 수 없습니다."
        echo "  CLAUDE_CONFIG_DIR 환경변수를 설정하세요:"
        echo "    export CLAUDE_CONFIG_DIR=/mnt/c/Users/<사용자명>/.claude"
        echo ""
        exit 1
      fi
      echo "$HOME/.claude"
      ;;
    Darwin*)
      echo "$HOME/.claude"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # Git Bash / MSYS2 / Cygwin on Windows
      if [[ -n "${USERPROFILE:-}" ]]; then
        # USERPROFILE을 Unix 경로로 변환
        local unix_path
        unix_path=$(cygpath -u "$USERPROFILE" 2>/dev/null || echo "$USERPROFILE" | sed 's|\\|/|g')
        echo "$unix_path/.claude"
      else
        echo "$HOME/.claude"
      fi
      ;;
    *)
      echo "$HOME/.claude"
      ;;
  esac
}

CLAUDE_DIR="$(detect_claude_dir)"

# 경로 유효성 확인
if [[ -z "$CLAUDE_DIR" ]]; then
  echo "ERROR: Claude Code 설정 디렉토리를 결정할 수 없습니다."
  echo "CLAUDE_CONFIG_DIR 환경변수를 설정하세요."
  exit 1
fi

echo "=== WI System Installer ==="
echo ""
echo "Claude Code 설정 디렉토리: $CLAUDE_DIR"
echo ""

#--- v4.0: 필수 의존성 체크 (fail-fast) ---
echo "[0/6] 필수 의존성 확인..."

# jq — flowset.sh의 JSON 파싱에 사용 (v4.0부터 필수)
if ! command -v jq &> /dev/null; then
  echo "  ❌ ERROR: jq가 설치되어 있지 않습니다. v4.0부터 필수 의존성입니다."
  echo "     Windows: winget install jqlang.jq"
  echo "     macOS:   brew install jq"
  echo "     Linux:   sudo apt install jq  (또는 sudo yum install jq)"
  exit 1
fi
echo "  ✅ jq $(jq --version 2>&1 | head -1)"

# bash 4.4+ — lib/state.sh와 filter-rebuild에서 빈 배열 확장 안전성
# 단일 조건식으로 if-else 분기 (이전 버전의 line 118 조건식 버그 수정)
if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  echo "  ✅ bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
else
  echo "  ⚠️  WARN: bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} 감지 (4.4+ 권장)"
  echo "     빈 배열 확장(\"\${arr[@]}\") 시 unbound variable 오류 가능"
  echo "     해당 사용처에 \"\${arr[@]-}\" 방어 권장"
  echo "     Homebrew(macOS): brew install bash"
fi

# shellcheck / bats — 개발용(선택)
if command -v shellcheck &> /dev/null; then
  echo "  ✅ shellcheck $(shellcheck --version 2>&1 | grep version | head -1 | awk '{print $2}')"
else
  echo "  ℹ️  shellcheck 미설치 (개발용, 선택). CI에서 사용"
fi

if command -v bats &> /dev/null; then
  echo "  ✅ bats $(bats --version 2>&1 | head -1) (system-wide)"
else
  echo "  ℹ️  bats 시스템 전역 미설치 (tests/bats submodule 사용)"
fi

# v4.0 WI-A3: bats-core submodule 초기화 (FlowSet 저장소 자체 개발자용)
# 다운스트림 프로젝트(/wi:init 대상)는 무관 — tests/bats/는 templates/에 복사되지 않음
if [[ -f "$SCRIPT_DIR/.gitmodules" ]] && grep -q 'tests/bats' "$SCRIPT_DIR/.gitmodules"; then
  if [[ ! -f "$SCRIPT_DIR/tests/bats/bin/bats" ]]; then
    echo "  ℹ️  tests/bats/ submodule 미초기화 — 자동 초기화 시도..."
    if (cd "$SCRIPT_DIR" && git submodule update --init --recursive tests/bats 2>&1 | tail -3); then
      echo "  ✅ tests/bats $(bash "$SCRIPT_DIR/tests/bats/bin/bats" --version 2>&1 | head -1)"
    else
      echo "  ⚠️  submodule 초기화 실패 (네트워크/권한 확인). 수동 실행: git submodule update --init --recursive"
    fi
  else
    echo "  ✅ tests/bats $(bash "$SCRIPT_DIR/tests/bats/bin/bats" --version 2>&1 | head -1)"
  fi
fi

echo ""

#--- 1. 디렉토리 생성 ---
echo "[1/5] 디렉토리 생성..."
mkdir -p "$CLAUDE_DIR/commands/wi"
mkdir -p "$CLAUDE_DIR/rules"

#--- 2. 스킬 설치 ---
echo "[2/5] 스킬 설치 (wi:*)..."
SKILLS_SRC="$SCRIPT_DIR/skills/wi"
SKILLS_DST="$CLAUDE_DIR/commands/wi"

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "  ERROR: $SKILLS_SRC 디렉토리를 찾을 수 없습니다."
  exit 1
fi

for skill in "$SKILLS_SRC"/*.md; do
  name=$(basename "$skill")
  cp "$skill" "$SKILLS_DST/$name"
  echo "  ✅ $name"
done

#--- 3. 글로벌 규칙 설치 ---
echo "[3/5] 글로벌 규칙 설치..."
RULES_SRC="$SCRIPT_DIR/rules"
RULES_DST="$CLAUDE_DIR/rules"

if [[ -d "$RULES_SRC" ]]; then
  for rule in "$RULES_SRC"/*.md; do
    name=$(basename "$rule")
    cp "$rule" "$RULES_DST/$name"
    echo "  ✅ $name"
  done
else
  echo "  SKIP: 규칙 파일 없음"
fi

#--- 4. Git UTF-8 설정 (글로벌) ---
echo "[4/5] Git UTF-8 설정..."
git config --global core.quotepath false
git config --global i18n.commitEncoding utf-8
git config --global i18n.logOutputEncoding utf-8
git config --global gui.encoding utf-8
echo "  ✅ git core.quotepath=false (한글 파일명 표시)"
echo "  ✅ git i18n.commitEncoding=utf-8"
echo "  ✅ git i18n.logOutputEncoding=utf-8"
echo "  ✅ git gui.encoding=utf-8"

#--- 5. 템플릿 확인 ---
echo "[5/6] 템플릿 확인..."
if [[ -d "$SCRIPT_DIR/templates" ]]; then
  echo "  templates/ 존재 (wi:init에서 참조)"
else
  echo "  ERROR: templates/ 디렉토리를 찾을 수 없습니다."
  exit 1
fi

#--- 6. 템플릿을 ~/.claude/templates/flowset/에 복사 ---
echo "[6/6] 템플릿 설치..."
TEMPLATE_DST="$CLAUDE_DIR/templates/flowset"
mkdir -p "$TEMPLATE_DST"
cp -r "$SCRIPT_DIR/templates/"* "$TEMPLATE_DST/" 2>/dev/null || true
cp -r "$SCRIPT_DIR/templates/".* "$TEMPLATE_DST/" 2>/dev/null || true
echo "  $TEMPLATE_DST/"

echo ""
echo "=== 설치 완료 ==="
echo ""
echo "설치된 항목:"
echo "  스킬: $SKILLS_DST/"
for f in "$SKILLS_DST"/*.md; do
  [[ -f "$f" ]] && echo "    - $(basename "$f")"
done
echo "  규칙: $RULES_DST/"
for f in "$RULES_DST"/wi-*.md; do
  [[ -f "$f" ]] && echo "    - $(basename "$f")"
done
echo "  템플릿: $SCRIPT_DIR/templates/"
echo ""
echo "사용법:"
echo "  /wi:init <project-name> --type <type> --org <github-org>"
echo "  /wi:prd <프로젝트 설명>"
echo "  /wi:start"
echo "  /wi:status"
echo "  /wi:guide"
