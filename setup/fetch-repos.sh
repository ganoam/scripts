#!/usr/bin/env bash
# deps/scripts/setup/fetch-repos.sh [-y|--yes]
# Downloads/syncs git submodule dependencies only.

set -uo pipefail

if [[ -z $CONFIGROOT ]]; then
  echo "[$basename "$0"] ERROR: variable CONFIGROOT not set."
  return 1
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

  submodule_dirty() { [ -n "$(git -C "$CALLER_ROOT/$1" status --porcelain 2>/dev/null)" ]; }
  submodule_check() { [ "$(submodule_state "$1")" = "ok" ]; }

  submodule_describe() {
      case "$(submodule_state "$1")" in
          unregistered)   echo "not registered as a submodule" ;;
          not_initialized) echo "not initialized" ;;
          dirty)          echo "has uncommitted changes" ;;
          wrong_commit)   echo "on a different commit than expected" ;;
      esac
  }

  submodule_install() {
      case "$(submodule_state "$1")" in
          dirty)
              log "WARNING: '$1' has uncommitted changes, skipping update."
              return 1
              ;;
          unregistered|not_initialized|wrong_commit)
              git -C "$CALLER_ROOT" submodule update --init --recursive -- "$1"
              ;;
      esac
  }

  state=$(submodule_state "$name")
  if [ "$state" = "ok" ]; then
      log "submodule:$name already present, skipping."
  elif [ "$state" = "dirty" ]; then
      log "WARNING: submodule:$name has uncommitted changes, skipping (not prompting)."
  else
      ensure_tool "submodule:$name" "submodule_check $name" "submodule_install $name" "submodule_describe $name"
  fi
done

