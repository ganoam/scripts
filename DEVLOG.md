# DEVLOG.md

## 2026-11-20: agent workflow onboarding

- Onboarded this repo onto the shared agent workflow as a dependency repo: no `deps/workflows` submodule of its own, `AGENTS.md` points at the sibling `../workflows` checkout with `~/workspaceconfig/deps/workflows` and the injected plugin copies as fallback chain.
