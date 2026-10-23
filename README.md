# Tap to top

`tap_to_top.koplugin` moves a tapped text line to the top of the screen in
KOReader's *continuous* View Mode.

## See it in action

<p align="center">
  <img src="docs/demos/tap-to-top-text.gif" width="480" alt="Two taps in KOReader bring the selected text lines to the top of the screen.">
</p>

<table>
  <tr>
    <th>Images and PDFs</th>
    <th>Conflicting tap actions</th>
  </tr>
  <tr>
    <td width="50%"><img src="docs/demos/tap-to-top-images-pdf.gif" width="360" alt="Tap an image detail, then a line on the next visible PDF page, to move each position to the top."></td>
    <td width="50%"><img src="docs/demos/tap-to-top-conflicting-actions.gif" width="360" alt="Choose two-finger tap for saved highlights, then right-click a highlight to open its menu."></td>
  </tr>
</table>

Captured in KOReader with Tap to top v1.3.6. Teal markers show where to tap.

## Behavior and settings

- **Tap on a word/line to align (its page level) to the top of the screen.**
> [!NOTE]
> The plugin is smart enough to detect word/line height boundaries. It doesn't merely scroll pixels at tap position to top. Therefore, you don't have to be highly precise when tapping on line of words and worry if the words will be clipped by the edge of the screen.
>
> Taps on whitespace or images use the exact tap position.
- In the plugin settings: left (20%), right (20%), top (0%), and bottom (0%) margins exempt parts of the screen from the reach of the plugin, so that left/right page turns continue working without being affected by the new tap behaviour.

- Top and bottom menu tap zones keep their normal behavior. Corner tap and long-press zones take priority when an action is assigned,
  unassigned corners remain part of the configured region.
> [!TIP]
> If you find yourself accidentally activating Top or Bottom menus while using tap-to-top frequently on screen positions that happen to collide with KOReader Menu tap zones, a solution is to adjust Menu zone values at:\
> `Top Panel > Tools > More tools > Advance settings`, these keys:
> 
>  <img width="348" height="276" alt="image" src="https://github.com/user-attachments/assets/2f9faad7-c30d-4fe6-bda5-0cff823a2826"/> <br> 
>  **_MENU** is for *TOP MENU*,&ensp;**_CONFIG** is for *BOTTOM MENU*.&ensp;**_EXT** suffix is for extra/secondary zones of TOP and BOTTOM menus, it is recommended to disable extra/secondary zones by setting its values to 0 for a better plugin experience.
- Inside the tap-to-top region, opening Highlight menu is done by long press instead of a tap in order to not conflict with the plugin behaviour (outside the tap-to-tap region, it still uses tap to open). Links keep their original single-tap behavior
  by default. Both can be configured independently under **Conflicting tap actions** in the plugin settings page.
- Both non-reflowable (PDF, DJVU, etc.) and reflowable (EPUB, MOBI, etc.) are supported.

## Conflicting tap actions

### `Top Panel > Settings > Taps and gestures > Scrolling > Tap to top > Conflicting tap actions`

Choose how to open **Links** and **Saved highlights** inside the tap-to-top
region:

- **Keep original single tap** leaves that action on single tap instead of
  scrolling the tapped line to the top.
- **Long press**, **Double tap**, or **Two-finger tap** replaces single tap with
  tap-to-top and moves the original action to the selected gesture.

Both actions always remain available. Links default to their original single tap;
saved highlights default to long press. Tap-to-top itself always uses a single
tap and cannot be rebound to another gesture. Page turns have no plugin setting:
single taps in the region scroll to the tapped line, except where a link or
highlight keeps its original single tap.

Hold **Conflicting tap actions** for an explanation. The main plugin settings
also show the installed plugin version.

The replacement action uses the gesture's location. Two-finger tap uses the
midpoint between the fingers. Outside the configured region, all reader actions,
including page turns, use KOReader's normal behavior. Reader menus, the status
bar, and assigned corner tap zones keep their normal behavior.

On PC, **Two-finger tap (right-click)** also accepts the touchpad's two-finger
tap or a mouse right-click on the link or saved highlight. This choice is
available on desktop even without a touchscreen.

Long presses assigned to an action run on release. Dragging starts native text
selection; release-only movement uses the existing **Long-press movement
threshold**, which defaults to `40 px`. Unclaimed long presses retain normal
selection and dictionary behavior. The threshold appears as a read-only gray row
in **Conflicting tap actions** only while at least one action uses long press.
Hold that row for an explanation of the threshold.

Only taps on a link or saved highlight assigned to **Double tap** wait for
KOReader's double-tap interval. Ordinary text, images, whitespace, and actions
using another input respond immediately. Taps outside the region keep their
normal timing. Choosing two-finger tap enables combined two-finger recognition
inside the region; that choice is available on multitouch devices and PC. The
reader's gesture preferences stay unchanged.

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
luajit tests/test_gesture_detection.lua /path/to/koreader/frontend desktop
```

This plugin was extracted from
[velocity_scroll.koplugin](https://github.com/drkhn1234/velocity_scroll.koplugin).
