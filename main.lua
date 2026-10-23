local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local LuaSettings = require("luasettings")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

if not Device:isTouchDevice() then
    return { disabled = true }
end

local Screen = Device.screen
local IS_DESKTOP_SDL = Device.isDesktop and Device:isDesktop() and Device.isSDL and Device:isSDL()
local SETTINGS_PATH = ffiUtil.joinPath(DataStorage:getSettingsDir(), "tap_to_top.lua")
local LEGACY_SETTINGS_PATH = ffiUtil.joinPath(DataStorage:getSettingsDir(), "velocity_scroll.lua")
local DEFAULT_TAP_TO_TOP_ENABLED = true
local DEFAULT_TAP_REGION_MARGINS = {
    tap_region_left_margin = 20,
    tap_region_right_margin = 20,
    tap_region_top_margin = 0,
    tap_region_bottom_margin = 10,
}
local DEFAULT_LONG_PRESS_MOVEMENT_THRESHOLD = 32
local MIN_TAP_REGION_SIZE_PERCENT = 5
local TAP_ACTIONS = {
    { key = "links", title = _("Links"), default = "tap" },
    { key = "highlights", title = _("Saved highlights"), default = "double_tap" },
}
local ACTION_MODES = {
    { key = "tap", title = _("Keep original single tap") },
    { key = "hold", title = _("Long press") },
    { key = "double_tap", title = _("Double tap") },
    { key = "two_finger_tap", title = IS_DESKTOP_SDL
        and _("Two-finger tap (right-click)") or _("Two-finger tap") },
}
local ACTION_MODE_TITLES = {}
for _, mode in ipairs(ACTION_MODES) do
    ACTION_MODE_TITLES[mode.key] = mode.title
end

local TAP_TO_TOP_UI_TAP_ZONES = {
    "readerfooter_tap",
    "readerconfigmenu_ext_tap",
    "readerconfigmenu_tap",
    "readermenu_ext_tap",
    "readermenu_tap",
}
local TAP_TO_TOP_CORNER_TAP_ZONES = {
    "tap_top_left_corner",
    "tap_top_right_corner",
    "tap_left_bottom_corner",
    "tap_right_bottom_corner",
}
local TAP_TO_TOP_UI_HOLD_ZONES = {
    "readerfooter_hold",
}
local TAP_TO_TOP_CORNER_HOLD_ZONES = {
    "hold_top_left_corner",
    "hold_top_right_corner",
    "hold_bottom_left_corner",
    "hold_bottom_right_corner",
}

local TapToTop = WidgetContainer:extend{
    name = "tap_to_top",
    version = "1.4.1",
    is_doc_only = true,
    settings_data = nil,
    enabled = DEFAULT_TAP_TO_TOP_ENABLED,
    tap_region_left_margin = DEFAULT_TAP_REGION_MARGINS.tap_region_left_margin,
    tap_region_right_margin = DEFAULT_TAP_REGION_MARGINS.tap_region_right_margin,
    tap_region_top_margin = DEFAULT_TAP_REGION_MARGINS.tap_region_top_margin,
    tap_region_bottom_margin = DEFAULT_TAP_REGION_MARGINS.tap_region_bottom_margin,
    long_press_movement_threshold = DEFAULT_LONG_PRESS_MOVEMENT_THRESHOLD,
    tap_hold_tracking = nil,
    tap_to_top_suppressed = false,
    updated = false,
    zones_registered = false,
}

-- Import the combined plugin's options once, without changing its settings.
function TapToTop:migrateLegacySettings()
    if self.settings_data:readSetting("legacy_settings_migrated", false) then
        return
    end
    local legacy = LuaSettings:open(LEGACY_SETTINGS_PATH)
    local keys = {
        enabled = "tap_to_top_enabled",
        tap_region_left_margin = "tap_region_left_margin",
        tap_region_right_margin = "tap_region_right_margin",
        tap_region_top_margin = "tap_region_top_margin",
        tap_region_bottom_margin = "tap_region_bottom_margin",
        long_press_movement_threshold = "long_press_movement_threshold",
    }
    for key, legacy_key in pairs(keys) do
        if self.settings_data:readSetting(key) == nil then
            local value = legacy:readSetting(legacy_key)
            if value == nil and key == "long_press_movement_threshold" then
                value = legacy:readSetting("long_press_sideways_threshold")
            end
            if value ~= nil then
                self.settings_data:saveSetting(key, value)
            end
        end
    end
    self.settings_data:saveSetting("legacy_settings_migrated", true)
    self.settings_data:flush()
