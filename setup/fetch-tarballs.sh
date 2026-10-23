#!/usr/bin/env bash
# deps/scripts/setup/fetch-tarballs.sh [-y|--yes]
# Downloads tar.gz/tgz dependencies described in tarballs.yaml
# at the root of the calling repo.

set -uo pipefail
SCRIPT_NAME="$(basename "$0")"

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
    esac
done

find_repo_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        [ -e "$dir/.git" ] && { echo "$dir"; return 0; }
        dir=$(dirname "$dir")
    done
    return 1
}

CALLER_ROOT=$(find_repo_root) || { echo "[$SCRIPT_NAME] ERROR: could not find repo root."; exit 1; }
mkdir -p "$CALLER_ROOT/deps"

MANIFEST="$CALLER_ROOT/tarballs.yaml"
[ -f "$MANIFEST" ] || { echo "[$SCRIPT_NAME] No tarballs.yaml found, nothing to do."; exit 0; }

ensure_tool() {
    local name="$1" check_fn="$2" install_fn="$3" describe_fn=$4
    if eval "$check_fn"; then
        echo "[$SCRIPT_NAME] $name already present, skipping."
        return
    fi
    local reason="not found"
    [ -n "$describe_fn" ] && reason="$(eval "$describe_fn")"
    local answer="n"
    if [ "$ASSUME_YES" -eq 1 ]; then
        answer="y"
    else
        read -p "$name: $reason. Install it now? [y/N] " answer
    fi
    case "$answer" in
        y|Y|yes|Yes)
            echo "[$SCRIPT_NAME] Installing $name ..."
            if eval "$install_fn"; then
                echo "[$SCRIPT_NAME] $name installed."
            else
                echo "[$SCRIPT_NAME] ERROR: failed to install $name."
            fi
            ;;
        *)
            echo "[$SCRIPT_NAME] Skipping $name install."
            ;;
    esac
}


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
while IFS= read -r line; do
    case "$line" in
        [a-zA-Z0-9_-]*:) process_entry
                         name="${line%:}"; url=""; hash="" ;;
        *url:*)  url=$(echo "$line" | awk '{print $2}') ;;
        *hash:*) hash=$(echo "$line" | awk '{print $2}') ;;
    esac
done < "$MANIFEST"
process_entry
