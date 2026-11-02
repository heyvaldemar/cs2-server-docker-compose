#!/bin/bash
# tools/rcon.sh, against a stand-in that speaks rcon, inside the pinned image.
#
# CI does not download the 60 GB game, so the server here is
# tests/fixtures/fake-rcon.py. It runs in the pinned image itself, as the
# cs2-server service of the real compose file with only its entrypoint
# replaced, so the test exercises what a person running tools/rcon.sh does:
# the same `docker compose exec`, the image's own python3 (there is no rcon
# program in it), the password on stdin.
#
#   the port  the compose file must not set CS2_RCON_PORT to the game port:
#          the image then proxies that TCP port to itself with socat before
#          the game starts, and every rcon connection is closed unanswered,
#          as it was up to v1.3 on a real CS2; a copy with the line put back
#          is the plant
#   cases  status, read to the end marker, in two packets; a server that
#          never answers the marker, read until it goes quiet; a wrong
#          password, exit 2; no password in .env, exit 1
#   plant  a copy of the client that waits only for the marker: against the
#          server without one it is cut off by its timeout, which is what the
#          quiet-period read prevents
# shellcheck disable=SC2015   # pass and fail always exit 0, so "A && pass || fail" is if-then-else here
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }
T="$(mktemp -d)"
P="rcon-test-$$"
mkdir -p "$T/tools"
COMPOSE_FILE=$(sed -n 's/^COMPOSE_FILE=${[A-Z0-9_]*:-\(.*\)}$/\1/p' tools/rcon.sh)
cp tools/rcon.sh "$T/tools/"; cp "$COMPOSE_FILE" tests/fixtures/fake-rcon.py "$T/"
SERVICE=$(sed -n 's/^SERVICE=//p' tools/rcon.sh)
PWVAR=$(sed -n "s/^pw=\$(sed -n 's\/^\([A-Z0-9_]*\)=\/\/p'.*/\1/p" tools/rcon.sh)
dc() { (cd "$T" && docker compose -f "$COMPOSE_FILE" -f override.yml -p "$P" "$@"); }
cleanup() { dc down -t 1 >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
[ -n "$SERVICE" ] && [ -n "$PWVAR" ] && [ -f "$COMPOSE_FILE" ] && pass "the client names its compose file ($COMPOSE_FILE), service ($SERVICE) and password ($PWVAR)" \
  || { fail "cannot read COMPOSE_FILE=, SERVICE= or the password variable from tools/rcon.sh"; exit 1; }

echo "=== the port ==="
sed -E 's/^([A-Z0-9_]+)=$/\1=ci-placeholder/' .env.example >"$T/.env"
self_proxy() {  # compose file: does it proxy the rcon port onto the game port?
  (cd "$T" && docker compose -f "$1" config --format json 2>/dev/null) | python3 -c '
import json, sys
env = json.load(sys.stdin)["services"][sys.argv[1]].get("environment") or {}
r, g = env.get("CS2_RCON_PORT"), env.get("CS2_PORT", "27015")
print("yes" if r and r == g else "no")' "$SERVICE"
}
[ "$(self_proxy "$COMPOSE_FILE")" = no ] && pass "CS2_RCON_PORT is not the game port, so the game gets its own rcon socket" \
  || fail "the compose file sets CS2_RCON_PORT to the game port: the image's socat takes the port and forwards it to itself"
sed -E 's/^(      CS2_PORT: .*)$/\1\n      CS2_RCON_PORT: 27015/' "$COMPOSE_FILE" >"$T/plant.yml"
[ "$(self_proxy plant.yml)" = yes ] && pass "the plant, CS2_RCON_PORT put back at the game port, is caught" \
  || fail "the plant was not caught, so this check cannot tell"

start() {  # marker 1|0: the stand-in, in the pinned image, as the real service
  cat >"$T/override.yml" <<YML
services:
  $SERVICE:
    entrypoint: ["python3", "/fake-rcon.py"]
    command: !reset []
    ports: !reset []
    volumes: !override
      - ./fake-rcon.py:/fake-rcon.py:ro
    environment:
      FAKE_PW: right-password
      FAKE_MARKER: "$1"
    healthcheck:
      disable: true
volumes: !reset {}
YML
  sed -E 's/^([A-Z0-9_]+)=$/\1=ci-placeholder/' .env.example >"$T/.env"
  sed -i.bak "s/^$PWVAR=.*/$PWVAR=right-password/" "$T/.env"
  dc up -d --force-recreate >/dev/null 2>&1 || { fail "the stand-in did not start"; dc logs; exit 1; }
  for _ in $(seq 1 30); do dc logs "$SERVICE" 2>/dev/null | grep -q "fake rcon listening" && return; sleep 1; done
  fail "the stand-in never listened"; dc logs "$SERVICE"; exit 1
}
run() { out=$(cd "$T" && COMPOSE_PROJECT_NAME="$P" tools/rcon.sh "$@" 2>&1); rc=$?; }

echo "=== a server that answers the end marker ==="
start 1
run status
[ "$rc" = 0 ] && [[ $out == *"hostname: stand-in"*"version : 1.41.9.4"* ]] && pass "status, both packets, read to the marker" || fail "status: exit $rc, $out"
t0=$(date +%s); run echo hi; t=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && [[ $out == "ran: echo hi"* ]] && [ "$t" -lt 5 ] && pass "a command with arguments, back in ${t}s" || fail "echo: exit $rc in ${t}s, $out"
sed -i.bak "s/^$PWVAR=.*/$PWVAR=wrong-password/" "$T/.env"; run status
[ "$rc" = 2 ] && [[ $out == *"refused the password"* ]] && pass "a wrong password: refused, exit 2" || fail "wrong password: exit $rc, $out"
sed -i.bak "s/^$PWVAR=.*/$PWVAR=/" "$T/.env"; run status
[ "$rc" = 1 ] && [[ $out == *"is not set in .env"* ]] && pass "no password in .env: exit 1, said" || fail "no password: exit $rc, $out"

echo "=== a server that never answers the marker ==="
start 0
t0=$(date +%s); run status; t=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && [[ $out == *"hostname: stand-in"*"version : 1.41.9.4"* ]] && [ "$t" -lt 10 ] \
  && pass "status read whole until the server went quiet, in ${t}s, no hang" || fail "no marker: exit $rc in ${t}s, $out"

echo "=== plant: a client that waits only for the marker ==="
sed -e 's/^        s.settimeout(1.5)                     # then: quiet this long is the end$/        s.settimeout(30)/' tools/rcon.sh >"$T/tools/rcon.sh"
grep -q 'settimeout(30)' "$T/tools/rcon.sh" || fail "the plant did not apply"
t0=$(date +%s); run status; t=$(( $(date +%s) - t0 ))
[ "$t" -ge 25 ] && pass "without the quiet-period read it sat ${t}s on a reply that had ended: the case above can tell" \
  || fail "the plant returned in ${t}s, so the no-marker case cannot tell the difference"

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
