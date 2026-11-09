#!/usr/bin/env bash
# deps/scripts/setup/fetch-repos.sh [-y|--yes]
# Downloads/syncs git submodule dependencies only.

set -uo pipefail

if [[ -z ${CONFIGROOT:-} ]]; then
  echo "[$(basename "$0")] ERROR: variable CONFIGROOT not set. Source sourceme/sourceme.sh first." >&2
  exit 1
fi

# source function libarary
LIB=/setup/lib.sh
if [ -f "$CONFIGROOT/../deps/scripts/$LIB" ]; then
  source $CONFIGROOT/../deps/scripts/setup/lib.sh
else
  # The scripts repo hasn't been checked out yet.
  # bootstrap_script must have been exported.
  bootstrap_script "$LIB" "source"
fi
parse_common_args "$@"

CALLER_ROOT=$(find_caller_root) || { log "ERROR: could not find caller repo root."; exit 1; }
mkdir -p "$CALLER_ROOT/deps"

mapfile -t submodule_names < <(git -C "$CALLER_ROOT" config --file "$CALLER_ROOT/.gitmodules" --get-regexp path | awk '{print $2}')

submodule_dirty() { [ -n "$(git -C "$CALLER_ROOT/$1" status --porcelain 2>/dev/null)" ]; }

FAILED=()
for name in "${submodule_names[@]}"; do

  submodule_state() {
      local status_line
      status_line=$(git -C "$CALLER_ROOT" submodule status -- "$1" 2>/dev/null)
      if [ -z "$status_line" ]; then
          echo "unregistered"
      elif [[ "$status_line" == -* ]]; then
          echo "not_initialized"
      elif [[ "$status_line" == +* ]]; then
          if submodule_dirty "$1"; then
              echo "dirty"
          else
              echo "wrong_commit"
          fi
      else
          echo "ok"
      fi
  }


  state=$(submodule_state "$name")
  case "$state" in
      ok)
          log "submodule:$name already present, skipping."
          ;;
      dirty)
          log "WARNING: submodule:$name has uncommitted changes, skipping."
          FAILED+=("$name")
          ;;
      *)
          if git -C "$CALLER_ROOT" submodule update --init --recursive -- "$name"; then
              log "submodule:$name fetched."
          else
              log "ERROR: failed to fetch submodule:$name."
              FAILED+=("$name")
          fi
          ;;
  esac
done

if ((${#FAILED[@]})); then
    log "ERROR: ${#FAILED[@]} submodule(s) not synced: ${FAILED[*]}"
    exit 1
fi

