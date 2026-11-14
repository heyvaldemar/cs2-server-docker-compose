#!/bin/bash
# sv-password.sh [NAME]: the server's sv_password, read over rcon (tools/rcon.sh),
# against the value tests/secret-probe.sh planted for NAME, or empty when no
# NAME is given. Prints the reply with every planted value replaced by its
# name, never a value; exits 0 only on a match. CS2 reports no password in its
# A2S answer, with the image's own +sv_password either (run 43555619039), so
# rcon is where a join password can be seen in effect.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
umask 077
VALUES="${PROBE_VALUES:-${RUNNER_TEMP:-/tmp}/secret-probe.values}"
out="$(mktemp)"; trap 'rm -f "$out"' EXIT
tools/rcon.sh sv_password >"$out" 2>&1
WANT="${1:-}" VALUES="$VALUES" OUT="$out" python3 - <<'PY'
import os, re, sys
vals = dict(l.rstrip("\n").split("\t", 1) for l in open(os.environ["VALUES"]))
out = open(os.environ["OUT"], errors="replace").read()
want = vals.get(os.environ["WANT"], "") if os.environ["WANT"] else ""
m = re.search(r"sv_password\s*=\s*(.*)", out)
have = m.group(1).strip().strip('"') if m else None
shown = out
for k, v in vals.items():
    shown = shown.replace(v, "<" + k + ">")
print("rcon sv_password:", " ".join(shown.split())[:160])
sys.exit(0 if have is not None and have == want else 1)
PY