end

function TapToTop:init()
    self.settings_data = LuaSettings:open(SETTINGS_PATH)
    self:migrateLegacySettings()
    self.enabled = self.settings_data:readSetting("enabled", DEFAULT_TAP_TO_TOP_ENABLED)
    for key, default in pairs(DEFAULT_TAP_REGION_MARGINS) do
        self[key] = self.settings_data:readSetting(key, default)
    end
    self.long_press_movement_threshold = math.max(1, self.settings_data:readSetting(
        "long_press_movement_threshold", DEFAULT_LONG_PRESS_MOVEMENT_THRESHOLD
    ))
    self:normalizeTapRegionMargins()
    self.action_modes = {}
    self.input_overrides = {}
    local saved_modes = self.settings_data:readSetting("action_modes", {})
    if type(saved_modes) ~= "table" then saved_modes = {} end
    for _, action in ipairs(TAP_ACTIONS) do
        local mode = saved_modes[action.key]
        self.action_modes[action.key] = ACTION_MODE_TITLES[mode] and mode or action.default
    end
    local modes_changed = false
    for key, mode in pairs(self.action_modes) do
        modes_changed = modes_changed or saved_modes[key] ~= mode
    end
    for key in pairs(saved_modes) do
        modes_changed = modes_changed or self.action_modes[key] == nil
    end
    if modes_changed then
        self.settings_data:saveSetting("action_modes", self.action_modes)
        self.updated = true
        self:onFlushSettings()
    end

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.ui:registerPostReaderReadyCallback(function()
        self:registerTouchZones()
        self:updateGestureDetection()
        self:registerGestureInput()
    end)
end

function TapToTop:onDispatcherRegisterActions()
    Dispatcher:registerAction("toggle_tap_to_top", {
        category = "none",
        event = "ToggleTapToTop",
        title = _("Toggle tap to top"),
        reader = true,
    })
end

function TapToTop:registerTouchZones()
    if self.zones_registered then return end
    local zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 }
    self.ui:registerTouchZones({
        {
            id = "tap_to_top_touch",
            ges = "touch",
            screen_zone = zone,
            overrides = { "inertial_scrolling_touch", "velocity_scroll_touch" },
            handler = function(ges)
                self.tap_hold_tracking = nil
                self.tap_to_top_suppressed = false
                self:updateGestureDetection(ges)
            end,
        },
        {
            id = "tap_to_top_pan",
            ges = "pan",
            screen_zone = zone,
            -- Observe before scrollers that may consume the gesture. The
            -- velocity plugin is optional; unknown zone IDs are harmless.
            overrides = { "velocity_scroll_pan", "paging_pan", "rolling_pan" },
            handler = function(ges)
                if not ges.mousewheel_direction then
                    self:updateGestureDetection()
                    self.tap_hold_tracking = nil
                    self.tap_to_top_suppressed = true
                end
            end,
        },
    })
    self:registerTapToTopZone()
    self.zones_registered = true
end

function TapToTop:onCloseDocument()
    self:updateGestureDetection()
    self.gesture_input_active = false
    if self.gesture_detector and self.gesture_detector.feedEvent == self.gesture_feed_event then
        self.gesture_detector.feedEvent = self.original_gesture_feed_event
    end
    self.tap_hold_tracking = nil
    self.tap_to_top_suppressed = false
end

function TapToTop:isDesktopTwoFingerTarget(detector, pos)
    if not self.gesture_input_active or not self.enabled or not self:isContinuousMode()
            or UIManager:getTopmostVisibleWidget() ~= self.ui then
        return false
    end
    local tap = detector:adjustGesCoordinate({
        ges = "tap", pos = { x = pos.x, y = pos.y, w = 0, h = 0 },
    })
    if not self:isInTapToTopRegion(tap) or self:shouldPreserveTapZone(tap) then return false end
    local action = self:getNativeTapAction(tap)
    return action and self.action_modes[action] == "two_finger_tap" or false
end

