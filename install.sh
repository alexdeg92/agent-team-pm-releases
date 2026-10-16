#!/usr/bin/env bash
# Download a released package, check its digest and use its Node installer.
set -euo pipefail
VERSION=${AGENT_TEAM_PM_VERSION:-0.1.1}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid release version" >&2; exit 2; }
for cmd in node curl tar; do command -v "$cmd" >/dev/null || { echo "$cmd is required" >&2; exit 1; }; done
node -e 'if (Number(process.versions.node.split(".")[0]) < 18) process.exit(1)' || { echo "Node.js 18 or later is required" >&2; exit 1; }
if command -v shasum >/dev/null; then CHECK=(shasum -a 256 -c); elif command -v sha256sum >/dev/null; then CHECK=(sha256sum -c); else echo "shasum or sha256sum is required" >&2; exit 1; fi
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FILE="agent-team-pm-$VERSION.tgz"
BASE="https://github.com/alexdeg92/agent-team-pm-releases/releases/download/v$VERSION"
for suffix in '' .sha256; do
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 "$BASE/$FILE$suffix" -o "$WORK/$FILE$suffix"
done
(cd "$WORK" && "${CHECK[@]}" "$FILE.sha256")
tar -xzf "$WORK/$FILE" -C "$WORK"
[ $# -gt 0 ] || set -- install
node "$WORK/package/bin/agent-team-pm.js" "$@"
