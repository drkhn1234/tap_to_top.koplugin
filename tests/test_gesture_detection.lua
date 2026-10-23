-- Verify full touch sequences against KOReader's real detector, not synthetic taps.
local S = dofile('tests/support.lua')
local frontend = assert(arg[1], 'usage: luajit tests/test_gesture_detection.lua /path/to/koreader/frontend')
package.preload.dbg = function() return { guard = function() end } end
package.preload.util = function() return {} end
package.preload['ffi/posix_h'] = function() return {} end
package.preload.optmath = function() return dofile(frontend .. '/optmath.lua') end
package.preload['ui/geometry'] = function() return dofile(frontend .. '/ui/geometry.lua') end
package.preload.depgraph = function() return dofile(frontend .. '/depgraph.lua') end
package.preload['ui/gesturerange'] = function() return dofile(frontend .. '/ui/gesturerange.lua') end
G_reader_settings = { readSetting = function() return nil end }
local time = require('ui/time')
time.s, time.huge = function(value) return value end, math.huge
local InputContainer = dofile(frontend .. '/ui/widget/container/inputcontainer.lua')
package.loaded['ui/widget/container/inputcontainer'] = InputContainer
S.registerTouchZones = InputContainer.registerTouchZones
S.Device.screen.scaleByDPI = function(_, value) return value end
local Detector = dofile(frontend .. '/device/gesturedetector.lua')
S.reset()
S.Device.screen.getTouchRotation = function() return 0 end
local desktop = arg[2] == 'desktop'
if desktop then
    S.Device.isDesktop = function() return true end
    S.Device.isSDL = function() return true end
    S.Device.hasMultitouch = function() return false end
end
local ui = S.newUI('rolling')
ui.disable_double_tap, ui.allow_concurrent_taps = true, true
S.top_widget = ui
S.Device.input.disable_double_tap = true
S.Device.input.allow_concurrent_taps = true
ui.view.highlight = { visible_boxes = { { index = 1, rect = { x = 200, y = 400, w = 200, h = 200 } } } }
local activated = 0
local native_taps = 0
ui.highlight = { onTap = function(_, _, ges)
    assert(ges.ges == 'tap')
    activated = activated + 1
    return true
end }
local plugin = S.load('main.lua', ui)
ui:ready()
ui:registerTouchZones({ { id = 'tap_forward', ges = 'tap',
    screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
    handler = function() native_taps = native_taps + 1; return true end } })
plugin:setActionMode('highlights', 'double_tap')
assert(S.Device.input.disable_double_tap == true and ui.disable_double_tap == true,
    'choosing a mode must not change recognition across the reader')
local input, timers, slots, emitted = S.Device.input, {}, {}, {}
input.main_finger_slot = 0
function input:setTimeout(slot, kind, callback)
    timers[slot] = timers[slot] or {}
    timers[slot][kind] = callback
end
function input:clearTimeout(slot, kind)
    if timers[slot] then timers[slot][kind] = nil end
end
local detector = Detector:new{
    input = input, screen = S.Device.screen, clock_id = 1,
    active_contacts = {}, contact_count = 0, previous_tap = {},
}
input.gesture_detector = detector
local original_feed_event = detector.feedEvent
plugin:registerGestureInput()
-- The global screenshot listener sees gestures before the reader's touch zones.
-- Use its real rate/span filters so converted mouse gestures satisfy the whole
-- two-finger payload contract, even when the reader later consumes the gesture.
package.preload['ui/bidi'] = function() return {} end
package.preload['ui/widget/buttondialog'] = function() return {} end
package.preload['apps/filemanager/filemanagerutil'] = function() return {} end
require('datastorage').getFullDataDir = function() return '/test-data' end
S.Device.hasKeyboard = function() return false end
S.Device.hasScreenKB = function() return false end
local Screenshoter = dofile(frontend .. '/ui/widget/screenshoter.lua')
local screenshoter = Screenshoter:new{ key_events = {}, _ordered_touch_zones = {} }
local screenshots = 0
function screenshoter:handleEvent()
    screenshots = screenshots + 1
    return true