function TapToTop:registerGestureInput()
    local input = Device.input
    local detector = input and input.gesture_detector
    if not detector or self.gesture_detector then return end
    self.gesture_input_active = true
    self.gesture_detector = detector
    self.original_gesture_feed_event = detector.feedEvent
    self.gesture_feed_event = function(this, events)
        if not self.gesture_input_active then return self.original_gesture_feed_event(this, events) end
        local event = #events == 1 and events[1]
        local contact = event and this:getContact(event.slot)
        -- While waiting for a second tap, KOReader reuses the contact and omits
        -- its touch event. Recheck that second down so a tap beside the original
        -- target becomes immediate rather than inheriting its double-tap wait.
        if event and contact and contact.pending_double_tap_timer
                and not contact.down and event.id ~= -1 then
            self:updateGestureDetection(this:adjustGesCoordinate({
                ges = "touch", time = event.timev,
                pos = { x = event.x, y = event.y, w = 0, h = 0 },
            }))
        end
        -- SDL translates the right mouse button to slot 1, tracking ID 1.
        -- A standalone contact is a click; paired contacts keep native multitouch.
        local right_click = IS_DESKTOP_SDL and event and event.slot == 1
            and (contact and contact.tap_to_top_right_click
                or not contact and event.id == 1 and not this:getContact(0))
        local mapped = right_click and self:isDesktopTwoFingerTarget(this, event)
        local disable_double_tap = input.disable_double_tap
        -- A right-click is already a complete secondary click: emit it on release.
        if mapped then input.disable_double_tap = true end
        local gestures = self.original_gesture_feed_event(this, events)
        if mapped then input.disable_double_tap = disable_double_tap end
        if right_click then
            contact = this:getContact(1)
            if contact then contact.tap_to_top_right_click = true end
            if mapped then
                for _, ges in ipairs(gestures) do
                    if ges.ges == "tap" then
                        ges.ges = "two_finger_tap"
                        -- Native two-finger gestures include a span. A mouse
                        -- click has no finger separation; global listeners
                        -- (e.g., the screenshot shortcut) still require it.
                        ges.span = 0
                    end
                end
            end
        end
        return gestures
    end
    detector.feedEvent = self.gesture_feed_event
end

function TapToTop:updateGestureDetection(ges)
    local input = Device.input
    local reader_on_top = UIManager.getTopmostVisibleWidget
        and UIManager:getTopmostVisibleWidget() == self.ui
    -- Restore the previous contact's flags before deciding about this one.
    -- Reader/widget preferences stay unchanged, including while menus are open.
    for key, override in pairs(self.input_overrides) do
        if input and reader_on_top and input[key] == override.forced then
            input[key] = override.value
        end
        self.input_overrides[key] = nil
    end
    if not input or not reader_on_top or not ges or not self.enabled
            or not self:isContinuousMode() or not self:isInTapToTopRegion(ges) then
        return
    end
    local tap = self:asTapGesture(ges)
    if self:shouldPreserveTapZone(tap) then return end

    -- Only a link or highlight assigned to double tap needs the wait. Normal
    -- tap-to-top contacts are immediate, including with native doubles enabled.
    local action = self:getNativeTapAction(tap)
    local disable_double_tap = not (action and self.action_modes[action] == "double_tap")
    if input.disable_double_tap ~= disable_double_tap then
        self.input_overrides.disable_double_tap = {
            value = input.disable_double_tap, forced = disable_double_tap,
        }
        input.disable_double_tap = disable_double_tap
    end
    -- Two-finger targeting uses the midpoint, so allow the pair to form before
    -- testing its target. This does not introduce a single-tap timeout.
    for action, mode in pairs(self.action_modes) do
        if mode == "two_finger_tap" and self:isTapActionEnabled(action) and input.allow_concurrent_taps then
            self.input_overrides.allow_concurrent_taps = {
                value = input.allow_concurrent_taps, forced = false,
            }
            input.allow_concurrent_taps = false
        end
    end
end

function TapToTop:onChangeViewMode()
    self:updateGestureDetection()
end

function TapToTop:onSetScrollMode()
    self:updateGestureDetection()
end

function TapToTop:normalizeTapRegionMargins()
    local max_combined_margin = 100 - MIN_TAP_REGION_SIZE_PERCENT
    self.tap_region_left_margin = math.max(0, math.min(self.tap_region_left_margin, max_combined_margin))
    self.tap_region_right_margin = math.max(0, math.min(
        self.tap_region_right_margin,
        max_combined_margin - self.tap_region_left_margin
    ))
    self.tap_region_top_margin = math.max(0, math.min(self.tap_region_top_margin, max_combined_margin))
    self.tap_region_bottom_margin = math.max(0, math.min(
        self.tap_region_bottom_margin,
        max_combined_margin - self.tap_region_top_margin
    ))
end

