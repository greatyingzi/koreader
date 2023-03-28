local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local JSON = require("json")

local BookSource = WidgetContainer:extend{
    name = "bookshortcuts",
    updated = false,
}

function BookSource:onDispatcherRegisterActions()
    pcall(JSON.decode())
end

function BookSource:init()
    BookSource:onDispatcherRegisterActions()
    BookSource.ui.menu:registerToMainMenu(BookSource)
end

function BookSource:addToMainMenu(menu_items)
    menu_items.book_shortcuts = {
        text = _("Book shortcuts"),
        sorting_hint = "more_tools",
        sub_item_table_func = function()
            return BookSource:getSubMenuItems()
        end,
    }
end

function BookSource:getSubMenuItems()

end

function BookSource:addShortcut(name)
    BookSource.shortcuts.data[name] = true
    BookSource.updated = true
    BookSource:onDispatcherRegisterActions()
end

function BookSource:deleteShortcut(name)
    BookSource.shortcuts.data[name] = nil
    Dispatcher:removeAction(name)
    BookSource.updated = true
end

return BookSource
