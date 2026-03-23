#!/usr/bin/env bash
# rollback.sh — 코드/DB 롤백 유틸리티
# 사용법: bash .flowset/scripts/rollback.sh [code|db|deploy] [options]

set -euo pipefail

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

ACTION="${1:-help}"
shift || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 코드 롤백: git revert → PR → CI → merge queue
rollback_code() {
  local commit="${1:-}"
  if [[ -z "$commit" ]]; then
    echo "사용법: bash .flowset/scripts/rollback.sh code <commit-hash>"
    echo ""
    echo "최근 머지 커밋:"
    git log --oneline --merges -5 main 2>/dev/null
    exit 1
  fi

  log "코드 롤백 시작: $commit"

  # revert 브랜치 생성
  local branch="fix/WI-revert-$(echo "$commit" | cut -c1-7)"
  git checkout main
  git pull origin main
  git checkout -b "$branch"

  # revert 커밋 (머지 커밋이면 -m 1)
  if git cat-file -p "$commit" | grep -q '^parent.*parent'; then
    git revert -m 1 "$commit" --no-edit
  else
    git revert "$commit" --no-edit
  fi

  # PR 생성 + merge queue
  git push origin "$branch"
  local pr_url
  pr_url=$(gh pr create \
    --title "WI-fix revert ${commit:0:7}" \
    --body "## Rollback
- Reverted commit: ${commit}
- Reason: 프로덕션 장애 대응

## Checklist
- [ ] CI 통과
- [ ] 기능 검증" 2>&1)

  log "PR 생성: $pr_url"

  if [[ -f ".flowset/scripts/enqueue-pr.sh" ]]; then
    local pr_number
    pr_number=$(gh pr view --json number --jq '.number' 2>/dev/null)
    bash .flowset/scripts/enqueue-pr.sh "$pr_number" --wait
  fi

  log "코드 롤백 완료"
}

# DB 롤백: prisma migrate resolve
rollback_db() {
  local migration="${1:-}"
  if [[ -z "$migration" ]]; then
    echo "사용법: bash .flowset/scripts/rollback.sh db <migration-name>"
    echo ""
    echo "적용된 마이그레이션:"
    npx prisma migrate status 2>/dev/null || echo "prisma 미설치"
    exit 1
  fi

  log "DB 롤백 시작: $migration"

  # 실패한 마이그레이션 해결
  npx prisma migrate resolve --rolled-back "$migration"

  log "DB 마이그레이션 롤백 완료: $migration"
  log "주의: 스키마 변경에 따른 코드 수정이 필요할 수 있습니다."
}

# 배포 롤백: 플랫폼별
rollback_deploy() {
  local platform="${1:-vercel}"

  case "$platform" in
    vercel)
      log "Vercel 롤백 시작"
      # 최근 성공 배포로 롤백
      if command -v vercel &>/dev/null; then
        vercel rollback
        log "Vercel 롤백 완료"
      else
        log "ERROR: vercel CLI 미설치. npm i -g vercel"
        exit 1
      fi
      ;;
    *)
      echo "지원 플랫폼: vercel"
      echo "다른 플랫폼은 수동 롤백 필요"
      exit 1
      ;;
  esac
}

case "$ACTION" in
  code)
    rollback_code "$@"
    ;;
  db)
    rollback_db "$@"
    ;;
  deploy)
    rollback_deploy "$@"
    ;;
  help|*)
    echo "FlowSet 롤백 유틸리티"
    echo ""
    echo "사용법:"
    echo "  bash .flowset/scripts/rollback.sh code <commit-hash>   # git revert → PR"
    echo "  bash .flowset/scripts/rollback.sh db <migration-name>  # prisma migrate resolve"
    echo "  bash .flowset/scripts/rollback.sh deploy [vercel]      # 배포 롤백"
    echo ""
    echo "규칙:"
    echo "  - 롤백도 정상 PR 프로세스를 따름 (hotfix 제외)"
    echo "  - 롤백 후 반드시 regression 테스트"
    echo "  - 데이터 유실 시 Supabase 백업에서 복원"
    ;;
esac
