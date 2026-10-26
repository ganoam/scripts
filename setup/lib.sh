#!/usr/bin/env bash
# deps/scripts/setup/lib.sh
# Shared helpers for bootstrap.sh / fetch-repos.sh / fetch-tarballs.sh
# Source this; do not execute directly.

SCRIPT_NAME="$(basename "$0")"
ASSUME_YES=0

log() {
    echo "[$SCRIPT_NAME] $*" >&2
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

add_to_path() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) ;;                 # already present, do nothing
        *) export PATH="$dir:$PATH" ;; # not present, prepend
    esac
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

# --- apt deps from <tool>-deps.yml ---
read_deps_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    grep -E '^\s*-\s*' "$file" | sed -E 's/^\s*-\s*//'
}

apt_pkg_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

missing_apt_pkgs() {
    local missing=()
    for pkg in "$@"; do
        apt_pkg_installed "$pkg" || missing+=("$pkg")
    done
    echo "${missing[@]}"
}

# --- Tool installs ---
tool_state() {
    local bin="$1" venv="${2:-}"
    local state

    if [ -z "$venv" ]; then
        if command -v "$bin" >/dev/null 2>&1; then
            state="ok"
        else
            state="not_installed"
        fi
    elif [ -x "$venv/bin/$bin" ]; then
        state="ok"
    elif [ -d "$venv" ]; then
        state="venv_exists_no_tool"
    else
        state="not_installed"
    fi

    local deps_file="$CONFIGROOT/../$(basename "$bin")-deps.yml"
    if [ -f "$deps_file" ]; then
        local pkgs missing
        pkgs=$(read_deps_file "$deps_file")
        missing=$(missing_apt_pkgs $pkgs)
        if [ -n "$missing" ]; then
            log "WARNING: $bin missing apt packages: $missing"
            state="missing_deps:$missing"
        fi
    fi

    echo "$state"
}

tool_check() {
    local bin="$1" venv="${2:-}"
    local state; state=$(tool_state "$bin" "$venv")
    [[ "$state" == "ok" ]]
}

tool_describe() {
    local bin="$1" venv="${2:-}"
    local state; state=$(tool_state "$bin" "$venv")
    case "$state" in
        venv_exists_no_tool) log "venv exists but $bin is missing" ;;
        not_installed)       log "not installed" ;;
        missing_deps:*)      log "missing apt packages: ${state#missing_deps:}" ;;

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

    local state; state=$(tool_state "$name")
    if [[ "$state" == missing_deps:* ]]; then
        local missing="${state#missing_deps:}"
        local answer="n"
        if [ "$ASSUME_YES" -eq 1 ]; then
            answer="y"
        else
            prompt answer "$name: missing apt packages ($missing). Install with sudo apt install? [y/N]"
        fi
        case "$answer" in
            y|Y|yes|Yes)
                sudo apt install -y $missing
                ;;
            *)
                log "Skipping apt install for $name."
                ;;
        esac
    fi

    local reason="not found"
    [ -n "$describe_fn" ] && reason="$(eval "$describe_fn")"
    local answer="n"
    if [ "$ASSUME_YES" -eq 1 ]; then
        answer="y"
    else
        prompt answer "$name: $reason. Install it now? [y/N]"
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