function TapToTop:getTapToTopZone()
    return {
        ratio_x = self.tap_region_left_margin / 100,
        ratio_y = self.tap_region_top_margin / 100,
        ratio_w = (100 - self.tap_region_left_margin - self.tap_region_right_margin) / 100,
        ratio_h = (100 - self.tap_region_top_margin - self.tap_region_bottom_margin) / 100,
    }
end

function TapToTop:matchesRegisteredTouchZone(ges, zone_id)
    local zone = self.ui._zones and self.ui._zones[zone_id]
    return zone and zone.gs_range and zone.gs_range:match(ges) or false
end

function TapToTop:isInTapToTopRegion(ges)
    return ges and ges.pos and ges.pos.x and ges.pos.y
        and self:matchesRegisteredTouchZone(self:asTapGesture(ges), "tap_to_top") or false
end

function TapToTop:matchesAnyRegisteredTouchZone(ges, zone_ids)
    for _, zone_id in ipairs(zone_ids) do
        if self:matchesRegisteredTouchZone(ges, zone_id) then
            return true
        end
    end
    return false
end

function TapToTop:matchesAssignedCornerZone(ges, zone_ids)
    local gestures = self.ui.gestures
    if not (gestures and gestures.gestures) then
        return false
    end
    if ges.ges == "hold" and gestures.ignore_hold_corners then
        return false
    end

    for _, zone_id in ipairs(zone_ids) do
        if gestures.gestures[zone_id]
                and self:matchesRegisteredTouchZone(ges, zone_id) then
            return true
        end
    end
    return false
end

function TapToTop:shouldPreserveTapZone(ges)
    return self:matchesAnyRegisteredTouchZone(ges, TAP_TO_TOP_UI_TAP_ZONES)
        or self:matchesAssignedCornerZone(ges, TAP_TO_TOP_CORNER_TAP_ZONES)
end

function TapToTop:shouldPreserveHoldZone(ges)
    return self:matchesAnyRegisteredTouchZone(ges, TAP_TO_TOP_UI_HOLD_ZONES)
        or self:matchesAssignedCornerZone(ges, TAP_TO_TOP_CORNER_HOLD_ZONES)
end

function TapToTop:registerTapToTopZone()
    local full_screen_zone = {
        ratio_x = 0,
        ratio_y = 0,
        ratio_w = 1,
        ratio_h = 1,
    }
    self.ui:registerTouchZones({
        {
            id = "tap_to_top",
            ges = "tap",
            screen_zone = self:getTapToTopZone(),
            overrides = {
                "inertial_scrolling_tap",
                "tap_link",
                "readerhighlight_tap_select_mode",
                "readerhighlight_tap",
                "tap_top_left_corner",
                "tap_top_right_corner",
                "tap_left_bottom_corner",
                "tap_right_bottom_corner",
                "readerfooter_tap",
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
                "readermenu_ext_tap",
                "readermenu_tap",
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges)
                return self:onTapToTop(ges)
            end,
        },
        {
            id = "tap_to_top_double_tap",
            ges = "double_tap",
            screen_zone = self:getTapToTopZone(),
            overrides = {
                "double_tap_left_side", "double_tap_right_side",
                "double_tap_top_left_corner", "double_tap_top_right_corner",
                "double_tap_bottom_left_corner", "double_tap_bottom_right_corner",
            },
            handler = function(ges) return self:onAlternateTap(ges) end,
        },
        {
            id = "tap_to_top_two_finger_tap",
            ges = "two_finger_tap",
            screen_zone = self:getTapToTopZone(),
            overrides = {
                "two_finger_tap_top_left_corner", "two_finger_tap_top_right_corner",
                "two_finger_tap_bottom_left_corner", "two_finger_tap_bottom_right_corner",
            },
            handler = function(ges) return self:onAlternateTap(ges) end,
        },
        {
            id = "tap_to_top_hold",
            ges = "hold",
            screen_zone = self:getTapToTopZone(),
            overrides = {
                "hold_top_left_corner",
                "hold_top_right_corner",
                "hold_bottom_left_corner",
                "hold_bottom_right_corner",
                "readerfooter_hold",
                "readerhighlight_hold",
            },
            handler = function(ges)
                return self:onTapToTopHold(ges)
            end,
        },
        {
            id = "tap_to_top_hold_pan",
            ges = "hold_pan",
            screen_zone = full_screen_zone,
            overrides = {
                "readerhighlight_hold_pan",
            },
            handler = function(ges)
                return self:onTapToTopHoldPan(ges)
            end,
        },
        {
            id = "tap_to_top_hold_release",
            ges = "hold_release",
            screen_zone = full_screen_zone,
            overrides = {
                "readerhighlight_hold_release",
            },
            handler = function(ges)
                return self:onTapToTopHoldRelease(ges)
            end,
        },
    })
