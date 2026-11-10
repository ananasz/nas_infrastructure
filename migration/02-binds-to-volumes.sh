#!/bin/bash
# Copy the old bind-mounted service data into named Docker volumes.
# Run as root on the NAS after "docker compose down" of the old nas-stack.
# The source directories stay untouched, so the old stack can be started again.
# The ZFS pool (/nas-data/zfs-pool) is not copied; the new stacks mount it in place.
set -euo pipefail

dry_run=false
case "${1:-}" in
    '') ;;
    --dry-run) dry_run=true ;;
    *) echo 'Usage: 02-binds-to-volumes.sh [--dry-run]' >&2; exit 2 ;;
esac

helper=debian:trixie-slim

# volume  source  (file sources are copied into the volume root)
mappings=(
    'certs              /nas-data/container-data/certs'
    'portainer-data     /nas-data/config/portainer'
    'authelia-data      /nas-data/container-data/authelia'
    'authelia-data      /nas-data/config/authelia/users_database.yml'
    'jellyfin-config    /nas-data/config/jellyfin'
    'radarr-config      /nas-data/config/radarr'
    'sonarr-config      /nas-data/config/sonarr'
    'bazarr-config      /nas-data/config/bazarr'
    'qbittorrent-config /nas-data/config/qbittorrent'
    'prowlarr-config    /nas-data/config/prowlarr'
    'jellyseerr-config  /nas-data/config/jellyseerr'
    'verdaccio-conf     /nas-data/config/verdaccio'
    'verdaccio-storage  /nas-data/container-data/verdaccio/storage'
    'verdaccio-plugins  /nas-data/container-data/verdaccio/plugins'
)
# Rebuilt by Jellyfin; created empty instead of copying /nas-data/cache/jellyfin.
empty_volumes=(jellyfin-cache)

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

left="$(docker ps -aq --filter label=com.docker.compose.project=nas-stack)"
[[ -z "$left" ]] || die 'old nas-stack containers still exist; run "docker compose down" in /nas-data/config'

# Validate everything before creating any volume.
declare -A seen
for mapping in "${mappings[@]}"; do
    read -r volume source <<< "$mapping"
    [[ -e "$source" ]] || die "missing source $source"
    if [[ -z "${seen[$volume]+set}" ]] && docker volume inspect "$volume" >/dev/null 2>&1; then
        die "volume $volume already exists; remove it if it is from an aborted run"
    fi
    seen[$volume]=1
done
for volume in "${empty_volumes[@]}"; do
    ! docker volume inspect "$volume" >/dev/null 2>&1 || die "volume $volume already exists"
done

for mapping in "${mappings[@]}"; do
    read -r volume source <<< "$mapping"
    printf '%-20s <- %s (%s)\n' "$volume" "$source" "$(du -sh -- "$source" | cut -f1)"
done
printf '%-20s (empty)\n' "${empty_volumes[@]}"
if $dry_run; then
    exit 0
fi

docker pull -q "$helper" >/dev/null
for mapping in "${mappings[@]}"; do
    read -r volume source <<< "$mapping"
    docker volume create "$volume" >/dev/null
    if [[ -d "$source" ]]; then
        docker run --rm -v "$source:/src:ro" -v "$volume:/dst" "$helper" cp -a /src/. /dst/
    else
        docker run --rm -v "$source:/src/$(basename -- "$source"):ro" -v "$volume:/dst" "$helper" \
            cp -a "/src/$(basename -- "$source")" /dst/
    fi
    printf 'Copied %s\n' "$source"
done
for volume in "${empty_volumes[@]}"; do
    docker volume create "$volume" >/dev/null
done

# Ownership and modes are preserved by cp -a; a quick size comparison for review:
for mapping in "${mappings[@]}"; do
    read -r volume source <<< "$mapping"
    [[ -d "$source" ]] || continue
    printf '%-20s %s / %s\n' "$volume" "$(du -s --apparent-size -- "$source" | cut -f1)" \
        "$(docker run --rm -v "$volume:/v:ro" "$helper" du -s --apparent-size /v | cut -f1)"
done
echo 'Done. The original directories are kept; remove them only after the new stacks are verified.'
