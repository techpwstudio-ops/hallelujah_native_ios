#!/usr/bin/env bash
# Reopens this Claude Code session (g-hallelujah-ios) in a new external
# Terminal.app window via `claude --resume <session-id>`.
set -euo pipefail

PROJECT_DIR="/Users/teja/company/projects/projectH/app/g-hallelujah-ios"
SESSION_ID="8339d5d2-b5ce-471c-8468-37db7b2d1901"
CLAUDE_BIN="/Users/teja/.local/bin/claude"

CMD="cd '${PROJECT_DIR}' && '${CLAUDE_BIN}' --resume ${SESSION_ID}"

osascript -e "tell application \"Terminal\" to activate" \
          -e "tell application \"Terminal\" to do script \"${CMD}\""
