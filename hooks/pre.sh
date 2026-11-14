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
__cfg="${STEAMAPPDIR}/game/csgo/cfg"
__umask=$(umask)
umask 077
{
  if [ -n "${CS2T_STEAM_TOKEN:-}" ]; then printf 'sv_setsteamaccount "%s"\n' "$CS2T_STEAM_TOKEN"; fi
  printf 'rcon_password "%s"\n' "${CS2T_RCON_PASSWORD:-}"
  printf 'sv_password "%s"\n' "${CS2T_SERVER_PASSWORD:-}"
} > "$__cfg/secrets.cfg"
umask "$__umask"
chmod 600 "$__cfg/secrets.cfg"
printf '\nexec secrets.cfg\n' >> "$__cfg/server.cfg"
echo "pre.sh: secrets.cfg written ($(wc -l < "$__cfg/secrets.cfg") settings), and executed by server.cfg on every map"
unset CS2T_STEAM_TOKEN CS2T_RCON_PASSWORD CS2T_SERVER_PASSWORD __cfg __umask
}
