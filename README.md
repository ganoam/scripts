# scripts

Agent-generated

Personal scripts and utilities repo; `AGENTS.md` carries the layout and the consuming-repo rules.
Documentation is partial: only `git-hooks/` is covered below; the rest is pending.

## `git-hooks/`

Run-parts hook multiplexers for consumer repos of the git-privacy workflow.
Consumers point `core.hooksPath` at this directory via `git-util/setup-git-hooks.sh`.

### How dispatch works

`pre-commit` and `pre-push` are identical multiplexers; `<hook>` below is the file's basename.
Each saves stdin to a temp file once, then runs every executable found in two directories, in order:

1. `<this dir>/<hook>.d/*`: shared guards shipped here.
2. `<repo>/git-hooks/<hook>.d/*`: consumer-local gates in the calling repo's own `git-hooks/` dir.

Each hook gets the original hook arguments and a fresh read of the saved stdin (pre-push's pushed-ref list).
The first nonzero exit aborts; later hooks never run.

### Shared guards

`<hook>.d/10-git-private` holds the git-privacy guards; see `git-util/` for the rest of the mechanism.
Numeric prefixes set execution order inside a `.d` dir (shell glob order): `10-` leaves room to slot earlier entries later.

### Adding a consumer-local gate

Drop an executable in `<consumer repo>/git-hooks/<hook>.d/`; it runs after the shared guards on every matching hook.
Example: `workspaceconfig/git-hooks/pre-push.d/readme-docs` runs `./update-docs.sh --check`.
A local gate can veto (nonzero exit) but cannot skip or precede the shared guards.
pre-push local gates see every remote, not just the public one.

### Details

- stdin is saved up front because the pre-push guard consumes it and local hooks may want it too; skipped when stdin is a tty (manual runs).
- A repo with no `git-hooks/` dir and a `.d` dir with no executables exits 0: the multiplexers are no-ops until a hook file exists.
- `tests/test-git-privacy.sh` exercises the dispatch: order, stdin replay, abort-on-failure.

## Pending documentation

`git-util/`, `setup/`, `bin/`, `util/`, `tests/`, `shell/`, `shortcut-menus/`, `etc/` are not documented here yet; `AGENTS.md` carries the layout summary meanwhile.
