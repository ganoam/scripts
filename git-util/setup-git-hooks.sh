#!/bin/sh
# Install the shared .gitprivate guard hooks into this clone.
# Canonical copies live in ~/workspaceconfig/git-hooks/ (versioned,
# shared across repos); this copies them into .git/hooks/ so the guard
# keeps working even if workspaceconfig is later moved or removed.
# Fails loudly if the source is missing — never silently unprotected.
hooks_src="$HOME/workspaceconfig/git-hooks"
[ -d "$hooks_src" ] || {
  echo "setup-git-hooks: missing $hooks_src"
  echo "  checkout workspaceconfig first, then re-run."
  exit 1
}
hooks_dst="$(git rev-parse --git-dir)/hooks"
cp -v "$hooks_src"/pre-commit "$hooks_src"/pre-push "$hooks_dst/"
chmod +x "$hooks_dst"/pre-commit "$hooks_dst"/pre-push
git config --unset core.hooksPath 2>/dev/null
echo "setup-git-hooks: installed to $hooks_dst"
