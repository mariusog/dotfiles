#!/usr/bin/env bash
# Runs once when VS Code clones this dotfiles repo into a new Dev Container.
#
# Three independent, idempotent steps:
#
#   1. Symlink claude/CLAUDE.md into ~/.claude/CLAUDE.md so every Claude
#      Code session in the devcontainer auto-loads the brain-memory
#      directive (and any other user-level conventions).
#
#   2. Symlink the Stop-notify hook into ~/.claude/hooks/ and register it
#      once in ~/.claude/settings.json so every project in this container
#      pings the brain's Discord when a session goes idle.
#
#   3. Install a ~/.bashrc snippet that interactively prompts for the
#      superbrain API token on the first terminal opened in the
#      container, then registers the brain MCP at user scope.
#      Subsequent shells skip the prompt because the MCP is already
#      registered.

set -euo pipefail

# Resolve where VS Code cloned this repo. `dirname $0` works for the
# typical dotfiles install command (`~/dotfiles/install.sh`).
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. User-level CLAUDE.md ---
# `ln -sf` is idempotent: replaces an existing symlink, no-op when the
# link already points at the right target.
mkdir -p "${HOME}/.claude"
ln -sf "${DOTFILES_DIR}/claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"

# --- 2. Stop-notify hook (superbrain idle pings) ---
# Symlink the credential-free Stop hook to a stable user path, then register
# it once in ~/.claude/settings.json so every project in this container pings
# the brain's Discord when a session goes idle. The hook carries no secret —
# at runtime it borrows the bearer token from the superbrain MCP block that
# step 3 (below) registers in ~/.claude.json.
#
# Both halves are idempotent: `ln -sf` re-points the symlink, and the jq
# merge is a no-op when the hook command is already present in Stop. We bake
# the resolved absolute path into settings.json (rather than relying on a
# runtime $HOME expansion), since the installer already knows ${HOME} and the
# generated settings.json is per-container, never committed.
mkdir -p "${HOME}/.claude/hooks"
ln -sf "${DOTFILES_DIR}/claude/hooks/notify-stop.sh" "${HOME}/.claude/hooks/notify-stop.sh"

if command -v jq >/dev/null 2>&1; then
  SETTINGS="${HOME}/.claude/settings.json"
  HOOK_CMD="${HOME}/.claude/hooks/notify-stop.sh"
  [[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"
  TMP_SETTINGS="$(mktemp)"
  if jq --arg cmd "$HOOK_CMD" '
        .hooks //= {} |
        .hooks.Stop //= [] |
        if ([.hooks.Stop[].hooks[]?.command] | index($cmd))
        then .
        else .hooks.Stop += [{ hooks: [{ type: "command", command: $cmd, timeout: 15 }] }]
        end
      ' "$SETTINGS" > "$TMP_SETTINGS"; then
    mv "$TMP_SETTINGS" "$SETTINGS"
  else
    rm -f "$TMP_SETTINGS"
    echo "[dotfiles] Warning: could not register Stop hook in $SETTINGS" >&2
  fi
else
  echo "[dotfiles] Warning: jq not found; skipping Stop-notify hook registration" >&2
fi

# --- 3. Brain MCP registration via bashrc snippet ---
BASHRC="${HOME}/.bashrc"
MARKER_START="# >>> superbrain MCP registration >>>"
MARKER_END="# <<< superbrain MCP registration <<<"

if grep -qF "$MARKER_START" "$BASHRC" 2>/dev/null; then
  exit 0
fi

cat >> "$BASHRC" <<'EOF'

# >>> superbrain MCP registration >>>
if [[ $- == *i* ]] && command -v claude >/dev/null 2>&1; then
  if ! claude mcp get superbrain >/dev/null 2>&1; then
    echo "[superbrain] Brain MCP not registered in this container."
    read -r -s -p "[superbrain] Paste API token (Enter to skip): " __SB_TOKEN
    echo
    if [[ -n "$__SB_TOKEN" ]]; then
      if claude mcp add --scope user --transport http superbrain \
           https://superbrain.taleth.pro/api/v1/mcp \
           --header "Authorization: Bearer $__SB_TOKEN" >/dev/null 2>&1; then
        echo "[superbrain] Registered."
      else
        echo "[superbrain] Registration failed. Run 'claude mcp add' manually."
      fi
    fi
    unset __SB_TOKEN
  fi
fi
# <<< superbrain MCP registration <<<
EOF
