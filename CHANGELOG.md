# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/releases/tag/v1.0.0
