# pre.sh - the image's pre-start hook: secrets into a cfg, none on a command line.
# shellcheck shell=bash
#
# The image (joedwards32/cs2) sources ${STEAMAPPDIR}/pre.sh after it has
# written server.cfg and before it builds the server's command line. Up to
# v1.4 it put the game server token (+sv_setsteamaccount), the rcon password
# (+rcon_password) and the join password (+sv_password) on that command line,
# where every process in the container and `ps` on the host can read them for
# as long as the server runs, and passed it through eval, which ran a ";" in a
# password as a shell command. The compose file now hands the image those
# three empty and the real values under names the image does not read.
#
# HERE, the values are written with bash builtins (printf, no command line)
# into game/csgo/cfg/secrets.cfg, mode 600, owned by the game's user, which
# runs this. It is rewritten on every start, so a changed .env takes effect on
# the next one. The server runs it twice: at start, from +exec secrets.cfg on
# its command line (CS2_ADDITIONAL_ARGS), so it logs into Steam with the token,
# and on every map, from the line appended here to server.cfg, which the image
# copies fresh on each start and whose own rcon_password and sv_password the
# image left empty.
#
# Sourced, not run: bash, the image's own shell, so it ends without exit,
# which would end the image's entrypoint. One brace group all the same, read
# whole before the first line runs. Every name it sets is unset at the end.
{
# FAIL CLOSED. A secrets.cfg that could not be written is a server with no
# join password, no rcon password and no token: open, and off Steam's list.
# Any failure here ends the image's entrypoint (this file is sourced, so exit
# ends it), and the container stops instead of starting that server. Should a
# server start anyway, server.cfg (copied fresh by the image on every start)
# then ends in quit, and the server stops on its first map instead of opening.
# The new file is written beside the old one, read back and compared, and only
# then moved over it in one rename; a failure removes both, so no start leaves
# old credentials in the volume.
__cfg=""
__fail() {
  if [ -n "$__cfg" ]; then
    rm -f "$__cfg/.secrets.cfg.new" "$__cfg/secrets.cfg"
    [ -f "$__cfg/server.cfg" ] && printf '\nquit\n' >> "$__cfg/server.cfg"
  fi
  echo "pre.sh: $1; not starting a server without its secrets" >&2
  exit 1
}
[ -n "${STEAMAPPDIR:-}" ] || __fail "STEAMAPPDIR is not set"
__cfg="${STEAMAPPDIR}/game/csgo/cfg"
[ -d "$__cfg" ] && [ -f "$__cfg/server.cfg" ] || __fail "no $__cfg/server.cfg"
# A value with a double quote or a line break in it would end its cfg line
# early, and the server would take a different password without a word.
for __v in "${CS2T_STEAM_TOKEN:-}" "${CS2T_RCON_PASSWORD:-}" "${CS2T_SERVER_PASSWORD:-}"; do
  case "$__v" in *'"'*|*$'\n'*|*$'\r'*) __fail "a token or password holds a double quote or a line break" ;; esac
done
__want=""
if [ -n "${CS2T_STEAM_TOKEN:-}" ]; then __want+="sv_setsteamaccount \"${CS2T_STEAM_TOKEN}\""$'\n'; fi
__want+="rcon_password \"${CS2T_RCON_PASSWORD:-}\""$'\n'
__want+="sv_password \"${CS2T_SERVER_PASSWORD:-}\""$'\n'
__umask=$(umask)
umask 077
printf '%s' "$__want" > "$__cfg/.secrets.cfg.new" || __fail "secrets.cfg could not be written"
umask "$__umask"
chmod 600 "$__cfg/.secrets.cfg.new" || __fail "secrets.cfg could not be made private"
# Read back with a bash builtin and compared whole: what the server will read.
__have="$(< "$__cfg/.secrets.cfg.new")"
[ "$__have"$'\n' = "$__want" ] || __fail "secrets.cfg does not hold what was written"
mv -f "$__cfg/.secrets.cfg.new" "$__cfg/secrets.cfg" || __fail "secrets.cfg could not be put in place"
printf '\nexec secrets.cfg\n' >> "$__cfg/server.cfg" || __fail "server.cfg could not be told to run secrets.cfg"
grep -qx 'exec secrets.cfg' "$__cfg/server.cfg" || __fail "server.cfg does not run secrets.cfg"
echo "pre.sh: secrets.cfg written and checked ($(wc -l < "$__cfg/secrets.cfg") settings), and executed by server.cfg on every map"
unset -f __fail
unset CS2T_STEAM_TOKEN CS2T_RCON_PASSWORD CS2T_SERVER_PASSWORD __cfg __umask __want __have __v
}
