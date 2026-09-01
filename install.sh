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
#      registered. The prompt echoes what you type and the token is
#      checked against the brain before it is written to
#      ~/.claude.json, so a mangled paste fails at the prompt instead
#      of 401'ing silently in every later session.

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
# Wrapped in a function purely so the token stays a `local` and the failure
# paths can return early without aborting the rest of .bashrc.
__sb_register() {
  local url="https://superbrain.taleth.pro/api/v1/mcp"
  local token code

  command -v claude >/dev/null 2>&1 || return 0
  claude mcp get superbrain >/dev/null 2>&1 && return 0

  echo "[superbrain] Brain MCP not registered in this container."
  # Visible prompt on purpose. A silent `read -s` here once let a stray shell
  # command and the token merge into one unseen line; the resulting 108-char
  # header 401'd every session until someone read ~/.claude.json by hand.
  # Seeing what you pasted is worth more than hiding it.
  read -r -p "[superbrain] Paste API token (Enter to skip): " token

  # Trim whitespace the paste may have carried along.
  token="${token#"${token%%[![:space:]]*}"}"
  token="${token%"${token##*[![:space:]]}"}"

  if [[ -z $token ]]; then
    echo "[superbrain] Skipped."
    return 0
  fi

  case $token in
    *[[:space:]]*|*\'*|*\"*)
      echo "[superbrain] Token contains whitespace or quotes — looks like more than" \
           "one thing was pasted. Not registered."
      return 1
      ;;
  esac

  # Verify against the brain before writing it to ~/.claude.json: a bad token
  # is otherwise invisible until the next session fails to connect.
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -H "Authorization: Bearer $token" \
      --max-time 20 \
      --data-binary '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"dotfiles-install","version":"1"}}}')
    if [[ $code != 200 ]]; then
      echo "[superbrain] ${#token}-char token rejected by the brain" \
           "(HTTP ${code:-no response}). Not registered."
      return 1
    fi
  fi

  if claude mcp add --scope user --transport http superbrain "$url" \
       --header "Authorization: Bearer $token" >/dev/null 2>&1; then
    echo "[superbrain] Registered (${#token}-char token verified)."
  else
    echo "[superbrain] 'claude mcp add' failed. Run it manually."
    return 1
  fi
}

if [[ $- == *i* ]]; then
  __sb_register
fi
unset -f __sb_register
# <<< superbrain MCP registration <<<
EOF
