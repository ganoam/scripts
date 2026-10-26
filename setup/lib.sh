#!/usr/bin/env bash
# deps/scripts/setup/lib.sh
# Shared helpers for bootstrap.sh / fetch-repos.sh / fetch-tarballs.sh
# Source this; do not execute directly.

SCRIPT_NAME="$(basename "$0")"
ASSUME_YES=0

log() {
    echo "[$SCRIPT_NAME] $*"
}

prompt() {
    local __resultvar="$1"
    local message="$2"
    local __answer
    read -p "[$SCRIPT_NAME] $message " __answer
    printf -v "$__resultvar" '%s' "$__answer"
}

parse_common_args() {
    for arg in "$@"; do
        case "$arg" in
            -y|--yes) ASSUME_YES=1 ;;
        esac
    done
}

# find root of containing repo
find_repo_root() {
    local dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    while [ "$dir" != "/" ]; do
        [ -e "$dir/.git" ] && { echo "$dir"; return 0; }
        dir=$(dirname "$dir")
    done
    return 1
}

# find root of repo from where I'm called.
find_caller_root () {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        [ -e "$dir/.git" ] && { echo "$dir"; return 0; }
        dir=$(dirname "$dir")
    done
    return 1
}

bootstrap_script() {
    local RELPATH="$1"
    local MODE="${2:-run}" # source or run

    _run_script() {
      local script="$1"
      if [ "$MODE" == "source" ]; then
        source "$script"
      else
        bash "$script"
      fi
    }

    if [[ -z $CONFIGROOT ]]; then
      echo "[$basename "$0"] ERROR: variable CONFIGROOT not set."
      return 1
    fi

    local FULLPATH="$CONFIGROOT/../deps/scripts/$RELPATH"
    if [ ! -f "$FULLPATH" ]; then
        local SHA
        SHA=$(git -C "$CONFIGROOT" ls-tree HEAD -- deps/scripts | awk '{print $2}')
        if [ -z "$SHA" ]; then
            log ": WARNING: no pinned commit found for deps/scripts in the index."
            SHA="master"
        fi
        local tmp
        tmp=$(mktemp)
        curl -fsSL "https://raw.githubusercontent.com/koalemo/scripts/$SHA/$RELPATH" -o "$tmp"
        pushd "$CONFIGROOT" > /dev/null # fetch scripts need to run from workspaceconfig root.
        _run_script "$tmp"
        popd > /dev/null
        rm -f "$tmp"
    else
        pushd "$ROOT" > /dev/null
        _run_script "$FULLPATH"
        popd > /dev/null
    fi
}

# --- Tool installs ---
tool_state() {
    local bin="$1" venv="${2:-}"
    if [ -z "$venv" ]; then
        if command -v "$bin" >/dev/null 2>&1; then
            echo "ok"
        else
            echo "not_installed"
        fi
        return
    fi

    if [ -x "$venv/bin/$bin" ]; then
        echo "ok"
    elif [ -d "$venv" ]; then
        echo "venv_exists_no_tool"
    else
        echo "not_installed"
    fi
}

tool_check() {
    local bin="$1" venv="${2:-}"
    [ "$(tool_state "$bin" "$venv")" = "ok" ]
}

tool_describe() {
    local bin="$1" venv="${2:-}"
    case "$(tool_state "$bin" "$venv")" in
        venv_exists_no_tool) echo "venv exists but $bin is missing" ;;
        not_installed)       echo "not installed" ;;
    esac
}

ensure_venv() {
    local venv="${1:-$MAIN_VENV}"
    [ -d "$venv" ] || python3 -m venv "$venv" || return 1
    "$venv/bin/pip" install --upgrade pip
}
ensure_tool() {
    local name="$1" check_fn="$2" install_fn="$3" describe_fn="${4:-}"
    if eval "$check_fn"; then
        log "$name already present, skipping."
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
            log "Installing $name ..."
            if eval "$install_fn"; then
                log "$name installed."
            else
                log "ERROR: failed to install $name."
            fi
            ;;
        *)
            log "Skipping $name install."
            ;;
    esac
}
