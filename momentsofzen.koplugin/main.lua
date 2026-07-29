local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local DocSettings = require("docsettings")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local ReadHistory = require("readhistory")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local LuaSettings = require("luasettings")
local _ = require("gettext")

local ID = "momentsofzen.quotes"
local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/settings.momentsofzen.lua")
local annotation_cache
local quote_history = {}
local history_position = 0
local DEFAULT_QUOTES = {}
local ok_defaults, defaults = pcall(
    require, "modules/filebrowser/patches/home/quote_list"
)
if not ok_defaults then
    ok_defaults, defaults = pcall(
        dofile,
        DataStorage:getDataDir()
            .. "/plugins/zen_ui.koplugin/modules/filebrowser/patches/home/quote_list.lua"
    )
end
if ok_defaults and type(defaults) == "table" then DEFAULT_QUOTES = defaults end

local QUOTES_TEMPLATE = [[return {
    -- Add your quotes here, then enable Custom quotes in the widget settings.
    -- { text = "Quote text", author = "Author" },
    -- { text = "Quote text", author = "Author", title = "Book title" },
    -- "Plain quote without author",
}
]]

local MomentsOfZen = WidgetContainer:extend{
    name = "momentsofzen",
    is_doc_only = false,
}

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function normalize_custom(raw)
    if type(raw) == "table" and type(raw.quotes) == "table" then
        raw = raw.quotes
    end
    if type(raw) ~= "table" then return {} end

    local quotes = {}
    for _, item in ipairs(raw) do
        local text, author, title
        if type(item) == "string" then
            text, author, title = item, "", ""
        elseif type(item) == "table" then
            -- Support the current Zen UI format, the original Zen UI format,
            -- and the older SimpleUI-style format used by this plugin.
            text = item.q or item.text or item[1]
            author = item.a or item.author or item[2] or ""
            title = item.b or item.book or item.title or item[3] or ""
        end
        text = trim(text)
        if text ~= "" then
            author, title = trim(author), trim(title)
            local attribution = author
            if title ~= "" then
                attribution = attribution .. (attribution ~= "" and ",  " or "") .. title
            end
            quotes[#quotes + 1] = {
                text = text,
                author = author,
                title = title,
                attribution = attribution,
            }
        end
    end
    return quotes
end

local function load_custom_quotes()
    local dir = DataStorage:getSettingsDir() .. "/Zen UI"
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local path = dir .. "/quotes.lua"
    if lfs.attributes(path, "mode") ~= "file" then
        local file = io.open(path, "w")
        if file then
            file:write(QUOTES_TEMPLATE)
            file:close()
        end
    end
    local ok, raw = pcall(dofile, path)
    return ok and normalize_custom(raw) or {}
end

local function has_custom_quotes()
    return #load_custom_quotes() > 0
end

local function book_info(data, path)
    local props = type(data.doc_props) == "table" and data.doc_props or {}
    local filename = path:match("([^/\\]+)$") or path
    local title = trim(props.title)
    local authors = trim(props.authors)
    if title == "" then title = filename:gsub("%.[^.]+$", "") end
    return title, authors
end

local function append_annotations(quotes, path, seen_quotes)
    if type(path) ~= "string" or lfs.attributes(path, "mode") ~= "file" then return end
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, path)
    if not ok or not doc_settings or type(doc_settings.data) ~= "table" then return end

    local data = doc_settings.data
    local title, authors = book_info(data, path)
    local attribution = title
    if authors ~= "" then
        attribution = attribution .. (attribution ~= "" and ",  " or "") .. authors
    end

    local function add(item, fallback_page)
        if type(item) ~= "table" or not item.drawer then return end
        local text = trim(item.text)
        if text == "" then return end
        local key = path .. "\0" .. text
        if seen_quotes[key] then return end
        seen_quotes[key] = true
        quotes[#quotes + 1] = {
            text = text,
            author = authors,
            title = title,
            -- Match SimpleUI highlights: book title first, then author.
            attribution = attribution,
            is_annotation = true,
            filepath = path,
            pos0 = item.pos0,
            page = item.page or item.pageno or tonumber(fallback_page),
        }
    end

    if type(data.annotations) == "table" and #data.annotations > 0 then
        for _, item in ipairs(data.annotations) do add(item) end
    else
        for page, page_items in pairs(type(data.highlight) == "table" and data.highlight or {}) do
            if type(page_items) == "table" then
                for _, item in ipairs(page_items) do add(item, page) end
            end
        end
    end
