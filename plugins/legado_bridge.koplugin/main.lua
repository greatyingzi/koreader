--[[
KOReader - Legado API桥接插件
实现与Legado阅读APP的API集成，提供在线书源功能
支持搜索、章节获取、内容阅读等完整功能
]]--

local BookSourcePlugin = {
    name = "legado_bridge",
    fullname = "Legado书源桥接",
    description = "通过API与Legado应用集成，提供在线书源功能",
}

local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local logger = require("logger")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")

-- 配置常量
local CONFIG = {
    -- Legado Web API配置
    api = {
        host = "192.168.1.100",  -- 默认设置为常见的内网IP段
        port = "1122",
        timeout = 30,
        base_url = function(self) 
            return "http://" .. self.host .. ":" .. self.port 
        end
    },
    
    -- 插件配置
    cache_dir = "legado_cache",
    max_search_results = 20,
    max_chapters_preview = 5,
    
    -- 网络配置
    user_agent = "KOReader-LegadoBridge/1.0",
    request_delay = 1000, -- 请求间隔(毫秒)
}

-- API客户端类
local LegadoAPI = {}

function LegadoAPI:new()
    local api = {
        base_url = CONFIG.api:base_url(),
        timeout = CONFIG.api.timeout
    }
    setmetatable(api, self)
    self.__index = self
    return api
end