end

function TapToTop:isContinuousMode()
    if not self.view then
        return false
    end
    return (self.ui.paging and self.view.page_scroll)
        or (self.ui.rolling and self.view.view_mode == "scroll")
end

function TapToTop:getTappedLineY(ges)
    local tap_y = ges and ges.pos and ges.pos.y
    if not tap_y or not self.ui.document or not self.view then
        return tap_y
    end

    local screen_pos = {
        x = ges.pos.x,
        y = tap_y,
    }
    local document_pos = self.view:screenToPageTransform(screen_pos)
    if not document_pos or type(self.ui.document.getWordFromPosition) ~= "function" then
        return tap_y
    end

    local ok, word = pcall(
        self.ui.document.getWordFromPosition,
        self.ui.document,
        document_pos,
        true
    )
    if not ok or not word then
        return tap_y
    end

    local screen_box
    if self.ui.paging and word.pbox then
        screen_box = self.view:pageToScreenTransform(document_pos.page, word.pbox)
    else
        screen_box = word.sbox
    end

    -- Some document engines return the nearest word even when the tap is on
    -- an image or in whitespace. Only snap to that word's line when the tap
    -- actually landed inside its box; otherwise keep the tapped screen y.
    if screen_box and screen_box.x ~= nil and screen_box.y ~= nil
            and screen_box.w ~= nil and screen_box.h ~= nil then
        local tolerance = 1
        if screen_pos.x < screen_box.x - tolerance
                or screen_pos.x > screen_box.x + screen_box.w + tolerance
                or screen_pos.y < screen_box.y - tolerance
                or screen_pos.y > screen_box.y + screen_box.h + tolerance then
            return tap_y
        end
    end
    return (screen_box and screen_box.y) or tap_y
end

function TapToTop:scrollPagedLineToTop(distance)
    local paging = self.ui.paging
    local page_states = self.view.page_states
    if not page_states or #page_states < 2 then
        return paging:onPanningRel(distance)
    end

    local page_gap = self.view.page_gap and self.view.page_gap.height or 0
    -- KOReader discards the overshoot when a relative pan leaves a PDF page.
    -- Cross each visible page separately, then scroll within the target page.
    -- Keep the original states: onPanningRel replaces the viewport's states.
    for index, state in ipairs(page_states) do
        local height = state.visible_area.h
        if distance < height or index == #page_states then
            return paging:onPanningRel(distance)
        end
        paging:onPanningRel(height)
        -- The gap above the next page disappears when that page becomes first.
        distance = distance - height - page_gap
        if distance <= 0 then
            return
        end
    end
end

function TapToTop:scrollLineToTop(line_y)
    local distance = math.max(0, math.floor((line_y or 0) + 0.5))
    if distance == 0 then
        return true
    end

    if self.ui.scrolling then
        self.ui.scrolling:cancelInertialScroll()
    end
    self:clearNativePanState()

    if self.ui.paging and self.view.page_scroll then
        self:scrollPagedLineToTop(distance)
    elseif self.ui.rolling and self.view.view_mode == "scroll" then
        local rolling = self.ui.rolling
        local was_ui_scrolling = UIManager.currently_scrolling
        local was_view_scrolling = self.view.currently_scrolling
        UIManager.currently_scrolling = true
        self.view.currently_scrolling = true
        rolling:_gotoPos(rolling.current_pos + distance)
        rolling.xpointer = self.ui.document:getXPointer()
        UIManager.currently_scrolling = was_ui_scrolling
        self.view.currently_scrolling = was_view_scrolling
        UIManager:setDirty(self.view.dialog, "partial")
    end
    return true
end

function TapToTop:onTapToTop(ges)
    self:updateGestureDetection()
    if not self.enabled or not self:isContinuousMode()
            or not self:isInTapToTopRegion(ges) then
        return
    end

    if self.tap_to_top_suppressed then
        self.tap_hold_tracking = nil
        return true
    end
    if self:shouldPreserveTapZone(ges) then
        return
    end
    -- Let KOReader resolve its optional enlarged link tap areas as well as
    -- exact link hits when the user keeps the original single-tap action.
    if self.action_modes.links == "tap" and self:isTapActionEnabled("links") and self.ui.link
            and type(self.ui.link.onTap) == "function" and self.ui.link:onTap(nil, ges) then
        return true
    end
    local action = self:getNativeTapAction(ges)
    if action and self.action_modes[action] == "tap" then
        return
    end

    return self:scrollLineToTop(self:getTappedLineY(ges))
