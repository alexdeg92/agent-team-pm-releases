#!/usr/bin/env bash
# Run a heavy command (a full test suite, a deploy, a GPU job) under a named machine-wide lock, so agents and
# the PM queue instead of colliding. Usage: run-exclusive.sh <lock-name> <command…>   [WAIT=3600]
set -u
name=$1; shift
lock=/tmp/run-exclusive-$USER-$name.lock
exec 9>"$lock"
# flock(1) on Linux. macOS has no flock binary, so perl takes the same flock(2) lock on fd 9; it outlives perl
# because this shell still holds the descriptor.
lock9() {
  if command -v flock >/dev/null; then flock -w "$1" 9; return; fi
  perl -MFcntl=:flock -e 'open(my $f, ">&=", 9) or exit 1; my $end = time + shift;
    until (flock($f, LOCK_EX | LOCK_NB)) { exit 1 if time >= $end; select(undef, undef, undef, 0.5) }' "$1"
}
if ! lock9 "${WAIT:-3600}"; then echo "run-exclusive: '$name' still held after ${WAIT:-3600}s by: $(cat "$lock.owner" 2>/dev/null)" >&2; exit 75; fi
echo "${HERDR_PANE_ID:-$$} $(date +%H:%M) $*" > "$lock.owner"
"$@"; rc=$?
rm -f "$lock.owner"
exit $rc
