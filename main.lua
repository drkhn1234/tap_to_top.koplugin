local DataStorage = require("datastorage")
local Device = require("device")
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
local SETTINGS_PATH = ffiUtil.joinPath(DataStorage:getSettingsDir(), "tap_to_top.lua")
local LEGACY_SETTINGS_PATH = ffiUtil.joinPath(DataStorage:getSettingsDir(), "velocity_scroll.lua")
local DEFAULT_TAP_TO_TOP_ENABLED = false
local DEFAULT_TAP_REGION_MARGIN = 0
local DEFAULT_LONG_PRESS_MOVEMENT_THRESHOLD = Screen:scaleBySize(20)
local MIN_TAP_REGION_SIZE_PERCENT = 5

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
    is_doc_only = true,
    settings_data = nil,
    enabled = DEFAULT_TAP_TO_TOP_ENABLED,
    tap_region_left_margin = DEFAULT_TAP_REGION_MARGIN,
    tap_region_right_margin = DEFAULT_TAP_REGION_MARGIN,
    tap_region_top_margin = DEFAULT_TAP_REGION_MARGIN,
    tap_region_bottom_margin = DEFAULT_TAP_REGION_MARGIN,
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
    self.tap_region_left_margin = self.settings_data:readSetting("tap_region_left_margin", DEFAULT_TAP_REGION_MARGIN)
    self.tap_region_right_margin = self.settings_data:readSetting("tap_region_right_margin", DEFAULT_TAP_REGION_MARGIN)
    self.tap_region_top_margin = self.settings_data:readSetting("tap_region_top_margin", DEFAULT_TAP_REGION_MARGIN)
    self.tap_region_bottom_margin = self.settings_data:readSetting("tap_region_bottom_margin", DEFAULT_TAP_REGION_MARGIN)
    self.long_press_movement_threshold = math.max(1, self.settings_data:readSetting(
        "long_press_movement_threshold", DEFAULT_LONG_PRESS_MOVEMENT_THRESHOLD
    ))
    self:normalizeTapRegionMargins()

    self.ui.menu:registerToMainMenu(self)
    self.ui:registerPostReaderReadyCallback(function()
        self:registerTouchZones()
    end)
end

function TapToTop:registerTouchZones()
    if self.zones_registered then return end
    local zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 }
    self.ui:registerTouchZones({
        {
            id = "tap_to_top_touch",
            ges = "touch",
            screen_zone = zone,
            handler = function()
                self.tap_hold_tracking = nil
                self.tap_to_top_suppressed = false
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
    self.tap_hold_tracking = nil
    self.tap_to_top_suppressed = false
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
    return (screen_box and screen_box.y) or tap_y
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
        self.ui.paging:onPanningRel(distance)
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
    if not self.enabled or not self:isContinuousMode()
            or not (ges and ges.pos and ges.pos.y) then
        return
    end

    if self.tap_to_top_suppressed then
        self.tap_hold_tracking = nil
        return true
    end
    if self:shouldPreserveTapZone(ges) then
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

function TapToTop:hasLinkAtGesture(ges)
    if not (self.ui.link and type(self.ui.link.getLinkFromGes) == "function") then
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

function TapToTop:hasLongPressTapTarget(ges)
    return self:hasLinkAtGesture(ges) or self:hasSavedHighlightAtGesture(ges)
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
    if not self.enabled or not self:isContinuousMode()
            or not (ges and ges.pos and ges.pos.x and ges.pos.y) then
        return
    end
    if self:shouldPreserveHoldZone(ges) then
        return
    end
    if not self:hasLongPressTapTarget(ges) then
        self.tap_hold_tracking = nil
        return
    end

    self.tap_hold_tracking = {
        mode = "tap",
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
        self:activateNativeLongPress(ges)
    end

    if self.ui.highlight
            and type(self.ui.highlight.onHoldPan) == "function" then
        self.ui.highlight:onHoldPan(nil, ges)
    end
    return true
end

function TapToTop:performLongPressTapAction(ges)
    if self.ui.link and type(self.ui.link.onTap) == "function"
            and self.ui.link:onTap(nil, ges) then
        return true
    end
    if self.ui.highlight and type(self.ui.highlight.onTap) == "function"
            and self.ui.highlight:onTap(nil, ges) then
        return true
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
    return self:performLongPressTapAction(tracking.gesture)
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

    if notify then
        Notification:notify(T(
            _("Tap line to top: %1"),
            self.enabled and _("on") or _("off")
        ))
    end
    return true
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
end

function TapToTop:addToMainMenu(menu_items)
    local function tapRegionMarginItem(title, key, opposite_key)
        return {
            text_func = function()
                return T(_("%1: %2%"), title, self[key])
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = title,
                    info_text = _("Screen margin excluded from the tap-to-top region."),
                    value = self[key],
                    value_min = 0,
                    value_max = 100 - MIN_TAP_REGION_SIZE_PERCENT - self[opposite_key],
                    value_step = 1,
                    value_hold_step = 5,
                    unit = "%",
                    default_value = DEFAULT_TAP_REGION_MARGIN,
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
                text = _("Tap-to-top region"),
                sub_item_table = {
                    tapRegionMarginItem(_("Left margin"), "tap_region_left_margin", "tap_region_right_margin"),
                    tapRegionMarginItem(_("Right margin"), "tap_region_right_margin", "tap_region_left_margin"),
                    tapRegionMarginItem(_("Top margin"), "tap_region_top_margin", "tap_region_bottom_margin"),
                    tapRegionMarginItem(_("Bottom margin"), "tap_region_bottom_margin", "tap_region_top_margin"),
                    {
                        text_func = function()
                            return T(
                                _("Long-press movement threshold: %1 px"),
                                self.long_press_movement_threshold
                            )
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UIManager:show(SpinWidget:new{
                                title_text = _("Long-press movement threshold"),
                                info_text = _("On a link or saved highlight, move this far in any direction before release to select the word instead of performing its tap action. A hold-drag selects immediately."),
                                value = self.long_press_movement_threshold,
                                value_min = 5,
                                value_max = math.max(200, math.floor(Screen:getWidth() / 3)),
                                value_step = 5,
                                value_hold_step = 20,
                                unit = _("px"),
                                default_value = DEFAULT_LONG_PRESS_MOVEMENT_THRESHOLD,
                                callback = function(spin)
                                    self:setLongPressMovementThreshold(spin.value)
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            })
                        end,
                    },
                },
                separator = true,
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
