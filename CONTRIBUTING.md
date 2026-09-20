# Contributing

Thank you for your interest in OpenPromptr. This project is
intentionally kept small — please read the [Project scope](#project-scope)
section before making larger changes.

## Requirements

- The platform and toolchain requirements in the
  [README](README.md#requirements)
- For signed builds: a "Developer ID Application" or "Apple Development"
  certificate in the keychain

The only third-party dependencies are `AppUpdater` and `Swifter`, resolved by
SwiftPM; `swift build` is enough.

## Development workflow

The build, test, format and bundle commands are in
[`AGENTS.md`](AGENTS.md#build--validate), which is their one home.

The app icon and the runtime self-test are described in the
[README](README.md#app-icon) and [its self-test section](README.md#optional-runtime-self-test).

## Before the pull request

- The validation commands in [`AGENTS.md`](AGENTS.md#build--validate) pass.
- The change was checked manually with at least one source.
- Behavior changes are described in `README.md`.

## Conventions

- **Language:** All user-facing text, code comments, and commit messages are in
  **English**. Symbol names are in **English**.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/),
  subject line in English, for example `fix: keep output above the menu bar`.
- **Formatting:** Four spaces for indentation, line length of 80 characters as
  a guideline.
- **Dependencies:** None. If a task can be solved without an external package,
  it is solved without one.
- **Private APIs:** Access to `CGVirtualDisplay` and related APIs happens
  exclusively through `NSClassFromString` in `Sources/VirtualDisplayBridge`.
  Private symbols are not linked.

## Project scope

The app does exactly one thing: capture a source, mirror or rotate the image,
and output it full-screen on a target display — with the lowest possible
resource usage.

Text editor, script management, scrolling text, remote control, and recording
are explicitly **not** part of the project. Specialized teleprompter
applications exist for such functions.

## Reporting bugs

Please use the [issue templates](https://github.com/trsdn/OpenPromptr/issues/new/choose).
Please do **not** create an issue for security-relevant findings; report them as
described in [SECURITY.md](SECURITY.md).

## Working together

The [Code of Conduct](CODE_OF_CONDUCT.md) applies to all project areas.
