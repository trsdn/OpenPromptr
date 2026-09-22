# AGENTS.md

Guidance for AI coding agents working in this repository.

## Build & validate

There is no single gate script yet; run the pieces directly:

```bash
# Compile check
swift build

# Unit tests (swift-testing: @Test / #expect, no XCTest)
swift test

# Stream Deck plugin: format, static checks and tests (Node 20+; run in CI too)
(cd Tools/openpromptr-streamdeck && npm test)

# Formatting check (must be clean; CI enforces this)
swift format lint --strict --recursive Sources Tests Package.swift

# Build, bundle, and sign -> dist/OpenPromptr.app
./build-app.sh

# Render the app's windows to PNG for a visual HIG review (see docs/ui-snapshot-review.md)
.build/debug/OpenPromptr --render-ui-snapshots .artifacts/ui-snapshots

# Smoke-test a published release (downloads it; no operator needed)
Scripts/smoke-published.sh v<version>
```

There is no Xcode project. Everything goes through SwiftPM; the app bundle is
assembled manually in `build-app.sh`.

`build-app.sh` derives `CFBundleShortVersionString`/`CFBundleVersion` from
`git describe --tags` and the commit count, so it needs real git history
(`git fetch --tags` / a non-shallow checkout) to produce a meaningful version;
outside a git checkout it falls back to whatever is in `Config/Info.plist`.

