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
echo "[5/5] 템플릿 확인..."
if [[ -d "$SCRIPT_DIR/templates" ]]; then
  echo "  ✅ templates/ 존재 (wi:init에서 참조)"
else
  echo "  ERROR: templates/ 디렉토리를 찾을 수 없습니다."
  exit 1
fi

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
