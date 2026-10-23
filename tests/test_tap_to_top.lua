local S = dofile('tests/support.lua')
local function create(mode, settings, legacy)
    S.reset()
    S.settings['/settings/tap_to_top.lua'] = settings or { enabled = true }
    S.settings['/settings/velocity_scroll.lua'] = legacy or {}
    local ui = S.newUI(mode or 'rolling')
    local plugin = S.load('main.lua', ui)
    ui:ready()
    return plugin, ui
end
local plugin, ui = create('rolling', {}, {
    enabled = false, tap_to_top_enabled = true, tap_region_left_margin = 10,
    tap_region_right_margin = 15, tap_region_top_margin = 5, tap_region_bottom_margin = 8,
    long_press_sideways_threshold = 35,
})
assert(plugin.enabled, 'migrate tap state independently of velocity enable state')
assert(plugin.tap_region_left_margin == 10 and plugin.tap_region_right_margin == 15)
assert(plugin.tap_region_top_margin == 5 and plugin.tap_region_bottom_margin == 8)
assert(plugin.long_press_movement_threshold == 35)
assert(not S.settings['/settings/velocity_scroll.lua'].flushes, 'legacy settings must be read-only')
plugin:setEnabled(false)
S.settings['/settings/velocity_scroll.lua'].tap_region_left_margin = 40
local reopened = S.load('main.lua', S.newUI('rolling'))
assert(not reopened.enabled and reopened.tap_region_left_margin == 10, 'migration must only run once')

