#!/bin/bash
# Does the health check notice when the GAME dies and the wrapper does not?
#
# The container runs two commands: `cs2`, the game, and `cs2.sh`, the script
# that supervises it. A health check written as a substring search is satisfied
# by either, so the game can crash and leave the wrapper standing while the
# container reports healthy for as long as it takes somebody to look. And
# docker does not restart an unhealthy container by itself, so nothing else
# would have caught it either.
#
# That is not hypothetical. A Killing Floor 2 server on the machine this
# template comes from crashed with a core dump and spent the rest of the night
# green, because its check matched the shell running the check.
#
# So this asserts BOTH directions, against a real container:
#   * the exact form goes red when only the wrapper is left,
#   * the substring form stays green, which is what makes the exact form worth
#     the two extra characters.
#
# No CS2 download involved: two processes with the right names are enough, and
# the check reads /proc, not the game.
set -uo pipefail

RUN="cs2hc-$$"
PASSED=0; FAILED=0
cleanup() { docker rm -f "$RUN" >/dev/null 2>&1; }
trap cleanup EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

EXACT='grep -qsx cs2 /proc/[0-9]*/comm'
LOOSE='grep -qs cs2 /proc/[0-9]*/comm'

echo "=== the health check, in both directions ==="
echo

docker rm -f "$RUN" >/dev/null 2>&1
# debian, not alpine: busybox dispatches on argv[0], so a copy of its sleep
# named cs2 is not an applet it knows and exits immediately. A real standalone
# binary takes the name it is invoked under, which is what /proc/N/comm reads.
docker run -d --name "$RUN" debian:stable-slim sh -c '
  cp /bin/sleep /tmp/cs2
  cp /bin/sleep /tmp/cs2.sh
  /tmp/cs2 3600 &
  /tmp/cs2.sh 3600 &
  wait' >/dev/null 2>&1 || { echo "cannot start the fixture container"; exit 1; }

# Both processes have to exist before anything is asserted, or a pass below
# would only mean the container was slow.
ready=false
for _ in $(seq 1 40); do
  if docker exec "$RUN" sh -c "$EXACT" 2>/dev/null; then ready=true; break; fi
  sleep 0.5
done
if [ "$ready" = true ]; then
  pass "with the game running, the exact check is green"
else
  fail "the fixture never came up; nothing below would mean anything"
  docker logs "$RUN" 2>&1 | tail -5 | sed 's/^/        /'
  echo; echo "passed: $PASSED   failed: $FAILED"; exit 1
fi

# Both names are present, so the loose form is green too. It has to be, or the
# comparison below proves nothing.
if docker exec "$RUN" sh -c "$LOOSE" 2>/dev/null; then
  pass "and so is the substring check, as expected"
else
  fail "the substring check was already red, so the fixture is wrong"
fi

# THE CASE THIS EXISTS FOR: kill the game, leave the wrapper.
#
# /proc rather than pgrep: debian:stable-slim ships no procps, and a missing
# command exits non-zero, which a naive check reads as "the process is gone".
# The first version of this file did exactly that and reported a kill that
# never happened - the same shape of silent no-op the health check itself is
# written to avoid.
docker exec "$RUN" sh -c 'for p in /proc/[0-9]*; do
  [ "$(cat "$p/comm" 2>/dev/null)" = "cs2" ] && kill -9 "${p##*/}" 2>/dev/null
done; true' >/dev/null 2>&1
# Waiting on something OTHER than the assertion. Waiting until $EXACT fails and
# then asserting that $EXACT fails proves nothing at all; this reads the comm
# files itself and counts.
gone=false
for _ in $(seq 1 20); do
  n="$(docker exec "$RUN" sh -c 'c=0; for p in /proc/[0-9]*; do
        [ "$(cat "$p/comm" 2>/dev/null)" = "cs2" ] && c=$((c+1)); done; echo "$c"' 2>/dev/null)"
  if [ "${n:-1}" = "0" ]; then gone=true; break; fi
  sleep 0.5
done
if [ "$gone" != true ]; then
  fail "could not kill the game process, so the assertion below is meaningless"
else
  if docker exec "$RUN" sh -c "$EXACT" 2>/dev/null; then
    fail "the exact check stayed green with the game dead"
  else
    pass "with the game dead, the exact check goes red"
  fi

  if docker exec "$RUN" sh -c "$LOOSE" 2>/dev/null; then
    pass "and the substring check stays green — which is the trap this avoids"
  else
    fail "the substring check also went red, so there is nothing to avoid and the comment is wrong"
  fi
fi

# And the wrapper is genuinely still there, so "green" above was about it.
if docker exec "$RUN" sh -c 'grep -qsx cs2.sh /proc/[0-9]*/comm' 2>/dev/null; then
  pass "the wrapper is still running, which is what made the substring check lie"
else
  fail "the wrapper died too, so the scenario was not the one described"
fi

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
