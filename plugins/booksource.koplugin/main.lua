local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local DataStorage = require("datastorage")
local _ = require("gettext")
local JSON = require("json")
local NetUtils = require("netutils")
local logger = require("logger")
local util = require("ffi/util")



local BookSource = WidgetContainer:extend{
    name = "booksource",
    is_doc_only = false,
}

function BookSource:onDispatcherRegisterActions()
    Dispatcher:registerAction("booksource_action", {category="none", event="BookSource", title=_("Book Source"), general=true,})
end

function BookSource:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function BookSource:onAddBookSource(touchmenu_instance)
    local old_booksource_url = G_reader_settings:readSetting("booksource_url")
    local sample_input
    sample_input = InputDialog:new{
        title = _("Dialog title"),
        input = old_booksource_url,
        input_hint = _("Book source json url"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(sample_input)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_url = sample_input:getInputText()
                        if new_url:match("^https?://[%w-_%.%?%.:/%+=&]+") then
                            G_reader_settings:saveSetting("booksource_url", new_url)
                            UIManager:close(sample_input)
                            UIManager:show(InfoMessage:new{text = _("save success")})
                            touchmenu_instance:updateItems()
                        else
                            UIManager:show(InfoMessage:new{text = _("uninvalid url")})
                        end
                    end,
                },
            }
        },
    }
    UIManager:show(sample_input)
    sample_input:onShowKeyboard()
end

function BookSource:onAsyncBookSource()
    local old_booksource_url = G_reader_settings:readSetting("booksource_url")
    local l = InfoMessage:new{text = _("Syncing")}
    UIManager:show(l)
    local success, ret;
    logger.dbg("Response start1 :", UIManager:getTime())
    -- util.sleep(5)
    logger.dbg("Response start2 :", UIManager:getTime())
    success, ret = NetUtils:getUrlContent(old_booksource_url, 100, 5)
    UIManager:close(l)
    UIManager:show(InfoMessage:new{text = _("Syncing success")})
    local json = JSON.decode(ret)
    logger.dbg("Response :", success, json)
end

function BookSource:addToMainMenu(menu_items)
    menu_items.book_source = {
        text = _("Book Source"),
        sorting_hint = "more_tools",
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Hello, book source"),
            })
        end,
        sub_item_table = {
            {
                text = _("About book source"),
                callback = function()
                    local about_text = _("this is a book source")
                    UIManager:show(InfoMessage:new{
                        text = about_text,
                    })
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Add book source"),
                callback = function(touchmenu_instance)
                    BookSource:onAddBookSource(touchmenu_instance)
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Sync book source"),
                callback = function(touchmenu_instance)
                    util.runInSubProcess(BookSource.onAsyncBookSource, false, false)
                end,
                keep_menu_open = true,
                separator = true,
            },
        }
    }
end

function BookSource:onBookSource()
    local popup = InfoMessage:new{
        text = _("Book Source"),
    }
    UIManager:show(popup)
end

return BookSource
