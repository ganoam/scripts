#!/usr/bin/env bash
# deps/scripts/setup/fetch-tarballs.sh [-y|--yes]
# Downloads tar.gz/tgz dependencies described in tarballs.yaml
# at the root of the calling repo.

set -uo pipefail

if [[ -z $CONFIGROOT ]]; then
  echo "[$basename "$0"] ERROR: variable CONFIGROOT not set."
  return 1
fi

source $CONFIGROOT/../deps/scripts/setup/lib.sh

CALLER_ROOT=$(find_caller_root) || { log "ERROR: could not find repo root."; exit 1; }
mkdir -p "$CALLER_ROOT/deps"

MANIFEST="$CALLER_ROOT/tarballs.yaml"
[ -f "$MANIFEST" ] || { log "No tarballs.yaml found, nothing to do."; exit 0; }


tarball_check() {
    local name="$1" hash="$2"
    local dest="$CALLER_ROOT/deps/$name"
    local archive="$CALLER_ROOT/deps/.cache/$name.archive"
    [ -d "$dest" ] || return 1
    local actual_hash=""
    [ -f "$archive" ] && actual_hash=$(sha256sum "$archive" | awk '{print $1}')
    if [ -n "$hash" ] && [ -n "$actual_hash" ] && [ "$hash" != "$actual_hash" ]; then
        return 1   # present but mismatched -> treat as "not ok"
    fi
    return 0
}

tarball_describe() {
    local name="$1" hash="$2"
    local dest="$CALLER_ROOT/deps/$name"
    if [ -d "$dest" ]; then
        echo "hash mismatch"
    else
        echo "not found"
    fi
}

tarball_install() {
    local name="$1" url="$2"
    local archive="$CALLER_ROOT/deps/.cache/$name.archive"
    local dest="$CALLER_ROOT/deps/$name"
    mkdir -p "$CALLER_ROOT/deps/.cache"
    curl -fsSL "$url" -o "$archive" || return 1
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xf "$archive" -C "$dest" --strip-components=1
}

# Minimal YAML parse: name/url/hash blocks
name="" url="" hash=""
process_entry() {
    [ -z "$name" ] && return
    ensure_tool "$name" "tarball_check $name $hash" "tarball_install $name $url" "tarball_describe $name $hash"
}

mapfile -t tarball_names < <(cat $MANIFEST)

for line in "${tarball_names[@]}"; do
    case "$line" in
        [a-zA-Z0-9_-]*:) process_entry
                         name="${line%:}"; url=""; hash="" ;;
        *url:*)  url=$(echo "$line" | awk '{print $2}') ;;
        *hash:*) hash=$(echo "$line" | awk '{print $2}') ;;
    esac
done
process_entry
