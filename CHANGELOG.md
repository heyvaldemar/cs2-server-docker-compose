# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.5.0] - 2026-11-14

### Security

- **The game server token, the rcon password and the join password are no longer on the server's command line.** The image put all three there (`+sv_setsteamaccount`, `+rcon_password`, `+sv_password`), readable by every process in the container and by `ps` on the host for as long as the server ran. The compose file now passes them to the image empty, and `hooks/pre.sh`, the image's pre-start hook, writes them into `game/csgo/cfg/secrets.cfg` (mode 600), which the server executes at start and on every map. If the file cannot be written and read back whole, or a value holds a double quote or a line break, the container stops rather than start a server without its secrets.
- **A `;` in a password no longer runs as a shell command.** The image builds the server's command line with `eval`, so a password containing `;` (or `$(…)`) was executed by the container's shell at every start. No password reaches that `eval` any more.

### Fixed

- **The health check could cut its own request in two.** bash writes printf's output line by line, so the query echoing the server's challenge went out as two datagrams whenever the challenge held a newline byte (0x0a), and that try went unanswered. The request now goes to a file first and out in one write. `tests/e2e-healthcheck.sh` proves it against a stand-in whose challenge holds one: the v1.4 check sends 26 and 3 bytes and stays unhealthy, this one one datagram of 29.

- **An index pushed again over the same build is no longer reported as drift.** The daily pin check compared each pin with the digest the tag's index has now and failed on any difference, so a publisher re-pushing the index over the very same images (a platform added, an attestation rewritten) turned it red for an image nobody rebuilt, and no pin would ever move to turn it green. It now also compares the linux/amd64 build under both digests, the one CI runs and proves: the same build passes with a notice naming both digests, a new build fails as drift exactly as before, and a build that cannot be read still fails.

### Changed

