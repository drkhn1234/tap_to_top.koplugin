local S = dofile('tests/support.lua')
if arg[1] then
    local frontend = arg[1]
    package.preload.depgraph = function() return dofile(frontend .. '/depgraph.lua') end
    package.preload['ui/geometry'] = function()
        return { new = function(_, rect) return rect end }
    end
    package.preload['ui/gesturerange'] = function()
        return { new = function(_, zone)
            function zone:match(ges)
                local r, p = self.range, ges.pos
                return ges.ges == self.ges and p.x >= r.x and p.x <= r.x + r.w
                    and p.y >= r.y and p.y <= r.y + r.h
            end
            return zone
        end }
    end
    S.registerTouchZones = dofile(frontend .. '/ui/widget/container/inputcontainer.lua').registerTouchZones
end
local function create(mode, target, modes, flags)
    S.reset()
    local ui = S.newUI(mode)
    flags = flags or {}
    ui.disable_double_tap = flags.disable_double_tap
    ui.allow_concurrent_taps = flags.allow_concurrent_taps
    S.top_widget = ui
    S.Device.input.disable_double_tap = ui.disable_double_tap ~= false
    S.Device.input.allow_concurrent_taps = ui.allow_concurrent_taps == true
    S.settings['/settings/tap_to_top.lua'] = { enabled = true, action_modes = modes or {} }
    local calls = { links = 0, highlights = 0, forward = 0, backward = 0, hold = 0, drag = 0, release = 0 }
    local full = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 }
    ui.link = {
        getLinkFromGes = function() if target == 'links' or target == 'overlap' then return {} end end,
        onTap = function(_, _, ges)
            assert(ges.ges == 'tap', 'native action must receive a tap gesture')
            if target == 'links' or target == 'overlap' or target == 'nearby_link' then
                calls.links = calls.links + 1
                return true
            end
        end,
    }
    ui.view.highlight = { visible_boxes = {} }
    if target == 'highlights' or target == 'overlap' then
        ui.view.highlight.visible_boxes = { { index = 1, rect = { x = 120, y = 300, w = 360, h = 400 } } }
    end
    ui.highlight = {
        onTap = function(_, _, ges)
            assert(ges.ges == 'tap')
            if target == 'highlights' or target == 'overlap' then
                calls.highlights = calls.highlights + 1
                return true
            end
        end,
        onHold = function() calls.hold = calls.hold + 1; return true end,
        onHoldPan = function() calls.drag = calls.drag + 1; return true end,
        onHoldRelease = function() calls.release = calls.release + 1; return true end,
    }
    ui:registerTouchZones({
        { id = 'tap_link', ges = 'tap', screen_zone = full,
            overrides = { 'readerhighlight_tap', 'tap_forward', 'tap_backward' },
            handler = function(ges) return ui.link:onTap(nil, ges) end },
        { id = 'readerhighlight_tap', ges = 'tap', screen_zone = full,
            overrides = { 'tap_forward', 'tap_backward' },
            handler = function(ges) return ui.highlight:onTap(nil, ges) end },
        { id = 'tap_forward', ges = 'tap', screen_zone = { ratio_x = .5, ratio_y = 0, ratio_w = .5, ratio_h = 1 },
            handler = function(ges) assert(ges.ges == 'tap'); calls.forward = calls.forward + 1; return true end },
        { id = 'tap_backward', ges = 'tap', screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = .5, ratio_h = 1 },
            handler = function(ges) assert(ges.ges == 'tap'); calls.backward = calls.backward + 1; return true end },
        { id = 'readerhighlight_hold', ges = 'hold', screen_zone = full,
            handler = function(ges) return ui.highlight:onHold(nil, ges) end },
        { id = 'readerhighlight_hold_pan', ges = 'hold_pan', screen_zone = full,
            handler = function(ges) return ui.highlight:onHoldPan(nil, ges) end },
        { id = 'readerhighlight_hold_release', ges = 'hold_release', screen_zone = full,
            handler = function() return ui.highlight:onHoldRelease() end },
    })
    local plugin = S.load('main.lua', ui)
    ui:ready()
    return plugin, ui, calls
end
local function activate(ui, mode, x)
    ui:dispatch(S.gesture('touch', x, 500))
    if mode == 'hold' then
        ui:dispatch(S.gesture('hold', x, 500))
        return ui:dispatch(S.gesture('hold_release', x, 500))
    end
    return ui:dispatch(S.gesture(mode, x, 500))
