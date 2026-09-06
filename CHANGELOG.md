# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.1] - 2026-09-06

### Fixed

- **The freshness job was watching the wrong pins.** It looped over
  `MINECRAFT_SERVER_IMAGE_TAG` and `MINECRAFT_SERVER_BACKUP_IMAGE_TAG`, names
  carried over from the template this workflow was adapted from and absent from
  the compose file here. The CS2 pin was never compared against the registry:
  the one thing the job exists to do was not happening, while the job failed
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

[Unreleased]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/heyvaldemar/cs2-server-docker-compose/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/heyvaldemar/cs2-server-docker-compose/releases/tag/v1.0.0