- **CI proves no secret leaks, on the real server.** `tests/secret-probe.sh` gives every secret the compose file passes a value of its own (the token is the real one, from a repository secret) and requires it in no `docker compose logs`, no game log, no command line in the container and no `ps` on the host, after the first start and again after a restart, with a self-test that plants a canary in all three places. `real-server.yml` also proves the token is in effect (the server's SteamID is a persistent game server's), the join password is (the server's `sv_password`, read over rcon, is the planted value, and empty with none set, so an open server stays open; CS2's A2S reports no password either way, measured with the image's own `+sv_password` too) and a wrong rcon password is refused.
## [1.4.0] - 2026-11-09

### Changed

- **The health check asks the game, not its process.** It looked for `cs2` in `/proc`, which a hung or stopped game keeps. `tools/healthcheck.sh`, mounted read-only, now sends A2S_INFO to the game port at the address the game answers on and is healthy only on the engine's reply (challenge handled, two tries for a map change, within 7 seconds). It reads `/proc/net/udp6` as well as `/proc/net/udp`: CS2 now binds `[::]`, a dual-stack socket only udp6 lists (measured 2026-11-08; on 2026-11-01 it bound `0.0.0.0`). It asks from inside the container, so it does not prove the port is published on the host or open in a firewall; the README says so.
- **A new workflow, Real Server, boots the game and proves the check against it.** Red before the game runs, green on the engine's A2S answer, answering again after a map change with Docker healthy throughout, red with the game stopped by SIGSTOP while the old `/proc` check stays green, green again after SIGCONT. The install is 73 GB, so it runs on a push or pull request that touches the check, its test, the compose file, `.env.example` or the workflow, every Monday, and by hand. Every push runs the check in the pinned image against a stand-in.
- **The README names Docker Engine 29.4.2.** That release alone stops SteamCMD, which this image runs to install and update the game (measured on this template's pinned image in tf2-server-docker-compose run 42496129688): upgrade to 29.4.3 or later, which reverted the rule, or point the daemon's `seccomp-profile` at the profile 29.4.3 ships. Ubuntu 26.04's own `docker.io` (27.5.1) never had it; on GitHub Actions the ubuntu-26.04 runner image ships it ([actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790), moving to 29.7.2 in [#15205](https://github.com/actions/runner-images/pull/15205)). Documentation only.
## [1.3.3] - 2026-11-01

### Changed

- **The fall-back night is shown on a neutral zone.** `tests/timers.sh` reads Berlin's fall-back on 25 October 2026; any zone with a fall-back shows the same skip, and the test still fails on a calendar without `UTC`. The README and the timer's comment no longer name the night by date and hour.
## [1.3.2] - 2026-11-01

### Fixed

- **rcon works; before this release it could not, for two reasons.** The README said `docker compose -p cs2 exec cs2-server rcon status`, and the pinned image has no rcon program (`command -v rcon` inside it is empty). And the compose file set `CS2_RCON_PORT` to the game port since 1.0.0; the image's entry script then starts `socat` on that TCP port, forwarding it to itself, before the game starts, so the game never got its rcon socket and every rcon connection was closed unanswered. Measured on a real CS2 booted on a CI runner: with the old file the connection was closed (run 41369517037); without `CS2_RCON_PORT`, `tools/rcon.sh status` returned the hostname and version 1.41.9.4, a wrong password was refused, and Steam called the server current (run 41372125676). `tools/rcon.sh` runs the protocol in the image's own python3 from inside the container, with the password from `.env` on stdin, never in argv. `tests/rcon.sh` runs it in CI against a stand-in started in the pinned image as this compose file's service, and fails if `CS2_RCON_PORT` comes back at the game port.
## [1.3.1] - 2026-11-01

### Changed

- **The Steam check's probe image is pinned by digest.** `tools/steam-uptodate.sh` asks A2S and Steam from a python container in the server's network namespace; 1.3.0 named it by tag, `python:3.13-alpine`, so whoever moved that tag decided what ran there. It is now `python:3.13-alpine@sha256:7984cf56…`, and `STEAM_UPTODATE_PROBE_IMAGE` still overrides it.
## [1.3.0] - 2026-11-01

### Added

- **`tools/steam-uptodate.sh` and a systemd timer: Steam is asked every fifteen minutes whether the server is current, and an empty server that is not gets restarted.** This image updates the game on every start, and nothing decided when a start was due. The script reads the version the server reports over A2S and asks Steam's `UpToDateCheck`, the question that, on the machine this template comes from, nobody asked while Team Fortress 2 sat out of date for days with every check green. Behind with people on, it says so once and waits. Behind and empty, it restarts the server and asks Steam again until Steam calls the new version current: the proof is Steam's answer, never the restart. At most three restarts in 24 hours, then it says so once and fails every run. One update per host per pass, by a lock and a stamp shared with the other Source templates: two 73 GB verifications back to back took a CPU there to 81 °C. A silent server or Steam decides nothing, for up to six hours. Something new also goes to `STEAM_UPTODATE_NOTIFY` when it is set. The timer is on UTC with an `OnUnitActiveSec` net (`tests/timers.sh`), the script is one brace group read whole before it runs (`tests/read-whole.sh`), and `tests/steam-uptodate.sh` drives every branch against stubbed answers, with four plants, one rule taken out each.
## [1.2.2] - 2026-10-25

### Added

- **The image's user is declared and checked.** Every file in `cs2-server-data` belongs to the user the image runs as, and `joedwards32/cs2` moved it twice in eight days in September 2026, 1000 to 999 and back; on the machine this template comes from, the first move left the servers unable to write their logs for a day and a half while every health check stayed green. The compose file declares `x-image-user: "1000:1000"`, and `tests/image-user.sh`, run in CI, fails when the pinned image runs as anyone else, so a pin refresh that moves the user stops before it ships as a patch. Nothing changes for a running server: every release so far, this one included, pins an image that runs as 1000:1000.

## [1.2.1] - 2026-10-24

### Changed

- **`joedwards32/cs2:5.0.0` moved to `joedwards32/cs2:5.0.1`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.
- **The freshness check has its own workflow, Pin Freshness.** It ran inside Deployment Verification, whose badge is the one at the top of this README. Across the fleet, nine red runs in ten were a pin one version behind - which the fleet's triage moves within the day - and a reader cannot tell that from a stack that does not boot. The badge now says whether the stack boots. The job itself is unchanged.

### Fixed

- **`update.sh` no longer stops without a word when a release adds a variable and no compose file requires one.** The search for `${VAR:?}` came back empty, and under `pipefail` that empty result ended the script with status 1 right after it listed the new variables.
- **`update.sh` stops on a `.env` it cannot read, before the checkout.** It used to fall through: every new required variable read as "not set", or, with none, the tree moved to the new tag and `docker compose up` failed on the permission. Now it names the file, its owner and mode, and changes nothing.

## [1.2.0] - 2026-09-20

### Added

- **`CS2_SERVER_DELTATICKS_ENFORCE` and `CS2_SERVER_TV_RELAYVOICE`.** Upstream added both in 5.0.0 with defaults baked into the image, so the server behaves the same whether or not they are set. They are wired through and documented because a knob nobody can find is a knob that does not exist. The second one decides whether GOTV relays player voice, which is a privacy question on a public server rather than a tuning one.

### Changed

- **`joedwards32/cs2:4.0.1` moved to `joedwards32/cs2:5.0.0`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.
- **The container's base runtime changed, and nothing in this file had to.** Upstream marked 5.0.0 breaking for moving off Steam Runtime "sniper" onto steamrt4, and for replacing the RCON forwarder `simpleproxy` with `socat`. Both live inside the image: the ports, the variables and the compose interface are unchanged, and the `socat` form forks per connection where the old one did not. The review was right to stop on that marker: the release notes carry the title and nothing else, so what `!` meant could not be read from them. It is readable from the change itself — upstream PR 218 is a directory rename plus two lines of Dockerfile, and that is what settled it.

## [1.1.0] - 2026-09-07

### Added

- **`update.sh`: move between release tags on purpose.** It updates to the latest release (a combination this repository's CI has booted and smoke-tested), refuses to cross a major version unattended, refuses to run over local changes, and names any new required variable before anything has moved. `--dry-run` says what would happen.

ne thing the job exists to do was not happening, while the job failed
  daily for an unrelated reason.
- **An absent variable no longer reports itself as a registry failure.** An
  empty pin fell through to the image lookup and surfaced as "did not resolve
  after three attempts", which points at Docker Hub. The variable is checked
  first now and the error names this file, so the same mistake is loud instead
  of misleading.

## [1.0.0] - 2026-09-05

### Added

- **A Counter-Strike 2 dedicated server**, image pinned by digest as an
  interpolation default, so `git pull` delivers the version this repository has
  tested and `.env` overrides survive it.
- **A health check that matches the game exactly rather than as a substring.**
  Two commands run in the container: `cs2`, the game, and `cs2.sh`, its
  supervisor. A substring search is satisfied by either, so the game can crash
  and leave the wrapper standing while the container reports healthy — and
  docker does not restart an unhealthy container by itself, so nothing else
  catches it. `tests/e2e-healthcheck.sh` proves the distinction against a real
  container, and no CS2 download is involved.
- **The game volume declared external**, so `docker compose down -v` cannot
  delete 60 GB of SteamCMD content. `down -v` is the command everyone reaches
  for when a stack misbehaves, and on a metered connection that content comes
  back twice: once in bytes, once on the bill.
- **The published port equal to the port the server binds.** Steam's list
  records what the server bound, not what was forwarded, so a mismatch hands
  players an address where a different server answers.
- **Measured limits.** A populated server sits near 950 MB; the ceiling exists
  so a leak here cannot get some other container OOM-killed in its place.
- **A 90 minute start period**, because the first boot downloads the game.
- **Deployment Verification CI**: shell and workflow linting, a Trivy scan of
  the pinned image, a daily freshness check on the pin, and the health-check
  suite. It deliberately does not boot the game: a runner has neither the disk
  for 60 GB nor the hours, and a test that pretends otherwise never runs.

[Unreleased]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.3.3...v1.4.0
[1.3.3]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/releases/tag/v1.0.0
