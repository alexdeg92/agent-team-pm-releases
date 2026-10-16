#!/usr/bin/env bash
# Frozen, gated snapshot of a worktree for a test instance, plus an optional immutable labelled copy for reviewers.
# Env: SRC (worktree), DST (staging dir), GATED (space-separated paths excluded until approved),
#      APPROVED_FILE (one approved gated path per line), LABEL (optional), SNAP_ROOT (where labelled copies go),
#      NODE_MODULES (optional dir to symlink as node_modules)
set -euo pipefail
: "${SRC:?}" "${DST:?}"; GATED=${GATED:-}; APPROVED_FILE=${APPROVED_FILE:-$DST.approved}; touch "$APPROVED_FILE"
EX=(--exclude node_modules --exclude .git)
for g in $GATED; do grep -qxF "$g" "$APPROVED_FILE" || EX+=(--exclude "/$g"); done
mkdir -p "$DST"; rsync -a --delete "${EX[@]}" "$SRC/" "$DST/"
for g in $GATED; do grep -qxF "$g" "$APPROVED_FILE" || rm -rf "${DST:?}/$g"; done
[ -n "${NODE_MODULES:-}" ] && ln -sfn "$NODE_MODULES" "$DST/node_modules"
echo "snapshot: $SRC -> $DST (approved gated: $(tr '\n' ' ' < "$APPROVED_FILE"))"
if [ -n "${LABEL:-}" ]; then
  D=${SNAP_ROOT:-$(dirname "$DST")/snapshots}/$LABEL; rm -rf "$D"; mkdir -p "$(dirname "$D")"
  rsync -a --exclude node_modules "$DST/" "$D/"; [ -n "${NODE_MODULES:-}" ] && ln -sfn "$NODE_MODULES" "$D/node_modules"
  chmod -R a-w "$D"; echo "labelled copy: $D"
fi