The optional runtime self-test is described in the
[README](README.md#optional-runtime-self-test).

`--version` prints the version/build and exits — no window is created.

## Forbidden and high-risk operations

**Never, under any circumstances:**

- **Add an Apple credential, certificate, provisioning profile, or App Store
  Connect key to this repository**, in any form. Distributable, notarized
  builds go through `trsdn/macos-notarization-broker` specifically so this
  never has to happen.
- **Add a secret to any workflow, or a write permission to any workflow other
  than `stats.yml`.** `ci.yml` runs with `contents: read` and no secrets, which
  is what makes it safe to run against any pull request, including from a
  fork. `stats.yml` is the one exception: it renders the repository statistics
  card (criterion `P09`) and may hold `contents: write`, declared on its job
  only, because it commits to the generated `stats` branch. It must stay that
  narrow: no secrets, no `pull_request` trigger, only `schedule`,
  `workflow_dispatch` and a `push` to `main` of its own file, and it writes
  only the `stats` branch, never `main`.
- **Rewrite published history.** No `git rebase`, `commit --amend`, or
  `push --force` against `main`. A ruleset blocks force pushes and deletion of
  `main`; branches with an open pull request are on trust.
- **Weaken the signing check in `build-app.sh`.** An ad-hoc signature loses
  every Screen Recording grant the user already gave the app, because TCC
  permissions are bound to the code signature.

**Ask before doing:**

- **Changing the bundle identifier, executable name, bundle layout, or
  minimum macOS version.** These are exactly what the notarization broker's
  release profile has to agree with once one exists (see #7); a mismatch
  fails release preflight silently rather than obviously.
- **Renaming the product.** The "Open" + vowel-dropped-name scheme
  (OpenPromptr = "Open" + "Promptr") is shared with sibling apps in this
  account; picking a new name risks colliding with one of them or an
  unrelated project.
- **Changing repository settings**: visibility, branch protection, required
  checks, topics, or security features. These are recorded in
  `.github/conformance.yml`, so changing one silently makes that record wrong.
- **Publishing a release, or triggering the notarization broker.**
- **Adding another third-party dependency.** `AppUpdater` (pinned exact,
  `Package.resolved` committed) is the only one, added deliberately for #7;
  the app otherwise links only system frameworks.
- **Adding a network connection beyond AppUpdater's GitHub Releases check.**
  `SECURITY.md` and the README's "Checking for updates" section state that
  check as the app's only network access; the only other inter-process
  communication is the local, unnamed pipe between the main process and its
  own headless virtual-display-host instance.
- **Making an update install automatic, or allowing it while `AppModel.canStop`
  is true.** A teleprompter must not restart mid-talk — see `UpdateFlow.swift`.
  Gate on `canStop`, not `isRunning`: `isRunning` goes false the instant a
  capture failure starts an automatic-recovery retry, even though that retry
  is still trying to restore the same session.
- **Loosening `NSScreenCaptureUsageDescription`** or any other usage-
  description string in `Config/Info.plist`.
- **Loosening the local API's security model**: binding anything but
  `127.0.0.1`, dropping bearer-token auth, or accepting a request that
  carries an `Origin` header. See `LocalAPIServer.swift`/`LocalAPI.swift`
  and issue #4.

## Generated and machine-owned paths

Do not hand-edit these:

| Path | Produced by | Source of truth |
| --- | --- | --- |
| `Resources/AppIcon.icns` | `swift Scripts/make-icon.swift`, called by `build-app.sh` | `Scripts/make-icon.swift` |
| `Resources/MenuBarIcon.png` | `swift Scripts/make-icon.swift`, called by `build-app.sh` | `Scripts/make-icon.swift` |
| `dist/` | `build-app.sh` | — (git-ignored) |
| `.build/` | SwiftPM | — (git-ignored) |
| `docs/assets/*` (once vendored) | copied from `trsdn/design-system` | `docs/assets/VENDORED.md` — re-vendor from a tag, never hand-edit |

`Config/Info.plist`'s `CFBundleShortVersionString` and `CFBundleVersion` look
hand-maintained but are overwritten by `build-app.sh` in the *built* bundle
from the git tag and commit count — the checked-in values are only the
fallback for a non-git checkout.

## Review expectation for agent-authored changes

- Every commit an agent makes carries a `Co-Authored-By` trailer.
- `main` requires the `Build and tests` and `App bundle` CI checks to pass
  before a merge (branch protection, strict mode) — an admin can still bypass
  this, but don't rely on that.
- Say what you did not verify. Unit tests exercise `OpenPromptrCore` only —
  they don't touch ScreenCaptureKit, the virtual display, or actual window
  capture, all of which need a real display and a Screen Recording grant. A
  change to the capture or virtual-display path is unverified by `swift test`
  alone until someone runs the built app.

## Releases go through the broker

Distributable, signed and notarized builds come from
`trsdn/macos-notarization-broker` (profile `openpromptr`), the same as
sibling apps in this account. See `RELEASE_CHECKLIST.md` for the actual
per-release steps. `v1.2.0` (2026-09-17) was the first one; release notes
are extracted automatically from the `CHANGELOG.md` entry for the tag,
and the broker refuses to publish if that entry is missing, empty, or
still sitting under `[Unreleased]` — update the changelog before tagging,
not after. `build-app.sh` is a local convenience for development builds, signed with
whatever identity is available locally (falling back to ad-hoc with a
warning); the broker assembles the app bundle itself via its own
`assemble_openpromptr` build step, so `build-app.sh` is not necessarily the
definition of what a broker-built release bundle looks like — keep the two
in sync deliberately, not by assumption, if one changes (bundle layout,
Info.plist location, resource bundles).

## Architecture

```text
Sources/
├── OpenPromptrCore/     Pure logic: models, capture sizing, aspect-fit math,
│                        the output-recovery policy, and the decisions behind
│                        start/stop/recovery (`OutputDecisions.swift`). No
│                        AppKit/SwiftUI, no I/O.
├── VirtualDisplayBridge/ Objective-C bridge to the private CGVirtualDisplay
│                        API, in its own target because a single SwiftPM
│                        target can't mix Swift and Objective-C. ARC.
└── OpenPromptr/         App wiring: SwiftUI views, AppModel, capture
                         pipeline, display catalog, the virtual-display-host
                         process, main.swift's dispatch between the two,
                         Update/ (AppUpdater integration, see #7), and
                         LocalAPI/ (the loopback HTTP control API, see #4).

Tools/
└── openpromptr-streamdeck/  OpenDeck / Stream Deck plugin (plain JavaScript,
                         no dependencies, no build step). A client of the local
                         API; installed with its own `install.sh`.
```

Three source types feed one output pipeline: a private virtual display, a
mirrored physical display, or a single window — see `README.md`'s "The
virtual source display" section for why the virtual display needs a second,
headless process at all (capture callbacks for a self-created virtual
display aren't reliably delivered to the process that created it).

## Non-negotiable design constraints

- **Never capture the same physical display the output is shown on.** That's
  the entire reason the virtual-display and window source types exist —
  capturing the target display creates a visible feedback loop. `AppModel`
  enforces source ≠ target for `.display` mode.
- **Display identity must not silently downgrade.** A display is matched by,
  in order of preference: hardware serial, stable display UUID, then
  name + native pixel dimensions as a last-resort unique fallback. A stored
  identity that had a serial or UUID must never match against a weaker
  candidate that lacks one — see `DisplayIdentityMatcher` and its tests in
  `ModelTests.swift`, which exist specifically to pin this behavior after it
  was easy to get wrong once.
- **A transient `CGDirectDisplayID` is never persisted alone.** IDs are
  reassigned across reconnects; only the identity struct above is stored.
- **The private `CGVirtualDisplay` classes are used only via
  `NSClassFromString`.** No private symbols are linked, so a future macOS
  that removes the API fails at runtime with a reported error, not a broken
  build.
- **Recovery has a fixed budget.** `OutputRecoveryPolicy` allows exactly three
  retries at 2s/5s/15s, replenished only after 30 seconds of stable output
  since the first rendered frame. Don't change the schedule without updating
  its tests — they encode the actual product decision, not just current
  behavior.
- **A manual Stop always wins.** It suppresses automatic recovery and
  automatic restart-on-reconnect for the rest of the app session; only an
  explicit Start lifts that suppression.
- **A closure written inside a `@MainActor` type inherits that isolation
  implicitly, even with no annotation on the closure itself.** `LocalAPIServer`
  hands its route/middleware closures to Swifter, which calls them on its own
  background queue — measured as a `SIGTRAP` in `dispatch_assert_queue` the
  first time this was tried with the class marked `@MainActor`, since the
  compiler let it through silently and only the runtime's dynamic isolation
  check caught it. That's why `LocalAPIServer` is deliberately *not*
  `@MainActor`: every actual touch of `AppModel`'s state goes through an
  explicit hop instead (`runOnMainActorSync` for reads, `Task { @MainActor
  in ... }` for actions).

## Repository quality standard

This repository is assessed against the
[trsdn Repository Quality Standard](https://github.com/trsdn/.github/blob/main/docs/repository-quality-standard.md).

The result lives in exactly two places, and this section is deliberately not
a third:

- `.github/conformance.yml` — the machine-readable record: which version of
  the standard, when it was assessed, the overall state, and a result for
  every criterion in the catalog.
- `docs/self-assessment.md` — the evidence: what was observed for each
  criterion that is not a clean pass, and what would have to change.

If you change something that affects a criterion, update the record and the
assessment, not this paragraph — a fact with two homes has no home (`B13`).