end

function TapToTop:copyGesture(ges)
    local copy = {}
    for key, value in pairs(ges) do
        copy[key] = value
    end
    copy.pos = {
        x = ges.pos.x,
        y = ges.pos.y,
        w = ges.pos.w or 0,
        h = ges.pos.h or 0,
    }
    return copy
end

function TapToTop:getHoldMovementDistance(ges)
    if not (self.tap_hold_tracking and ges and ges.pos
            and ges.pos.x and ges.pos.y) then
        return 0
    end
    local delta_x = ges.pos.x - self.tap_hold_tracking.start_x
    local delta_y = ges.pos.y - self.tap_hold_tracking.start_y
    return math.sqrt(delta_x * delta_x + delta_y * delta_y)
end

function TapToTop:isTapActionEnabled(action)
    if action ~= "links" then return true end
    local enabled = G_reader_settings and G_reader_settings:readSetting("tap_to_follow_links")
    return enabled == nil or enabled == true
end

function TapToTop:hasLinkAtGesture(ges)
    if not self:isTapActionEnabled("links")
            or not (self.ui.link and type(self.ui.link.getLinkFromGes) == "function") then
        return false
    end
    local ok, link = pcall(self.ui.link.getLinkFromGes, self.ui.link, ges)
    return ok and link ~= nil
end

function TapToTop:hasSavedHighlightAtGesture(ges)
    local visible_boxes = self.view and self.view.highlight
        and self.view.highlight.visible_boxes
    if not (visible_boxes and #visible_boxes > 0
            and type(self.view.screenToPageTransform) == "function") then
        return false
    end

    local pos = self.view:screenToPageTransform(ges.pos)
    if not pos then
        return false
    end
    for _, box in ipairs(visible_boxes) do
        local rect = box.rect
        if box.index and rect and rect.x <= pos.x and rect.y <= pos.y
                and rect.x + rect.w >= pos.x and rect.y + rect.h >= pos.y then
            return true
        end
    end
    return false
end

function TapToTop:getNativeTapAction(ges)
    if self:hasLinkAtGesture(ges) then return "links" end
    if self:hasSavedHighlightAtGesture(ges) then return "highlights" end
end

function TapToTop:asTapGesture(ges)
    local tap = self:copyGesture(ges)
    tap.ges = "tap"
    return tap
end

function TapToTop:onAlternateTap(ges)
    self:updateGestureDetection()
    if not self.enabled or not self:isContinuousMode()
            or not self:isInTapToTopRegion(ges) then
        return
    end
    local tap = self:asTapGesture(ges)
    if self:shouldPreserveTapZone(tap) then return end
    local action = self:getNativeTapAction(tap)
    if not action or self.action_modes[action] ~= ges.ges then return end
    if not self.tap_to_top_suppressed then
        self:performNativeTapAction(action, tap)
    end
    return true
end

function TapToTop:activateNativeLongPress(ges)
    local tracking = self.tap_hold_tracking
    if not tracking or tracking.mode == "native" then
        return
    end

    tracking.mode = "native"
    if self.ui.highlight and type(self.ui.highlight.onHold) == "function" then
        self.ui.highlight:onHold(nil, tracking.gesture)
    end
end

function TapToTop:onTapToTopHold(ges)
    self:updateGestureDetection()
    if not self.enabled or not self:isContinuousMode()
            or not self:isInTapToTopRegion(ges) then
        return
    end
    if self:shouldPreserveHoldZone(ges) then
        return
    end
    local tap = self:asTapGesture(ges)
    local action = self:getNativeTapAction(tap)
    if self:shouldPreserveTapZone(tap) or not action
            or self.action_modes[action] ~= "hold" then
        self.tap_hold_tracking = nil
        return
    end

    self.tap_hold_tracking = {
        mode = "tap",
        action = action,
        gesture = self:copyGesture(ges),
        start_x = ges.pos.x,
        start_y = ges.pos.y,
    }
    return true
end

