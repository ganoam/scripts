#!/bin/sh
# Point this repo's hooks at the guard hooks shipped in the scripts
# repo (sibling git-hooks/ dir next to this script). core.hooksPath is
# set relative to the repo root, so a submodule update alone refreshes
# the hooks — nothing to copy.
set -e
cd "$(git rev-parse --show-toplevel)"

hooks_src="$(cd "$(dirname "$0")/../git-hooks" && pwd)"
git config core.hooksPath "$(realpath --relative-to="$PWD" "$hooks_src")"
echo "setup-git-hooks: core.hooksPath -> $(git config core.hooksPath)"
