#!/usr/bin/env bash
# Deliver a prompt to a team agent reliably: retry while it is blocked or compacting, resolve by pane title when
# its herdr name was lost (after a reboot), and confirm delivery. It is runtime-agnostic and needs only herdr and jq.
# Usage: prompt-agent.sh <name|pane_id|title-substring> "<message>"   [TIMEOUT=1800 RETRY=30]
set -u
target=$1; msg=$2; TIMEOUT=${TIMEOUT:-1800}; RETRY=${RETRY:-30}
resolve() {
  herdr agent list 2>/dev/null | jq -r --arg t "$target" '.result.agents[]
    | select(.name==$t or .pane_id==$t or ((.terminal_title_stripped // "") | contains($t))) | .pane_id' | head -1
}
deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  pane=$(resolve)
  if [ -z "$pane" ]; then echo "prompt-agent: no agent matches '$target'" >&2; exit 2; fi
  out=$(herdr agent prompt "$pane" "$msg" 2>&1)
  if grep -q '"agent_prompted"' <<<"$out"; then echo "delivered to $target ($pane)"; exit 0; fi
  code=$(grep -o '"code":"[a-z_]*"\|"type":"[a-z_]*"' <<<"$out" | head -1)
  # An agent that is visibly working, with a queued input, isn't stuck: keep waiting while it shows progress.
  if herdr pane read "$pane" --source recent --lines 15 2>/dev/null | tr '\n' ' ' | grep -Eiq 'queued follow-up|working \(|esc to interrupt'; then
    deadline=$(( $(date +%s) + TIMEOUT )); fi
  if (( $(date +%s) > deadline )); then echo "prompt-agent: gave up on $target after ${TIMEOUT}s ($code)" >&2; exit 1; fi
  sleep "$RETRY"
done
