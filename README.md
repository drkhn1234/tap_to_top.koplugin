# Tap to top

`tap_to_top.koplugin` moves a tapped text line to the top of the screen in
KOReader's continuous/scroll mode. It works independently of
[velocity_scroll.koplugin](https://github.com/drkhn1234/velocity_scroll.koplugin),
and both plugins can be used together.

## Installation

Download **tap_to_top.koplugin.zip** from the
[latest release](https://github.com/drkhn1234/tap_to_top.koplugin/releases/latest).
Create `koreader/plugins/tap_to_top.koplugin/` and extract the ZIP contents
directly into it. The ZIP contains the plugin files at its root.

Alternatively, copy this repository into `koreader/plugins/tap_to_top.koplugin`,
or clone it:

```sh
git clone https://github.com/drkhn1234/tap_to_top.koplugin.git /path/to/koreader/plugins/tap_to_top.koplugin
```

Restart KOReader and enable **Tap to top** in the plugin manager if needed. Open
a document in continuous/scroll mode, then browse:

```text
Reader menu -> Scrolling -> Tap to top
```

**Tap a line to scroll it to top** is enabled by default for new installs.
Existing saved settings, including imported settings, are preserved. Its menu
is available only in continuous/scroll mode on touch devices.

## Gesture toggle

In Gesture Manager, assign **Reader -> Toggle tap to top** to a reading gesture.
This switches the same setting as the plugin menu, saves the new state, and
shows an on/off notification. The action remains available while tap-to-top is
off, so the same gesture can turn it back on.

## Behavior and settings

- A tap inside the configured region aligns the top of the tapped word with the
  top of the screen. Whitespace uses the tap position instead.
- Left, right, top, and bottom percentage margins exclude parts of the screen.
  Defaults are `20%` left, `20%` right, `0%` top, and `10%` bottom; the region
  stays at least `5%` wide and high.
- Reader menu and footer tap zones keep their normal behavior. Gesture Manager
  corner tap and long-press zones take priority when an action is assigned;
  unassigned corners remain part of the configured region.
- Normal taps inside the region become tap-to-top. A stationary long press on a
  link or saved highlight follows the link or opens the highlight properties.
- Other long presses pass through to KOReader, preserving word selection,
  dictionary lookup, images, hold-drag selection, and release behavior.
- Dragging a held link or highlight switches to native text selection and
  forwards the first movement. Release-only movement uses the configurable
  long-press movement threshold, which defaults to `40 px`.
- A pan cannot also trigger tap-to-top. With velocity scroll installed, a tap
  interrupting a velocity gesture stops scrolling without moving the tapped line.
- Both paged documents in continuous mode and reflowable documents in scroll mode
  are supported. Mouse-wheel input keeps its normal behavior.
- When multiple PDF pages are visible, tapping a later page aligns the tapped
  line to the top, accounting for page gaps and the remaining part of each page.

## Upgrading from the combined velocity scroll plugin

Install this plugin alongside the updated velocity scroll plugin. On first use,
it imports the tap enable state, four region margins, and long-press movement
threshold from `settings/velocity_scroll.lua`. The older
`long_press_sideways_threshold` setting is also supported. Existing tap-to-top
settings take priority, and migration never writes to the velocity settings file.

Keep the old settings file until the first import completes. Later changes are
saved independently in `settings/tap_to_top.lua`; velocity scroll can then be
uninstalled if you only want tap-to-top. Use the split version of velocity scroll
when running both plugins together, so the old combined tap handler is removed.

## Tests

Run from the repository directory with LuaJIT:

```sh
luajit tests/test_tap_to_top.lua
```

To check PDF page-boundary behavior against KOReader's actual paging, view, and
geometry code, also run with a KOReader source checkout:

```sh
luajit tests/test_pdf_scrolling.lua /path/to/koreader/frontend
```

This plugin was extracted from
[velocity_scroll.koplugin](https://github.com/drkhn1234/velocity_scroll.koplugin).