-- 发送HTTP请求的通用方法
function LegadoAPI:request(method, endpoint, data)
    local url = self.base_url .. endpoint
    local response_body = {}
    
    local request_params = {
        url = url,
        method = method,
        headers = {
            ["User-Agent"] = CONFIG.user_agent,
            ["Accept"] = "application/json",
        },
        sink = ltn12.sink.table(response_body)
    }
    
    -- 如果有数据需要发送
    if data and (method == "POST" or method == "PUT") then
        local json_data = json.encode(data)
        request_params.headers["Content-Type"] = "application/json"
        request_params.headers["Content-Length"] = tostring(#json_data)
        request_params.source = ltn12.source.string(json_data)
    end
    
    logger.info("LegadoAPI: 请求", method, url)
    
    local result, status_code, headers = http.request(request_params)
    
    if not result then
        logger.err("LegadoAPI: 请求失败", status_code)
        return nil, "网络请求失败: " .. tostring(status_code)
    end
    
    local response_text = table.concat(response_body)
    
    if status_code ~= 200 then
        logger.err("LegadoAPI: HTTP错误", status_code, response_text)
        return nil, "HTTP错误: " .. status_code
    end
    
    -- 解析JSON响应
    local success, response_data = pcall(json.decode, response_text)
    if not success then
        logger.err("LegadoAPI: JSON解析失败", response_text)
        return nil, "响应格式错误"
    end
    
    return response_data, nil
end

-- 搜索书籍
function LegadoAPI:searchBooks(keyword)
    logger.info("LegadoAPI: 搜索书籍", keyword)
    
    local data = {
        searchKey = keyword,
        searchScope = "all"  -- 搜索所有书源
    }
    
    local response, err = self:request("POST", "/searchBook", data)
    if err then
        return nil, err
    end
    
    -- 处理搜索结果
    if response and response.data then
        return response.data, nil
    else
        return {}, "没有找到相关书籍"
    end
end

-- 获取书籍详情
function LegadoAPI:getBookInfo(book_url, origin)
    logger.info("LegadoAPI: 获取书籍详情", book_url)
    
    local data = {
        bookUrl = book_url,
        origin = origin
    }
    
    local response, err = self:request("POST", "/getBookInfo", data)
    if err then
        return nil, err
    end
    
    return response.data, nil
end

-- 获取章节列表
function LegadoAPI:getChapterList(book_url, origin)
    logger.info("LegadoAPI: 获取章节列表", book_url)
    
    local data = {
        bookUrl = book_url,
        origin = origin
    }
    
    local response, err = self:request("POST", "/getChapterList", data)
    if err then
        return nil, err
    end
    
    return response.data, nil
end

-- 获取章节内容
function LegadoAPI:getBookContent(book_url, chapter_index, origin)
    logger.info("LegadoAPI: 获取章节内容", book_url, chapter_index)
    
    local data = {
        bookUrl = book_url,
        index = chapter_index,
        origin = origin
    }
    
    local response, err = self:request("POST", "/getBookContent", data)
    if err then
        return nil, err
    end
    
    return response.data, nil
end

-- 检查Legado服务状态
function LegadoAPI:checkStatus()
    local response, err = self:request("GET", "/", nil)
    return response ~= nil, err
end

-- 缓存管理类
local CacheManager = {}

function CacheManager:new(plugin)
    local cache = {
        plugin = plugin,
        cache_dir = plugin.path .. "/" .. CONFIG.cache_dir
    }
    setmetatable(cache, self)
    self.__index = self
    
    -- 确保缓存目录存在
    lfs.mkdir(cache.cache_dir)
    
    return cache
end

function CacheManager:getCacheKey(type, params)
    local key = type .. "_" .. table.concat(params, "_")
    return key:gsub("[^%w_%-]", "_") -- 清理文件名非法字符
end

function CacheManager:get(cache_key)
    local file_path = self.cache_dir .. "/" .. cache_key .. ".json"
    local file = io.open(file_path, "r")
    
    if not file then
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, data = pcall(json.decode, content)
    if success then
        return data
    else
        return nil
    end
end

function CacheManager:set(cache_key, data, ttl)
    ttl = ttl or 3600 -- 默认1小时过期
    
    local cache_data = {
        data = data,
        timestamp = os.time(),
        ttl = ttl
    }
    
    local file_path = self.cache_dir .. "/" .. cache_key .. ".json"
    local file = io.open(file_path, "w")
    
    if file then
        file:write(json.encode(cache_data))
        file:close()
        return true
    else
        return false
    end
end

function CacheManager:isExpired(cache_key)
    local cache_data = self:get(cache_key)
    if not cache_data then
        return true
    end
    
    local current_time = os.time()
    return (current_time - cache_data.timestamp) > cache_data.ttl
end

-- 配置管理类
local ConfigManager = {}

function ConfigManager:new(plugin)
    local config_mgr = {
        plugin = plugin,
        config_file = plugin.path .. "/legado_config.json"
    }
    setmetatable(config_mgr, self)
    self.__index = self
    return config_mgr
end

function ConfigManager:load()
    local file = io.open(self.config_file, "r")
    if not file then
        logger.info("LegadoBridge: 配置文件不存在，使用默认配置")
        return self:getDefaultConfig()
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, config = pcall(json.decode, content)
    if success and config then
        logger.info("LegadoBridge: 加载配置成功")
        return config
    else
        logger.warn("LegadoBridge: 配置文件解析失败，使用默认配置")
        return self:getDefaultConfig()
    end
end

function ConfigManager:save(config)
    local file = io.open(self.config_file, "w")
    if not file then
        logger.err("LegadoBridge: 无法保存配置文件")
        return false
    end
    
    local success, json_str = pcall(json.encode, config)
    if success then
        file:write(json_str)
        file:close()
        logger.info("LegadoBridge: 配置保存成功")
        return true
    else
        file:close()
        logger.err("LegadoBridge: 配置序列化失败")
        return false
    end
end

function ConfigManager:getDefaultConfig()
    return {
        api = {
            host = "192.168.1.100",
            port = "1122",
            timeout = 30
        },
        cache = {
            search_ttl = 1800,  -- 30分钟
            content_ttl = 3600  -- 1小时
        },
        ui = {
            max_search_results = 20,
            max_chapters_preview = 5
        }
    }
end

-- 主插件类方法实现
function BookSourcePlugin:init()
    logger.info("LegadoBridge: 初始化插件")
    
    -- 初始化配置管理器
    self.config_mgr = ConfigManager:new(self)
    local user_config = self.config_mgr:load()
    
    -- 更新全局配置
    CONFIG.api.host = user_config.api.host
    CONFIG.api.port = user_config.api.port
    CONFIG.api.timeout = user_config.api.timeout
    
    -- 初始化API客户端
    self.api = LegadoAPI:new()
    
    -- 初始化缓存管理器
    self.cache = CacheManager:new(self)
    
    -- 添加菜单项
    self.ui.menu:registerToMainMenu(self)
    
    logger.info("LegadoBridge: 使用服务地址 " .. CONFIG.api.host .. ":" .. CONFIG.api.port)
end

function BookSourcePlugin:addToMainMenu(menu_items)
    menu_items.legado_bridge = {
        text = "📚 在线书源",
        sorting_hint = "tools",
        callback = function()
            self:showMainMenu()
        end,
    }
end

-- 显示主菜单
function BookSourcePlugin:showMainMenu()
    local menu_items = {
        {
            text = "🔍 搜索书籍",
            callback = function()
                self:showSearchDialog()
            end
        },
        {
            text = "⚙️ 设置",
            callback = function()
                self:showSettings()
            end
        },
        {
            text = "📊 状态检查",
            callback = function()
                self:checkLegadoStatus()
            end
        },
        {
            text = "🗑️ 清理缓存",
            callback = function()
                self:clearCache()
            end
        }
    }
    
    local menu = Menu:new{
        title = "Legado书源",
        item_table = menu_items,
        width_factor = 0.6,
    }
    
    UIManager:show(menu)
end

-- 显示搜索对话框
function BookSourcePlugin:showSearchDialog()
    local input_dialog = InputDialog:new{
        title = "搜索书籍",
        input_hint = "请输入书名或作者",
        buttons = {
            {
                {
                    text = "取消",
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = "搜索",
                    callback = function()
                        local keyword = input_dialog:getInputText()
                        if keyword and keyword:len() > 0 then
                            UIManager:close(input_dialog)
                            self:performSearch(keyword)
                        end
                    end,
                },
            }
        },
    }
    
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

-- 执行搜索
function BookSourcePlugin:performSearch(keyword)
    -- 显示加载信息
    UIManager:show(InfoMessage:new{
        text = "正在搜索: " .. keyword,
        timeout = 2,
    })
    
    -- 检查缓存
    local cache_key = self.cache:getCacheKey("search", {keyword})
    local cached_results = nil
    
    if not self.cache:isExpired(cache_key) then
        cached_results = self.cache:get(cache_key)
        if cached_results then
            logger.info("LegadoBridge: 使用缓存的搜索结果")
            self:showSearchResults(cached_results.data, keyword)
            return
        end
    end
    
    -- 执行API搜索
    local results, err = self.api:searchBooks(keyword)
    
    if err then
        UIManager:show(InfoMessage:new{
            text = "搜索失败: " .. err,
            timeout = 3,
        })
        return
    end
    
    if not results or #results == 0 then
        UIManager:show(InfoMessage:new{
            text = "没有找到相关书籍",
            timeout = 3,
        })
        return
    end
    
    -- 缓存搜索结果
    self.cache:set(cache_key, results, 1800) -- 30分钟缓存
    
    -- 显示搜索结果
    self:showSearchResults(results, keyword)
end

-- 显示搜索结果
function BookSourcePlugin:showSearchResults(results, keyword)
    local menu_items = {}
    
    for i, book in ipairs(results) do
        if i > CONFIG.max_search_results then
            break
        end
        
        local item_text = string.format("📖 %s\n👤 %s | 📚 %s", 
                                       book.name or "未知书名",
                                       book.author or "未知作者", 
                                       book.origin or "未知来源")
        
        table.insert(menu_items, {
            text = item_text,
            callback = function()
                self:showBookDetail(book)
            end
        })
    end
    
    if #menu_items == 0 then
        UIManager:show(InfoMessage:new{
            text = "搜索结果为空",
            timeout = 3,
        })
        return
    end
    
    local menu = Menu:new{
        title = "搜索结果: " .. keyword,
        item_table = menu_items,
        width_factor = 0.8,
    }
    
    UIManager:show(menu)
end

-- 显示书籍详情
function BookSourcePlugin:showBookDetail(book)
    -- 获取书籍详细信息
    local book_info, err = self.api:getBookInfo(book.bookUrl, book.origin)
    
    if err then
        UIManager:show(InfoMessage:new{
            text = "获取书籍信息失败: " .. err,
            timeout = 3,
        })
        return
    end
    
    -- 显示书籍信息和操作选项
    local detail_text = string.format([[
📖 书名: %s
👤 作者: %s  
📚 来源: %s
📝 简介: %s
]], 
        book_info.name or book.name,
        book_info.author or book.author,
        book_info.origin or book.origin,
        (book_info.intro and book_info.intro:sub(1, 100) .. "...") or "暂无简介"
    )
    
    local menu_items = {
        {
            text = "📋 查看章节列表",
            callback = function()
                self:showChapterList(book_info)
            end
        },
        {
            text = "⬇️ 下载整本书",
            callback = function()
                self:downloadBook(book_info)
            end
        }
    }
    
    local menu = Menu:new{
        title = detail_text,
        item_table = menu_items,
        width_factor = 0.8,
    }
    
    UIManager:show(menu)
end

-- 显示章节列表
function BookSourcePlugin:showChapterList(book_info)
    UIManager:show(InfoMessage:new{
        text = "正在获取章节列表...",
        timeout = 2,
    })
    
    local chapters, err = self.api:getChapterList(book_info.bookUrl, book_info.origin)
    
    if err then
        UIManager:show(InfoMessage:new{
            text = "获取章节列表失败: " .. err,
            timeout = 3,
        })
        return
    end
    
    local menu_items = {}
    
    for i, chapter in ipairs(chapters) do
        table.insert(menu_items, {
            text = string.format("%d. %s", i, chapter.title),
            callback = function()
                self:readChapter(book_info, chapter, i)
            end
        })
    end
    
    local menu = Menu:new{
        title = "章节列表: " .. book_info.name,
        item_table = menu_items,
        width_factor = 0.8,
    }
    
    UIManager:show(menu)
end

-- 阅读章节
function BookSourcePlugin:readChapter(book_info, chapter, chapter_index)
    UIManager:show(InfoMessage:new{
        text = "正在获取章节内容...",
        timeout = 2,
    })
    
    local content, err = self.api:getBookContent(book_info.bookUrl, chapter_index - 1, book_info.origin)
    
    if err then
        UIManager:show(InfoMessage:new{
            text = "获取章节内容失败: " .. err,
            timeout = 3,
        })
        return
    end
    
    -- 创建临时文件并打开阅读
    local temp_file = self:createTempBookFile(book_info, chapter, content)
    if temp_file then
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(temp_file)
    end
end

-- 创建临时书籍文件
function BookSourcePlugin:createTempBookFile(book_info, chapter, content)
    local temp_dir = self.path .. "/temp"
    lfs.mkdir(temp_dir)
    
    local filename = string.format("%s_%s.txt", 
                                 book_info.name:gsub("[^%w_%-]", "_"),
                                 chapter.title:gsub("[^%w_%-]", "_"))
    local filepath = temp_dir .. "/" .. filename
    
    local file = io.open(filepath, "w")
    if not file then
        return nil
    end
    
    -- 写入章节内容
    file:write(string.format("# %s\n\n## %s\n\n%s", 
                           book_info.name, 
                           chapter.title, 
                           content))
    file:close()
    
    return filepath
end

-- 检查Legado状态
function BookSourcePlugin:checkLegadoStatus()
    local is_available, err = self.api:checkStatus()
    
    local status_text
    if is_available then
        status_text = "✅ Legado服务连接正常\n服务地址: " .. self.api.base_url
    else
        status_text = "❌ Legado服务连接失败\n错误信息: " .. (err or "未知错误") .. 
                     "\n\n请确保:\n1. Legado应用已启动\n2. Web服务已开启\n3. 服务地址正确"
    end
    
    UIManager:show(InfoMessage:new{
        text = status_text,
        timeout = 5,
    })
end

-- 清理缓存
function BookSourcePlugin:clearCache()
    local confirm_box = ConfirmBox:new{
        text = "确定要清理所有缓存吗？\n这将删除搜索结果和章节内容缓存。",
        ok_callback = function()
            -- 删除缓存目录中的所有文件
            for file in lfs.dir(self.cache.cache_dir) do
                if file ~= "." and file ~= ".." then
                    local filepath = self.cache.cache_dir .. "/" .. file
                    os.remove(filepath)
                end
            end
            
            UIManager:show(InfoMessage:new{
                text = "缓存已清理",
                timeout = 2,
            })
        end,
    }
    
    UIManager:show(confirm_box)
end

-- 显示设置界面
function BookSourcePlugin:showSettings()
    local menu_items = {
        {
            text = string.format("📡 服务地址: %s:%s", CONFIG.api.host, CONFIG.api.port),
            callback = function()
                self:showServerSettings()
            end
        },
        {
            text = string.format("⏱️ 请求超时: %d秒", CONFIG.api.timeout),
            callback = function()
                self:showTimeoutSettings()
            end
        },
        {
            text = "🔍 自动发现服务",
            callback = function()
                self:autoDiscoverService()
            end
        },
        {
            text = "📋 常用IP地址",
            callback = function()
                self:showCommonIPs()
            end
        },
        {
            text = "💾 导出配置",
            callback = function()
                self:exportConfig()
            end
        },
        {
            text = "📥 导入配置",
            callback = function()
                self:importConfig()
            end
        }
    }
    
    local menu = Menu:new{
        title = "Legado桥接设置",
        item_table = menu_items,
        width_factor = 0.7,
    }
    
    UIManager:show(menu)
end

-- 显示服务器设置
function BookSourcePlugin:showServerSettings()
    local input_dialog = InputDialog:new{
        title = "设置Legado服务地址",
        input_hint = "格式: IP:端口 (如: 192.168.1.100:1122)",
        input = CONFIG.api.host .. ":" .. CONFIG.api.port,
        buttons = {
            {
                {
                    text = "取消",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = "测试连接",
                    callback = function()
                        local input_text = input_dialog:getInputText()
                        local host, port = input_text:match("([^:]+):([^:]+)")
                        
                        if host and port then
                            self:testConnection(host, port)
                        else
                            UIManager:show(InfoMessage:new{
                                text = "地址格式错误",
                                timeout = 2,
                            })
                        end
                    end,
                },
                {
                    text = "保存",
                    callback = function()
                        local input_text = input_dialog:getInputText()
                        local host, port = input_text:match("([^:]+):([^:]+)")
                        
                        if host and port then
                            CONFIG.api.host = host
                            CONFIG.api.port = port
                            self.api.base_url = CONFIG.api:base_url()
                            
                            -- 保存到配置文件
                            local config = self.config_mgr:load()
                            config.api.host = host
                            config.api.port = port
                            self.config_mgr:save(config)
                            
                            UIManager:close(input_dialog)
                            UIManager:show(InfoMessage:new{
                                text = "服务地址已保存: " .. host .. ":" .. port,
                                timeout = 3,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = "地址格式错误",
                                timeout = 2,
                            })
                        end
                    end,
                },
            }
        },
    }
    
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

-- 测试连接功能
function BookSourcePlugin:testConnection(host, port)
    UIManager:show(InfoMessage:new{
        text = "正在测试连接: " .. host .. ":" .. port,
        timeout = 2,
    })
    
    -- 创建临时API客户端
    local temp_api = {
        base_url = "http://" .. host .. ":" .. port,
        timeout = 10
    }
    setmetatable(temp_api, {__index = LegadoAPI})
    
    local is_available, err = temp_api:checkStatus()
    
    local status_text
    if is_available then
        status_text = "✅ 连接测试成功!\n服务地址: " .. temp_api.base_url .. "\n可以保存此配置"
    else
        status_text = "❌ 连接测试失败\n错误: " .. (err or "未知错误") .. "\n\n请检查:\n• Legado应用是否运行\n• Web服务是否开启\n• IP地址是否正确"
    end
    
    UIManager:show(InfoMessage:new{
        text = status_text,
        timeout = 5,
    })
end

-- 显示常用IP地址
function BookSourcePlugin:showCommonIPs()
    local common_ips = {
        "192.168.1.100:1122",
        "192.168.1.101:1122", 
        "192.168.1.102:1122",
        "192.168.0.100:1122",
        "192.168.0.101:1122",
        "10.0.0.100:1122",
        "127.0.0.1:1122"
    }
    
    local menu_items = {}
    
    for _, ip in ipairs(common_ips) do
        table.insert(menu_items, {
            text = "📱 " .. ip,
            callback = function()
                local host, port = ip:match("([^:]+):([^:]+)")
                if host and port then
                    CONFIG.api.host = host
                    CONFIG.api.port = port
                    self.api.base_url = CONFIG.api:base_url()
                    
                    -- 保存配置
                    local config = self.config_mgr:load()
                    config.api.host = host
                    config.api.port = port
                    self.config_mgr:save(config)
                    
                    UIManager:show(InfoMessage:new{
                        text = "已选择: " .. ip .. "\n点击状态检查测试连接",
                        timeout = 3,
                    })
                end
            end
        })
    end
    
    local menu = Menu:new{
        title = "选择常用IP地址",
        item_table = menu_items,
        width_factor = 0.6,
    }
    
    UIManager:show(menu)
end

-- 自动发现服务
function BookSourcePlugin:autoDiscoverService()
    UIManager:show(InfoMessage:new{
        text = "正在扫描网络中的Legado服务...",
        timeout = 2,
    })
    
    -- 简单的网络扫描
    local discovered_services = {}
    local common_networks = {"192.168.1", "192.168.0", "10.0.0", "172.16.0"}
    
    for _, network in ipairs(common_networks) do
        for i = 100, 110 do
            local test_ip = network .. "." .. i
            local temp_api = {
                base_url = "http://" .. test_ip .. ":1122",
                timeout = 3
            }
            setmetatable(temp_api, {__index = LegadoAPI})
            
            local is_available = temp_api:checkStatus()
            if is_available then
                table.insert(discovered_services, test_ip .. ":1122")
            end
        end
    end
    
    if #discovered_services > 0 then
        local menu_items = {}
        for _, service in ipairs(discovered_services) do
            table.insert(menu_items, {
                text = "🎯 发现服务: " .. service,
                callback = function()
                    local host, port = service:match("([^:]+):([^:]+)")
                    CONFIG.api.host = host
                    CONFIG.api.port = port
                    self.api.base_url = CONFIG.api:base_url()
                    
                    -- 保存配置
                    local config = self.config_mgr:load()
                    config.api.host = host
                    config.api.port = port
                    self.config_mgr:save(config)
                    
                    UIManager:show(InfoMessage:new{
                        text = "已自动配置: " .. service,
                        timeout = 3,
                    })
                end
            })
        end
        
        local menu = Menu:new{
            title = "发现的Legado服务",
            item_table = menu_items,
            width_factor = 0.7,
        }
        
        UIManager:show(menu)
    else
        UIManager:show(InfoMessage:new{
            text = "❌ 未发现Legado服务\n请确保:\n• Legado应用正在运行\n• Web服务已开启\n• 设备在同一网络",
            timeout = 5,
        })
    end
end

-- 导出配置
function BookSourcePlugin:exportConfig()
    local config = self.config_mgr:load()
    local export_text = json.encode(config)
    
    local export_path = self.path .. "/legado_config_export.json"
    local file = io.open(export_path, "w")
    if file then
        file:write(export_text)
        file:close()
        
        UIManager:show(InfoMessage:new{
            text = "✅ 配置已导出到:\n" .. export_path,
            timeout = 4,
        })
    else
        UIManager:show(InfoMessage:new{
            text = "❌ 导出失败",
            timeout = 3,
        })
    end
end

-- 导入配置
function BookSourcePlugin:importConfig()
    local import_path = self.path .. "/legado_config_export.json"
    local file = io.open(import_path, "r")
    
    if not file then
        UIManager:show(InfoMessage:new{
            text = "❌ 未找到配置文件:\n" .. import_path,
            timeout = 4,
        })
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, imported_config = pcall(json.decode, content)
    if success and imported_config then
        -- 应用导入的配置
        if self.config_mgr:save(imported_config) then
            CONFIG.api.host = imported_config.api.host or CONFIG.api.host
            CONFIG.api.port = imported_config.api.port or CONFIG.api.port
            CONFIG.api.timeout = imported_config.api.timeout or CONFIG.api.timeout
            
            self.api.base_url = CONFIG.api:base_url()
            
            UIManager:show(InfoMessage:new{
                text = "✅ 配置导入成功\n服务地址: " .. CONFIG.api.host .. ":" .. CONFIG.api.port,
                timeout = 4,
            })
        else
            UIManager:show(InfoMessage:new{
                text = "❌ 配置保存失败",
                timeout = 3,
            })
        end
    else
        UIManager:show(InfoMessage:new{
            text = "❌ 配置文件格式错误",
            timeout = 3,
        })
    end
end

return BookSourcePlugin