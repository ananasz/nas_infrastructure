#!/bin/sh
set -eu
umask 077

case "${1:-}" in
    '') reload=true ;;
    --init) reload=false ;;
    *) echo 'Usage: renew-internal-certificate.sh [--init] (from base)'; exit 2 ;;
esac
if [ "$#" -gt 1 ] || [ "$(id -u)" -ne 0 ]; then
    echo 'Run as root from /opt/compose/base.' >&2
    exit 1
fi

config=configs/internal-tls.cnf
tls_dir=secrets/db-tls
key="$tls_dir/privkey.pem"
cert="$tls_dir/fullchain.pem"
state="$tls_dir/config.sha256"
test -f "$config"
install -d -m 0700 "$tls_dir"

if [ -s "$key" ] && [ -s "$cert" ] && [ -f "$state" ] \
    && openssl x509 -in "$cert" -checkend 2592000 -noout >/dev/null 2>&1 \
    && sha256sum --check --status "$state"; then
    exit 0
fi

tmp_cert=$(mktemp "$tls_dir/.cert.XXXXXXXX")
tmp_state=$(mktemp "$tls_dir/.state.XXXXXXXX")
tmp_key=''
trap 'rm -f -- "$tmp_cert" "$tmp_state" "$tmp_key"' EXIT
signing_key="$key"
if [ ! -s "$key" ]; then
    tmp_key=$(mktemp "$tls_dir/.key.XXXXXXXX")
    openssl genrsa -out "$tmp_key" 2048
    signing_key="$tmp_key"
fi

openssl req -x509 -new -sha256 -days 365 -key "$signing_key" -config "$config" -out "$tmp_cert"
sha256sum "$config" > "$tmp_state"
chmod 0600 "$signing_key" "$tmp_cert" "$tmp_state"
if [ -n "$tmp_key" ]; then
    mv -- "$tmp_key" "$key"
    tmp_key=''
fi
# A failed reload leaves no state file, so the next run retries.
rm -f -- "$state"
mv -- "$tmp_cert" "$cert"

if [ "$reload" = true ]; then
    running=$(docker compose -f compose.yml ps --status running -q nginx)
    if [ -n "$running" ]; then
        docker compose -f compose.yml exec -T nginx nginx -t
        docker compose -f compose.yml exec -T nginx nginx -s reload
    fi
fi
mv -- "$tmp_state" "$state"
echo 'Internal certificate renewed.'
