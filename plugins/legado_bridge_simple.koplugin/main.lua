-- Legado书源桥接插件 - 简化版
-- 为KOReader提供Legado书源API连接功能

local BD = require("ui/bidi")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Menu = require("ui/widget/menu")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local _ = require("gettext")
local T = require("ffi/util").template
local logger = require("logger")

-- 添加详细日志
logger.info("[LEGADO] 插件开始加载...")

-- HTTP和JSON模块检测
local http_module = nil
local json_module = nil

-- 尝试加载HTTP模块
local function loadHttpModule()
    local modules = {"socket.http", "ssl.https"}
    for _, module_name in ipairs(modules) do
        local success, module = pcall(require, module_name)
        if success then
            logger.info("[LEGADO] HTTP模块: 使用" .. module_name)
            return module
        end
    end
    logger.warn("[LEGADO] 无法加载HTTP模块，将使用curl命令")
    return nil
end

-- 尝试加载JSON模块
local function loadJsonModule()
    local modules = {"rapidjson", "cjson", "dkjson"}
    for _, module_name in ipairs(modules) do
        local success, module = pcall(require, module_name)
        if success then
            logger.info("[LEGADO] JSON模块: 使用" .. module_name)
            return module
        end
    end
    logger.warn("[LEGADO] 无法加载JSON模块")
    return nil
end

-- 初始化模块
http_module = loadHttpModule()
json_module = loadJsonModule()

-- 主插件类（完全模仿Calibre插件结构）
local LegadoBridge = WidgetContainer:extend{
    name = "legado_bridge",
    is_doc_only = false,
}

logger.info("[LEGADO] LegadoBridge类定义完成")

-- 配置文件
local CONFIG_FILE = "legado_config.lua"
local DEFAULT_CONFIG = {
    server_url = "192.168.1.100:1122",
    last_search = "",
    cache_enabled = true,
    timeout = 10,
}

-- 书籍搜索和管理
local BookManager = {}

function BookManager:new(server_url)
    local o = {
        server_url = server_url or "192.168.1.100:1122",
        books = {},
        chapters = {}
    }
    setmetatable(o, self)
    self.__index = self
    logger.info("[LEGADO] BookManager初始化完成，服务器: " .. o.server_url)
    return o
end

function BookManager:setServer(server_url)
    self.server_url = server_url
    logger.info("[LEGADO] 服务器更新为: " .. server_url)
end

function BookManager:httpRequest(url)
    if http_module then
        local response_body = {}
        local result, status = http_module.request{
            url = url,
            sink = function(chunk)
                if chunk then
                    table.insert(response_body, chunk)
                end
            end
        }
        
        if status == 200 then
            return table.concat(response_body)
        else
            logger.warn("[LEGADO] HTTP请求失败: " .. tostring(status))
            return nil
        end
    else
        -- 使用curl作为备选方案
        local cmd = string.format('curl -s "%s"', url)
        local handle = io.popen(cmd)
        if handle then
            local result = handle:read("*a")
            handle:close()
            return result
        end
        return nil
    end
end

