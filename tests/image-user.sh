#!/bin/bash
# Does the pinned image still run as the user the volume belongs to?
#
# Every file in cs2-server-data is owned by the user the image runs as, and a
# volume does not follow when an image moves it. joedwards32/cs2 moved it
# twice in eight days, 1000 to 999 on 2026-09-21 and back on 2026-09-23. On
# the machine this template comes from, the first move left both CS2 servers
# unable to write their logs for a day and a half, with the containers
# healthy, the games answering and Steam listing them. A check that asks
# whether the game answers cannot see it.
#
# So the compose file declares the user (x-image-user), and this asks the
# registry what the pinned image runs as. A pin refresh that moves the user
# fails here instead of shipping as a patch. A deliberate move changes
# x-image-user, ships as a major release, and its notes carry the command
# that re-owns the volume:
#   docker run --rm -v cs2-server-data:/v alpine chown -R <uid>:<gid> /v
#
# Then the whole check is run again on a copy of the compose file declaring
# another user, and must fail, so a check that could never fail does not pass
# for one that works.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

COMPOSE=${IMAGE_USER_COMPOSE:-cs2-server-docker-compose.yml}
IMAGE="$(grep -m1 -oE '\$\{CS2_SERVER_IMAGE_TAG:-.*' "$COMPOSE" | sed -E -e ':a' -e 's/\$\{[A-Z0-9_]+:-([^{}]*)\}/\1/' -e 'ta')"
DECLARED="$(grep -m1 -oE '^x-image-user: "[0-9]+:[0-9]+"' "$COMPOSE" | grep -oE '[0-9]+:[0-9]+')"
[ -n "$IMAGE" ] || { echo "could not read the pinned image from $COMPOSE"; exit 1; }
[ -n "$DECLARED" ] || { echo "$COMPOSE declares no x-image-user"; exit 1; }

# The registry's answer, without pulling the image: the config of the
# linux/amd64 image, or of the only image when the pin is not an index.
ACTUAL="$(docker buildx imagetools inspect "$IMAGE" --format '{{json .Image}}' 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "config" not in d:
    d = d.get("linux/amd64", {})
print(d.get("config", {}).get("User", ""))')"
[ -n "$ACTUAL" ] || { echo "could not read the user of $IMAGE from the registry"; exit 1; }
case "$ACTUAL" in
  *[!0-9:]*) echo "FAIL: $IMAGE runs as '$ACTUAL', a name, so the owner its volume needs cannot be read from the image"; exit 1 ;;
esac
# "1000" and "1000:1000" are the same user to a volume: Docker uses the
# user's own group when the image names none.
[ "${ACTUAL#*:}" = "$ACTUAL" ] && ACTUAL="$ACTUAL:$ACTUAL"

if [ "$ACTUAL" != "$DECLARED" ]; then
  echo "  FAIL: ${IMAGE##*/} runs as $ACTUAL, and $COMPOSE declares $DECLARED. Every volume created before this pin belongs to $DECLARED, so upgrading leaves the server unable to write its files. Ship it as a major release with the chown from this script's header in its notes, and change x-image-user."
  exit 1
fi
[ -n "${IMAGE_USER_COMPOSE:-}" ] && exit 0
echo "  PASS: ${IMAGE##*/} runs as $ACTUAL, the user $COMPOSE declares and the volume belongs to"

uid=${ACTUAL%%:*}
moved="$(mktemp)"
trap 'rm -f "$moved"' EXIT
sed -E "s/^x-image-user: \"[0-9]+:[0-9]+\"/x-image-user: \"$((uid + 1)):$((uid + 1))\"/" "$COMPOSE" >"$moved"
if IMAGE_USER_COMPOSE="$moved" "$PWD/tests/image-user.sh" >/dev/null 2>&1; then
  echo "  FAIL: a compose file declaring $((uid + 1)):$((uid + 1)) passed too: this check cannot fail"; exit 1
fi
echo "  PASS: the same check on a copy declaring $((uid + 1)):$((uid + 1)) fails"
