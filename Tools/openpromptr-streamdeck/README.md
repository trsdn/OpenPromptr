# openpromptr-streamdeck

A plugin for [OpenDeck](https://github.com/nekename/OpenDeck) and the Elgato
Stream Deck, so hardware keys can drive OpenPromptr.

Keys start and stop the output and change the rotation and mirroring — and they
show what OpenPromptr is actually doing. The output key lights up while output
runs, a flip key while the image is flipped, whether the change came from a key,
the menu bar or ⌘. The plugin polls OpenPromptr's [local HTTP API](../../README.md#local-http-api)
once a second and repaints on every change, rather than remembering what it
last sent.

One folder serves both apps. No dependencies and no build step: OpenDeck runs
plugins with the system Node, Stream Deck with one it bundles, and everything
here is plain JavaScript.

## Install

1. In OpenPromptr, open **Settings (⌘,) → Remote control** and switch on
   **Enable local HTTP API**.
2. Run:

   ```bash
   ./install.sh
   ```

   It copies the plugin into whichever apps are installed:

   - `~/Library/Application Support/opendeck/plugins/`
   - `~/Library/Application Support/com.elgato.StreamDeck/Plugins/`

3. Restart the deck app, and re-run `./install.sh` after any change — both read
   the copy, not the repository.

A copy rather than a symlink because OpenDeck does not follow one out of its
plugins directory, and fails at it silently.

The plugin needs no configuration: OpenPromptr writes its port and a fresh token
to `~/Library/Application Support/com.github.trsdn.OpenPromptr/local-api.json`
(mode 0600) on every launch, and the plugin reads it again whenever it cannot
reach the app.

## Actions

| Action | What a press does | What the key shows |
| --- | --- | --- |
| **Start / stop output** | Starts the output, or stops it while it runs or starts | Lit while running; `Running`, `Starting` or `Stopped` |
| **Rotate** | A quarter turn clockwise or counter-clockwise, or a fixed 0°/90°/180°/270° | The current rotation; a fixed one lights while it is the current one |
| **Flip** | Mirrors horizontally or vertically | Lit while flipped |

While OpenPromptr is not running or its API is off, keys keep their layout, show
`—` and flash an alert when pressed.

## Labels

Every key has its own label in the property inspector: **Show label** switches
it off, and the **Label** field replaces the default text. A label may use
placeholders, filled in live, and `\n` for a line break; leave it empty for the
key's default.

| Placeholder | Value |
| --- | --- |
| `{state}` | `Running`, `Starting`, `Stopped` |
| `{status}` | OpenPromptr's status line |
| `{display}` | Name of the target display |
| `{source}` | The source kind (virtual display, display, window) |
| `{rotation}` | Current rotation, e.g. `90°` |
| `{target}` | The rotation a Rotate key leads to |
| `{axis}` | `H` or `V` for a Flip key |
| `{flipped}` | `On` or `Off` for a Flip key's axis |

Unknown placeholders stay as typed.

## Tests

```bash
npm test
```

Checks the manifest against Elgato's rules, the WebSocket client against a
stand-in deck, the key logic, the API client against a stand-in OpenPromptr, and
runs `plugin.js` as a process against both. None of it touches a real deck or a
real OpenPromptr; the last step is looking at real keys.

## Not covered

Switching the target display from a key: the API can select a display by id but
has no way to list them, so a key could not offer a choice by name.
