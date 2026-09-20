#!/usr/bin/env bash
#
# Smoke kit: checks a published OpenPromptr release as a consumer receives it,
# with nobody operating the app.
#
#   Scripts/smoke-published.sh v1.3.0
#
# Downloads the release's DMGs and checksums from GitHub, then verifies that the
# published files are intact, notarized and signed, that the copy AppUpdater
# fetches is the same file, and that the app inside launches and reports the
# version the tag names. Exit status 0 means every check passed.
#
# What it does NOT do: capture a source or draw on a display. That needs a
# display and a Screen Recording grant, i.e. someone at the machine.

set -euo pipefail

tag="${1:-}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Usage: $0 vX.Y.Z" >&2
    exit 2
}
version="${tag#v}"
repo="${OPENPROMPTR_REPO:-trsdn/OpenPromptr}"
dmg="OpenPromptr-v${version}-macOS-arm64.dmg"
updater_dmg="OpenPromptr-${version}.dmg"
zip="OpenPromptr-v${version}-macOS-arm64.zip"

work="$(mktemp -d)"
mount_point="$work/mnt"
cleanup() {
    hdiutil detach -quiet "$mount_point" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1" >&2; exit 1; }

echo "Smoke test of $repo $tag"

gh release download "$tag" -R "$repo" -D "$work" \
    -p "$dmg" -p "$dmg.sha256" -p "$updater_dmg" -p "$updater_dmg.sha256" \
    -p "$zip" -p "$zip.sha256" >/dev/null || fail "download of the release assets"
pass "release assets downloaded"

(cd "$work" && shasum -a 256 -c "$dmg.sha256" "$zip.sha256" "$updater_dmg.sha256" >/dev/null) \
    || fail "published checksums"
pass "checksums match"

cmp -s "$work/$dmg" "$work/$updater_dmg" || fail "the AppUpdater copy differs from the DMG"
pass "the AppUpdater copy is the same file as the DMG"

xcrun stapler validate "$work/$dmg" >/dev/null 2>&1 || fail "notarization ticket is not stapled"
pass "notarization ticket stapled"

spctl --assess --type open --context context:primary-signature "$work/$dmg" 2>/dev/null \
    || fail "Gatekeeper does not accept the DMG"
pass "Gatekeeper accepts the DMG"

mkdir -p "$mount_point"
hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$work/$dmg" >/dev/null \
    || fail "the DMG does not mount"
app="$mount_point/OpenPromptr.app"
[[ -d "$app" ]] || fail "OpenPromptr.app is not in the DMG"
pass "DMG mounts and holds OpenPromptr.app"

codesign --verify --deep --strict "$app" 2>/dev/null || fail "code signature"
spctl --assess --type execute "$app" 2>/dev/null || fail "Gatekeeper does not accept the app"
pass "app signature valid and accepted by Gatekeeper"

plist="$app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw "$plist")" == "com.github.trsdn.OpenPromptr" ]] \
    || fail "bundle identifier"
[[ "$(plutil -extract CFBundleShortVersionString raw "$plist")" == "$version" ]] \
    || fail "CFBundleShortVersionString is not $version"
pass "bundle identifier and version $version in Info.plist"

reported="$("$app/Contents/MacOS/OpenPromptr" --version)" || fail "the app does not launch"
[[ "$reported" == "OpenPromptr $version "* ]] || fail "--version reported \"$reported\""
pass "app launches and reports: $reported"

echo "All checks passed for $tag (core function not exercised; see the header)."
