#!/usr/bin/env bash
# Superseded by team-watch.sh (idle plus provider errors, stalls, blocks, gone agents, status files).
exec "$(dirname "$0")/team-watch.sh" "$@"
