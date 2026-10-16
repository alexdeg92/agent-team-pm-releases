#!/usr/bin/env bash
# Spawn a role-named coding agent in a herdr pane, in no-approval mode, with visible role titles.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: spawn-agent.sh --name <agent-name> --kind <claude|codex|cursor> --title "<Role · job>" --cwd <dir>
                      [--role <role>] [EXTRA_ARGS="-c model_reasoning_effort=high"]
                      (--split-from <pane-id> [--direction right|down] | --new-tab "<tab label>" [--workspace <ws-id>])

Starts the agent with its no-approval flags:
  claude  --dangerously-skip-permissions
  codex   --dangerously-bypass-approvals-and-sandbox
  cursor  --yolo --trust
Then it names the agent, labels the pane and sets herdr display metadata. It also sets the agent's own
session title (what apps like Moshi show) with /rename: two Enters for Codex, whose first Enter only
picks the slash-command menu item. Claude, Codex and Cursor all accept /rename.
Prints the pane id on the last line.
EOF
}

NAME= KIND= ROLE= TITLE= CWD= SPLIT= DIR=right TAB= WS="${HERDR_WORKSPACE_ID:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME=$2; shift 2;; --kind) KIND=$2; shift 2;; --role) ROLE=$2; shift 2;; --title) TITLE=$2; shift 2;;
    --cwd) CWD=$2; shift 2;; --split-from) SPLIT=$2; shift 2;; --direction) DIR=$2; shift 2;;
    --new-tab) TAB=$2; shift 2;; --workspace) WS=$2; shift 2;;
    -h|--help) usage; exit 0;; *) echo "unknown arg: $1" >&2; usage; exit 2;;
  esac
done
[ "${HERDR_ENV:-}" = 1 ] || { echo "not running inside herdr (HERDR_ENV!=1)" >&2; exit 1; }
[ -n "$NAME" ] && [ -n "$KIND" ] && [ -n "$TITLE" ] && [ -n "$CWD" ] || { usage; exit 2; }
[[ "$NAME" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || { echo "bad name (use [a-z][a-z0-9_-]{0,31})" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

case "$KIND" in
  claude) FLAGS=(--dangerously-skip-permissions);;
  codex)  FLAGS=(--dangerously-bypass-approvals-and-sandbox);;
  cursor) FLAGS=(--yolo --trust);;
  *) echo "kind must be claude, codex or cursor" >&2; exit 2;;
esac

# Split arguments without eval; shell quotes inside EXTRA_ARGS are literal.
if [ -n "${EXTRA_ARGS:-}" ]; then
  read -r -a extra <<< "$EXTRA_ARGS"
  FLAGS+=("${extra[@]}")
fi
CWD=$(cd "$CWD" && pwd -P)
TEAM_SCRIPT=$(cd "$(dirname "$0")" && pwd)/team

if [ -n "$TAB" ]; then
  R=$(herdr tab create ${WS:+--workspace "$WS"} --cwd "$CWD" --label "$TAB" --no-focus)
  PANE=$(echo "$R" | jq -r '.result.root_pane.pane_id')
elif [ -n "$SPLIT" ]; then
  PANE=$(herdr pane split --pane "$SPLIT" --direction "$DIR" --cwd "$CWD" --no-focus | jq -r '.result.pane.pane_id')
else
  echo "give --split-from <pane> or --new-tab <label>" >&2; exit 2
fi
[ -n "$PANE" ] && [ "$PANE" != null ] || { echo "could not create pane" >&2; exit 1; }
sleep 2

