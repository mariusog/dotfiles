# User-level Claude Code conventions

Loaded into every Claude Code session in this devcontainer, alongside any
per-repo `CLAUDE.md`. Repo-agnostic — phrased to apply in any project.

## Brain Memory at Session Start

At the start of any non-trivial task in this devcontainer, pull the
superbrain's cross-session memory once via:

    mcp__superbrain__read_memory(project: "<cwd-derived-slug>")

The `<slug>` is Claude Code's native cwd-derived form with the leading
dash stripped — e.g. cwd `/workspaces/foo-bar` → slug `workspaces-foo-bar`,
cwd `/workspaces/superbrain` → slug `workspaces-superbrain`.

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

### Canonical reference

https://brain.taleth.pro/concepts/session-start-brain-memory-lookup
