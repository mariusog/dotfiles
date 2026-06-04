#!/usr/bin/env bash
set -uo pipefail
# Notify the brain's Discord channel when a Claude Code session goes idle
# (issue #330). Claude Code fires the `Stop` hook every time the assistant
# finishes a turn and hands control back; this script pings Discord so the
# owner gets told out-of-band that a session they walked away from is ready
# for them.
#
# Two design constraints shape this:
#
#   1. No credentials in the repo. This file is committed and shared across
#      every project that uses the brain, so it carries NO secret. Instead
#      it borrows the bearer token from the superbrain MCP integration that
#      each project already configures in ~/.claude.json — the same HTTP MCP
#      server Claude talks to. A project without that integration is a silent
#      no-op (exit 0).
#
#   2. Stop fires on EVERY turn, which would be spam. We throttle by idle
#      gap: only notify when more than CLAUDE_STOP_NOTIFY_THRESHOLD_SECONDS
#      (default 300s) elapsed since this session's previous Stop — i.e. when
#      Claude was working a while (or you were away), not a rapid
#      back-and-forth. State is a per-session stamp under $TMPDIR.
#
# Claude Code hook contract: JSON on stdin, exit 0 (non-blocking). We never
# block the session — every failure path is a quiet exit 0.

command -v jq >/dev/null 2>&1 || { echo "Warning: jq not found, skipping notify-stop hook" >&2; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "Warning: curl not found, skipping notify-stop hook" >&2; exit 0; }

INPUT=$(cat)

# Re-entrancy guard: when a Stop hook itself blocks and Claude continues,
# the follow-up Stop carries stop_hook_active=true. Never notify on those.
if [[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" == "true" ]]; then
  exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
# The session id lands in a filename below — strip anything that could
# traverse or escape the stamp directory, so a hostile id can't clobber a
# path outside $TMPDIR.
SESSION_ID="${SESSION_ID//[^A-Za-z0-9_-]/_}"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[[ -z "$CWD" ]] && CWD="$PWD"
PROJECT=$(basename "$CWD")

# Borrow the superbrain MCP endpoint + bearer token from ~/.claude.json.
# Prefer a project-scoped server block, fall back to the user-level one.
CONFIG="${HOME}/.claude.json"
[[ -f "$CONFIG" ]] || exit 0

URL=$(jq -r --arg cwd "$CWD" '
  (.projects[$cwd].mcpServers.superbrain.url // .mcpServers.superbrain.url) // empty
' "$CONFIG" 2>/dev/null)
AUTH=$(jq -r --arg cwd "$CWD" '
  (.projects[$cwd].mcpServers.superbrain.headers.Authorization
    // .mcpServers.superbrain.headers.Authorization) // empty
' "$CONFIG" 2>/dev/null)

# Project without the brain MCP wired in → nothing to call, stay silent.
[[ -z "$URL" || -z "$AUTH" ]] && exit 0

# Throttle by idle gap, keyed on session_id so parallel sessions don't
# share a clock. The stamp is updated on every Stop; we notify only when
# the gap since the previous Stop crosses the threshold.
THRESHOLD="${CLAUDE_STOP_NOTIFY_THRESHOLD_SECONDS:-300}"
STAMP="${TMPDIR:-/tmp}/claude-stop-notify-${SESSION_ID}"
NOW=$(date +%s)

GAP=-1
if [[ -f "$STAMP" ]]; then
  PREV=$(cat "$STAMP" 2>/dev/null || echo "")
  [[ "$PREV" =~ ^[0-9]+$ ]] && GAP=$(( NOW - PREV ))
fi
printf '%s' "$NOW" > "$STAMP" 2>/dev/null || true

# First Stop of a session has no baseline to measure idleness against, and a
# rapid back-and-forth turn is below the threshold — skip both.
(( GAP < 0 )) && exit 0
(( GAP < THRESHOLD )) && exit 0

human_duration() {
  local s=$1 m h
  m=$(( s / 60 ))
  if (( m < 60 )); then
    echo "${m}m"
  else
    h=$(( m / 60 )); m=$(( m % 60 )); echo "${h}h ${m}m"
  fi
}
DURATION=$(human_duration "$GAP")

TITLE="Claude session idle — ${PROJECT}"
DESC="\`${PROJECT}\` — Claude finished a turn and is idle after ~${DURATION}. Come review."

PAYLOAD=$(jq -nc --arg title "$TITLE" --arg desc "$DESC" '{
  jsonrpc: "2.0",
  id: 1,
  method: "tools/call",
  params: {
    name: "notify_discord",
    arguments: { title: $title, description: $desc, level: "info" }
  }
}')

# Fire-and-forget: a notification must never delay or fail the session.
curl -sS -m 10 -X POST "$URL" \
  -H "Authorization: ${AUTH}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null 2>&1 || true

exit 0
