#!/usr/bin/env bash
# Watch every named team agent and exit with one line per event, so the PM wakes up.
# It is runtime-agnostic: it uses herdr status plus the patterns in references/error-patterns.tsv.
#
# Events:
#   FINISHED <agent>          working → idle/done (both count as "not working"), or a new status file
#   ERROR    <agent> <class>  provider/auth/crash/update/question/context pattern seen in recent pane text
#   STALLED  <agent>          status says working, but the pane text is unchanged for STALL_MIN minutes
#   BLOCKED  <agent>          blocked for longer than BLOCK_MIN minutes (a short block is a compaction or queued prompt)
#   GONE     <agent>          the agent was seen before and has left the list (exit, crash, self-update)
#
# Env:
#   PM_NAME=pm (set to the brief's actual PM name, e.g. pm-project)
#   INTERVAL=60  STALL_MIN=20  BLOCK_MIN=10  IGNORE=pm,name2
#   STATUS_GLOB='design/reports/*.status.json' (completion files; optional)
#   ONCE=1 prints the current snapshot and exits (for debugging)
#   TEAM_ROOT=$(team root) also wakes on new messages in the PM's team inbox (MAIL)
# The state lives in $STATE_DIR (default /tmp/team-watch-$USER-$PM_NAME) so the watcher can restart without losing history.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PATTERNS=${PATTERNS:-$HERE/../references/error-patterns.tsv}
INTERVAL=${INTERVAL:-60}; STALL_MIN=${STALL_MIN:-20}; BLOCK_MIN=${BLOCK_MIN:-10}
PM_NAME=${PM_NAME:-pm}; IGNORE=${IGNORE:-$PM_NAME}; STATE_DIR=${STATE_DIR:-/tmp/team-watch-$USER-$PM_NAME}
mkdir -p "$STATE_DIR"
now() { date +%s; }
emit() { echo "$1 $(date +%H:%M)"; EVENTS=1; }

classify() {   # $1 = the joined pane text → prints the first matching class
  local text=$1 cls kind re
  while IFS=$'\t' read -r cls kind re; do
    [[ -z "$cls" || "$cls" == \#* ]] && continue
    if grep -Eiq -- "$re" <<<"$text"; then echo "$cls"; return; fi
  done < "$PATTERNS"
}

while true; do
  EVENTS=0
  list=$(herdr agent list 2>/dev/null) || { sleep "$INTERVAL"; continue; }
  rows=$(jq -r --arg ign "$IGNORE" '($ign|split(",")) as $skip | .result.agents[]
    | select(.name and (.name as $n | ($skip|index($n))|not))
    | [.name, .agent_status, .pane_id] | @tsv' <<<"$list")
  # Agents report to "pm". If no pane carries that name (e.g. lost after a reboot), reports bounce with agent_not_found.
  if ! jq -e --arg pm "$PM_NAME" '.result.agents[] | select(.name==$pm)' <<<"$list" >/dev/null; then
    [ -f "$STATE_DIR/.pm-warned" ] || { emit "NOPM no pane is named $PM_NAME: resolve with herdr pane current, then rename it $PM_NAME"; touch "$STATE_DIR/.pm-warned"; }
  else rm -f "$STATE_DIR/.pm-warned"; fi
  current=""
  while IFS=$'\t' read -r name status pane; do
    [ -z "$name" ] && continue
    current="$current $name"
    d="$STATE_DIR/$name"; mkdir -p "$d"
    prev=$(cat "$d/status" 2>/dev/null || echo "")
    case "$status" in idle|done) norm=rest ;; *) norm=$status ;; esac
    # The last 40 lines, joined: a narrow pane wraps messages across lines.
    text=$(herdr pane read "$pane" --source recent --lines 40 2>/dev/null | tr '\n' ' ' | tr -s ' ')
    hash=$(printf %s "$text" | cksum | cut -d' ' -f1)
    # A finished agent was working on the previous tick.
    if [ "$norm" = rest ] && [ "$prev" = working ]; then
      cls=$(classify "$(printf %s "$text" | tail -c 1500)")
      if [ -n "$cls" ] && [ "$cls" != update ] && [ "$cls" != busy ]; then emit "ERROR $name $cls"; else emit "FINISHED $name"; fi
    fi
    # Stalled: working, with the same pane text for STALL_MIN.
    if [ "$norm" = working ]; then
      if [ "$hash" != "$(cat "$d/hash" 2>/dev/null)" ]; then now > "$d/changed"; fi
      since=$(cat "$d/changed" 2>/dev/null || now)
      if (( $(now) - since > STALL_MIN*60 )) && [ ! -f "$d/stall-reported" ]; then emit "STALLED $name"; touch "$d/stall-reported"; fi
    else rm -f "$d/stall-reported"; fi
    # Blocked: longer than BLOCK_MIN.
    if [ "$norm" = blocked ]; then
      [ "$prev" = blocked ] || now > "$d/blocked-since"
      if (( $(now) - $(cat "$d/blocked-since") > BLOCK_MIN*60 )) && [ ! -f "$d/block-reported" ]; then
        cls=$(classify "$text")
        # "blocked" because a queued prompt waits behind running work is normal, not a stop.
        if [ "$cls" = busy ]; then now > "$d/blocked-since"; else emit "BLOCKED $name${cls:+ $cls}"; touch "$d/block-reported"; fi; fi
    else rm -f "$d/block-reported"; fi
    printf %s "$hash" > "$d/hash"; printf %s "$norm" > "$d/status"
    [ "${ONCE:-}" = 1 ] && echo "$name $status ($norm) pane=$pane"
  done <<<"$rows"
  # Gone: in the last snapshot, but not in this one.
  for n in $(cat "$STATE_DIR/.names" 2>/dev/null); do
    [[ ",$IGNORE," == *",$n,"* ]] && continue
    [[ " $current " == *" $n "* ]] || emit "GONE $n"
  done
  echo "$current" > "$STATE_DIR/.names"
  # Completion files: one event per new or updated file.
  if [ -n "${STATUS_GLOB:-}" ]; then
    for f in $STATUS_GLOB; do [ -f "$f" ] || continue
      m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f"); k="$STATE_DIR/.sf-$(printf %s "$f" | cksum | cut -d' ' -f1)"
      if [ "$m" != "$(cat "$k" 2>/dev/null)" ]; then
        [ -f "$k" ] && emit "STATUSFILE $f $(jq -r '.agent+" "+.state' "$f" 2>/dev/null)"
        echo "$m" > "$k"; fi
    done
  fi
  # Team board: new messages in the PM's inbox (team msg / task state changes / reviews).
  if [ -n "${TEAM_ROOT:-}" ] && [ -f "$TEAM_ROOT/inbox/$PM_NAME.jsonl" ]; then
    n=$(wc -l < "$TEAM_ROOT/inbox/$PM_NAME.jsonl"); r=$(cat "$TEAM_ROOT/inbox/$PM_NAME.jsonl.read" 2>/dev/null || echo 0)
    [ "$n" -gt "${r:-0}" ] && [ "$n" != "$(cat "$STATE_DIR/.mail" 2>/dev/null)" ] && { emit "MAIL $PM_NAME has $((n - r)) unread: run team inbox"; echo "$n" > "$STATE_DIR/.mail"; }
  fi
  [ "${ONCE:-}" = 1 ] && exit 0
  [ "$EVENTS" = 1 ] && exit 0
  sleep "$INTERVAL"
done