end

local function load_annotation_quotes()
    if annotation_cache then return annotation_cache end
    local quotes, seen_books, seen_quotes = {}, {}, {}

    local function add_book(path)
        if type(path) ~= "string" or seen_books[path] then return end
        seen_books[path] = true
        append_annotations(quotes, path, seen_quotes)
    end

    for _, item in ipairs(ReadHistory.hist or {}) do
        add_book(item.file)
    end

    local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
    local db_path = DataStorage:getDataDir() .. "/bookinfo_cache.db"
    if ok_sq and lfs.attributes(db_path, "mode") == "file" then
        local ok_db, db = pcall(SQ3.open, db_path)
        if ok_db and db then
            local ok_stmt, stmt = pcall(function()
                return db:prepare(
                    "SELECT directory, filename FROM bookinfo "
                    .. "WHERE directory IS NOT NULL AND filename IS NOT NULL"
                )
            end)
            if ok_stmt and stmt then
                pcall(function()
                    for row in stmt:nrows() do
                        local separator = row.directory:sub(-1) == "/" and "" or "/"
                        add_book(row.directory .. separator .. row.filename)
                    end
                end)
                pcall(function() stmt:close() end)
            end
            pcall(function() db:close() end)
        end
    end

    annotation_cache = quotes
    return quotes
end

local function source_enabled(name)
    local sources = settings:readSetting("sources")
    if type(sources) ~= "table" then return name == "default" end
    return sources[name] == true
end

local function automatic_font_size()
    return settings:readSetting("automatic_font_size") == true
end

local function font_size()
    return math.max(4, math.min(32, tonumber(settings:readSetting("font_size")) or 12))
end

local function max_font_size()
    return math.max(4, math.min(32, tonumber(settings:readSetting("max_font_size")) or 16))
end

local function show_author()
    return settings:readSetting("show_author") ~= false
end

local function show_title()
    return settings:readSetting("show_title") ~= false
end

local function rotation_mode()
    return settings:readSetting("rotation") == "refresh" and "refresh" or "daily"
end

local function shuffle(count)
    local deck = {}
    for i = 1, count do deck[i] = i end
    for i = count, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end

