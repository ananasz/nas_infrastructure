#!/bin/bash
# Copy the old secret files into the new stacks' .env files.
# Run as root on the NAS after the repo files are in /opt/compose. The old files stay untouched.
set -euo pipefail
umask 077

old_auth=/nas-data/config/authelia/secrets
old_cetli=/opt/cetli
auth_env=/opt/compose/auth/.env
cetli_env=/opt/compose/cetli/.env

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# One trailing newline is dropped, as with "$(cat FILE)".
read_secret() {
    [[ -f "$1" ]] || die "missing $1"
    local value
    value="$(cat -- "$1")"
    [[ -n "$value" ]] || die "empty $1"
    if [[ "$value" =~ [[:space:]]$ ]]; then
        printf 'Warning: %s ends with whitespace; check the result.\n' "$1" >&2
    fi
    printf '%s' "$value"
}

# Single quotes keep "$" literal in Compose .env files; multi-line PEM uses double quotes.
append() {
    local file=$1 key=$2 value=$3
    if [[ -f "$file" ]] && grep -q "^$key=" "$file"; then
        printf 'Skip %s: already in %s\n' "$key" "$file"
        return
    fi
    if [[ -s "$file" && -n "$(tail -c 1 -- "$file")" ]]; then
        echo >> "$file"
    fi
    if [[ "$value" == *$'\n'* ]]; then
        [[ "$value" != *[\"\$\\\`]* ]] || die "$key: multi-line value with quote, \$ or backslash"
        printf '%s="%s"\n' "$key" "$value" >> "$file"
    else
        [[ "$value" != *"'"* ]] || die "$key: value contains a single quote"
        printf "%s='%s'\n" "$key" "$value" >> "$file"
    fi
    printf 'Added %s to %s\n' "$key" "$file"
}

# Separate assignment so that a read error stops the script under set -e.
add_secret() {
    local value
    value="$(read_secret "$3")"
    append "$1" "$2" "$value"
}

[[ -d /opt/compose/auth && -d /opt/compose/cetli ]] || die 'copy rootfs/opt/compose first'

touch "$auth_env"
add_secret "$auth_env" JWT_SECRET "$old_auth/jwt_secret"
add_secret "$auth_env" SESSION_SECRET "$old_auth/session_secret"
add_secret "$auth_env" STORAGE_ENCRYPTION_KEY "$old_auth/storage_encryption_key"
add_secret "$auth_env" OIDC_HMAC_SECRET "$old_auth/oidc_hmac_secret"
add_secret "$auth_env" OIDC_JWKS_PRIVATE_KEY "$old_auth/oidc_jwks_private_key.pem"
add_secret "$auth_env" CETLI_CLIENT_SECRET_HASH "$old_auth/oidc_clients/cetli-backend_hash"

# Keep the existing cetli settings (DB credentials, URLs) and add the secrets.
if [[ ! -f "$cetli_env" && -f "$old_cetli/.env" ]]; then
    cp -- "$old_cetli/.env" "$cetli_env"
    printf 'Copied %s/.env to %s\n' "$old_cetli" "$cetli_env"
fi
touch "$cetli_env"
add_secret "$cetli_env" COOKIE_SECRET "$old_cetli/secrets/cookie_secret"
add_secret "$cetli_env" OIDC_CLIENT_SECRET "$old_cetli/secrets/oidc_client_secret"

chmod 0600 "$auth_env" "$cetli_env"
printf '\nCheck: docker compose --project-directory /opt/compose/auth config --quiet\n'
printf '       docker compose --project-directory /opt/compose/cetli config --quiet\n'
