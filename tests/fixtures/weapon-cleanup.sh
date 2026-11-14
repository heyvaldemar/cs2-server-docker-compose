#!/bin/bash
# weapon-cleanup.sh <label>: the server's weapon_max_before_cleanup and
# weapon_auto_cleanup_time, read over rcon (tools/rcon.sh), against the values
# hooks/pre.sh writes into server.cfg (64 and 120 unless .env says otherwise).
# Run after a start and after a map change: server.cfg runs on every map.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
label="${1:-now}"
envv() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -1; }
max="$(envv CS2_SERVER_WEAPON_MAX_BEFORE_CLEANUP)"; max="${max:-64}"
age="$(envv CS2_SERVER_WEAPON_AUTO_CLEANUP_TIME)"; age="${age:-120}"
bad=0
for pair in "weapon_max_before_cleanup $max" "weapon_auto_cleanup_time $age"; do
  name="${pair% *}"; want="${pair#* }"
  got="$(tools/rcon.sh "$name" 2>/dev/null | sed -nE "s/.*${name}[^0-9-]*(-?[0-9]+).*/\1/p" | head -1)"
  echo "$label: $name is ${got:-?} (want $want)"
  [ "$got" = "$want" ] || bad=1
done
exit "$bad"
