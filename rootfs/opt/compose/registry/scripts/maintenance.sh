#!/bin/bash
set -euo pipefail

case "${1:-}" in
    retention|gc) action=$1 ;;
    *) echo 'Usage: maintenance.sh retention|gc [--dry-run]' >&2; exit 2 ;;
esac
dry_run=()
case "${2:-}" in
    '') ;;
    --dry-run) dry_run=(--dry-run) ;;
    *) echo 'Expected --dry-run.' >&2; exit 2 ;;
esac
if (( $# > 2 )); then exit 2; fi

cd -- "$(dirname -- "$0")/.."
exec 9>/run/lock/registry-maintenance.lock
flock 9
compose=(docker compose -f compose.yml)

if [[ "$action" == retention ]]; then
    "${compose[@]}" run --rm --no-deps -T retention "${dry_run[@]}"
    exit
fi

if [[ -z "$("${compose[@]}" ps --status running -q registry)" ]]; then
    echo 'Registry is not running; skipping GC without starting it.' >&2
    exit 1
fi

resume_registry() {
    result=$?
    trap - EXIT
    "${compose[@]}" start registry || result=1
    exit "$result"
}
trap resume_registry EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"${compose[@]}" stop registry
# Retention removes expired manifests through the API, including unused platform
# manifests. Normal GC reclaims their blobs without --delete-untagged.
"${compose[@]}" run --rm --no-deps -T gc garbage-collect "${dry_run[@]}" /etc/distribution/config.yml