plugin = create('rolling', { enabled = false, tap_region_left_margin = 7 }, {
    tap_to_top_enabled = true, tap_region_left_margin = 50,
})
assert(not plugin.enabled and plugin.tap_region_left_margin == 7, 'existing new settings take priority')
plugin = create('rolling', {}, { tap_to_top_enabled = false })
assert(not plugin.enabled, 'false must not be mistaken for a missing setting')
plugin, ui = create('rolling', {}, {})
assert(plugin.enabled, 'fresh install defaults to enabled')
assert(ui:dispatch(S.gesture('tap')) and #ui.scrolls == 1, 'fresh install works without enabling it manually')

local toggle_action = assert(S.actions.toggle_tap_to_top, 'gesture toggle must be registered during init')
assert(toggle_action.category == 'none' and toggle_action.reader, 'toggle belongs in Reader actions')
local toggle = assert(plugin['on' .. toggle_action.event], 'registered event must have a handler')
plugin.tap_hold_tracking = { mode = 'tap' }
plugin.tap_to_top_suppressed = true
assert(toggle(plugin) and not plugin.enabled)
assert(not plugin.tap_hold_tracking and not plugin.tap_to_top_suppressed, 'toggle clears stale gesture state')
assert(S.settings['/settings/tap_to_top.lua'].enabled == false, 'gesture toggle persists the disabled state')
assert(not ui:dispatch(S.gesture('tap')) and #ui.scrolls == 1, 'disabled state yields document taps')
local toggle_menu = {}
plugin:addToMainMenu(toggle_menu)
assert(not toggle_menu.tap_to_top.sub_item_table[1].checked_func(), 'menu reflects gesture toggle')
local disabled_reopened = S.load('main.lua', S.newUI('rolling'))
assert(not disabled_reopened.enabled, 'saved gesture toggle survives reopening')
assert(toggle(plugin) and plugin.enabled, 'registered action also works while disabled')
assert(S.settings['/settings/tap_to_top.lua'].enabled == true)
assert(toggle_menu.tap_to_top.sub_item_table[1].checked_func())
ui:dispatch(S.gesture('touch'))
assert(ui:dispatch(S.gesture('tap')) and #ui.scrolls == 2)

plugin, ui = create()
local menus = {}
plugin:addToMainMenu(menus)
assert(menus.tap_to_top and not menus.velocity_scroll)
ui.document.getWordFromPosition = function() return { sbox = { y = 180 } } end
assert(ui:dispatch(S.gesture('tap', 300, 500)))
assert(ui.rolling.current_pos == 280, 'align the word top instead of the raw tap position')
assert(ui.rolling.xpointer == 'position' and not S.UIManager.currently_scrolling)
ui.document.getWordFromPosition = function() error('no word') end
ui:dispatch(S.gesture('touch'))
ui:dispatch(S.gesture('tap', 300, 200))
assert(ui.rolling.current_pos == 480, 'whitespace and lookup failures use tap position')

plugin, ui = create('paging')
ui.document.getWordFromPosition = function() return { pbox = { y = 170 } } end
ui.paging._pan_to_scroll_later = 42
assert(ui:dispatch(S.gesture('tap')))
assert(ui.scrolls[1] == 170 and ui.paging._pan_to_scroll_later == 0)
plugin:setTapRegionMargin('tap_region_left_margin', 'tap_region_right_margin', 30)
assert(not ui:dispatch(S.gesture('tap', 100, 500)), 'margin changes update the touch zone')
assert(ui:dispatch(S.gesture('tap', 300, 500)))
plugin:setTapRegionMargin('tap_region_right_margin', 'tap_region_left_margin', 100)
assert(plugin.tap_region_right_margin == 65, 'region must remain at least 5% wide')

plugin, ui = create()
local full = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 }
local native_taps = 0
ui:registerTouchZones({ { id = 'readermenu_tap', ges = 'tap', screen_zone = full,
    handler = function() native_taps = native_taps + 1; return true end } })
assert(ui:dispatch(S.gesture('tap')))
assert(native_taps == 1 and #ui.scrolls == 0, 'menu tap zones must retain priority')

plugin, ui = create()
ui.gestures = { gestures = { tap_top_left_corner = true, hold_top_left_corner = true } }
ui:registerTouchZones({
    { id = 'tap_top_left_corner', ges = 'tap', screen_zone = full, handler = function() return true end },
    { id = 'hold_top_left_corner', ges = 'hold', screen_zone = full, handler = function() return true end },
})
assert(ui:dispatch(S.gesture('tap')) and #ui.scrolls == 0)
assert(ui:dispatch(S.gesture('hold')) and not plugin.tap_hold_tracking)
ui.gestures.gestures.tap_top_left_corner = nil
assert(ui:dispatch(S.gesture('tap')) and #ui.scrolls == 1, 'unassigned corner stays in tap region')

plugin, ui = create()
local holds, drags, releases, links = 0, 0, 0, 0
ui.highlight = {
    onHold = function() holds = holds + 1 end,
    onHoldPan = function() drags = drags + 1 end,
    onHoldRelease = function() releases = releases + 1 end,
}
assert(not ui:dispatch(S.gesture('hold')), 'ordinary hold must pass through to native selection')
assert(not ui:dispatch(S.gesture('hold_pan')) and not ui:dispatch(S.gesture('hold_release')))
assert(holds == 0 and drags == 0 and releases == 0)
ui.link = {
    getLinkFromGes = function() return {} end,
    onTap = function() links = links + 1; return true end,
}
assert(ui:dispatch(S.gesture('hold')))
assert(ui:dispatch(S.gesture('hold_release')))
assert(links == 1 and holds == 0, 'stationary link hold follows the link')
ui:dispatch(S.gesture('hold'))
ui:dispatch(S.gesture('hold_pan', 301, 500))
ui:dispatch(S.gesture('hold_release', 301, 500))
assert(holds == 1 and drags == 1 and releases == 1 and links == 1, 'hold-drag forwards native selection')
ui:dispatch(S.gesture('hold'))
ui:dispatch(S.gesture('hold_release', 340, 500))
assert(holds == 2 and releases == 2 and links == 1, 'release movement threshold starts selection')
ui.link = nil
ui.view.highlight = { visible_boxes = { { index = 1, rect = { x = 290, y = 490, w = 20, h = 20 } } } }
local highlights = 0
ui.highlight.onTap = function() highlights = highlights + 1; return true end
ui:dispatch(S.gesture('hold'))
ui:dispatch(S.gesture('hold_release'))
assert(highlights == 1, 'stationary highlight hold opens highlight properties')

plugin, ui = create()
ui:dispatch(S.gesture('touch'))
ui:dispatch(S.gesture('pan'))
assert(ui:dispatch(S.gesture('tap')) and #ui.scrolls == 0, 'pan must suppress a stray tap')
ui:dispatch(S.gesture('touch'))
assert(ui:dispatch(S.gesture('tap')) and #ui.scrolls == 1, 'new contact must reset suppression')
ui:dispatch(S.gesture('touch'))
local wheel = S.gesture('pan')
wheel.mousewheel_direction = 'south'
ui:dispatch(wheel)
assert(not plugin.tap_to_top_suppressed, 'mousewheel is not a touch pan')
plugin:setEnabled(false)
assert(not ui:dispatch(S.gesture('tap')) and not ui:dispatch(S.gesture('hold')))
plugin:setEnabled(true)
ui.view.view_mode = 'page'
assert(not ui:dispatch(S.gesture('tap')), 'page mode must retain native taps')
plugin:onCloseDocument()
assert(not plugin.tap_hold_tracking and not plugin.tap_to_top_suppressed)
S.Device.isTouchDevice = function() return false end
assert(dofile('main.lua').disabled)
print('Tap-to-top behavioral tests passed')
