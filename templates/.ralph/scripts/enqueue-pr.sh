#!/usr/bin/env bash
# PR을 merge queue에 등록하는 래퍼 스크립트
# 사용법: bash .ralph/scripts/enqueue-pr.sh <PR번호>
# merge queue 미지원 시 gh pr merge --auto --squash fallback

set -euo pipefail

PR_NUMBER="${1:?PR 번호를 입력하세요. 예: bash .ralph/scripts/enqueue-pr.sh 79}"

OWNER=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || echo "")
REPO=$(gh repo view --json name --jq '.name' 2>/dev/null || echo "")

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  echo "ERROR: GitHub 레포 정보를 가져올 수 없습니다."
  exit 1
fi

# PR node ID 조회
PR_NODE_ID=$(gh api graphql -f query="{ repository(owner: \"$OWNER\", name: \"$REPO\") { pullRequest(number: $PR_NUMBER) { id } } }" --jq '.data.repository.pullRequest.id' 2>/dev/null || true)

if [[ -z "${PR_NODE_ID:-}" ]]; then
  echo "ERROR: PR #$PR_NUMBER 을 찾을 수 없습니다."
  exit 1
fi

# merge queue 존재 여부 확인
HAS_MERGE_QUEUE=$(gh api repos/"$OWNER"/"$REPO"/rulesets --jq '[.[] | select(.rules[]?.type == "merge_queue")] | length' 2>/dev/null || echo "0")

# merge queue에 등록 시도
RESULT=$(gh api graphql -f query="mutation { enqueuePullRequest(input: { pullRequestId: \"$PR_NODE_ID\" }) { mergeQueueEntry { position } } }" 2>&1 || true)

if echo "$RESULT" | grep -q '"position"'; then
  POSITION=$(echo "$RESULT" | grep -oE '"position":[0-9]+' | grep -oE '[0-9]+')
  echo "✅ PR #$PR_NUMBER → merge queue position $POSITION"
elif echo "$RESULT" | grep -qi "already.*queue"; then
  echo "✅ PR #$PR_NUMBER → 이미 큐에 등록됨"
elif [[ "$HAS_MERGE_QUEUE" -gt 0 ]]; then
  # merge queue 있지만 enqueue 실패 (CI 미통과, 충돌 등)
  echo "⏳ enqueue 실패 (CI 대기 또는 충돌) — auto-merge 설정"
  echo "   에러: $(echo "$RESULT" | grep -oE '"message":"[^"]*"' | head -1)"
  # merge queue repo: --squash 금지 (queue가 method 관리)
  gh pr merge "$PR_NUMBER" --auto 2>/dev/null || {
    echo "⚠️ auto-merge 설정 실패"
  }
  echo "✅ PR #$PR_NUMBER → auto-merge 설정 완료 (CI 통과 후 자동 큐 등록)"
else
  # merge queue 없음 → fallback
  echo "ℹ️ merge queue 미설정 — gh pr merge --auto --squash fallback"
  gh pr merge "$PR_NUMBER" --auto --squash 2>/dev/null || {
    echo "⚠️ auto-merge 설정 실패"
  }
  echo "✅ PR #$PR_NUMBER → auto-merge 설정 완료"
fi
