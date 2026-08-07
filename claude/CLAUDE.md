# User-level Claude Code conventions

Loaded into every Claude Code session in this devcontainer, alongside any
per-repo `CLAUDE.md`. Repo-agnostic — phrased to apply in any project.

## Brain Memory at Session Start

At the start of any non-trivial task in this devcontainer, pull the
superbrain's cross-session memory once via:

    mcp__superbrain__read_memory(project: "<repo-slug>")

The `<slug>` is the **repository name**, not the working directory — e.g.
cwd `/workspaces/superbrain` → slug `superbrain`, cwd `/workspace` → slug
`kaia_trade`, cwd `/app` → slug `kaia_portal` / `fpl-stats` /
`absolute-relative` depending on which repo is checked out. Derive it from
the git remote or the repo name, not from `pwd`.

Do NOT use the cwd-derived form. Several repos mount at the same path
(`/app` hosts three different projects), so a cwd-derived slug collides —
it produced a single junk `app` scope mixing them all, cleaned up
2026-08-07. The product-owner agent already writes to the repo-name slug
(superbrain issue #946 made it pass `project: <repo_slug>` literally
rather than deriving it from its working directory); matching that here
keeps both producers on one scope per project.

The brain is the only source of truth for memory (per superbrain issue
#236). The result merges the project's own scope ∪ the cross-cutting
`global` scope, so even a brand-new repo (with no project-specific
entries yet) still surfaces useful globals like preferred workflows and
operational rules.

### When to call

- Once per session, before significant new work (a single MCP round-trip).
- Before any task touching workflow conventions, git/commit machinery,
  deploy flow, or memory itself.
- When a user reference feels like it might match a saved preference
  (e.g. "use my usual workflow").

### When to skip

- Trivial one-shot questions ("what's the output of X").
- When the user has already pasted the relevant memory into the conversation.

### When the brain isn't available

If `mcp__superbrain__*` isn't in this session's tool list, the brain
isn't connected from this devcontainer — skip the lookup silently. (The
dotfiles installer's bashrc snippet prompts for the token on the first
interactive shell; it may have been skipped, or the registration may
have failed.)

### Don't duplicate

Do not try to read `~/.claude/projects/<slug>/memory/` — the local
auto-memory dir was deprecated as a write target by superbrain issue
#236. The brain MCP is the only place memory now lives.