end
local function dispatch(ges)
    if ges and desktop then ges = detector:adjustGesCoordinate(ges) end
    if ges then
        emitted[#emitted + 1] = ges.ges
        if not screenshoter:onGesture(ges) then ui:dispatch(ges) end
    end
end
local function feed(slot, id, at, x)
    slots[slot] = slots[slot] or { slot = slot }
    local event = slots[slot]
    event.id, event.timev, event.x, event.y = id, at, x or 300, 500
    for _, ges in ipairs(detector:feedEvent({ event })) do dispatch(ges) end
end
local function fire(slot, kind)
    local callback = assert(timers[slot] and timers[slot][kind], kind .. ' timer was not scheduled')
    timers[slot][kind] = nil
    dispatch(callback())
end
feed(0, 101, 1)
assert(input.disable_double_tap == false and ui.disable_double_tap == true)
feed(0, -1, 1.05)
assert(activated == 0 and #ui.scrolls == 0, 'first tap must wait instead of moving the document')
feed(0, 102, 1.15)
feed(0, -1, 1.20)
assert(emitted[#emitted] == 'double_tap' and activated == 1 and #ui.scrolls == 0)
assert(input.disable_double_tap == true, 'restore detection after the completed double tap')
feed(0, 103, 2)
feed(0, -1, 2.05)
assert(#ui.scrolls == 0)
fire(0, 'double_tap')
assert(emitted[#emitted] == 'tap' and activated == 1 and #ui.scrolls == 1, 'timed-out single tap still scrolls to top')

plugin:setActionMode('highlights', 'two_finger_tap')
assert(input.disable_double_tap == true and input.allow_concurrent_taps == true)
feed(0, 104, 3, 280)
assert(input.allow_concurrent_taps == false and ui.allow_concurrent_taps == true)
feed(1, 105, 3.02, 320)
feed(0, -1, 3.10, 280)
feed(1, -1, 3.12, 320)
assert(emitted[#emitted] == 'two_finger_tap' and activated == 2 and #ui.scrolls == 1,
    'two-finger tap must use its midpoint and must not emit independent single taps')
assert(input.allow_concurrent_taps == true)

plugin:setActionMode('highlights', 'hold')
feed(0, 106, 4)
fire(0, 'hold')
assert(activated == 2, 'stationary long press runs on release')
feed(0, -1, 4.6)
assert(emitted[#emitted] == 'hold_release' and activated == 3 and #ui.scrolls == 1)
assert(not next(detector.active_contacts), 'gesture contacts must clean up')

-- Native timing remains immediate outside the region even when doubles are assigned.
plugin:setActionMode('highlights', 'double_tap')
feed(0, 201, 5, 550)
assert(input.disable_double_tap == true)
feed(0, -1, 5.05, 550)
assert(emitted[#emitted] == 'tap' and native_taps == 1 and #ui.scrolls == 1)
feed(0, 202, 5.15, 550)
feed(0, -1, 5.20, 550)
assert(emitted[#emitted] == 'tap' and native_taps == 2 and activated == 3,
    'rapid outside taps must remain native taps instead of being combined or delayed')

-- Outside multitouch must emit exactly the sequence the unmodified detector uses.
plugin:setActionMode('highlights', 'two_finger_tap')
local function outside_pair(at, id)
    local first = #emitted + 1
    feed(0, id, at, 520)
    feed(1, id + 1, at + .02, 560)
    assert(input.allow_concurrent_taps == true)
    feed(0, -1, at + .10, 520)
    feed(1, -1, at + .12, 560)
    return table.concat(emitted, ',', first)
end
local enabled_sequence = outside_pair(6, 203)
plugin:setEnabled(false)
assert(enabled_sequence == outside_pair(7, 205), 'outside two-finger input must retain its native recognition')

if desktop then
    plugin:setEnabled(true)
    plugin:setActionMode('highlights', 'two_finger_tap')
    plugin:setActionMode('links', 'double_tap')
    local before = #ui.scrolls
    -- These are the exact slot/tracking ID values produced by SDL for right-click.
    feed(1, 1, 8)
    feed(1, -1, 8.05)
    assert(emitted[#emitted] == 'two_finger_tap' and activated == 4 and #ui.scrolls == before,
        'right-click must immediately activate the two-finger action once without scrolling')
    assert(not next(detector.active_contacts), 'right-click must not leave a delayed tap pending')

    local links = 0
    ui.link = {
        getLinkFromGes = function(_, ges) if ges.pos.x == 340 then return {} end end,
        onTap = function(_, _, ges)
            assert(ges.ges == 'tap')
            links = links + 1
            return true
        end,
    }
    plugin:setActionMode('links', 'two_finger_tap')
    feed(1, 1, 9, 340)
    feed(1, -1, 9.05, 340)
    assert(links == 1 and activated == 4 and #ui.scrolls == before)

    -- Left click still activates tap-to-top; right click outside stays native.
    feed(0, 0, 10)
    feed(0, -1, 10.05)
    assert(emitted[#emitted] == 'tap' and #ui.scrolls == before + 1)
    local native_before = native_taps
    feed(1, 1, 11, 550)
    feed(1, -1, 11.05, 550)
    assert(emitted[#emitted] == 'tap' and native_taps == native_before + 1 and activated == 4)

    -- A real two-contact gesture, even with tracking ID 1, is still native multitouch.
    feed(0, 301, 12, 280)
    feed(1, 1, 12.02, 320)
    feed(0, -1, 12.10, 280)
    feed(1, -1, 12.12, 320)
    assert(emitted[#emitted] == 'two_finger_tap' and activated == 5)

    -- Hit testing and dispatch must agree when the desktop view is rotated.
    S.Device.screen.DEVICE_ROTATED_UPSIDE_DOWN = 2
    S.Device.screen.getTouchRotation = function() return 2 end
    plugin:setActionMode('highlights', 'hold')
    feed(1, 1, 12.3, 260)
    feed(1, -1, 12.35, 260)
    assert(links == 2 and activated == 5 and #ui.scrolls == before + 1,
        'right-click target must use the displayed coordinates in a rotated view')
    S.Device.screen.getTouchRotation = function() return 0 end
    plugin:setActionMode('highlights', 'two_finger_tap')

    local reader_controls = 0
    ui:registerTouchZones({ { id = 'readermenu_tap', ges = 'tap',
        screen_zone = { ratio_x = .45, ratio_y = 0, ratio_w = .1, ratio_h = 1 },
        overrides = { 'tap_forward' },
        handler = function() reader_controls = reader_controls + 1; return true end } })
    feed(1, 1, 12.6)
    feed(1, -1, 12.65)
    assert(emitted[#emitted] == 'tap' and reader_controls == 1 and activated == 5,
        'reserved reader controls must keep their native right-click behavior')

    local menu = {}
    plugin:addToMainMenu(menu)
    for _, row in ipairs(menu.tap_to_top.sub_item_table[2].sub_item_table) do
        if row.sub_item_table then
            local option = row.sub_item_table[4]
            assert(option.enabled_func() and option.text:find('right-click', 1, true),
                'desktop users must be able to choose the right-click option without multitouch hardware')
        end
    end

    -- Popup gestures are left to the popup, even over the underlying highlight.
    S.top_widget = { name = 'popup' }
    local popup_event = { slot = 1, id = 1, timev = 13, x = 340, y = 500 }
    detector:feedEvent({ popup_event })
    popup_event.id, popup_event.timev = -1, 13.05
    local popup_gestures = detector:feedEvent({ popup_event })
    assert(#popup_gestures == 1 and popup_gestures[1].ges == 'tap')
    S.top_widget = ui
    plugin:setEnabled(false)
    feed(1, 1, 14)
    feed(1, -1, 14.05)
    assert(emitted[#emitted] == 'tap' and activated == 5, 'disabled plugin must leave mouse input native')
    plugin:setEnabled(true)
    ui.view.view_mode = 'page'
    feed(1, 1, 15, 340)
    feed(1, -1, 15.05, 340)
    assert(emitted[#emitted] == 'tap' and links == 2, 'paged mode must keep native mouse input')
    ui.view.view_mode = 'scroll'
end

-- Only the action under this contact may introduce a double-tap wait.
plugin:setEnabled(true)
ui.view.view_mode = 'scroll'
local target_link_calls = 0
ui.link = {
    getLinkFromGes = function(_, ges)
        if ges.pos.x >= 345 and ges.pos.x <= 375 then return {} end
    end,
    onTap = function(_, _, ges)
        if ges.pos.x >= 345 and ges.pos.x <= 375 then
            target_link_calls = target_link_calls + 1
            return true
        end
    end,
}
local original_highlight_tap = ui.highlight.onTap
ui:registerTouchZones({ { id = 'readerhighlight_tap', ges = 'tap',
    screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
    overrides = { 'tap_forward' },
    handler = function(ges)
        if plugin:hasSavedHighlightAtGesture(ges) then return original_highlight_tap(ui.highlight, nil, ges) end
    end } })
local next_id = 1000
local function single(x, at)
    next_id = next_id + 1
    feed(0, next_id, at, x)
    feed(0, -1, at + .05, x)
end
local function immediate(x, at, native_highlight)
    local scrolls, highlights = #ui.scrolls, activated
    single(x, at)
    assert(not (timers[0] and timers[0].double_tap), 'unrelated taps must not schedule the double-tap wait')
    assert(#ui.scrolls == scrolls + (native_highlight and 0 or 1)
        and activated == highlights + (native_highlight and 1 or 0),
        'the correct single-tap action must run immediately on release')
end
plugin:setActionMode('highlights', 'double_tap')
plugin:setActionMode('links', 'hold')
immediate(450, 20) -- ordinary text, while highlights use double tap
immediate(350, 21) -- link using long press takes priority over overlapping highlight
local scrolls = #ui.scrolls
single(240, 22)
assert(#ui.scrolls == scrolls and timers[0].double_tap, 'the relevant highlight must still wait')
fire(0, 'double_tap')
assert(#ui.scrolls == scrolls + 1)

plugin:setActionMode('links', 'double_tap')
plugin:setActionMode('highlights', 'tap')
immediate(450, 23) -- ordinary text, while links use double tap
immediate(240, 24, true) -- highlight kept on single tap
scrolls = #ui.scrolls
single(350, 25)
assert(#ui.scrolls == scrolls and timers[0].double_tap, 'the relevant link must still wait')
single(350, 25.15)
assert(target_link_calls == 1 and #ui.scrolls == scrolls, 'double-tap link action must fire once')

-- Inside ordinary text stays immediate even when native double taps were enabled.
ui.disable_double_tap, input.disable_double_tap = false, false
immediate(450, 26)
assert(input.disable_double_tap == false and ui.disable_double_tap == false,
    'contact-specific timing must restore the reader preference')
single(550, 27)
assert(timers[0].double_tap, 'outside taps must retain the original reader double-tap behavior')
fire(0, 'double_tap')
ui.disable_double_tap, input.disable_double_tap = true, true

-- KOReader omits the second touch event while a double-tap timer is pending.
-- Moving to plain text within that interval must nevertheless act immediately.
plugin:setActionMode('links', 'hold')
plugin:setActionMode('highlights', 'double_tap')
scrolls = #ui.scrolls
single(395, 28)
assert(timers[0].double_tap)
single(415, 28.15)
assert(#ui.scrolls == scrolls + 1 and not timers[0].double_tap,
    'a pending highlight double tap must not delay a later ordinary tap')
plugin:onCloseDocument()
assert(screenshots == 0, 'normal taps and right-click aliases must not trigger the screenshot shortcut')
assert(detector.feedEvent == original_feed_event, 'desktop input wrapper must be removed on document close')
assert(ui.disable_double_tap == true and ui.allow_concurrent_taps == true)
print('Native gesture detection tests passed (inside actions and unchanged outside timing/multitouch'
    .. (desktop and ', desktop right-click' or '') .. ')')
