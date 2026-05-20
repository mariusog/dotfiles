#!/usr/bin/env bash
# Runs once when VS Code clones this dotfiles repo into a new Dev Container.
# Installs a ~/.bashrc snippet that interactively prompts for the superbrain
# API token on the first terminal opened in the container, then registers
# the brain MCP at user scope. Subsequent shells skip the prompt because
# the MCP is already registered.

set -euo pipefail

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
           https://brain.taleth.pro/api/v1/mcp \
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