function BookManager:searchBooks(keyword)
    if not keyword or keyword == "" then
        return {}
    end
    
    local url = string.format("http://%s/searchBook?name=%s", 
                             self.server_url, 
                             keyword)
    
    logger.info("[LEGADO] 搜索书籍: " .. keyword)
    local response = self:httpRequest(url)
    
    if response and json_module then
        local success, books = pcall(json_module.decode, response)
        if success and type(books) == "table" then
            self.books = books
            logger.info("[LEGADO] 找到 " .. #books .. " 本书")
            return books
        end
    end
    
    logger.warn("[LEGADO] 搜索失败或解析错误")
    return {}
end

function BookManager:getChapters(book_url)
    local url = string.format("http://%s/getChapterList?url=%s", 
                             self.server_url, 
                             book_url)
    
    logger.info("[LEGADO] 获取章节列表")
    local response = self:httpRequest(url)
    
    if response and json_module then
        local success, chapters = pcall(json_module.decode, response)
        if success and type(chapters) == "table" then
            self.chapters = chapters
            logger.info("[LEGADO] 找到 " .. #chapters .. " 个章节")
            return chapters
        end
    end
    
    logger.warn("[LEGADO] 获取章节失败")
    return {}
end

function BookManager:getContent(chapter_url)
    local url = string.format("http://%s/getBookContent?url=%s", 
                             self.server_url, 
                             chapter_url)
    
    logger.info("[LEGADO] 获取章节内容")
    local response = self:httpRequest(url)
    
    if response and json_module then
        local success, content = pcall(json_module.decode, response)
        if success and content and content.content then
            logger.info("[LEGADO] 内容获取成功")
            return content.content
        end
    end
    
    logger.warn("[LEGADO] 获取内容失败")
    return "无法获取章节内容"
end

function BookManager:testConnection()
    local url = string.format("http://%s/", self.server_url)
    logger.info("[LEGADO] 测试连接: " .. url)
    
    local response = self:httpRequest(url)
    return response ~= nil
end

-- 调度器事件处理（模仿Calibre）
function LegadoBridge:onLegadoSearch()
    logger.info("[LEGADO] 调度器事件: 搜索")
    self:showSearchDialog()
    return true
end

function LegadoBridge:onLegadoSettings()
    logger.info("[LEGADO] 调度器事件: 设置")
    self:showServerSettings()
    return true
end

-- 调度器注册（完全模仿Calibre的注册方式）
function LegadoBridge:onDispatcherRegisterActions()
    logger.info("[LEGADO] 开始注册调度器动作")
    Dispatcher:registerAction("legado_search", {
        category = "none",
        event = "LegadoSearch",
        title = _("Legado书籍搜索"),
        general = true,
    })
    Dispatcher:registerAction("legado_settings", {
        category = "none", 
        event = "LegadoSettings",
        title = _("Legado服务器设置"),
        general = true,
    })
    logger.info("[LEGADO] 调度器动作注册完成")
end

-- 初始化（完全模仿Calibre的init方法）
function LegadoBridge:init()
    logger.info("[LEGADO] ========== 插件初始化开始 ==========")
    
    self:loadConfig()
    self.book_manager = BookManager:new(self.config.server_url)
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    
    logger.info("[LEGADO] ========== 插件初始化完成 ==========")
end

function LegadoBridge:loadConfig()
    logger.info("[LEGADO] 开始加载配置")
    local config_path = DataStorage:getDataDir() .. "/" .. CONFIG_FILE
    logger.info("[LEGADO] 配置文件路径: " .. config_path)
    
    self.settings = LuaSettings:open(config_path)
    self.config = {}
    
    for key, default_value in pairs(DEFAULT_CONFIG) do
        self.config[key] = self.settings:readSetting(key) or default_value
    end
    
    self.settings:close()
    logger.info("[LEGADO] 配置加载完成，服务器: " .. self.config.server_url)
end

function LegadoBridge:saveConfig()
    logger.info("[LEGADO] 保存配置")
    local config_path = DataStorage:getDataDir() .. "/" .. CONFIG_FILE
    local settings = LuaSettings:open(config_path)
    
    for key, value in pairs(self.config) do
        settings:saveSetting(key, value)
    end
    
    settings:flush()
    settings:close()
    logger.info("[LEGADO] 配置保存完成")
end

-- 主菜单注册（完全模仿Calibre的addToMainMenu结构）
function LegadoBridge:addToMainMenu(menu_items)
    logger.info("[LEGADO] ========== 开始添加主菜单（Calibre模式） ==========")
    
    menu_items.legado_bridge = {
        text = "📚 Legado书源",
        sub_item_table = {
            {
                text = "🔍 搜索书籍",
                callback = function()
                    self:showSearchDialog()
                end,
            },
            {
                text = "⚙️ 服务器设置", 
                callback = function()
                    self:showServerSettings()
                end,
            },
            {
                text = "📊 测试连接",
                callback = function()
                    self:testConnection()
                end,
            },
        }
    }
    
    logger.info("[LEGADO] ✅ Legado菜单项添加成功")
    logger.info("[LEGADO] ========== 主菜单添加完成（Calibre模式） ==========")
end

function LegadoBridge:showSearchDialog()
    logger.info("[LEGADO] 显示搜索对话框")
    self.search_dialog = InputDialog:new{
        title = "搜索Legado书籍",
        input_hint = "请输入书名或作者",
        buttons = {
            {
                {
                    text = "取消",
                    callback = function()
                        UIManager:close(self.search_dialog)
                    end,
                },
                {
                    text = "搜索",
                    is_enter_default = true,
                    callback = function()
                        local keyword = self.search_dialog:getInputText()
                        UIManager:close(self.search_dialog)
                        if keyword and keyword ~= "" then
                            self:performSearch(keyword)
                        end
                    end,
                },
            }
        },
    }
    
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

function LegadoBridge:performSearch(keyword)
    logger.info("[LEGADO] 执行搜索: " .. keyword)
    
    UIManager:show(InfoMessage:new{
        text = "正在搜索: " .. keyword,
        timeout = 1,
    })
    
    local books = self.book_manager:searchBooks(keyword)
    
    if #books > 0 then
        self:showBookList(books)
    else
        UIManager:show(InfoMessage:new{
            text = "未找到相关书籍",
            timeout = 2,
        })
    end
end

function LegadoBridge:showBookList(books)
    logger.info("[LEGADO] 显示书籍列表")
    local book_items = {}
    
    for _, book in ipairs(books) do
        table.insert(book_items, {
            text = string.format("%s - %s", book.name or "未知书名", book.author or "未知作者"),
            callback = function()
                self:showBookChapters(book)
            end,
        })
    end
    
    local book_menu = Menu:new{
        title = "搜索结果",
        item_table = book_items,
        width = UIManager.screen:getWidth() * 0.9,
        height = UIManager.screen:getHeight() * 0.8,
    }
    
    UIManager:show(book_menu)
end

function LegadoBridge:showBookChapters(book)
    logger.info("[LEGADO] 显示章节列表: " .. (book.name or "未知"))
    UIManager:show(InfoMessage:new{
        text = "正在获取章节列表...",
        timeout = 1,
    })
    
    local chapters = self.book_manager:getChapters(book.bookUrl)
    
    if #chapters > 0 then
        local chapter_items = {}
        for _, chapter in ipairs(chapters) do
            table.insert(chapter_items, {
                text = chapter.title or ("第" .. _(i .. "章"),
                callback = function()
                    self:showChapterContent(chapter)
                end
            })
        end
        
        local chapter_menu = Menu:new{
            title = book.name or "章节列表",
            item_table = chapter_items,
            width = UIManager.screen:getWidth() * 0.9,
            height = UIManager.screen:getHeight() * 0.8,
        }
        
        UIManager:show(chapter_menu)
    else
        UIManager:show(InfoMessage:new{
            text = "无法获取章节列表",
            timeout = 2,
        })
    end
end

function LegadoBridge:showChapterContent(chapter)
    logger.info("[LEGADO] 显示章节内容: " .. (chapter.title or "未知章节"))
    
    UIManager:show(InfoMessage:new{
        text = "正在获取章节内容...",
        timeout = 1,
    })
    
    local content = self.book_manager:getContent(chapter.url)
    
    UIManager:show(InfoMessage:new{
        text = content,
        timeout = 10,
    })
end

function LegadoBridge:showServerSettings()
    logger.info("[LEGADO] 显示服务器设置")
    
    self.settings_dialog = InputDialog:new{
        title = "Legado服务器设置",
        input = self.config.server_url,
        input_hint = "IP:端口 (例如: 192.168.1.100:1122)",
        buttons = {
            {
                {
                    text = "取消",
                    callback = function()
                        UIManager:close(self.settings_dialog)
                    end,
                },
                {
                    text = "保存",
                    is_enter_default = true,
                    callback = function()
                        local new_server = self.settings_dialog:getInputText()
                        UIManager:close(self.settings_dialog)
                        if new_server and new_server ~= "" then
                            self.config.server_url = new_server
                            self.book_manager:setServer(new_server)
                            self:saveConfig()
                            UIManager:show(InfoMessage:new{
                                text = "服务器设置已保存: " .. new_server,
                                timeout = 2,
                            })
                        end
                    end,
                },
            }
        },
    }
    
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function LegadoBridge:testConnection()
    logger.info("[LEGADO] 测试连接")
    
    UIManager:show(InfoMessage:new{
        text = "正在测试连接...",
        timeout = 1,
    })
    
    local success = self.book_manager:testConnection()
    
    if success then
        UIManager:show(InfoMessage:new{
            text = "连接成功！服务器: " .. self.config.server_url,
            timeout = 3,
        })
    else
        UIManager:show(InfoMessage:new{
            text = "连接失败！请检查服务器地址和网络",
            timeout = 3,
        })
    end
end

logger.info("[LEGADO] 插件模块加载完成")

return LegadoBridge

