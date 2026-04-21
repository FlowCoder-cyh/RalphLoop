#!/usr/bin/env bash
set -euo pipefail

# vault-helpers.sh — 하위 호환 shim (v4.0 WI-A2e)
#
# 본체는 `lib/vault.sh`로 이관됨(WI-A2e). 이 파일은 기존 hook 호환용 얇은 shim:
#   - .flowset/hooks/commit-msg
#   - .flowset/scripts/stop-vault-sync.sh
#   - .flowset/scripts/stop-rag-check.sh
#
# flowset.sh는 `lib/vault.sh`를 직접 source (이 shim 불필요). flowset.sh가 이 파일을 source
# 하지 않도록 :54-56 블록 제거됨.
#
# 탐색 순서:
#   1) cwd 기준 `lib/vault.sh` (Claude Code hook이 프로젝트 루트에서 실행되는 경우)
#   2) 본 shim 위치 상대 `../../lib/vault.sh` (셸 스크립트 절대 경로 기반)
#
# 두 경로 모두 실패 시 return 1 (source 문맥에서 exit는 호출자까지 종료시키므로 금지).

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

_vault_shim_load() {
  if [[ -f "lib/vault.sh" ]]; then
    source "lib/vault.sh"
    return 0
  fi
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${self_dir}/../../lib/vault.sh" ]]; then
    source "${self_dir}/../../lib/vault.sh"
    return 0
  fi
  echo "ERROR: lib/vault.sh 없음. v4.0부터 lib/ 모듈 구조입니다." >&2
  echo "  /wi:init 재실행 또는 cp templates/lib/vault.sh ./lib/" >&2
  return 1
}

_vault_shim_load
