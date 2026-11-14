# CS2 server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/workflows/deployment-verification.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14894/badge)](https://www.bestpractices.dev/projects/14894)
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
docker compose -p cs2 ps          # healthy once the game answers A2S_INFO
```

## What this file knows that a fresh one does not

**The health check asks the game, not its process.** `tools/healthcheck.sh`, mounted read-only, sends A2S_INFO, the query every server browser sends, to the game port and is healthy only on the engine's reply. Up to v1.3.3 it looked for `cs2` in `/proc`, exactly so that the `cs2.sh` wrapper could not satisfy it; but a hung or stopped game keeps its process too, and on Docker Engine 29.4.2 Black Mesa's server, in its own template, ran with no socket at all while that kind of check stayed green. The log is not read either. A map change silences it for seconds; one check tries twice, and Docker allows three misses at a 60-second interval. Each check ends within 7 seconds. **It asks from inside the container**, at the address the game answers on: healthy proves the server answers there, not that the port is published on the host or open in your firewall. Check that from outside, with a server browser or `tools/steam-uptodate.sh --check`. The query goes out in one write: bash writes printf's output line by line, and up to v1.4 a request echoing the server's challenge was cut in two wherever the challenge held a newline byte, and that try went unanswered.

**The game volume is declared external, so `docker compose down -v` cannot delete it.** That is 60 GB of content SteamCMD fetched once, and `down -v` is the command everyone reaches for when a stack misbehaves. On a metered connection it comes back twice: once in bytes and once on the bill. Creating it by hand once is the price of not losing it by accident.

**The published port matches the port the server binds.** Steam's list records what the server bound, not what you forwarded. Publish 27016 for a server on 27015 and the list hands players an address where a different server answers: the connection succeeds, the handshake fails against the wrong game, and every log line blames the client.

**The memory ceiling is measured, not guessed.** A populated server sits around 950 MB; the 4 GB limit is there so a leak here cannot get some other container killed instead. With no limit at all the kernel's OOM killer chooses its victim by size, which means the process it kills is rarely the one at fault.

**Without a Steam token the server runs and is invisible.** It never joins the public list, which from a player's side is indistinguishable from a server that is down.

**The image's user is written down, and checked against the registry.** Every file in the volume belongs to the user the image runs as, and a volume does not follow when an image moves it. `joedwards32/cs2` moved it twice in eight days in September 2026, 1000 to 999 and back. On the machine this template comes from, the first move left both CS2 servers unable to write their logs for a day and a half, with the containers healthy, the games answering and Steam listing them. The compose file now declares `x-image-user: "1000:1000"`, and `tests/image-user.sh` fails when the pinned image runs as anyone else, so a pin refresh that moves the user cannot ship as a patch. Every release of this template so far has pinned an image that runs as 1000:1000. If one ever moves it, its notes carry the one command that re-owns the volume: `docker run --rm -v cs2-server-data:/v alpine chown -R <uid>:<gid> /v`.

**Docker Engine 29.4.2 stops SteamCMD, and only that release does.** Its default seccomp profile answers the 32-bit `socketcall` system call with "not implemented" ([moby/moby#52506](https://github.com/moby/moby/issues/52506); for GitHub Actions, the ubuntu-26.04 runner image ships it: [actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790), with the move to 29.7.2 in [actions/runner-images#15205](https://github.com/actions/runner-images/pull/15205)), and SteamCMD is a 32-bit program that makes every socket with it. With Steam and the network both up, it prints `!!! Fatal Error: Steamcmd needs to be online to update.` or `CreateBoundSocket: failed to create socket, error [no name available] (38)`, and the game is never installed or updated. Measured in [a CI run on GitHub's ubuntu-26.04 runner, which ships 29.4.2](https://github.com/heyvaldemar/tf2-server-docker-compose/blob/main/docs/evidence/docker-29.4.2-socketcall.md): SteamCMD failed in this template's pinned image there, and logged in once the daemon had the profile Docker 29.4.3 ships. 29.4.3 reverted the rule, and Ubuntu 26.04's own `docker.io` (27.5.1) never had it. Check with `docker version --format '{{.Server.Version}}'` and upgrade; until you can, point [`seccomp-profile` in `daemon.json`](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file) at [moby/profiles seccomp v0.2.3](https://github.com/moby/profiles/blob/836ae4d37ef2ec995c77c99fc55f5b5f3af3a897/seccomp/default.json) and restart Docker.

**No secret on the server's command line.** The image puts the game server token, the rcon password and the join password on the game's command line (`+sv_setsteamaccount`, `+rcon_password`, `+sv_password`), where every process in the container and `ps` on the host can read them for as long as the server runs, and builds that line with `eval`, which ran a `;` in a password as a shell command. The compose file hands the image those three empty and the real values to `hooks/pre.sh`, the image's pre-start hook, which writes them with bash builtins into `game/csgo/cfg/secrets.cfg` (mode 600, the game's user) on every start. The server executes it at start (`+exec secrets.cfg`, so it logs into Steam with the token) and on every map, from a line appended to `server.cfg`. `tests/secret-probe.sh` gives each a value of its own on the real server and requires it in no `docker compose logs`, no game log, no command line in the container and no `ps` on the host; it also proves the server still logs in with the token (its SteamID is a persistent game server's), that its `sv_password`, read over rcon, is the join password and is empty when none is set (CS2's A2S answer reports no password either way, with the image's own `+sv_password` too: [run 43555619039](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/runs/43555619039)), and that a wrong rcon password is refused.

CS2 does not report a join password in its A2S answer ("password required" reads no with the image's own `+sv_password` as well as from `secrets.cfg`: [run 43555619039](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/runs/43555619039)), so the real-server test reads `sv_password` over rcon instead, the moment the health check first goes green.

## Hiding your home address

If you run this at home, the server's address is in Steam's public list. To keep it off, put the game container in the network namespace of a WireGuard sidecar that dials out to a cheap relay: players reach the relay, your router forwards nothing, and nothing at home listens on the internet.

That pattern, including the local door so players in your own house do not travel to another country and back, is [game-server-wireguard-relay-docker-compose](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose).

One warning if you go that way: `network_mode: host` hangs srcds at Steam initialisation on a machine with more than one interface, with no error. The sidecar's namespace is bridge-style, which is why these servers start at all.

## Administration

```bash
# rcon, using the password from .env
tools/rcon.sh status

