#!/usr/bin/env bash
set -euo pipefail

# Registers the superbrain MCP at user scope inside a Dev Container.
# Runs automatically when VS Code clones this repo into a new container
# (via dev.containers.dotfilesRepository in VS Code user settings).
#
# Reads SUPERBRAIN_TOKEN from the env. Pass it through from the host in
# each project's .devcontainer/devcontainer.json:
#
#   "remoteEnv": { "SUPERBRAIN_TOKEN": "${localEnv:SUPERBRAIN_TOKEN}" }
#
# and export SUPERBRAIN_TOKEN in your host shell rc.

SUPERBRAIN_URL="https://brain.taleth.pro/api/v1/mcp"
SUPERBRAIN_NAME="superbrain"

log() { echo "[dotfiles] $*"; }

if [[ -z "${SUPERBRAIN_TOKEN:-}" ]]; then
  log "SUPERBRAIN_TOKEN not set; skipping ${SUPERBRAIN_NAME} MCP registration."
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  log "claude CLI not on PATH; skipping ${SUPERBRAIN_NAME} MCP registration."
  exit 0
fi

if claude mcp list 2>/dev/null | grep -q "^${SUPERBRAIN_NAME}"; then
  log "${SUPERBRAIN_NAME} MCP already registered."
  exit 0
fi

claude mcp add \
  --scope user \
  --transport http \
  "${SUPERBRAIN_NAME}" \
  "${SUPERBRAIN_URL}" \
  --header "Authorization: Bearer ${SUPERBRAIN_TOKEN}"

log "${SUPERBRAIN_NAME} MCP registered."