function TapToTop:onTapToTopHoldPan(ges)
    local tracking = self.tap_hold_tracking
    if not tracking or not (ges and ges.pos and ges.pos.x and ges.pos.y) then
        return
    end

    if tracking.mode == "tap" then
        if self:getHoldMovementDistance(ges) < self.long_press_movement_threshold then
            return true
        end
        self:activateNativeLongPress(ges)
    end

    local highlight = self.ui.highlight
    if highlight and type(highlight.onHoldPan) == "function" then
        local was_word_selection = highlight.is_word_selection
        local previous_text = highlight.selected_text and highlight.selected_text.text
        highlight:onHoldPan(nil, ges)
        -- KOReader treats every hold-pan as a range selection, even when the
        -- finger stays in the original word. Keep dictionary lookup available.
        if was_word_selection and previous_text and previous_text ~= ""
                and highlight.selected_text and highlight.selected_text.text == previous_text then
            highlight.is_word_selection = true
        end
    end
    return true
end

function TapToTop:performNativeTapAction(action, ges)
    if not self:isTapActionEnabled(action) then return true end
    local tap = self:asTapGesture(ges)
    if action == "links" and self.ui.link and type(self.ui.link.onTap) == "function" then
        self.ui.link:onTap(nil, tap)
    elseif action == "highlights" and self.ui.highlight
            and type(self.ui.highlight.onTap) == "function" then
        self.ui.highlight:onTap(nil, tap)
    end
    return true
end

function TapToTop:onTapToTopHoldRelease(ges)
    local tracking = self.tap_hold_tracking
    if not tracking then
        return
    end

    if tracking.mode == "tap"
            and self:getHoldMovementDistance(ges) >= self.long_press_movement_threshold then
        self:activateNativeLongPress(ges)
    end

    tracking = self.tap_hold_tracking
    self.tap_hold_tracking = nil
    if tracking.mode == "native" then
        if self.ui.highlight and type(self.ui.highlight.onHoldRelease) == "function" then
            self.ui.highlight:onHoldRelease()
        end
        return true
    end
    return self:performNativeTapAction(tracking.action, tracking.gesture)
end

function TapToTop:clearNativePanState()
    for _, native_scroller in pairs({ self.ui.rolling, self.ui.paging }) do
        if native_scroller then
            native_scroller._pan_to_scroll_later = 0
            native_scroller._pan_has_scrolled = false
            native_scroller._pan_started = false
            native_scroller._pan_activation_time = false
            native_scroller._pan_page_states_to_restore = nil
        end
    end
end

function TapToTop:setEnabled(enabled, notify)
    self.enabled = enabled and true or false
    self.tap_hold_tracking = nil
    self.tap_to_top_suppressed = false
    self.settings_data:saveSetting("enabled", self.enabled)
    self.updated = true
    self:onFlushSettings()
    self:updateGestureDetection()

    if notify then
        Notification:notify(T(
            _("Tap line to top: %1"),
            self.enabled and _("on") or _("off")
        ))
    end
    return true
end

function TapToTop:setActionMode(action_key, mode)
    if self.action_modes[action_key] == nil or not ACTION_MODE_TITLES[mode] then return end
    self.action_modes[action_key] = mode
    self.tap_hold_tracking = nil
    self.tap_to_top_suppressed = false
    self.settings_data:saveSetting("action_modes", self.action_modes)
    self.updated = true
    self:onFlushSettings()
    self:updateGestureDetection()
end

function TapToTop:onToggleTapToTop()
    return self:setEnabled(not self.enabled, true)
end

function TapToTop:setLongPressMovementThreshold(value)
    self.long_press_movement_threshold = math.max(1, value)
    self.settings_data:saveSetting(
        "long_press_movement_threshold",
        self.long_press_movement_threshold
    )
    self.updated = true
    self:onFlushSettings()
end

function TapToTop:setTapRegionMargin(key, opposite_key, value)
    local max_margin = 100 - MIN_TAP_REGION_SIZE_PERCENT - self[opposite_key]
    self[key] = math.max(0, math.min(value, max_margin))
    self.settings_data:saveSetting(key, self[key])
    self.updated = true
    self:onFlushSettings()
    if self.zones_registered then
        self:registerTapToTopZone()
    end
    self:updateGestureDetection()
end

