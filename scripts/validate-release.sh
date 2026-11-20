#!/bin/zsh
#
# Checks that a release tag, the app version in project.yml, and the release notes agree,
# before anything gets built or published. Prints the version on success.
#
#   ./scripts/validate-release.sh v1.1.0
#
set -euo pipefail

root="${0:A:h:h}"
tag="${1:-}"
project="${PROJECT_YML_PATH:-$root/project.yml}"
release_notes_dir="${RELEASE_NOTES_DIR:-$root/docs/releases}"

fail() {
    echo "Release validation failed: $1" >&2
    exit 1
}

[[ "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "tag must use vMAJOR.MINOR.PATCH"
[[ -f "$project" ]] || fail "missing project.yml at $project"

version="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/p' "$project" | head -1)"
build="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/p' "$project" | head -1)"
[[ -n "$version" ]] || fail "MARKETING_VERSION is missing from project.yml"
[[ "$version" == "${tag#v}" ]] || fail "tag ${tag#v} does not match MARKETING_VERSION $version"
[[ "$build" =~ '^[1-9][0-9]*$' ]] || fail "CURRENT_PROJECT_VERSION must be a positive integer"
[[ -s "$release_notes_dir/$tag.md" ]] || fail "missing release notes at $release_notes_dir/$tag.md"

echo "$version"
