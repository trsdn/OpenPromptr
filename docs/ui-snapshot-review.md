# UI snapshots for a visual review

For a review against the
[Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos),
the app can render its own windows to PNG without starting anything:

```sh
swift build
.build/debug/OpenPromptr --render-ui-snapshots .artifacts/ui-snapshots
```

It draws the production SwiftUI views (the control window and the Settings
window) through an offscreen `NSWindow` at their real width and a 2x scale, in
light and dark appearance, and writes four PNGs: `control-light.png`,
`control-dark.png`, `settings-light.png`, `settings-dark.png`. It exits non-zero
when its argument is missing or a PNG cannot be produced.

It does not start output, create the virtual display, ask for Screen Recording or
touch the network, and it keeps the preferences the app would write in a
throwaway defaults suite. What the control window shows still reflects the
displays connected to the Mac it runs on, and it reads (never writes) the
preferences of a previous *Teleprompter Mirror* install, so the pictures are
evidence of layout and styling, not a fixed reference image.

Deliberately not captured:

- **The menu bar menu.** It needs a live status item, and an offscreen mock would
  be misleading rather than faithful.
- **The About panel.** The system draws it.
- **A larger-text variant.** macOS has no Dynamic Type, so there is nothing to
  show.

`AGENTS.md` lists the command; CI runs it and checks that all four PNGs are
produced and non-empty, so the renderer cannot rot unnoticed. CI does not review
the pictures: the automated reviewer OpenWritr runs on pull requests needs a
Copilot token stored as a repository secret, which this repository does not hold.