local function load_deck(prefix, count)
    if settings:readSetting(prefix .. "_deck_count") ~= count then return nil end
    local position = settings:readSetting(prefix .. "_deck_position")
    local raw = settings:readSetting(prefix .. "_deck_order")
    if type(position) ~= "number" or position < 1 or position > count
            or type(raw) ~= "string" then
        return nil
    end
    local deck = {}
    for value in raw:gmatch("%d+") do deck[#deck + 1] = tonumber(value) end
    if #deck ~= count then return nil end
    return deck, position
end

local function draw_from(pool, prefix)
    local count = #pool
    if count == 0 then return nil end
    local deck, position = load_deck(prefix, count)
    if not deck then
        deck, position = shuffle(count), 1
    end

    local index = deck[position]
    position = position + 1
    if position > count then
        local last_index = index
        deck = shuffle(count)
        if count > 1 and deck[1] == last_index then
            deck[1], deck[2] = deck[2], deck[1]
        end
        position = 1
    end

    settings:saveSetting(prefix .. "_deck_order", table.concat(deck, ","))
    settings:saveSetting(prefix .. "_deck_position", position)
    settings:saveSetting(prefix .. "_deck_count", count)
    settings:flush()
    return pool[index]
end

local function selected_quotes()
    local quotes = {}
    local function append(items)
        for _, quote in ipairs(items) do quotes[#quotes + 1] = quote end
    end
    if source_enabled("default") then append(DEFAULT_QUOTES) end
    if source_enabled("custom") and has_custom_quotes() then append(load_custom_quotes()) end
    if source_enabled("annotations") then append(load_annotation_quotes()) end
    if #quotes == 0 then append(DEFAULT_QUOTES) end
    return quotes
end

local function draw_quote()
    return draw_from(selected_quotes(), "combined")
end

local function select_quote_for_rotation()
    local today = os.date("%Y-%j")
    local previous_day = settings:readSetting("quote_day")
    local quote
    if rotation_mode() == "daily" and previous_day == today
            and type(settings:readSetting("current_quote_text")) == "string" then
        local wanted = settings:readSetting("current_quote_text")
        for _, candidate in ipairs(selected_quotes()) do
            if candidate.text == wanted then
                quote = candidate
                break
            end
        end
    end
    if not quote then quote = draw_quote() end
    settings:saveSetting("quote_day", today)
    settings:saveSetting("current_quote_text", quote and quote.text or nil)
    settings:flush()
    return quote
end

local function reset_session_history()
    quote_history = {}
    history_position = 0
end

local function current_quote()
    if history_position < 1 then
        local quote = select_quote_for_rotation()
            or { text = _("No quotes available."), attribution = "" }
        quote_history[1] = quote
        history_position = 1
    end
    return quote_history[history_position]
end

local function refresh_widget()
    if MomentsOfZen.instance then MomentsOfZen.instance:registerWidget() end
end

local function step_quote(delta)
    current_quote()
    if delta < 0 then
        if history_position > 1 then history_position = history_position - 1 end
    elseif history_position < #quote_history then
        history_position = history_position + 1
    else
        local quote = draw_quote()
        if quote then
            quote_history[#quote_history + 1] = quote
            history_position = #quote_history
        end
    end
    refresh_widget()
end

local function toggle_source(name)
    local sources = settings:readSetting("sources")
    if type(sources) ~= "table" then sources = { default = true } end
    sources[name] = sources[name] ~= true
    if not sources.default and not sources.custom and not sources.annotations then
        sources.default = true
    end
    settings:saveSetting("sources", sources)
    settings:flush()
    reset_session_history()
    refresh_widget()
end

local function show_widget_settings()
    local dialog
    local function reopen()
        if dialog then UIManager:close(dialog) end
        UIManager:nextTick(show_widget_settings)
    end
    local function save_and_reopen(key, value, reset_quotes)
        settings:saveSetting(key, value)
        settings:flush()
        if reset_quotes then reset_session_history() end
        refresh_widget()
        reopen()
    end
    local function source_button(label, name, enabled)
        return {
            text = (source_enabled(name) and "\226\156\147  " or "     ") .. label,
            align = "left",
            enabled = enabled ~= false,
            callback = function()
                toggle_source(name)
                reopen()
            end,
        }
    end
    local size_label = automatic_font_size()
        and string.format(_("Maximum font size: %d"), max_font_size())
        or string.format(_("Font size: %d"), font_size())

    local buttons = {
            { { text = _("Quote sources"), enabled = false, align = "left" } },
            { source_button(_("Default quotes"), "default") },
            { source_button(_("Custom quotes"), "custom", has_custom_quotes()) },
    }
    if not has_custom_quotes() then
        buttons[#buttons + 1] = {
            { text = _("quotes.lua is empty"), enabled = false, align = "left" },
        }
    end
    buttons[#buttons + 1] = { source_button(_("Annotations"), "annotations") }
    local remaining = {
            {
                {
                    text = (rotation_mode() == "daily" and "\226\156\147  " or "     ")
                        .. _("New quote daily"),
                    align = "left",
                    callback = function()
                        save_and_reopen("rotation", "daily", true)
                    end,
                },
            },
            {
                {
                    text = (rotation_mode() == "refresh" and "\226\156\147  " or "     ")
                        .. _("New quote on Home refresh"),
                    align = "left",
                    callback = function()
                        save_and_reopen("rotation", "refresh", true)
                    end,
                },
            },
            {
                {
                    text = (automatic_font_size() and "\226\156\147  " or "     ")
                        .. _("Automatic font size"),
                    align = "left",
                    callback = function()
                        save_and_reopen(
                            "automatic_font_size", not automatic_font_size(), false
                        )
                    end,
                },
            },
            {
                {
                    text = size_label,
                    align = "left",
                    callback = function()
                        local SpinWidget = require("ui/widget/spinwidget")
                        local auto = automatic_font_size()
                        UIManager:show(SpinWidget:new{
                            title_text = auto and _("Maximum font size") or _("Font size"),
                            value = auto and max_font_size() or font_size(),
                            value_min = 4,
                            value_max = 32,
                            value_step = 1,
                            callback = function(spin)
                                settings:saveSetting(
                                    auto and "max_font_size" or "font_size", spin.value
                                )
                                settings:flush()
                                refresh_widget()
                                reopen()
                            end,
                        })
                    end,
                },
            },
            {
                {
                    text = (show_author() and "\226\156\147  " or "     ")
                        .. _("Show author"),
                    align = "left",
                    callback = function()
                        save_and_reopen("show_author", not show_author(), false)
                    end,
                },
            },
            {
                {
                    text = (show_title() and "\226\156\147  " or "     ")
                        .. _("Show title"),
                    align = "left",
                    callback = function()
                        save_and_reopen("show_title", not show_title(), false)
                    end,
                },
            },
            {
                {
                    text = _("Reload annotation quotes"),
                    align = "left",
                    callback = function()
                        annotation_cache = nil
                        reset_session_history()
                        refresh_widget()
                        reopen()
                    end,
                },
            },
        }
    for _, row in ipairs(remaining) do buttons[#buttons + 1] = row end
    dialog = ButtonDialog:new{
        title = _("Moments of Zen"),
        modal = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
    return true
end

local function open_annotation(quote)
    if not (quote and quote.is_annotation and quote.filepath) then return false end
    local filepath, pos0, page = quote.filepath, quote.pos0, quote.page
    local filename = filepath:match("([^/\\]+)$") or filepath

    local function open()
        UIManager:nextTick(function()
            local FileManager = require("apps/filemanager/filemanager")
            local filemanagerutil = require("apps/filemanager/filemanagerutil")
            local fm = FileManager.instance
            if filemanagerutil.openFile then
                filemanagerutil.openFile(fm, filepath)
            elseif fm and type(fm.openFile) == "function" then
                fm:openFile(filepath)
            else
                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(filepath)
            end
            if pos0 or page then
                UIManager:scheduleIn(0.5, function()
                    local reader = package.loaded["apps/reader/readerui"]
                    local instance = reader and reader.instance
                    if not instance then return end
                    local Event = require("ui/event")
                    if pos0 then
                        instance:handleEvent(Event:new("GotoXPointer", pos0))
                    elseif page then
                        instance:handleEvent(Event:new("GotoPage", tonumber(page) or page))
                    end
                end)
            end
        end)
    end

    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:nextTick(function()
        UIManager:show(ConfirmBox:new{
            text = _("Open this file?") .. "\n\n" .. filename,
            ok_text = _("Open"),
            cancel_text = _("Cancel"),
            ok_callback = open,
        })
    end)
    return true
end

local function build_widget(ctx)
    if rotation_mode() == "refresh" then reset_session_history() end
    local width, height = ctx.width, ctx.height
    local quote = current_quote()
    local screen = Device.screen
    local padding = screen:scaleBySize(10)
    local content_width = math.max(30, width - padding * 2)
    local gap = screen:scaleBySize(3)
    local quote_text = "\226\128\156" .. quote.text .. "\226\128\157"
    local attribution_parts = {}
    if show_author() and quote.author and quote.author ~= "" then
        attribution_parts[#attribution_parts + 1] = quote.author
    end
    if show_title() and quote.title and quote.title ~= "" then
        attribution_parts[#attribution_parts + 1] = quote.title
    end
    local attribution = table.concat(attribution_parts, ",  ")
    local attribution_text = attribution ~= "" and ("\226\128\148 " .. attribution) or nil
    local available_height = math.max(20, height - padding * 2)
    local auto_font = automatic_font_size()

    -- Pick the largest size whose naturally wrapped quote and attribution fit.
    local quote_size = auto_font and 4 or font_size()
    local natural_quote_height, author_height = 20, 0
    local largest_size = auto_font and max_font_size() or quote_size
    local smallest_size = auto_font and 4 or quote_size
    for candidate = largest_size, smallest_size, -1 do
        local candidate_quote_face = Font:getFace(
            "smallinfofont", screen:scaleBySize(candidate)
        )
        local quote_probe = TextBoxWidget:new{
            text = quote_text,
            width = content_width,
            face = candidate_quote_face,
            alignment = "center",
            line_height = 0.55,
        }
        local measured_quote_height = quote_probe:getSize().h or 20
        if quote_probe.free then pcall(quote_probe.free, quote_probe) end

        local measured_author_height = 0
        if attribution_text then
            local candidate_author_face = Font:getFace(
                "smallinfofont",
                screen:scaleBySize(
                    math.max(6, math.floor(candidate * 0.9))
                )
            )
            local author_probe = TextBoxWidget:new{
                text = attribution_text,
                width = content_width,
                face = candidate_author_face,
                alignment = "center",
            }
            measured_author_height = author_probe:getSize().h or 0
            if author_probe.free then pcall(author_probe.free, author_probe) end
        end

        local total_height = measured_quote_height + measured_author_height
            + (attribution_text and gap or 0)
        quote_size = candidate
        natural_quote_height = measured_quote_height
        author_height = measured_author_height
        if total_height <= available_height then break end
    end

    local author_size = math.max(6, math.floor(quote_size * 0.9))
    local quote_face = Font:getFace("smallinfofont", screen:scaleBySize(quote_size))
    local author_face = Font:getFace("smallinfofont", screen:scaleBySize(author_size))

    local author_widget
    if attribution_text then
        author_widget = TextBoxWidget:new{
            text = attribution_text,
            width = content_width,
            face = author_face,
            alignment = "center",
            height_overflow_show_ellipsis = true,
        }
    end

    local max_quote_height = math.max(
        20,
        available_height - author_height - (author_widget and gap or 0)
    )
    local quote_widget = TextBoxWidget:new{
        text = quote_text,
        width = content_width,
        height = math.min(natural_quote_height, max_quote_height),
        face = quote_face,
        alignment = "center",
        line_height = 0.55,
        height_overflow_show_ellipsis = true,
    }
    local group = VerticalGroup:new{
        align = "center",
        quote_widget,
    }
    if author_widget then
        group[#group + 1] = VerticalSpan:new{ width = gap }
        group[#group + 1] = author_widget
    end

    local body = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            group,
        },
    }
    local input = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        ges_events = {
            TapQuote = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{ x = 0, y = 0, w = screen:getWidth(), h = screen:getHeight() },
                },
            },
            HoldQuote = {
                GestureRange:new{
                    ges = "hold",
                    range = Geom:new{ x = 0, y = 0, w = screen:getWidth(), h = screen:getHeight() },
                },
            },
            SwipeQuote = {
                GestureRange:new{
                    ges = "swipe",
                    range = Geom:new{ x = 0, y = 0, w = screen:getWidth(), h = screen:getHeight() },
                },
            },
        },
        body,
    }
    input.onTapQuote = function(self, _, gesture)
        if not (self.dimen and gesture and gesture.pos and self.dimen:contains(gesture.pos)) then
            return false
        end
        if quote.is_annotation then
            return open_annotation(quote)
        end
        -- Custom quotes have no tap action; navigation is handled by swipes.
        return true
    end
    input.onSwipeQuote = function(self, _, gesture)
        if not (self.dimen and gesture and gesture.pos and self.dimen:contains(gesture.pos)) then
            return false
        end
        if gesture.direction == "west" then
            step_quote(1)
            return true
        elseif gesture.direction == "east" then
            step_quote(-1)
            return true
        end
        return false
    end
    input.onHoldQuote = function(self, _, gesture)
        if not (self.dimen and gesture and gesture.pos and self.dimen:contains(gesture.pos)) then
            return false
        end
        -- Match Zen UI's stock widgets: widget settings open from a hold while
        -- Home edit mode is active.
        if ctx.editMode then return show_widget_settings() end
        return false
    end
    return input
end

function MomentsOfZen:registerWidget()
    local register = rawget(_G, "__ZEN_UI_REGISTER_HOME_ITEM")
    if type(register) ~= "function" then return false end
    return register(ID, build_widget, {
        label = _("Moments of Zen"),
        size = { preferred_pct = 0.20, min_pct = 0.14, max_pct = 0.32 },
    })
end

function MomentsOfZen:init()
    MomentsOfZen.instance = self
    self:registerWidget()
end

function MomentsOfZen:onZenUIReady()
    self:registerWidget()
end

-- KOReader broadcasts this whenever a highlight or note is added, edited, or
-- removed. Discard the session cache so the next Home build reads fresh
-- annotation data from the book sidecars.
function MomentsOfZen:onAnnotationsModified()
    annotation_cache = nil
    reset_session_history()
end

-- Closing a book flushes its latest document settings to disk. Invalidating
-- here as well guarantees the Home widget sees that final saved state.
function MomentsOfZen:onCloseDocument()
    annotation_cache = nil
    reset_session_history()
end

return MomentsOfZen
