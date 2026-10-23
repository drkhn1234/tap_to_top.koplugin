-- Run against a KOReader source checkout to cover its real page-boundary logic.
local S = dofile('tests/support.lua')
local frontend = assert(arg[1], 'usage: luajit tests/test_pdf_scrolling.lua /path/to/koreader/frontend')
local Container = require('ui/widget/container/widgetcontainer')
for _, name in ipairs({
    'ui/bidi', 'ui/font', 'ui/data/optionsutil', 'ui/size', 'util',
    'apps/reader/modules/readerdogear', 'apps/reader/modules/readerflipping',
    'apps/reader/modules/readerfooter',
}) do
    package.preload[name] = function() return {} end
end
package.preload.dbg = function() return { guard = function() end } end
for _, name in ipairs({
    'ui/widget/container/inputcontainer', 'ui/widget/overlapgroup',
    'ui/widget/iconwidget', 'ui/widget/infomessage', 'ui/widget/textwidget',
}) do
    package.preload[name] = function() return Container end
end
package.preload['ffi/blitbuffer'] = function() return { gray = function(value) return value end } end
package.preload.optmath = function() return dofile(frontend .. '/optmath.lua') end
package.preload['ui/geometry'] = function() return dofile(frontend .. '/ui/geometry.lua') end
G_defaults = { readSetting = function() return 0 end }
local Geom = require('ui/geometry')
local Paging = dofile(frontend .. '/apps/reader/modules/readerpaging.lua')
local View = dofile(frontend .. '/apps/reader/modules/readerview.lua')

local function exercise(options)
    S.reset()
    local ui = S.newUI('paging')
    local view = ui.view
    view.ui = ui
    local zoom = options.zoom or 1
    local gap = options.gap or 0
    local target = options.target or 2
    local first_height = options.first_height or 320
    local line_offset = options.line_offset or 170
    local page_count = options.last_page and target or target + 1
    local areas = {}
    for page = 1, page_count do
        areas[page] = Geom:new{ x = 0, y = 40 * zoom, w = 600 * zoom, h = 1120 * zoom }
    end
    if target == 3 then areas[2].h = 220 end
    if options.short_last_page then areas[target].h = 500 end
    view.visible_area = Geom:new{ w = 600, h = 1000 }
    view.page_gap = { height = gap }
    view.state = { page = 1, zoom = zoom, rotation = 0, offset = Geom:new() }
    view.getPageArea = function(_, page) return areas[page]:copy() end
    for _, method in ipairs({
        'screenToPageTransform', 'pageToScreenTransform', 'getScrollPagePosition', 'getScrollPageRect',
    }) do
        view[method] = View[method]
    end
    ui.document.getNextPage = function(_, page) return page < page_count and page + 1 or 0 end
    ui.document.getPrevPage = function(_, page) return page > 1 and page - 1 or 0 end
    local paging = Paging:extend{
        ui = ui, view = view, page_positions = {}, current_page = 1, number_of_pages = page_count,
    }
    -- Only document-rendering events are mocked. Page generation, relative
    -- scrolling, geometry, coordinate transforms and position saving are real.
    function paging:_gotoPage(page)
        self.current_page = page
        view.state.page = page
        view.state.zoom = zoom
        view.state.offset = Geom:new()
    end
    ui.paging = paging
    view.page_states = {}
    local remaining, screen_y = 1000, 0
    local target_start
    for page = 1, page_count do
        if remaining <= 0 then break end
        local area = areas[page]
        local height = math.min(remaining, page == 1 and first_height or area.h)
        local y = page == 1 and area.y + area.h - first_height or area.y
        view.page_states[#view.page_states + 1] = {
            page = page, zoom = zoom, rotation = 0, gamma = 1, saturation = 1,
            offset = Geom:new(), page_area = area:copy(),
            visible_area = Geom:new{ x = 0, y = y, w = 600, h = height },
        }
        if page == target then target_start = screen_y end
        screen_y = screen_y + height + gap
        remaining = remaining - height - gap
    end
    assert(target_start, 'test target must initially be visible')
    local target_state = view.page_states[target]
    local line_page_y = target_state.visible_area.y + line_offset
    local word = Geom:new{ x = 250 / zoom, y = line_page_y / zoom, w = 100 / zoom, h = 16 / zoom }
    ui.document.getWordFromPosition = function(_, pos)
        assert(pos.page == target, 'word lookup must use the tapped PDF page')
        if options.whitespace then return nil end
        return { pbox = word }
    end
    local tap_y = target_start + line_offset + (options.whitespace and 0 or 8)
    local plugin = S.load('main.lua', ui)
    ui:ready()
    paging._pan_to_scroll_later = 42
    assert(ui:dispatch(S.gesture('tap', 300, tap_y)))
    assert(view.page_states[1].page == target, options.name .. ': wrong page at top')
    local expected_y = line_page_y
    if options.last_page then
        expected_y = math.min(expected_y, areas[target].y + math.max(0, areas[target].h - 1000))
    end
    local actual_y = view.page_states[1].visible_area.y
    assert(math.abs(actual_y - expected_y) <= 0.5,
        options.name .. ': expected page offset ' .. expected_y .. ', got ' .. actual_y)
    if not options.last_page then
        local box = view:pageToScreenTransform(target, word)
        assert(box and math.abs(box.y) <= 0.5, options.name .. ': tapped line did not reach screen top')
    end
    assert(paging._pan_to_scroll_later == 0, 'pending on-release scroll must be cleared')
    assert(paging:getPagePosition(target) == paging:getTopPosition(), 'final reading position must be saved')
end

exercise{ name = 'second page, word, page gap', gap = 12 }
exercise{ name = 'second page, no page gap' }
exercise{ name = 'second page, whitespace', gap = 18, whitespace = true }
exercise{ name = 'second page, zoom and crop', gap = 12, zoom = 1.5 }
exercise{ name = 'second page, fractional geometry', gap = 12.5, first_height = 319.5, zoom = 1.25 }
exercise{ name = 'third visible page', target = 3, gap = 12, first_height = 140 }
exercise{ name = 'next page top', gap = 12, line_offset = 0 }
exercise{ name = 'first visible page', target = 1, line_offset = 120 }
exercise{ name = 'last page clamp', gap = 12, last_page = true }
exercise{ name = 'short last page clamp', gap = 12, last_page = true, short_last_page = true }
print('PDF scrolling regression tests passed (10 cases using KOReader paging and view code)')
