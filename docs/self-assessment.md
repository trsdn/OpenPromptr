# Self-assessment

Assessed against the
[trsdn Repository Quality Standard](https://github.com/trsdn/.github/blob/main/docs/repository-quality-standard.md)
v1.11.1 on 2026-09-17. The machine-readable result is
[`.github/conformance.yml`](../.github/conformance.yml); this document is the
evidence for every criterion that isn't a clean pass. A clean pass isn't
repeated here — see `standard.yml`'s catalog for what each ID means.

## Profiles claimed

Baseline, Public, Software, Package And Release, Product Identity, Agent
Readiness, Language And Localization, Accessibility, Data Protection And
Privacy, and Published Site. OpenPromptr ships a product (a signed macOS app)
to an audience that never needs to open the repository, which is what
triggers Published Site under
[decision 0009](https://github.com/trsdn/.github/blob/main/docs/decisions/0009-published-sites-and-content-boundaries.md)
even though this isn't a "site repo" in the usual sense.

Not claimed: Documentation (the primary product is the app, not documentation
or content), Deployable (a distributed desktop app, not a deployed service),
Archived (the repository is active).

## Partial

- **B05** — `AGENTS.md` and the README document the individual commands
  (`swift build`, `swift test`, `swift format lint`, `./build-app.sh`), but
  there's no single combined gate script. Running all of them is a few lines,
  not one command.
- **I03** — the app bundle's `NSHumanReadableCopyright` names the copyright
  holder, but no license identifier (e.g. "MIT") is embedded in the bundle
  itself, only in the repository's `LICENSE` file.
- **L03** — the primary language is English in practice (`CONTRIBUTING.md`
  states it for contributions) and there is exactly one locale, but nothing
  states outright "this app is English-only, no localization is planned."
- **P08** — README badges (CI, License, Platform, Swift) exist but haven't
  been diffed against the org's specific badge convention document.
- **P09** — no self-hosted, generated repository-activity visualization
  exists; unclear whether this specific evidence is expected for a repo this
  size, so recorded as partial rather than guessed at either way.
- **R01, R02** — the README states the current version and macOS
  compatibility informally; there's no separate package manifest (this isn't
  a distributed package) and no explicit written compatibility/versioning
  policy beyond "tags are semver, see CHANGELOG."

## Fail (tracked, not fixed here)

- **R03–R08** — no release automation. Tags exist (`v1.0.0`, `v1.0.1`,
  `v1.1.0`) but there are no GitHub Releases, no release notes, and no
  automated signed/notarized artifact build. The signing side of this lives
  in the separate `trsdn/macos-notarization-broker` repository, whose profile
  for this app is still stale. Tracked in
  [issue #7](https://github.com/trsdn/OpenPromptr/issues/7); out of scope for
  this assessment pass because it needs a reviewed change in that other repo
  plus Apple Developer credentials this assessment has no access to.

## Not applicable

- **B14** — this repository references no credentials of its own; CI runs
  with no secrets.
- **D01–D06** — not deployed; see profiles above.
- **G08** — no repository-scoped agent platform integration (e.g. a GitHub
  App config) exists to be intentional about.
- **L04–L06** — single-locale app; no localization catalogs exist.
- **T01–T05** — not a documentation repository; see profiles above.
- **X04** — no meaningful CLI/terminal output surface beyond `--version` and
  `--self-test`, neither of which uses color or Unicode decoration.
- **Y06** — no data outlives a session; `UserDefaults` settings persist by
  design, but there's no retention/deletion policy question beyond "the user
  can clear the app's own preferences domain," which `README.md` and
  `SECURITY.md` already state.

## Worth noting on otherwise-passing criteria

- **X01** (keyboard operability) — verified by code review, not live
  end-to-end testing: every interactive control in `ControlView.swift` is a
  native SwiftUI `Button`/`Toggle`/`Picker`, which macOS gives standard Tab
  focus order and a focus ring for free, and there's no custom-drawn
  hit-testing that would bypass it. Not tested with an actual screen reader
  or a physical keyboard walkthrough.
- **W01** — "repeatable, documented process" here is simply: GitHub Pages
  serves `docs/` from `main` directly, no build step. That's the whole
  process; there's nothing to document beyond what `docs/assets/VENDORED.md`
  already says about updating the vendored assets.
