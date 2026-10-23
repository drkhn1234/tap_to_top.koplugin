-- Verify full touch sequences against KOReader's real detector, not synthetic taps.
local S = dofile('tests/support.lua')
local frontend = assert(arg[1], 'usage: luajit tests/test_gesture_detection.lua /path/to/koreader/frontend')
package.preload.dbg = function() return { guard = function() end } end
package.preload.util = function() return {} end
package.preload['ffi/posix_h'] = function() return {} end
package.preload.optmath = function() return dofile(frontend .. '/optmath.lua') end
package.preload['ui/geometry'] = function() return dofile(frontend .. '/ui/geometry.lua') end
G_reader_settings = { readSetting = function() return nil end }
local time = require('ui/time')
time.s, time.huge = function(value) return value end, math.huge
S.Device.screen.scaleByDPI = function(_, value) return value end
local Detector = dofile(frontend .. '/device/gesturedetector.lua')
S.reset()
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
local function dispatch(ges)
    if ges then emitted[#emitted + 1] = ges.ges; ui:dispatch(ges) end
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
plugin:onCloseDocument()
assert(ui.disable_double_tap == true and ui.allow_concurrent_taps == true)
print('Native gesture detection tests passed (inside actions and unchanged outside timing/multitouch)')
