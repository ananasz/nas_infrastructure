#!/bin/bash
set -Eeuo pipefail
umask 077
[[ $(id -u) == 0 ]] || { echo 'Run as root' >&2; exit 1; }
set -a
source /opt/compose/backup/.env
set +a
: "${RESTIC_REPOSITORY:?}" "${RESTIC_PASSWORD_FILE:?}" "${RCLONE_CONFIG:?}"
install -d -m 0700 /var/lib/nas-backup /var/cache/nas-backup
exec 9>/var/lib/nas-backup/lock
flock -n 9 || { echo 'Backup already running' >&2; exit 1; }
case "${1:-}" in
    init) exec restic init ;;
    snapshots) exec restic snapshots ;;
    check) exec restic check --read-data-subset=5% ;;
    prune) exec restic prune ;;
    backup) ;;
    *) echo 'Usage: nas-backup.sh init|backup|snapshots|check|prune' >&2; exit 2 ;;
esac
: "${PHOTOS_DATASET:?}" "${PHOTOS_PATH:?}"
mountpoint=$(zfs get -H -o value mountpoint "$PHOTOS_DATASET")
[[ "$mountpoint" == /* && "$mountpoint" != / && "$PHOTOS_PATH" == "$mountpoint"/* ]] || {
    # The photo directory may itself be a dataset mountpoint.
    [[ "$mountpoint" == "$PHOTOS_PATH" && "$mountpoint" != / ]] || exit 1
}
[[ $(findmnt -n -o SOURCE --target "$PHOTOS_PATH") == "$PHOTOS_DATASET" ]] || exit 1
# Child mounts would not be included in this non-recursive snapshot.
[[ $(findmnt -rn -o TARGET | awk -v p="$PHOTOS_PATH/" 'index($0,p)==1 {n++} END {print n+0}') == 0 ]] || {
    echo 'Child mounts under photos are unsupported' >&2; exit 1;
}
stage=/var/lib/nas-backup/staging
install -d -m 0700 "$stage"
restart=()
snapshot=''
mounted=false
cleanup() {
    rc=$?
    trap - EXIT
    for container in "${restart[@]}"; do docker start "$container" >/dev/null || rc=1; done
    if [[ "$mounted" == true ]]; then
        if umount /var/lib/nas-backup/photos; then mounted=false; else rc=1; fi
    fi
    if [[ -n "$snapshot" && "$mounted" == false ]]; then zfs destroy "$snapshot" || rc=1; fi
    if (( rc == 0 )); then date -u +%FT%TZ > /var/lib/nas-backup/last-success; fi
    exit "$rc"
}
trap cleanup EXIT
stop_running() {
    [[ $(docker inspect -f '{{.State.Running}}' "$1") == true ]] || {
        echo "Required container is not running: $1" >&2; return 1;
    }
    restart+=("$1")
    docker stop -t 120 "$1" >/dev/null
}
resume() {
    for container in "${restart[@]}"; do docker start "$container" >/dev/null; done
    restart=()
}
docker inspect immich_server immich_postgres anachronos-db cetli-db vaultwarden >"$stage/containers.json"
docker exec anachronos-db sh -c 'pg_dump --clean --if-exists --no-owner --no-acl -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$stage/anachronos.sql.tmp"
mv "$stage/anachronos.sql.tmp" "$stage/anachronos.sql"
stop_running cetli-db
couch_path=$(docker volume inspect -f '{{.Mountpoint}}' cetli_cetli-db-data)
tar -C "$couch_path" -cpf "$stage/cetli-data.tar.tmp" .
rm -rf -- "$stage/cetli-etc.tmp"
docker cp cetli-db:/opt/couchdb/etc "$stage/cetli-etc.tmp"
rm -rf -- "$stage/cetli-etc"
mv "$stage/cetli-etc.tmp" "$stage/cetli-etc"
mv "$stage/cetli-data.tar.tmp" "$stage/cetli-data.tar"
resume
# Stopped container keeps the SQLite DB/WAL consistent; icon_cache is regenerable.
stop_running vaultwarden
vault_path=$(docker volume inspect -f '{{.Mountpoint}}' vaultwarden-data)
tar -C "$vault_path" --exclude ./icon_cache -cpf "$stage/vaultwarden-data.tar.tmp" .
mv "$stage/vaultwarden-data.tar.tmp" "$stage/vaultwarden-data.tar"
resume
stop_running immich_server
docker exec immich_postgres sh -c 'pg_dump --clean --if-exists -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$stage/immich.sql.tmp"
mv "$stage/immich.sql.tmp" "$stage/immich.sql"
snapshot="$PHOTOS_DATASET@nas-backup-$(date -u +%Y%m%dT%H%M%SZ)"
zfs snapshot "$snapshot"
resume
relative=${PHOTOS_PATH#"$mountpoint"}
source_path="$mountpoint/.zfs/snapshot/${snapshot#*@}$relative"
[[ -d "$source_path/upload" && -d "$source_path/library" ]] || {
    echo 'Missing Immich directories in snapshot' >&2; exit 1;
}
# Stable path permits incremental metadata comparisons across ZFS snapshots.
install -d -m 0700 /var/lib/nas-backup/photos
mount --bind "$source_path" /var/lib/nas-backup/photos
mounted=true
restic backup --host nas --tag nas-data "$stage" /var/lib/nas-backup/photos \
    /opt/compose/immich /opt/compose/anachronos /opt/compose/cetli /opt/compose/vaultwarden \
    --exclude /var/lib/nas-backup/photos/thumbs \
    --exclude /var/lib/nas-backup/photos/encoded-video \
    --exclude /var/lib/nas-backup/photos/backups
umount /var/lib/nas-backup/photos
mounted=false
# Only expire snapshots after all services have been backed up successfully.
restic forget --host nas --tag nas-data --group-by host,tags \
    --keep-daily 7 --keep-weekly 5 --keep-monthly 12