# Recovery is bounded: one self-update restart, one trust confirmation. Never send
# rename until start succeeded or the trusted CLI is visibly idle at its composer.
start_agent() {
  if START_RESULT=$(herdr agent start "$NAME" --kind "$KIND" --pane "$PANE" --timeout 90000 -- "${FLAGS[@]}" 2>&1); then
    jq -e '.result.agent.name' <<< "$START_RESULT" >/dev/null 2>&1
  else return 1; fi
}
visible() { herdr pane read "$PANE" --source visible --lines 40 | tr '\n' ' ' | tr -s ' '; }
wait_shell() {
  local i
  for ((i=0; i<60; i++)); do
    if herdr pane process-info --pane "$PANE" | jq -e '
      .result.process_info | .shell_pid != null and
      .foreground_process_group_id == .shell_pid' >/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}
wait_composer() {
  local i
  for ((i=0; i<60; i++)); do
    if herdr pane get "$PANE" | jq -e --arg kind "$KIND" '
      .result.pane | .agent == $kind and
      (.agent_status == "idle" or .agent_status == "done")' >/dev/null; then
      if ! visible | grep -Fq 'Trust this folder?'; then return 0; fi
    fi
    sleep 1
  done
  return 1
}
if ! start_agent; then
  if [ "$KIND" != codex ] || ! grep -q 'agent_not_ready' <<< "$START_RESULT"; then
    echo "agent start failed in $PANE; inspect the pane" >&2; exit 1
  fi
  NEED_TRUST=1
  TEXT=$(visible)
  if grep -Eq 'Updating Codex via npm|Update ran successfully.*restart Codex' <<< "$TEXT"; then
    wait_shell || { echo "Codex update did not return to shell in $PANE" >&2; exit 1; }
    if start_agent; then NEED_TRUST=0; else
      grep -q 'agent_not_ready' <<< "$START_RESULT" || { echo "Codex restart failed in $PANE" >&2; exit 1; }
      TEXT=$(visible)
    fi
  fi
  if [ "$NEED_TRUST" = 1 ]; then
    if ! grep -Fq 'Trust this folder?' <<< "$TEXT"; then
      echo "Codex not ready in $PANE; inspect the pane" >&2; exit 1
    fi
    ACTUAL=$(herdr pane get "$PANE" | jq -r '.result.pane.foreground_cwd // empty')
    ACTUAL=$(cd "$ACTUAL" 2>/dev/null && pwd -P) || ACTUAL=
    [ "$ACTUAL" = "$CWD" ] || { echo "refusing folder trust: pane directory differs from chosen worktree" >&2; exit 1; }
    herdr pane send-keys "$PANE" enter >/dev/null
    wait_composer || { echo "Codex composer not ready in $PANE" >&2; exit 1; }
    herdr agent rename "$PANE" "$NAME" >/dev/null
  fi
fi

herdr pane rename "$PANE" "$TITLE ($KIND)" >/dev/null
herdr pane report-metadata "$PANE" --source pm --title "$TITLE" --display-agent "$NAME ($KIND)" >/dev/null || true

# Set the agent's own session title (shown by mobile/desktop agent viewers).
if true; then
  herdr pane send-text "$PANE" "/rename $TITLE" >/dev/null
  herdr pane send-keys "$PANE" enter >/dev/null
  if [ "$KIND" = codex ]; then sleep 2; herdr pane send-keys "$PANE" enter >/dev/null; fi
  sleep 3
  GOT=$(herdr pane get "$PANE" | jq -r '.result.pane.terminal_title_stripped')
  if [ "$KIND" = cursor ] && [[ "$GOT" != "$TITLE"* ]]; then
    herdr pane send-keys "$PANE" enter >/dev/null
    sleep 3
    GOT=$(herdr pane get "$PANE" | jq -r '.result.pane.terminal_title_stripped')
  fi
  case "$GOT" in "$TITLE"*) ;; *) echo "warning: session title did not take in $PANE" >&2;; esac
fi
# Record the member with a stable id and spawnedBy = the spawner, so dashboards (e.g. Agent Office) can show
# lineage from ids instead of guessing from names. ROLE comes from --role (default builder).
(cd "${CWD:-.}" && TEAM_NO_NUDGE=1 "$TEAM_SCRIPT" member register "$NAME" --role "${ROLE:-builder}" \
  --runtime "$KIND" --spawned-by "${TEAM_AGENT:-pm}" >/dev/null) || echo "warning: team member register failed" >&2
echo "$PANE"
