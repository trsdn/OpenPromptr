# Release checklist

Distributable, signed and notarized builds of OpenPromptr are produced by
[`trsdn/macos-notarization-broker`](https://github.com/trsdn/macos-notarization-broker)
(profile `openpromptr`), not by this repository.

## Why the broker owns the release

Apple credentials never reach this repository. The broker treats application
repositories as untrusted: it builds the app from a pinned commit in a job
with no secrets, validates and repackages the result on a second secretless
runner, and only then signs and notarizes with broker-owned code in a
protected environment.

The practical consequence is that **this repository does not define the
release bundle**. `build-app.sh` exists for local development and testing
only; the broker assembles the bundle itself with its own
`assemble_openpromptr` build step. If the two ever disagree, the broker's
preflight rejects the release rather than signing something unexpected.

That also means a change to the bundle — identifier, executable name,
layout, architecture, entitlements, or minimum macOS version — is not a
local decision. It requires a reviewed pull request against the broker's
`profiles/apps.json`, and the release fails until that lands.

## Per release

1. Update `CHANGELOG.md`: move entries out of *Unreleased* into a new
   version heading, with the date.
2. **Do not hand-bump the version.** Unlike some sibling apps,
   `Config/Info.plist`'s `CFBundleShortVersionString`/`CFBundleVersion` are
   only the fallback for a non-git checkout — both `build-app.sh` (local
   builds) and the broker's `assemble_openpromptr` (release builds) derive
   the real version from the git tag and stamp it into the built bundle. The
   tag is the source of truth; editing the plist by hand does nothing for a
   release.
3. `swift build && swift test` — must be clean. `swift format lint --strict
   --recursive Sources Tests Package.swift` — must be clean; CI enforces
   both, but check locally first.
4. `./build-app.sh` and run the result. At minimum, the
   [optional runtime self-test](README.md#optional-runtime-self-test) if the
   app already holds Screen Recording permission; otherwise a manual check —
   pick each source type in turn, start output, and confirm the physical
   target display shows the mirrored/rotated image correctly.
5. Merge to `main`, then tag `v<version>` and push the tag.
6. Request the notarized build from a checkout of the broker:

   ```bash
   scripts/request.sh openpromptr v<version> --publish
   ```

   The broker verifies the pinned commit and the reviewed dependency lock,
   builds with `assemble_openpromptr`, and produces the artifacts declared
   in the `openpromptr` profile: `OpenPromptr-v<version>-macOS-arm64.zip`,
   `OpenPromptr-v<version>-macOS-arm64.dmg`, and
   `OpenPromptr-<version>.dmg` — the last one is a copy of the DMG under the
   exact filename [AppUpdater](https://github.com/mxcl/AppUpdater) requires
   to find it. `--publish` uploads all three to the GitHub release for the
   tag, with release notes extracted automatically from this repository's
   `CHANGELOG.md` entry for `<version>` — which is exactly why step 1 has to
   happen first. `--publish` refuses to create the release at all if that
   entry is missing, empty, or still sitting under `[Unreleased]`.

## Local testing

```bash
./build-app.sh
```

Signed with whatever identity is on this machine (falling back to ad-hoc,
with a warning, if none is found), and not notarized. Good enough for
testing on this machine; publishing an ad-hoc or non-notarized build would
give users a Gatekeeper block on first launch.

## Verifying what you are about to publish

Notarization is easy to *believe* has happened, so check the broker's
artifact explicitly rather than trusting that a script printed something:

```bash
xcrun stapler validate OpenPromptr-v<version>-macOS-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 \
  OpenPromptr-v<version>-macOS-arm64.dmg
shasum -a 256 -c OpenPromptr-v<version>-macOS-arm64.dmg.sha256
```

Then mount it, drag the app to `/Applications`, and confirm on a machine
that has never run it that it starts without a Gatekeeper warning.

## Smoke test of the published release

`Scripts/smoke-published.sh` is the smoke kit. It needs nobody at the machine:

```bash
Scripts/smoke-published.sh v<version>
```

It downloads the published DMGs, zip and checksums, and checks the checksums,
that the AppUpdater copy is the same file, that the notarization ticket is
stapled, that Gatekeeper accepts the DMG and the app, that the signature
verifies, and that the app launches and reports the version the tag names. Exit
status 0 is a pass. It does **not** capture a source or draw on a display; that
needs a display and a Screen Recording grant, so it stays the manual check in
step 4 above.

Run it after every release and add a row. A record stands for later releases
until one changes how the app is built, signed or packaged.

| Version | Date | Result | Run by |
| --- | --- | --- | --- |
| v1.3.0 | 2026-09-20 | pass — 9 of 9 checks; app reports `OpenPromptr 1.3.0 (64)` | AI agent |

## Testing the updater

Existing installs of the pre-rename *Teleprompter Mirror* have no updater at
all and will never auto-update to OpenPromptr — see
[Upgrading from Teleprompter Mirror](README.md#upgrading-from-teleprompter-mirror)
in the README. Every OpenPromptr release from the first one onward carries
the updater, but there is nothing for it to find until a **second** release
exists. After cutting the second release:

1. Install the first release.
2. Launch it and use **Check for Updates…** (status menu or the app's
   Update menu). It should find the second release, download it, and offer
   **Install Update `<version>` and Restart…**.
3. Confirm installing actually replaces the app and relaunches it at the
   new version (`OpenPromptr --version` or the About panel).
4. Confirm the install is refused with an explanatory alert if attempted
   while output is running or recovering (`AppModel.canStop`) — start
   output first, then try installing, to check this deliberately rather
   than by accident.

## After a rename

The bundle identifier is part of every TCC grant. If it ever changes again,
old grants for the previous identifier stay behind in System Settings under
Privacy & Security, pointing at an app that no longer exists. Remove them
so users are not asked to trust two entries for one app. The broker's
profile pins the identifier, so a rename also needs a reviewed profile
change.
