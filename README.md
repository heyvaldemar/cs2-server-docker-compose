# CS2 server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Counter-Strike 2 dedicated server, pinned by digest, with the details that only show up after running one.

```bash
git clone https://github.com/heyvaldemar/cs2-server-docker-compose
cd cs2-server-docker-compose
cp .env.example .env && $EDITOR .env          # a Steam token and an rcon password
docker volume create cs2-server-data          # see "the volume", below
docker compose -f cs2-server-docker-compose.yml -p cs2 up -d
```

The first start downloads roughly 60 GB through SteamCMD, so it is slow once and fast afterwards. Watch it:

```bash
docker compose -p cs2 logs -f cs2-server
docker compose -p cs2 ps          # healthy once the game process is up
```

## What this file knows that a fresh one does not

**The health check matches the game exactly, not as a substring.** Two commands run in this container: `cs2`, the game, and `cs2.sh`, the script supervising it. Write the check as a substring search and either satisfies it, so the game can crash and leave the wrapper standing while the container reports healthy — and docker does not restart an unhealthy container on its own, so nothing else catches it either. `grep -qsx` anchors the match to the whole line.

That is not a theoretical concern. A Killing Floor 2 server on the machine this template comes from crashed with a core dump and spent seventeen hours green, because its check matched the shell that was running the check. `tests/e2e-healthcheck.sh` proves the distinction against a real container: with the game killed, the exact form goes red and the substring form stays green.

**The game volume is declared external, so `docker compose down -v` cannot delete it.** That is 60 GB of content SteamCMD fetched once, and `down -v` is the command everyone reaches for when a stack misbehaves. On a metered connection it comes back twice: once in bytes and once on the bill. Creating it by hand once is the price of not losing it by accident.

**The published port matches the port the server binds.** Steam's list records what the server bound, not what you forwarded. Publish 27016 for a server on 27015 and the list hands players an address where a different server answers: the connection succeeds, the handshake fails against the wrong game, and every log line blames the client.

**The memory ceiling is measured, not guessed.** A populated server sits around 950 MB; the 4 GB limit is there so a leak here cannot get some other container killed instead. With no limit at all the kernel's OOM killer chooses its victim by size, which means the process it kills is rarely the one at fault.

**Without a Steam token the server runs and is invisible.** It never joins the public list, which from a player's side is indistinguishable from a server that is down.

## Hiding your home address

If you run this at home, the server's address is in Steam's public list. To keep it off, put the game container in the network namespace of a WireGuard sidecar that dials out to a cheap relay: players reach the relay, your router forwards nothing, and nothing at home listens on the internet.

That pattern, including the local door so players in your own house do not travel to another country and back, is [game-server-wireguard-relay-docker-compose](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose).

One warning if you go that way: `network_mode: host` hangs srcds at Steam initialisation on a machine with more than one interface, with no error. The sidecar's namespace is bridge-style, which is why these servers start at all.

## Administration

```bash
# rcon, using the password from .env
docker compose -p cs2 exec cs2-server rcon status

# change the map
docker compose -p cs2 exec cs2-server rcon changelevel de_inferno
```

## Updating

The pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the version this repository has tested. To move deliberately, set `CS2_SERVER_IMAGE_VERSION` in `.env`. `./update.sh` does that on purpose: it moves to the latest release tag, refuses to cross a major unattended, and names any new required variable before anything has moved.

Valve updates CS2 often, and the server refuses connections from a client on a newer build. Pull the image, recreate, and the game content updates on start.

## Testing

`tests/e2e-healthcheck.sh` runs five assertions against a real container and needs no CS2 download: the exact check is green with the game running, the substring check is green too, and after the game is killed the exact one goes red while the substring one stays green with the wrapper still standing.

CI runs it on every push alongside shell and workflow linting, a Trivy scan of the pinned image, and a daily check that the pin still resolves to what upstream publishes.

CI does not boot the game. A GitHub runner has neither the disk for 60 GB of game content nor the hours, and a test that pretends otherwise would be a test that never runs.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
