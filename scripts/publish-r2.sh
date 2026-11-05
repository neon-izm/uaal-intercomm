#!/usr/bin/env bash
# Upload a directory or one file to the uaal-intercomm R2 bucket.
# Credentials come from the repo-root .env. Values are never printed.
#
#   scripts/publish-r2.sh <local-dir> <remote-prefix>
#   scripts/publish-r2.sh --file <local-file> <remote-key>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
HOSTING="$ROOT/scripts/hosting.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
# shellcheck disable=SC1091
source "$HOSTING"
set +a

load_cloudflare() {
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%:*}"
    value="${line#*:}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$key" in
      "account id") export CLOUDFLARE_ACCOUNT_ID="$value" ;;
      "api token") export CLOUDFLARE_API_TOKEN="$value" ;;
      "access key") export AWS_ACCESS_KEY_ID="$value" ;;
      "secret access key") export AWS_SECRET_ACCESS_KEY="$value" ;;
    esac
  done < "$ENV_FILE"
  if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" || -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    echo ".env is missing the Cloudflare account id or api token" >&2
    exit 1
  fi
}

load_cloudflare

put_object() {
  local file="$1"
  local key="$2"
  local cache="public, max-age=60"
  echo "upload ${R2_BUCKET}/${key}"
  npx --yes wrangler r2 object put "${R2_BUCKET}/${key}" \
    --cwd /tmp \
    --file "$file" \
    --content-type "$(file_type "$file")" \
    --cache-control "$cache" \
    --remote \
    -y
}

file_type() {
  case "$1" in
    *.json) echo "application/json" ;;
    *.hash) echo "text/plain" ;;
    *.zip) echo "application/zip" ;;
    *.sha256|*.sha1) echo "text/plain" ;;
    *.pom|*.xml) echo "application/xml" ;;
    *.aar) echo "application/java-archive" ;;
    *) echo "application/octet-stream" ;;
  esac
}

if [[ "${1:-}" == "--file" ]]; then
  file="${2:-}"
  key="${3:-}"
  if [[ -z "$file" || -z "$key" || ! -f "$file" ]]; then
    echo "usage: scripts/publish-r2.sh --file <local-file> <remote-key>" >&2
    exit 1
  fi
  put_object "$file" "$key"
  exit 0
fi

dir="${1:-}"
prefix="${2:-}"
prefix="${prefix#/}"
prefix="${prefix%/}"
if [[ -z "$dir" || -z "$prefix" || ! -d "$dir" ]]; then
  echo "usage: scripts/publish-r2.sh <local-dir> <remote-prefix>" >&2
  exit 1
fi

found=0
while IFS= read -r -d '' file; do
  rel="${file#"$dir"/}"
  put_object "$file" "${prefix}/${rel}"
  found=1
done < <(find "$dir" -type f -print0 | sort -z)

if [[ "$found" -eq 0 ]]; then
  echo "no files in $dir" >&2
  exit 1
fi
