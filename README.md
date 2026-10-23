# Tap to top

`tap_to_top.koplugin` moves a tapped text line to the top of the screen in
KOReader's continuous/scroll mode.

```text
Reader menu -> Scrolling -> Tap to top
```

## Behavior and settings

- A tap inside the configured region aligns the top of the tapped word with the
  top of the screen. Whitespace uses the tap position instead.
- Left, right, top, and bottom percentage margins exclude parts of the screen.
  Defaults are `20%` left, `20%` right, `0%` top, and `10%` bottom; the region
  stays at least `5%` wide and high.
- Top and bottom menu tap zones keep their normal behavior. Corner tap and long-press zones take priority when an action is assigned,
  unassigned corners remain part of the configured region.
- Inside the tap-to-top region, tap on highlighted text to open its properties menu action is overridden by the plugin and the action is performed by a long press instead. Tap on links behaviour is preserved but can be changed from the settings of the plugin, as well as highlight behaviour.
- Other long presses pass through to KOReader, preserving word selection,
  dictionary lookup, images, hold-drag selection, and release behavior.
- Both paged documents in  and reflowable documents in scroll mode
  are supported. Mouse-wheel input keeps its normal behavior.

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

This plugin was extracted from
[velocity_scroll.koplugin](https://github.com/drkhn1234/velocity_scroll.koplugin).
