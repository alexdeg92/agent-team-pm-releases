#!/usr/bin/env bash
# Inventory the coding-agent CLIs on this machine: which herdr kinds are installed, their version,
# auth status (when cheaply checkable), no-approval flag (found in their own --help), and notable
# capabilities. Output: a markdown table, or JSON with --json. Read-only; it never starts an agent session.
set -uo pipefail
JSON=0; [ "${1:-}" = --json ] && JSON=1

# herdr kind -> candidate executables (first found wins). A case, not an associative array: macOS ships bash 3.2.
KINDS="agy aider amp claude cline codex copilot cursor devin droid gemini goose grok hermes kilo kimi kiro letta
  maki mastracode muse omp opencode pi qodercli qwen"
exes() { case $1 in cursor) echo "cursor-agent agent";; kiro) echo "kiro-cli kiro";; *) echo "$1";; esac; }
# Kinds herdr can start, if herdr is present (others can still run in a plain pane).
HERDR_KINDS=$(herdr agent start --help 2>/dev/null | sed -n 's/.*possible values: \(.*\)\]/\1/p' | tr -d ' ')

# GNU timeout on Linux, gtimeout from Homebrew coreutils, else perl's alarm (always present on macOS).
TO=$(command -v timeout || command -v gtimeout || true)
t() { if [ -n "$TO" ]; then "$TO" "${2:-8}" bash -c "$1" 2>&1; else perl -e 'alarm shift; exec @ARGV' "${2:-8}" bash -c "$1" 2>&1; fi; }
rows=()
for kind in $KINDS; do
  bin=""; for c in $(exes "$kind"); do command -v "$c" >/dev/null 2>&1 && { bin=$c; break; }; done
  [ -z "$bin" ] && continue
  # `agent` is a generic name; only accept it if its help mentions Cursor.
  if [ "$kind" = cursor ] && [ "$bin" = agent ] && ! grep -qi cursor <<<"$(t "agent --help")"; then continue; fi
  ver=$(t "$bin --version" | head -1 | tr -d '\r' | cut -c1-60)
  help=$(t "$bin --help" 10)
  flag=$(grep -oE -- '--(dangerously-skip-permissions|dangerously-bypass-approvals-and-sandbox|yolo|force|dangerously-allow-all|allow-all-tools|allow-all|auto-approve|skip-permissions-unsafe|no-confirm)\b' <<<"$help" | head -1)
  [ "$kind" = codex ] && grep -q -- '--dangerously-bypass-approvals-and-sandbox' <<<"$help" && flag=--dangerously-bypass-approvals-and-sandbox
  [ "$kind" = cursor ] && grep -q -- '--yolo' <<<"$help" && flag="--yolo --trust"
  auth="unknown"; caps=""
  case "$kind" in
    # Linux keeps the login in ~/.claude/.credentials.json, macOS in the keychain.
    claude) auth=$( [ -n "$(ls ~/.claude/.credentials.json 2>/dev/null)" ] || [ -n "${ANTHROPIC_API_KEY:-}" ] \
              || security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 && echo likely || echo unknown);;
    codex)  auth=$(t "codex login status" | head -1 | cut -c1-40)
            # Capture before grepping: with pipefail, `grep -q` exits on the first match and codex then dies
            # writing the rest of the list (EPIPE, exit 101), which fails the whole pipeline.
            feats=$(t "codex features list")
            if grep -qE '^image_generation +[a-z ]+true' <<<"$feats"; then caps+="image-generation "
            elif grep -qE '^image_generation ' <<<"$feats"; then caps+="image-generation=OFF(codex features enable image_generation) "; fi
            caps+="model=$(grep -E '^model *=' ~/.codex/config.toml 2>/dev/null | cut -d'"' -f2) ";;
    cursor) auth=$(t "$bin status" | grep -oE 'Logged in as [^ ]+' | sed 's/Logged in as /logged-in /' | sed 's/@.*/@…/' || true);;
    gemini) [ -n "${GEMINI_API_KEY:-}" ] || ls ~/.gemini/oauth_creds.json >/dev/null 2>&1 && auth=likely;;
  esac
  inherdr=no; grep -qw "$kind" <<<"${HERDR_KINDS//,/ }" && inherdr=yes
  rows+=("$kind|$bin|${ver:-?}|${auth:-unknown}|${flag:-none found}|${caps:-}|$inherdr")
done

# ${rows[@]+…}: bash before 4.4 treats an empty array as unbound under set -u.
if [ $JSON = 1 ]; then
  printf '%s\n' ${rows[@]+"${rows[@]}"} | jq -R -s 'split("\n")|map(select(length>0)|split("|")|{kind:.[0],bin:.[1],version:.[2],auth:.[3],noApprovalFlag:.[4],caps:.[5],herdrKind:(.[6]=="yes")})'
else
  echo "| kind | bin | version | auth | no-approval flag | capabilities | herdr kind |"
  echo "| --- | --- | --- | --- | --- | --- | --- |"
  for r in ${rows[@]+"${rows[@]}"}; do echo "| ${r//|/ | } |"; done
  [ ${#rows[@]} -eq 0 ] && echo "(no agent CLIs found)"
fi
exit 0