function TapToTop:addToMainMenu(menu_items)
    local action_items = {}
    local function usesLongPress()
        for action_index, action in ipairs(TAP_ACTIONS) do
            if self:isTapActionEnabled(action.key) and self.action_modes[action.key] == "hold" then return true end
        end
        return false
    end
    local threshold_help = _("For actions assigned to long press, move at least this far before release to select text instead of performing the original tap action. Stay within one word to look it up in the dictionary; drag across words to select a passage.")
    local long_press_threshold_item = {
        text_func = function()
            return T(_("Long-press movement threshold: %1 px"), self.long_press_movement_threshold)
        end,
        enabled_func = usesLongPress,
        help_text = threshold_help,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                title_text = _("Long-press movement threshold"),
                info_text = threshold_help,
                value = self.long_press_movement_threshold,
                value_min = 1,
                value_max = math.max(200, math.floor(Screen:getWidth() / 3)),
                value_step = 1,
                value_hold_step = 8,
                unit = _("px"),
                default_value = DEFAULT_LONG_PRESS_MOVEMENT_THRESHOLD,
                callback = function(spin)
                    self:setLongPressMovementThreshold(spin.value)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
    }
    for action_index, action in ipairs(TAP_ACTIONS) do
        local action_key = action.key
        local action_title = action.title
        local modes = {}
        for mode_index, mode in ipairs(ACTION_MODES) do
            local mode_key = mode.key
            local mode_title = mode.title
            modes[#modes + 1] = {
                text = mode_title,
                radio = true,
                checked_func = function() return self.action_modes[action_key] == mode_key end,
                enabled_func = function()
                    return self:isTapActionEnabled(action_key)
                        and (mode_key ~= "two_finger_tap" or IS_DESKTOP_SDL or Device:hasMultitouch())
                end,
                callback = function(touchmenu_instance)
                    self:setActionMode(action_key, mode_key)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            }
        end
        action_items[#action_items + 1] = {
            text_func = function()
                return T(_("%1: %2"), action_title, ACTION_MODE_TITLES[self.action_modes[action_key]])
            end,
            enabled_func = function() return self:isTapActionEnabled(action_key) end,
            help_text = action_key == "links"
                and _([[This action follows KOReader's "Tap to follow links" setting. Turn that setting on in KOReader's Links menu to configure this action.]]) or nil,
            sub_item_table = modes,
        }
    end
    action_items[#action_items].separator = true
    action_items[#action_items + 1] = long_press_threshold_item
    local function tapRegionMarginItem(title, key, opposite_key)
        return {
            text_func = function()
                return T(_("%1: %2%"), title, self[key])
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local max_margin = 100 - MIN_TAP_REGION_SIZE_PERCENT - self[opposite_key]
                UIManager:show(SpinWidget:new{
                    title_text = title,
                    info_text = _("Screen margin excluded from the tap-to-top region."),
                    value = self[key],
                    value_min = 0,
                    value_max = max_margin,
                    value_step = 1,
                    value_hold_step = 5,
                    unit = "%",
                    default_value = math.min(DEFAULT_TAP_REGION_MARGINS[key], max_margin),
                    callback = function(spin)
                        self:setTapRegionMargin(key, opposite_key, spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        }
    end

    menu_items.tap_to_top = {
        text = _("Tap to top"),
        sorting_hint = "scrolling",
        enabled_func = function()
            return self:isContinuousMode()
        end,
        sub_item_table = {
            {
                text = _("Tap a line to scroll it to top"),
                checked_func = function()
                    return self.enabled
                end,
                callback = function(touchmenu_instance)
                    self:setEnabled(not self.enabled, true)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text = _("Conflicting tap actions"),
                help_text = _("Inside the tap-to-top region, choose how to open links and saved highlights: keep their single tap, or move the original action to long press, double tap, or two-finger tap. Tap-to-top always uses a single tap. Outside the region, normal reader actions apply."),
                sub_item_table = action_items,
            },
            {
                text = _("Tap-to-top region"),
                sub_item_table = {
                    tapRegionMarginItem(_("Left margin"), "tap_region_left_margin", "tap_region_right_margin"),
                    tapRegionMarginItem(_("Right margin"), "tap_region_right_margin", "tap_region_left_margin"),
                    tapRegionMarginItem(_("Top margin"), "tap_region_top_margin", "tap_region_bottom_margin"),
                    tapRegionMarginItem(_("Bottom margin"), "tap_region_bottom_margin", "tap_region_top_margin"),
                },
                separator = true,
            },
            {
                text = T(_("Version: %1"), self.version),
                enabled = false,
            },
        },
    }
end

function TapToTop:onFlushSettings()
    if self.settings_data and self.updated then
        self.settings_data:flush()
        self.updated = false
    end
end

return TapToTop
