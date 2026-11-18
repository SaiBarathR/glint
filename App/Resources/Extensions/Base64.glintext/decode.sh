#!/bin/sh
# Decode standard or URL-safe Base64 from stdin. Fails (exit 1) on input that isn't valid Base64
# or that doesn't decode to UTF-8 text.
input=$(tr -d ' \t\r\n' | tr '_-' '/+')
case "$input" in
  ''|*[!A-Za-z0-9+/=]*) echo "Not valid Base64" >&2; exit 1 ;;
esac
# Restore padding that URL-safe encoders drop.
while [ $(( ${#input} % 4 )) -ne 0 ]; do input="$input="; done
tmp=$(mktemp -t glint-b64) || exit 1
trap 'rm -f "$tmp"' EXIT
printf '%s' "$input" | /usr/bin/base64 -D > "$tmp" 2>/dev/null
if [ ! -s "$tmp" ] || ! /usr/bin/iconv -f UTF-8 -t UTF-8 "$tmp" >/dev/null 2>&1; then
  echo "Doesn't decode to text" >&2
  exit 1
fi
cat "$tmp"
