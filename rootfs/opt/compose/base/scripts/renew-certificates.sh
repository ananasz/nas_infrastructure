#!/bin/sh
# Separate certificate maintenance from the public-facing nginx container.
set -eu
base_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "${1:---dry-run}" in
    --dry-run) renewal_mode=--dry-run ;;
    --renew) renewal_mode= ;;
    *) printf 'Usage: %s [--dry-run|--renew]\n' "$0" >&2; exit 2 ;;
esac
compose() {
    docker compose -f "$base_dir/compose.yml" "$@"
}
# Explicitly replace a saved nginx authenticator/installer with webroot + no-op installer.
# Review saved lineage hooks when migrating certificates issued with the nginx plugin.
if test -n "$renewal_mode"; then
    compose run --rm --no-deps certbot renew --non-interactive --authenticator webroot \
        --installer null --webroot-path /var/www/certbot --no-directory-hooks "$renewal_mode"
else
    compose run --rm --no-deps certbot renew --non-interactive --authenticator webroot \
        --installer null --webroot-path /var/www/certbot --no-directory-hooks
    compose exec -T nginx nginx -t
    compose exec -T nginx nginx -s reload
fi
