#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
PRODUCT_NAME="OpenPromptr"
APP_NAME="OpenPromptr.app"
DIST_DIR="${SCRIPT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}"

if [[ "${CONFIGURATION}" != "release" && "${CONFIGURATION}" != "debug" ]]; then
    printf 'Error: CONFIGURATION must be "release" or "debug".\n' >&2
    exit 2
fi

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="${CODE_SIGN_IDENTITY}"
else
    IDENTITIES="$(
        security find-identity -v -p codesigning 2>/dev/null || true
    )"
    SIGN_IDENTITY="$(
        printf '%s\n' "${IDENTITIES}" \
            | sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(Developer ID Application: [^"]+)".*/\1/p' \
            | head -n 1
    )"
    if [[ -z "${SIGN_IDENTITY}" ]]; then
        SIGN_IDENTITY="$(
            printf '%s\n' "${IDENTITIES}" \
                | sed -nE 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(Apple Development: [^"]+)".*/\1/p' \
                | head -n 1
        )"
    fi
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

printf 'Building %s (%s) …\n' "${PRODUCT_NAME}" "${CONFIGURATION}"
swift build \
    --package-path "${SCRIPT_DIR}" \
    --configuration "${CONFIGURATION}" \
    --product "${PRODUCT_NAME}"

BIN_DIR="$(
    swift build \
        --package-path "${SCRIPT_DIR}" \
        --configuration "${CONFIGURATION}" \
        --show-bin-path
)"
EXECUTABLE="${BIN_DIR}/${PRODUCT_NAME}"

if [[ ! -x "${EXECUTABLE}" ]]; then
    printf 'Error: executable was not produced: %s\n' "${EXECUTABLE}" >&2
    exit 1
fi

rm -rf -- "${APP_DIR}"
mkdir -p -- "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
install -m 0755 "${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/${PRODUCT_NAME}"
install -m 0644 "${SCRIPT_DIR}/Config/Info.plist" "${APP_DIR}/Contents/Info.plist"

# AppUpdater ships its TUF trust roots as a SwiftPM resource bundle next to the
# built executable; without it in Contents/Resources the updater can't verify
# a release at runtime, even for local dev builds.
UPDATER_BUNDLE="${BIN_DIR}/AppUpdater_AppUpdater.bundle"
if [[ -d "${UPDATER_BUNDLE}" ]]; then
    cp -R "${UPDATER_BUNDLE}" "${APP_DIR}/Contents/Resources/"
fi

# The marketing version and build number come from the git tag/history rather
# than being hand-typed in Config/Info.plist. Both fall back to whatever is
# already in the plist when there's no tag to read (a tarball checkout, a
# shallow CI clone without tags, or no tag yet at all).
if [[ -z "${VERSION:-}" ]]; then
    VERSION="$(
        git -C "${SCRIPT_DIR}" describe --tags --match 'v*' --abbrev=0 2>/dev/null \
            | sed -E 's/^v//' || true
    )"
fi
if [[ -n "${VERSION}" && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Warning: tag-derived version "%s" is not X.Y.Z; keeping the version already in Config/Info.plist.\n' \
        "${VERSION}" >&2
    VERSION=""
fi
if [[ -z "${BUILD:-}" ]]; then
    BUILD="$(git -C "${SCRIPT_DIR}" rev-list --count HEAD 2>/dev/null || true)"
fi
if [[ -n "${VERSION}" ]]; then
    plutil -replace CFBundleShortVersionString -string "${VERSION}" \
        "${APP_DIR}/Contents/Info.plist"
fi
if [[ -n "${BUILD}" ]]; then
    plutil -replace CFBundleVersion -string "${BUILD}" \
        "${APP_DIR}/Contents/Info.plist"
fi

ICON_FILE="${SCRIPT_DIR}/Resources/AppIcon.icns"
if [[ -f "${ICON_FILE}" ]]; then
    install -m 0644 "${ICON_FILE}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
    printf 'Warning: %s is missing. Generate it with: swift Scripts/make-icon.swift\n' \
        "${ICON_FILE}" >&2
fi

plutil -lint "${APP_DIR}/Contents/Info.plist"

printf 'Signing app with identity "%s" …\n' "${SIGN_IDENTITY}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    printf 'Warning: no stable code signing identity found. With ad-hoc signed rebuilds macOS may ask for the screen recording permission again.\n' >&2
fi

TIMESTAMP_ARGUMENT="--timestamp=none"
if [[ "${SIGN_IDENTITY}" == Developer\ ID\ Application:* ]]; then
    TIMESTAMP_ARGUMENT="--timestamp"
fi

codesign \
    --force \
    --sign "${SIGN_IDENTITY}" \
    --options runtime \
    "${TIMESTAMP_ARGUMENT}" \
    "${APP_DIR}"

codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

printf '\nDone: %s\n' "${APP_DIR}"
printf 'Launch: open "%s"\n' "${APP_DIR}"
