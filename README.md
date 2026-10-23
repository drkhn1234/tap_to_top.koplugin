# Tap to top

`tap_to_top.koplugin` moves a tapped text line to the top of the screen in
KOReader's continuous/scroll mode.

```text
Reader menu -> Scrolling -> Tap to top
```

## Behavior and settings

- Tap on a word/line to align (its page level) to the top of the screen. (The plugin is smart enough to detect word/page line height boundaries. Therefore, you don't have to be highly precise so as not to accidentally clip words half-way through the top edge of the screen, the plugin handles small margins of error. Tapping on whitespace or an image uses the exact tap position instead.) 
- Left, right, top, and bottom percentage margins exclude parts of the screen.
  Defaults are `20%` left, `20%` right, `0%` top, and `10%` bottom; the region
  stays at least `5%` wide and high.
- Top and bottom menu tap zones keep their normal behavior. Corner tap and long-press zones take priority when an action is assigned,
  unassigned corners remain part of the configured region.
- Inside the tap-to-top region, links keep their original single-tap behavior
  by default. Saved highlight properties open on long press instead. Both can
  be configured independently under **Tap actions**.
- Other long presses pass through to KOReader, preserving word selection,
  dictionary lookup, images, hold-drag selection, and release behavior.
- Both paged documents in continuous mode and reflowable documents in scroll mode
  are supported. Mouse-wheel input keeps its normal behavior.

## Tap actions

Open **Reader menu -> Scrolling -> Tap to top -> Tap actions**. Choose a setting
independently for **Links**, **Saved highlights**, and **Page turns**:

- **Keep original single tap** leaves that action on single tap instead of
  scrolling the tapped line to the top.
- **Long press**, **Double tap**, or **Two-finger tap** replaces single tap with
  tap-to-top and moves the original action to the selected gesture.
- **Tap to top only** replaces single tap without assigning a replacement
  gesture. This is the default for page turns.

The replacement action uses the gesture's location. Two-finger tap uses the
midpoint between the fingers. Page turns use KOReader's existing forward and
backward tap zones. Reader menus, the status bar, and assigned corner tap zones
keep their normal behavior.

Long presses assigned to an action run on release. Dragging starts native text
selection; release-only movement uses the existing **Long-press movement
threshold**, which defaults to `40 px`. Unclaimed long presses retain normal
selection and dictionary behavior.

Choosing double tap enables its detection while the plugin is active in scroll
mode. Single taps then wait for KOReader's usual double-tap interval. Choosing
two-finger tap enables combined two-finger recognition; that choice is available
on multitouch devices. The reader's previous gesture settings are restored when
the feature is disabled or no longer needs those gestures.

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
luajit tests/test_tap_actions.lua
```

To also check KOReader's actual touch-zone ordering and gesture detection, pass
the `frontend` directory of a KOReader source checkout:

```sh
luajit tests/test_tap_actions.lua /path/to/koreader/frontend
luajit tests/test_gesture_detection.lua /path/to/koreader/frontend
```

This plugin was extracted from
[velocity_scroll.koplugin](https://github.com/drkhn1234/velocity_scroll.koplugin).
