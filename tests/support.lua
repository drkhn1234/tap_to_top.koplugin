-- Minimal KOReader fixtures for behavioral tests; neither plugin is required.
local Support = { settings = {}, scheduled = {} }
local function noop() end
local Object = {}
function Object:extend(o)
    o = o or {}
    return setmetatable(o, { __index = self })
end
function Object:new(o)
    o = self:extend(o)
    if o.init then o:init() end
    return o
end
local UIManager = { currently_scrolling = false }
function UIManager:scheduleIn(delay, callback, owner)
    Support.scheduled[callback] = { delay = delay, owner = owner }
end
function UIManager:unschedule(callback) Support.scheduled[callback] = nil end
function UIManager:nextTick(callback) callback() end
UIManager.setDirty, UIManager.show = noop, noop
Support.UIManager = UIManager
local screen = {
    getHeight = function() return 1000 end,
    getWidth = function() return 600 end,
    scaleBySize = function(_, value) return value end,
}
local device = { screen = screen, isTouchDevice = function() return true end }
Support.Device = device
package.preload.datastorage = function() return { getSettingsDir = function() return '/settings' end } end
package.preload.device = function() return device end
package.preload.luasettings = function()
    return { open = function(_, path)
        if not Support.settings[path] then Support.settings[path] = {} end
        local data = Support.settings[path]
        return {
            readSetting = function(_, key, default)
                if data[key] ~= nil then return data[key] end
                return default
            end,
            saveSetting = function(_, key, value) data[key] = value end,
            flush = function() data.flushes = (data.flushes or 0) + 1 end,
        }
    end }
end
package.preload['ui/widget/container/widgetcontainer'] = function() return Object end
package.preload['ui/widget/notification'] = function() return Object:extend{ notify = noop } end
package.preload['ui/widget/spinwidget'] = function() return Object end
package.preload['ui/uimanager'] = function() return UIManager end
package.preload['ui/event'] = function()
    return { new = function(_, name) return { name = name } end }
end
package.preload['ffi/util'] = function()
    return {
        joinPath = function(a, b) return a .. '/' .. b end,
        template = function(s, ...)
            local values = {...}
            return (s:gsub('%%(%d+)', function(i) return tostring(values[tonumber(i)]) end))
        end,
    }
end
package.preload.gettext = function() return function(s) return s end end
package.preload.logger = function() return { dbg = noop } end
package.preload['ui/time'] = function()
    return { to_s = function(value) return value end, ms = function(value) return value / 1000 end }
end
function Support.reset()
    Support.settings, Support.scheduled = {}, {}
    UIManager.currently_scrolling = false
end
function Support.tick(callback)
    local timer = assert(Support.scheduled[callback], 'timer was not scheduled')
    Support.scheduled[callback] = nil
    callback(timer.owner)
end
function Support.gesture(kind, x, y, elapsed)
    return { ges = kind, pos = { x = x or 300, y = y or 500 }, time = elapsed or 1 }
end
function Support.newUI(mode)
    local ui = { _zones = {}, order = {}, callbacks = {}, scrolls = {}, events = {},
        menu = { registerToMainMenu = noop, onShowMenu = noop }, config = { onShowConfigMenu = noop },
        document = { getXPointer = function() return 'position' end },
        scrolling = { cancelInertialScroll = noop },
    }
    ui.view = { page_scroll = mode == 'paging', view_mode = mode == 'rolling' and 'scroll' or 'page',
        visible_area = { h = 1000 }, dialog = {},
        screenToPageTransform = function(_, pos) return { x = pos.x, y = pos.y, page = 1 } end,
        pageToScreenTransform = function(_, _, box) return box end,
    }
    if mode == 'paging' then
        ui.paging = { onPanningRel = function(_, distance) ui.scrolls[#ui.scrolls + 1] = distance end }
    else
        ui.rolling = {
            current_pos = 100,
            _gotoPos = function(self, pos) self.current_pos = pos; ui.scrolls[#ui.scrolls + 1] = pos end,
            onGotoViewRel = function(_, fraction) ui.scrolls[#ui.scrolls + 1] = fraction end,
        }
    end
    function ui:registerPostReaderReadyCallback(callback) self.callbacks[#self.callbacks + 1] = callback end
    function ui:ready() for _, callback in ipairs(self.callbacks) do callback() end end
    function ui:handleEvent(event) self.events[#self.events + 1] = event.name end
    function ui:registerTouchZones(zones)
        for _, zone in ipairs(zones) do
            if not self._zones[zone.id] then self.order[#self.order + 1] = zone.id end
            local rect = zone.screen_zone
            self._zones[zone.id] = { def = zone, handler = zone.handler, gs_range = {
                match = function(_, ges)
                    return ges.ges == zone.ges and ges.pos.x >= rect.ratio_x * 600
                        and ges.pos.x <= (rect.ratio_x + rect.ratio_w) * 600
                        and ges.pos.y >= rect.ratio_y * 1000
                        and ges.pos.y <= (rect.ratio_y + rect.ratio_h) * 1000
                end,
            } }
        end
    end
    function ui:dispatch(ges)
        if self._ordered_touch_zones then
            for _, zone in ipairs(self._ordered_touch_zones) do
                if zone.gs_range:match(ges) and zone.handler(ges) then return true end
            end
            return
        end
        local visited, sorted = {}, {}
        local function visit(id)
            if visited[id] then return end
            visited[id] = true
            for _, other_id in ipairs(self.order) do
                for _, target in ipairs(self._zones[other_id].def.overrides or {}) do
                    if target == id then visit(other_id) end
                end
            end
            sorted[#sorted + 1] = self._zones[id]
        end
        for _, id in ipairs(self.order) do visit(id) end
        for _, zone in ipairs(sorted) do
            if zone.gs_range:match(ges) and zone.handler(ges) then return true end
        end
    end
    if Support.registerTouchZones then ui.registerTouchZones = Support.registerTouchZones end
    return ui
end
function Support.load(path, ui)
    return dofile(path):new{ ui = ui, view = ui.view }
end
return Support