end
local combinations = 0
for _, document_mode in ipairs({ 'rolling', 'paging' }) do
    for _, action in ipairs({ 'links', 'highlights' }) do
        for _, mode in ipairs({ 'tap', 'hold', 'double_tap', 'two_finger_tap' }) do
            local plugin, ui, calls = create(document_mode, action, { [action] = mode })
            local count = action
            assert(ui:dispatch(S.gesture('tap', 350, 500)))
            assert(#ui.scrolls == (mode == 'tap' and 0 or 1), 'single-tap override must respect the action setting')
            assert(calls[count] == (mode == 'tap' and 1 or 0), 'native tap action must run exactly once when preserved')
            local before = #ui.scrolls
            if mode ~= 'tap' then
                assert(activate(ui, mode, 350))
                assert(calls[count] == 1, 'chosen alternate gesture must activate the original action once')
                assert(#ui.scrolls == before, 'alternate action must not also tap-to-top')
                for _, other in ipairs({ 'double_tap', 'two_finger_tap' }) do
                    if other ~= mode then
                        assert(not activate(ui, other, 350), 'unselected gesture must pass through')
                    end
                end
            else
                assert(not activate(ui, 'double_tap', 350) and not activate(ui, 'two_finger_tap', 350))
            end
            combinations = combinations + 1
        end
    end
end
local plugin, ui, calls = create('rolling', 'links')
assert(plugin.action_modes.links == 'tap' and plugin.action_modes.highlights == 'hold')
ui:dispatch(S.gesture('tap'))
assert(calls.links == 1 and #ui.scrolls == 0, 'links retain their native tap by default')
plugin, ui, calls = create('rolling', 'nearby_link')
ui:dispatch(S.gesture('tap'))
assert(calls.links == 1 and #ui.scrolls == 0, 'native enlarged link tap area must also be preserved')
plugin, ui, calls = create('rolling', 'overlap', { links = 'double_tap', highlights = 'hold' })
activate(ui, 'hold', 350)
assert(calls.highlights == 0 and calls.links == 0 and calls.hold == 1, 'link precedence must not replay a highlight action')
activate(ui, 'double_tap', 350)
assert(calls.links == 1 and calls.highlights == 0)
-- Removed choices migrate to defaults; ordinary taps in the region always align.
plugin, ui, calls = create('paging', 'plain', {
    links = 'none', highlights = 'none', page_turns = 'two_finger_tap',
})
assert(plugin.action_modes.links == 'tap' and plugin.action_modes.highlights == 'hold')
assert(plugin.action_modes.page_turns == nil)
assert(S.settings['/settings/tap_to_top.lua'].action_modes.page_turns == nil)
plugin:setActionMode('links', 'none')
plugin:setActionMode('highlights', 'none')
plugin:setActionMode('page_turns', 'tap')
assert(plugin.action_modes.links == 'tap' and plugin.action_modes.highlights == 'hold'
    and plugin.action_modes.page_turns == nil, 'removed choices cannot disable actions or restore page turns')
ui:dispatch(S.gesture('tap', 350, 500))
assert(#ui.scrolls == 1 and calls.forward == 0 and calls.backward == 0)
for _, kind in ipairs({ 'hold', 'double_tap', 'two_finger_tap' }) do
    local before = #ui.scrolls
    activate(ui, kind, 350)
    assert(#ui.scrolls == before and calls.forward == 0 and calls.backward == 0,
        'other inputs must never invoke tap-to-top or displaced page turns')
end
for _, mode in ipairs({ 'tap', 'hold', 'double_tap', 'two_finger_tap' }) do
    for _, document_mode in ipairs({ 'rolling', 'paging' }) do
        plugin, ui, calls = create(document_mode, 'plain', { links = mode, highlights = mode })
        ui:dispatch(S.gesture('touch', 550, 500))
        ui:dispatch(S.gesture('tap', 550, 500))
        ui:dispatch(S.gesture('touch', 50, 500))
        ui:dispatch(S.gesture('tap', 50, 500))
        assert(calls.forward == 1 and calls.backward == 1 and #ui.scrolls == 0,
            'page turns outside the region must stay native for every configuration')
    end
end

-- Native selection survives every mode that does not claim a stationary hold.
plugin, ui, calls = create('rolling', 'highlights', { highlights = 'double_tap' })
activate(ui, 'hold', 350)
assert(calls.hold == 1 and calls.release == 1 and calls.highlights == 0)
plugin:setActionMode('highlights', 'hold')
ui:dispatch(S.gesture('hold', 350, 500))
ui:dispatch(S.gesture('hold_pan', 351, 500))
ui:dispatch(S.gesture('hold_release', 351, 500))
assert(calls.hold == 2 and calls.drag == 1 and calls.release == 2 and calls.highlights == 0)
ui:dispatch(S.gesture('hold', 350, 500))
plugin:setActionMode('highlights', 'tap')
assert(not plugin.tap_hold_tracking, 'changing settings cancels pending replacement actions')
ui:dispatch(S.gesture('hold_release', 350, 500))
assert(calls.highlights == 0)

-- Gesture detection changes only for contacts in the region; preferences stay native.
plugin, ui = create('rolling', 'highlights', {}, { disable_double_tap = true, allow_concurrent_taps = true })
plugin:setActionMode('highlights', 'double_tap')
plugin:setActionMode('links', 'two_finger_tap')
assert(ui.disable_double_tap == true and ui.allow_concurrent_taps == true)
assert(S.Device.input.disable_double_tap == true and S.Device.input.allow_concurrent_taps == true)
ui:dispatch(S.gesture('touch', 300, 500))
assert(S.Device.input.disable_double_tap == false and S.Device.input.allow_concurrent_taps == false)
ui:dispatch(S.gesture('touch', 550, 500))
assert(S.Device.input.disable_double_tap == true and S.Device.input.allow_concurrent_taps == true,
    'outside contacts must restore native timing and concurrent-tap recognition')
ui:dispatch(S.gesture('touch', 300, 500))
plugin:setEnabled(false)
assert(ui.disable_double_tap == true and ui.allow_concurrent_taps == true)
assert(S.Device.input.disable_double_tap == true and S.Device.input.allow_concurrent_taps == true)
plugin:setEnabled(true)
ui:dispatch(S.gesture('touch', 300, 500))
assert(S.Device.input.disable_double_tap == false and S.Device.input.allow_concurrent_taps == false)
ui.view.view_mode = 'page'
plugin:onChangeViewMode()
assert(S.Device.input.disable_double_tap == true and S.Device.input.allow_concurrent_taps == true)
ui.view.view_mode = 'scroll'
plugin:onChangeViewMode()
ui:dispatch(S.gesture('touch', 300, 500))
assert(S.Device.input.disable_double_tap == false)
plugin:onCloseDocument()
assert(ui.disable_double_tap == true and ui.allow_concurrent_taps == true)
assert(S.Device.input.disable_double_tap == true and S.Device.input.allow_concurrent_taps == true)
local reopened_ui = S.newUI('rolling')
local reopened = S.load('main.lua', reopened_ui)
assert(reopened.action_modes.highlights == 'double_tap' and reopened.action_modes.links == 'two_finger_tap')

-- A settings dialog must retain control of live detection until it closes.
plugin, ui = create('rolling', 'highlights', {}, { disable_double_tap = true })
S.top_widget = { name = 'menu' }
plugin:setActionMode('highlights', 'double_tap')
ui:dispatch(S.gesture('touch', 300, 500))
assert(ui.disable_double_tap == true and S.Device.input.disable_double_tap == true)
S.top_widget = ui
ui:dispatch(S.gesture('touch', 300, 500))
assert(S.Device.input.disable_double_tap == false)
plugin:setActionMode('highlights', 'tap')
assert(ui.disable_double_tap == true and S.Device.input.disable_double_tap == true)

plugin, ui = create('rolling', 'highlights', {}, { disable_double_tap = false })
plugin:setActionMode('highlights', 'double_tap')
ui:dispatch(S.gesture('touch', 300, 500))
plugin:setEnabled(false)
assert(ui.disable_double_tap == false and S.Device.input.disable_double_tap == false,
    'do not disable double tap when it was already enabled by the reader')
plugin, ui = create('rolling', 'highlights')
plugin:setActionMode('highlights', 'double_tap')
ui:dispatch(S.gesture('touch', 300, 500))
plugin:setEnabled(false)
assert(ui.disable_double_tap == nil, 'restore an unset reader flag rather than forcing a value')

plugin, ui, calls = create('rolling', 'highlights', { highlights = 'double_tap' })
local native_double = 0
ui:registerTouchZones({ { id = 'double_tap_right_side', ges = 'double_tap',
    screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
    handler = function() native_double = native_double + 1; return true end } })
activate(ui, 'double_tap', 350)
assert(calls.highlights == 1 and native_double == 0, 'configured action must precede a conflicting native double tap')
plugin:setTapRegionMargin('tap_region_left_margin', 'tap_region_right_margin', 25)
activate(ui, 'double_tap', 350)
assert(calls.highlights == 2 and native_double == 0, 'zone re-registration must retain precedence')
activate(ui, 'double_tap', 500)
assert(calls.highlights == 2 and native_double == 1, 'gestures outside the configured region stay native')
plugin:setActionMode('highlights', 'hold')
activate(ui, 'double_tap', 350)
assert(native_double == 2, 'a gesture not selected for this action stays native')
local menu_taps = 0
plugin, ui, calls = create('rolling', 'plain', { links = 'double_tap', highlights = 'two_finger_tap' },
    { disable_double_tap = true, allow_concurrent_taps = true })
ui:registerTouchZones({ { id = 'readermenu_tap', ges = 'tap',
    screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
    overrides = { 'tap_forward', 'tap_backward' },
    handler = function() menu_taps = menu_taps + 1; return true end } })
ui:dispatch(S.gesture('touch', 350, 500))
assert(S.Device.input.disable_double_tap == true and S.Device.input.allow_concurrent_taps == true,
    'reserved reader controls retain native gesture recognition')
ui:dispatch(S.gesture('tap', 350, 500))
assert(menu_taps == 1 and #ui.scrolls == 0, 'reader controls retain native single taps')
activate(ui, 'hold', 350)
assert(calls.forward == 0 and calls.hold == 1, 'reserved reader controls must not trigger a displaced document tap')

-- Changing any menu choice must address its own action, even with Lua closures.
local menu = {}
plugin:addToMainMenu(menu)
local root_items = menu.tap_to_top.sub_item_table
local conflicting_actions = root_items[2]
assert(conflicting_actions.text == 'Conflicting tap actions' and conflicting_actions.help_text,
    'the renamed submenu must explain the conflicting actions when held')
assert(#root_items[3].sub_item_table == 4, 'the region submenu must contain only screen margins')
assert(root_items[4].enabled == false and root_items[4].text:find(plugin.version, 1, true),
    'the main plugin settings must show the installed version as information')
local items = conflicting_actions.sub_item_table_func()
assert(#items == 2, 'only conflicting link and highlight actions belong in this menu')
for index, key in ipairs({ 'links', 'highlights' }) do
    assert(items[index].text_func():find(index == 1 and 'Links' or 'Saved highlights', 1, true),
        'rendering each action row must use gettext and its own title')
    assert(#items[index].sub_item_table == 4, 'actions must always have a usable input')
    items[index].sub_item_table[3].callback()
    assert(plugin.action_modes[key] == 'double_tap')
    assert(items[index].sub_item_table[3].checked_func())
end
items[1].sub_item_table[2].callback()
assert(#items == 3 and conflicting_actions.sub_item_table_func() == items,
    'choosing long press must add the threshold to the existing submenu when returning')
local threshold = items[3]
assert(threshold.enabled == false and not threshold.callback and threshold.help_text,
    'the threshold must be read-only gray text with a hold explanation')
assert(threshold.text_func() == 'Long-press movement threshold: 40 px')
items[2].sub_item_table[2].callback()
items[1].sub_item_table[3].callback()
assert(#items == 3, 'the threshold stays visible while either action uses long press')
items[2].sub_item_table[3].callback()
assert(#items == 2, 'the threshold disappears when the last long-press binding changes')
plugin:setActionMode('highlights', 'hold')
assert(#conflicting_actions.sub_item_table_func() == 3,
    'reopening the submenu must reflect bindings changed outside this menu')
plugin:setLongPressMovementThreshold(55)
assert(threshold.text_func() == 'Long-press movement threshold: 55 px',
    'the information row must display the stored threshold')
plugin:setEnabled(false)
assert(not ui:dispatch(S.gesture('double_tap')) and not ui:dispatch(S.gesture('two_finger_tap')))
print('Tap action tests passed (' .. combinations .. ' document/action/mode combinations plus persistence and selection checks)')
