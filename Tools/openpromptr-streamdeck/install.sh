#!/usr/bin/env bash
#
# Installs the plugin into every deck app on this machine.
#
# A copy rather than a symlink. OpenDeck does not follow one out of its plugins
# directory, and fails at it silently — no error, no plugin process, and nothing
# in the log to say why. Re-run this after changing the plugin: both apps read
# the copy, not the repository.

set -euo pipefail

plugin="com.trsdn.openpromptr.sdPlugin"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Both apps take the same folder; only the place they look in differs.
opendeck="$HOME/Library/Application Support/opendeck/plugins"
streamdeck="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins"

if ! command -v node >/dev/null; then
    echo "OpenDeck runs plugins with the system node, and there isn't one on PATH." >&2
    echo "Install Node 20 or newer, then run this again." >&2
    echo "(Stream Deck brings its own node, so this only matters for OpenDeck.)" >&2
    exit 1
fi

version="$(node --version)"
major="${version#v}"
major="${major%%.*}"
if (( major < 20 )); then
    echo "OpenDeck needs Node 20 or newer to run a plugin; this is $version." >&2
    exit 1
fi

installed=0
for target_dir in "$opendeck" "$streamdeck"; do
    [[ -d "$target_dir" ]] || continue
    rm -rf "${target_dir:?}/$plugin"
    cp -R "$here/$plugin" "$target_dir/$plugin"
    echo "Installed into $target_dir"
    installed=$((installed + 1))
done

if [[ $installed -eq 0 ]]; then
    echo "Neither OpenDeck nor Stream Deck has a plugins directory here:" >&2
    echo "  $opendeck" >&2
    echo "  $streamdeck" >&2
    echo "Start one of them once so that it creates one, then run this again." >&2
    exit 1
fi

echo
echo "Restart the deck app to pick it up, and run this again after any change."
echo "In OpenPromptr, switch on Settings → Remote control → Enable local HTTP API."
