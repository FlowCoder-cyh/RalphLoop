#!/usr/bin/env bash
# FlowSet을 새 터미널 창에서 실행하는 스크립트
# 사용법: bash .flowset/scripts/launch-loop.sh

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Windows에서 bash.exe 경로를 동적으로 탐색
find_windows_bash() {
  local bash_path
  bash_path=$(which bash 2>/dev/null || where bash 2>/dev/null | head -1)
  if [[ -n "$bash_path" && -x "$bash_path" ]]; then
    echo "$bash_path"; return
  fi
  for candidate in \
    "C:/Program Files/Git/bin/bash.exe" \
    "C:/Program Files (x86)/Git/bin/bash.exe" \
    "$LOCALAPPDATA/Programs/Git/bin/bash.exe" \
    "$PROGRAMFILES/Git/bin/bash.exe"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"; return
    fi
  done
  return 1
}

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    BASH_EXE=$(find_windows_bash)
    if [[ -n "$BASH_EXE" ]]; then
      start "" "$BASH_EXE" -c "cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter to close...'"
      echo "LAUNCHED"
    else
      if command -v wsl &>/dev/null; then
        wsl_path=$(wslpath "$PROJECT_DIR" 2>/dev/null || echo "/mnt/c${PROJECT_DIR:2}")
        start "" wsl bash -c "cd '$wsl_path' && bash flowset.sh; read -p 'Press Enter to close...'"
        echo "LAUNCHED"
      else
        echo "ERROR: bash를 찾을 수 없습니다."
        echo "  1. Git for Windows (https://git-scm.com)"
        echo "  2. WSL (wsl --install)"
        echo "  수동 실행: cd $PROJECT_DIR && bash flowset.sh"
      fi
    fi
    ;;
  Linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      setsid bash -c "cd '$PROJECT_DIR' && bash flowset.sh" &>/dev/null &
      echo "LAUNCHED"
    else
      if command -v gnome-terminal &>/dev/null; then
        gnome-terminal -- bash -c "cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter...'"
      elif command -v konsole &>/dev/null; then
        konsole -e bash -c "cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter...'" &
      elif command -v xterm &>/dev/null; then
        xterm -e "cd '$PROJECT_DIR' && bash flowset.sh; read -p 'Press Enter...'" &
      else
        setsid bash -c "cd '$PROJECT_DIR' && bash flowset.sh" &>/dev/null &
      fi
      echo "LAUNCHED"
    fi
    ;;
  Darwin*)
    # tmux: Claude Code 세션과 완전 독립 (stdout 리다이렉트 문제 없음)
    if command -v tmux &>/dev/null; then
      tmux kill-session -t flowset 2>/dev/null || true
      tmux new-session -d -s flowset -c "$PROJECT_DIR" "bash flowset.sh; echo ''; echo 'FlowSet 종료. Enter로 닫기'; read"
      echo "LAUNCHED"
      echo ""
      echo "🚀 FlowSet이 tmux 세션 'flowset'에서 시작되었습니다!"
      echo "   모니터링: tmux attach -t flowset"
      echo "   로그: tail -f $PROJECT_DIR/.flowset/logs/flowset.log"
    else
      # tmux 없으면 osascript fallback
      if osascript -e 'exists application "iTerm"' 2>/dev/null; then
        osascript -e "tell application \"iTerm\" to create window with default profile command \"cd '$PROJECT_DIR' && bash flowset.sh\""
      else
        osascript -e "tell application \"Terminal\" to do script \"cd '$PROJECT_DIR' && bash flowset.sh\""
      fi
      echo "LAUNCHED"
      echo ""
      echo "💡 tmux 설치 권장: brew install tmux"
      echo "   tmux를 사용하면 Claude Code 세션과 완전 독립적으로 실행됩니다."
    fi
    ;;
  *)
    echo "ERROR: 지원하지 않는 OS입니다. 수동 실행: cd $PROJECT_DIR && bash flowset.sh"
    ;;
esac
