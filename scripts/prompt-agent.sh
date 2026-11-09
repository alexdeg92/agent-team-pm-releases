#!/usr/bin/env bash
# Deliver a prompt to a team agent reliably: retry while it is blocked or compacting, resolve by pane title when
# its exact herdr name is absent (after a reboot), warn on fallback, and confirm delivery. It is runtime-agnostic and needs only herdr and jq.
# Usage: prompt-agent.sh <name|pane_id|title-substring> "<message>"   [TIMEOUT=1800 RETRY=30]
set -u
target=$1; msg=$2; TIMEOUT=${TIMEOUT:-1800}; RETRY=${RETRY:-30}
resolve() {
  local agents match mode pane
  agents=$(herdr agent list 2>/dev/null) || return 1
  match=$(jq -r --arg t "$target" '
    .result.agents as $agents
    | [$agents[] | select(.name==$t)] as $named
    | [$agents[] | select(.pane_id==$t)] as $panes
    | if ($named|length)>0 then ["name", $named[0].pane_id]
      elif ($panes|length)>0 then ["pane", $panes[0].pane_id]
      else [$agents[] | select((.terminal_title_stripped // "") | contains($t))] as $titles
        | if ($titles|length)==1 then ["title", $titles[0].pane_id]
          elif ($titles|length)>1 then ["ambiguous", ""]
          else empty end
      end | @tsv' <<<"$agents") || return 1
  IFS=$'\t' read -r mode pane <<<"$match"
  case "$mode" in
    name|pane) ;;
    title) echo "prompt-agent: warning: no exact agent name or pane id '$target'; falling back to title match ($pane)" >&2;;
    ambiguous) echo "prompt-agent: ambiguous title match for '$target'; use an exact agent name or pane id" >&2; return 1;;
    *) return 1;;
  esac
  [ -n "$pane" ] && [ "$pane" != null ] || return 1
  printf '%s\n' "$pane"
}
deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  if ! pane=$(resolve); then echo "prompt-agent: could not resolve '$target'; no prompt sent" >&2; exit 2; fi
  out=$(herdr agent prompt "$pane" "$msg" 2>&1)
  if grep -q '"agent_prompted"' <<<"$out"; then echo "delivered to $target ($pane)"; exit 0; fi
  code=$(grep -o '"code":"[a-z_]*"\|"type":"[a-z_]*"' <<<"$out" | head -1)
  # An agent that is visibly working, with a queued input, isn't stuck: keep waiting while it shows progress.
  if herdr pane read "$pane" --source recent --lines 15 2>/dev/null | tr '\n' ' ' | grep -Eiq 'queued follow-up|working \(|esc to interrupt'; then
    deadline=$(( $(date +%s) + TIMEOUT )); fi
  if (( $(date +%s) > deadline )); then echo "prompt-agent: gave up on $target after ${TIMEOUT}s ($code)" >&2; exit 1; fi
  sleep "$RETRY"
done