# change the map
tools/rcon.sh changelevel de_inferno
```

Up to v1.3 this said `docker compose -p cs2 exec cs2-server rcon status`, and rcon could not work at all, for two reasons. The image has no rcon program. And the compose file set `CS2_RCON_PORT` to the game port, which makes the image's entry script start `socat` on that TCP port, forwarding it to itself, before the game starts: the game never got its rcon socket, and every connection was closed unanswered. Both were measured on a real CS2 booted on a CI runner on 2026-11-01 (73 GB, 22 minutes): with the old file the connection was closed ([run](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/runs/41369517037)); without `CS2_RCON_PORT`, `tools/rcon.sh status` came back with the hostname and version 1.41.9.4, a wrong password was refused, and Steam called the server current ([run](https://github.com/heyvaldemar/cs2-server-docker-compose/actions/runs/41372125676)). `tools/rcon.sh` runs the protocol in the image's own python3 from inside the container and takes the password from `.env` on stdin, never from the command line where `ps` would show it.

## Keeping the game current

**A healthy server is not a joinable one.** On the machine this template comes from, Team Fortress 2 ran out of date for days in October 2026 while every check passed: the container was healthy, A2S answered, Steam listed the server, and the image watchers had nothing to say because the image had not changed. Players on the current client cannot join a server Steam calls out of date. Steam answers that question directly: `ISteamApps/UpToDateCheck` takes the version a server reports over A2S and says whether it is still accepted. `tools/steam-uptodate.sh` asks it every fifteen minutes, and this image updates the game on every start, so a restart is the update:

- **current**: nothing.
- **behind, people on**: it says so once and waits. A restart drops them.
- **behind, nobody on**: it restarts the server and asks Steam again until Steam calls the new version current. Steam's answer is the proof, not the restart.
- **still behind after three restarts in 24 hours**: it says so once, stops trying, and fails every run, so the timer shows up in `systemctl --failed`.
- **no answer** from the server or from Steam: nothing is decided. A player count it cannot read is never zero. Six hours of silence (`STEAM_UPTODATE_SILENCE`) and it fails.

**One update per host per pass.** On the machine this template comes from, CS2 and CS2 Classic were both behind on the same evening and were updated back to back; each restart had SteamCMD verify 73 GB, and the CPU reached 81 °C. The TF2, CS2, CS2 Classic and Left 4 Dead 2 templates ship the same script and share one host-wide lock and stamp (`/var/tmp/steam-uptodate.*`), so a second server that is behind waits for a pass fifteen minutes after the first one finished. Their timers fire three minutes apart for the same reason.

"Says so" is one line in the journal every run, and, when `STEAM_UPTODATE_NOTIFY` is set, a message on its stdin the first time something new happens: a webhook, mail, anything that reads stdin. The service file has an example.

```bash
# edit the two paths in the service file to where this repository is checked out
sudo cp systemd/steam-uptodate.service systemd/steam-uptodate.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now steam-uptodate.timer
tools/steam-uptodate.sh --check      # what Steam says right now
```

**The timer runs on UTC, with a net under it.** The night the clocks went back an hour, the server this template comes from ran none of its local-time timers for that hour: systemd reads a local calendar in wall-clock time and took the repeated hour as already gone. A calendar in UTC has no repeated hour, and `OnUnitActiveSec=16min` makes up a run missed for any other reason. `tests/timers.sh` checks both with `systemd-analyze` from one second before a fall-back (Berlin's, on 25 October 2026). The script is one brace group read whole before it runs, so an edit to its file mid-run cannot change what the run does (`tests/read-whole.sh`).

## Updating

The pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the version this repository has tested. To move deliberately, set `CS2_SERVER_IMAGE_VERSION` in `.env`. `./update.sh` does that on purpose: it moves to the latest release tag, refuses to cross a major unattended, and names any new required variable before anything has moved.

Valve updates CS2 often, and the server refuses connections from a client on a newer build. Pull the image, recreate, and the game content updates on start.

## Testing

`tests/e2e-healthcheck.sh` runs the health check in the pinned image against a stand-in that answers A2S_INFO, answers after a challenge, stays silent, or is not there: healthy, healthy, unhealthy within 7 seconds, unhealthy.

`tests/image-user.sh` asks the registry, without pulling, what the pinned image runs as, compares it with `x-image-user`, and then runs again on a copy of the compose file declaring another user, which must fail.

`tests/steam-uptodate.sh` drives every branch of `tools/steam-uptodate.sh` against stubbed A2S and Steam answers (current, behind with people on, behind and empty, a restart Steam does not accept, three tries a day, silence, another update on the host), then runs four copies with one rule taken out each (the player count, the proof by Steam, the host lock, the daily limit) and sees each do what the rule prevents. `tests/read-whole.sh` and `tests/timers.sh` check the script and its timer.

CI runs all of them on every push alongside shell and workflow linting, a Trivy scan of the pinned image, and a daily check that the pin still resolves to what upstream publishes.

`tests/e2e-healthcheck.sh` also runs the check against a stand-in whose challenge holds a newline byte and answers only one datagram of exactly the query and the challenge: the v1.4 check sent it in two pieces, 26 and 3 bytes, and stays unhealthy; this one sends one 29-byte datagram.

`tests/rcon.sh` runs `tools/rcon.sh` in the pinned image's own python3 against `tests/fixtures/fake-rcon.py`, started in the pinned image as this compose file's service: `status` read to its end marker, a server that never answers the marker (read until it goes quiet, no hang), a wrong password, no password, and a plant, a client that waits only for the marker. It also fails if `CS2_RCON_PORT` comes back at the game port, with a plant that puts it back.

**The real server** runs in `.github/workflows/real-server.yml`, not on every push: the install is 73 GB and took 22 minutes on a runner (measured 2026-11-01). It installs and boots the game, samples the health check before the game runs and needs it red, waits for it to go green on the engine's A2S answer, changes the map over rcon and needs it answering again on the new map with Docker healthy throughout, proves the token, the join password and the rcon password work from `secrets.cfg`, restarts it, runs `tests/secret-probe.sh` after the first start and after the restart, then **stops the game** with SIGSTOP and needs it red while the old `/proc` check stays green, and green again after SIGCONT. It runs on a push or pull request that touches the health check, its stand-in test, the compose file (every image pin is there), `.env.example` or the workflow itself, so a pin update meets the real server before it is merged; every Monday at 04:47 UTC; and by hand. It needs a real game server token in the repository secret `CS2_CI_STEAM_TOKEN`: with a placeholder, CS2 no longer logs into Steam and never binds its port (measured 2026-11-08 on two runner images; on 2026-11-01 a placeholder still worked), and until the secret exists the workflow stays red, which is the health check telling the truth about a server nobody can reach.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · CNCF Ambassador · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
