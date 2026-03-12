#!/usr/bin/env bash
set -euo pipefail

#==============================
# WI System Uninstaller
#
# 환경변수:
#   CLAUDE_CONFIG_DIR  Claude Code 설정 디렉토리 (기본: ~/.claude)
#==============================

#--- Claude Code 설정 디렉토리 탐지 (install.sh와 동일 로직) ---
detect_claude_dir() {
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    echo "$CLAUDE_CONFIG_DIR"
    return
  fi

  if [[ -n "${CLAUDE_HOME:-}" ]]; then
    echo "$CLAUDE_HOME"
    return
  fi

  local os_type
  os_type="$(uname -s)"

  case "$os_type" in
    Linux*)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        local win_home
        win_home=$(cmd.exe /C "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' | sed 's|\\|/|g' | sed 's|^\([A-Z]\):|/mnt/\L\1|')
        if [[ -n "$win_home" && -d "$win_home" ]]; then
          echo "$win_home/.claude"
          return
        fi
        echo ""
        echo "  WARNING: WSL 감지됨. CLAUDE_CONFIG_DIR 환경변수를 설정하세요."
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
      if [[ -n "${USERPROFILE:-}" ]]; then
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

if [[ -z "$CLAUDE_DIR" ]]; then
  echo "ERROR: Claude Code 설정 디렉토리를 결정할 수 없습니다."
  exit 1
fi

echo "=== WI System Uninstaller ==="
echo "Claude Code 설정 디렉토리: $CLAUDE_DIR"
echo ""

read -p "wi:* 스킬과 규칙을 삭제합니다. 계속할까요? (y/N) " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "취소됨."
  exit 0
fi

# 스킬 삭제
if [[ -d "$CLAUDE_DIR/commands/wi" ]]; then
  rm -rf "$CLAUDE_DIR/commands/wi"
  echo "✅ 스킬 삭제: $CLAUDE_DIR/commands/wi/"
else
  echo "  SKIP: 스킬 디렉토리 없음"
fi

# 글로벌 규칙 삭제 (wi-*.md 패턴으로 동적 탐색)
found_rules=0
for rule in "$CLAUDE_DIR/rules"/wi-*.md; do
  if [[ -f "$rule" ]]; then
    rm "$rule"
    echo "✅ 규칙 삭제: $(basename "$rule")"
    found_rules=$((found_rules + 1))
  fi
done
if [[ $found_rules -eq 0 ]]; then
  echo "  SKIP: 규칙 파일 없음"
fi

echo ""
echo "=== 삭제 완료 ==="
echo "삭제된 항목: 스킬 디렉토리 + ${found_rules}개 규칙 파일"
echo "템플릿(settings/templates/)은 삭제하지 않았습니다."
