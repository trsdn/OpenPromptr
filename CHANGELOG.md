# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Startup and recovery options and the local HTTP API switch moved from the
  control window into a Settings window (⌘,).
- The control window shows **Stop** only while output is running, starting or
  recovering.

### Fixed

- A missing target display no longer shows a red "Start failed" error; the app
  waits quietly for it, as it does for a missing source.
- Builds with the macOS 27 SDK no longer fail on a data-race diagnostic in
  `FrameRenderer`.

## [1.2.0] - 2026-09-17

### Added

- A local HTTP API (`127.0.0.1` only, token-authenticated, off by default)
  for starting/stopping output and reading status from a script or a Stream
  Deck, without going through the menu bar.
- In-app update checking against GitHub Releases, with **Check for
  Updates…**/**Check for Updates Automatically** and an install flow that
  never interrupts a running or recovering session.
- An About panel showing the app version and links to the repository and
  issue tracker; a `--version` command-line flag.

### Changed

- The app version is now derived from the release tag automatically instead
  of being hand-maintained in `Info.plist`.

### Fixed

- A status indicator that previously conveyed error/normal state by color
  alone now also shows an icon.

## [1.1.0] - 2026-09-07

### Changed

- Renamed the app to OpenPromptr, including the bundle identifier
  (`com.github.trsdn.OpenPromptr`). Existing stored setup carries over
  automatically, but because the bundle identifier changed, existing
  installs of the previous app do not auto-update — a fresh install is
  needed.
- Switched project language to English.

### Added

- Selectable capture source with monitor and window mode.
- Link to Display Settings when using the virtual display mode.
- Configurable automatic output recovery.

### Fixed

- Output no longer covers the target monitor's menu bar.

## [1.0.1] - 2026-08-20

### Fixed

- Separated virtual display ownership from the mirrored source display.

## [1.0.0] - 2026-08-20

### Added

- Initial release: virtual teleprompter display pipeline.
- Same-display teleprompter mirroring.

### Fixed

- Static same-screen captures.
- ScreenCaptureKit support on Swift 6.1.

[Unreleased]: https://github.com/trsdn/OpenPromptr/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/trsdn/OpenPromptr/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/trsdn/OpenPromptr/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/trsdn/OpenPromptr/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/trsdn/OpenPromptr/releases/tag/v1.0.0
