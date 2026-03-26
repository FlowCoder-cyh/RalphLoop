#!/usr/bin/env bash
# resolve-team.sh — TEAM_NAME 해소 유틸리티
# hook에서 source하여 사용
# 1순위: TEAM_NAME 환경변수
# 2순위: .flowset/teams/{팀명}.team 파일 스캔 (팀명 기반)
# 둘 다 없으면 빈 문자열 (solo 모드)

# $1: stdin INPUT (hook JSON) — 미사용이지만 호환 유지
# 결과: RESOLVED_TEAM_NAME 변수에 설정
resolve_team_name() {
  local input="${1:-}"

  # 1순위: 환경변수
  if [[ -n "${TEAM_NAME:-}" ]]; then
    RESOLVED_TEAM_NAME="$TEAM_NAME"
    return 0
  fi

  # 2순위: .flowset/teams/ 디렉토리에서 .team 파일 스캔
  # 파일명이 {TEAM_NAME}.team 형식
  if [[ -d ".flowset/teams" ]]; then
    local team_file
    team_file=$(ls -t .flowset/teams/*.team 2>/dev/null | head -1)
    if [[ -n "$team_file" ]]; then
      RESOLVED_TEAM_NAME=$(basename "$team_file" .team)
      return 0
    fi
  fi

  # 미설정 → solo 모드
  RESOLVED_TEAM_NAME=""
  return 0
}

# 팀 등록 (팀원 초기화 시 호출)
# $1: 팀명
register_team() {
  local team="${1:?register_team: team required}"
  mkdir -p .flowset/teams
  echo "registered" > ".flowset/teams/${team}.team"
}
