# Security Policy

## Supported versions

Security fixes are released for the latest release.
Older versions are not maintained.

## Reporting a vulnerability

Please do **not** report vulnerabilities through a public issue.

Instead, use GitHub's private reporting feature:
[Report Security Advisory](https://github.com/trsdn/OpenPromptr/security/advisories/new).

Helpful information for the analysis includes:

- affected app version and macOS version,
- a description of the impact,
- the briefest possible reproduction.

You will usually receive a response within seven days.

## Security-relevant context

The following architecture is relevant for evaluating reports:

- The app requires **Screen Recording** permission. Captured images are processed
  exclusively locally and displayed on a display; there is no telemetry and no
  storage of image content on disk.
- The only outbound network access is an update check against this
  repository's GitHub Releases, via [AppUpdater](https://github.com/mxcl/AppUpdater).
  See "Checking for updates" in `README.md`. It can be turned off; the app
  makes no other outbound connection.
- **Off by default**, the app can listen for local control commands (start,
  stop, transform, target display) on `127.0.0.1` only — never reachable
  from the network. Every request needs a per-launch random bearer token
  from a 0600 discovery file in the app's Application Support directory, and
  any request carrying an `Origin` header is rejected outright regardless of
  its value, closing off browser-based access including DNS rebinding. See
  "Local HTTP API" in `README.md`.
- In **Virtual display** mode, the app starts a second instance of the same
  signed binary as a headless display host. Only its own bundle path is started;
  no external programs are executed.
- Access to the private CoreGraphics classes happens dynamically through
  `NSClassFromString`, without linking private symbols.
- Settings remain unchanged in the app's `UserDefaults`. No credentials or
  personal data are stored there. The one exception is the local API's own
  bearer token (see above), which lives in a 0600 file, not `UserDefaults`,
  and is regenerated every launch.
- The bundles are signed with "Developer ID" and enabled Hardened Runtime.
