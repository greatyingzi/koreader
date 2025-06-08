--[[
-- AIGC START
KOReader 大型TXT文件优化器
加载时机：2 (在文档加载前运行)
功能：基于现有目录功能的TXT文件章节解析优化、大文件加载优化
适用场景：大型网络小说、长篇TXT文档阅读
-- AIGC END
]]--

local logger = require("logger")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local ConfirmBox = require("ui/widget/confirmbox")
local T = require("ffi/util").template

logger.info("TxtOptimizer: 启动大型TXT文件优化器...")

-- AIGC START
-- KOReader大型TXT文件优化器 v2.2
-- 基于现有目录功能的增强版本，支持编码检测和设置
-- 通过Hook方式集成，不重新实现章节导航功能
-- AIGC END

-- 尝试加载独立的章节匹配模块
local chapter_patterns
local module_load_success, module_error = pcall(function()
    chapter_patterns = require("patches/txt_chapter_patterns")
end)

if not module_load_success then
    logger.warn("TxtOptimizer: 无法加载独立章节匹配模块:", module_error)
    logger.info("TxtOptimizer: 使用内置备用章节匹配功能")
    
    -- 内置备用章节匹配功能（简化版）
    chapter_patterns = {
        -- 简化的编码检测
        detectEncoding = function(data, filename)
            if not data or #data == 0 then
                return "utf-8", "默认UTF-8"
            end
            
            -- 检测UTF-8 BOM
            if #data >= 3 and data:byte(1) == 0xEF and data:byte(2) == 0xBB and data:byte(3) == 0xBF then
                return "utf-8", "UTF-8 BOM检测"
            end
            
            -- 简单的中文字符密度检测
            local chinese_like_bytes = 0
            local total_bytes = math.min(#data, 8192)
            local i = 1
            
            while i <= total_bytes - 1 do
                local byte1 = data:byte(i)
                local byte2 = data:byte(i + 1)
                
                if byte1 and byte2 then
                    -- GBK/GB2312中文字符范围检测
                    if (byte1 >= 0xA1 and byte1 <= 0xFE and byte2 >= 0xA1 and byte2 <= 0xFE) or
                       (byte1 >= 0x81 and byte1 <= 0xFE and byte2 >= 0x40 and byte2 <= 0xFE and byte2 ~= 0x7F) then
                        chinese_like_bytes = chinese_like_bytes + 2
                        i = i + 2
                    else
                        i = i + 1
                    end
                else
                    i = i + 1
                end
            end
            
            local chinese_density = chinese_like_bytes / total_bytes
            
            if chinese_density > 0.3 then
                return "gbk", string.format("中文编码检测 (密度: %.1f%%)", chinese_density * 100)
            elseif chinese_density > 0.1 then
                return "gbk", string.format("可能的中文编码 (密度: %.1f%%)", chinese_density * 100)
            end
            
            -- 默认UTF-8
            return "utf-8", "默认UTF-8编码"
        end,
        
        -- 简化的章节匹配
        matchChapter = function(line)
            if not line or #line == 0 then return nil end
            
            -- 基本的章节模式
            local patterns = {
                "第[一二三四五六七八九十百千万零0-9]+章",
                "第[0-9]+章",
                "Chapter [0-9]+",
                "CHAPTER [0-9]+",
                "第[0-9]+节"
            }
            
            for _, pattern in ipairs(patterns) do
                if line:match(pattern) then
                    return {
                        name = pattern,
                        confidence = 0.9
                    }
                end
            end
            
            return nil
        end
    }
end

-- 配置参数
local TXT_CONFIG = {
    enable_chapter_detection = true,  -- 章节优化一直启用
    min_file_size = 256 * 1024,      -- 256KB阈值
    max_preview_size = 512 * 1024,   -- 预览大小512KB
    cache_enabled = true,
    cache_max_files = 50,
    debug_mode = false,
}

-- 全局缓存
local file_cache = {}
local cache_stats = {
    hits = 0,
    misses = 0,
    total_files = 0
}

-- 日志工具
local function debug_log(...)
    if TXT_CONFIG.debug_mode then
        logger.info("TxtOptimizer:", ...)
    end
end

-- 编码检测和处理
local function detectAndHandleEncoding(filepath)
    local file = io.open(filepath, "rb")
    if not file then
        return "utf-8", "文件无法打开"
    end
    
    -- 读取文件头部用于编码检测
    local sample_size = 8192
    local sample_data = file:read(sample_size)
    file:close()
    
    if not sample_data then
        return "utf-8", "文件为空"
    end
    
    local detected_encoding, reason = chapter_patterns.detectEncoding(sample_data, filepath)
    debug_log("编码检测结果:", detected_encoding, "原因:", reason)
    
    return detected_encoding, reason
end

-- 设置文档编码的函数
local function setDocumentEncoding(ui, encoding)
    if not ui or not ui.document then
        return false
    end
    
    -- 对于CRE文档（TXT文件通常使用CRE引擎）
    if ui.document.setCharset then
        debug_log("设置文档编码为:", encoding)
        ui.document:setCharset(encoding)
        return true
    elseif ui.document._document and ui.document._document.setCharset then
        debug_log("通过底层文档设置编码为:", encoding)
        ui.document._document:setCharset(encoding)
        return true
    end
    
    return false
end

-- 章节检测函数
local function detectChapters(content)
    if not content or #content == 0 then
        return {}
    end
    
    local chapters = {}
    local lines = {}
    
    -- 分割行
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    debug_log("分析", #lines, "行内容进行章节检测")
    
    for i, line in ipairs(lines) do
        local match = chapter_patterns.matchChapter(line)
        if match and match.confidence > 0.8 then
            table.insert(chapters, {
                title = line:sub(1, 100), -- 限制标题长度
                line_number = i,
                confidence = match.confidence,
                pattern = match.name
            })
            debug_log("检测到章节:", line:sub(1, 50), "置信度:", match.confidence)
        end
    end
    
    return chapters
end

-- 构建文件索引
local function buildIndex(filepath)
    local start_time = os.clock()
    
    -- 首先进行编码检测
    local detected_encoding, encoding_reason = detectAndHandleEncoding(filepath)
    
    local file = io.open(filepath, "rb")
    if not file then
        return nil
    end
    
    -- 读取文件头部进行分析
    local preview_content = file:read(TXT_CONFIG.max_preview_size)
    file:close()
    
    if not preview_content then
        return nil
    end
    
    local chapters = {}
    if TXT_CONFIG.enable_chapter_detection then
        chapters = detectChapters(preview_content)
    end
    
    local file_attr = lfs.attributes(filepath)
    local index = {
        filepath = filepath,
        filename = filepath:match("([^/\\]+)$") or filepath,
        file_size = file_attr.size,
        chapters = chapters,
        chapter_count = #chapters,
        created_time = os.time(),
        build_time = os.clock() - start_time,
        analyzer_version = "2.2", -- 版本标识（增加编码设置支持）
        encoding = detected_encoding,
        encoding_reason = encoding_reason,
    }
    
    logger.info("TxtOptimizer: 索引构建完成，检测到", #chapters, "个章节，耗时", 
                string.format("%.2f", index.build_time), "秒，编码:", detected_encoding)
    
    return index
end

-- 缓存管理
local function getCacheKey(filepath)
    local attr = lfs.attributes(filepath)
    if not attr then return nil end
    return filepath .. "_" .. attr.size .. "_" .. attr.modification
end

local function getOrCreateIndex(filepath)
    local cache_key = getCacheKey(filepath)
    if not cache_key then return nil end
    
    if TXT_CONFIG.cache_enabled and file_cache[cache_key] then
        cache_stats.hits = cache_stats.hits + 1
        debug_log("缓存命中:", filepath)
        return file_cache[cache_key]
    end
    
    cache_stats.misses = cache_stats.misses + 1
    local index = buildIndex(filepath)
    
    if index and TXT_CONFIG.cache_enabled then
        -- 缓存管理：限制缓存文件数量
        if #file_cache >= TXT_CONFIG.cache_max_files then
            -- 简单的LRU：清除一半缓存
            local keys = {}
            for k in pairs(file_cache) do
                table.insert(keys, k)
            end
            for i = 1, math.floor(#keys / 2) do
                file_cache[keys[i]] = nil
            end
        end
        
        file_cache[cache_key] = index
        debug_log("缓存存储:", filepath)
    end
    
    return index
end

-- 检查是否为大型TXT文件
local function shouldOptimize(filepath)
    if not filepath or not filepath:lower():match("%.txt$") then
        return false
    end
    
    local attr = lfs.attributes(filepath)
    if not attr or attr.mode ~= "file" then
        return false
    end
    
    return attr.size >= TXT_CONFIG.min_file_size
end

-- 显示优化信息
local function showOptimizationInfo(index)
    if not index then return end
    
    local message = T(_("TXT文件优化完成\n\n文件: %1\n大小: %2\n章节: %3个\n编码: %4\n分析耗时: %5秒"), 
                     index.filename,
                     string.format("%.2f MB", index.file_size / 1024 / 1024),
                     index.chapter_count,
                     index.encoding,
                     string.format("%.3f", index.build_time))
    
    UIManager:show(InfoMessage:new{
        text = message,
        timeout = 3,
    })
end

-- Hook ReaderUI的文档打开过程
local ReaderUI = require("apps/reader/readerui")
local original_onSetupDocument = ReaderUI.onSetupDocument

function ReaderUI:onSetupDocument()
    -- 调用原始方法
    local result = original_onSetupDocument(self)
    
    -- 检查是否为TXT文件且需要优化
    if self.document and self.document.file and shouldOptimize(self.document.file) then
        debug_log("检测到大型TXT文件:", self.document.file)
        
        -- 获取或创建索引
        local index = getOrCreateIndex(self.document.file)
        
        if index then
            -- 设置文档编码
            if index.encoding and index.encoding ~= "utf-8" then
                local encoding_set = setDocumentEncoding(self, index.encoding)
                if encoding_set then
                    logger.info("TxtOptimizer: 已设置文档编码为", index.encoding)
                    
                    -- 重新加载文档以应用编码设置
                    if self.document.loadDocument then
                        debug_log("重新加载文档以应用编码设置")
                        self.document:loadDocument()
                    end
                else
                    logger.warn("TxtOptimizer: 无法设置文档编码")
                end
            end
            
            -- 显示优化信息
            if TXT_CONFIG.debug_mode then
                showOptimizationInfo(index)
            end
            
            -- 更新统计
            cache_stats.total_files = cache_stats.total_files + 1
        end
    end
    
    return result
end

-- Hook ReaderToc的fillToc方法来增强目录功能
local ReaderToc = require("apps/reader/modules/readertoc")
local original_fillToc = ReaderToc.fillToc

function ReaderToc:fillToc()
    -- 调用原始方法
    original_fillToc(self)
    
    -- 检查是否为TXT文件且需要优化
    if self.ui.document and self.ui.document.file and shouldOptimize(self.ui.document.file) then
        local index = getOrCreateIndex(self.ui.document.file)
        
        if index and index.chapters and #index.chapters > 0 then
            debug_log("增强目录功能，添加", #index.chapters, "个检测到的章节")
            
            -- 如果原始目录为空或很少，添加我们检测到的章节
            if not self.toc or #self.toc < #index.chapters / 2 then
                self.toc = self.toc or {}
                
                for _, chapter in ipairs(index.chapters) do
                    table.insert(self.toc, {
                        title = chapter.title,
                        page = chapter.line_number, -- 使用行号作为页码
                        depth = 1,
                        chapter_confidence = chapter.confidence,
                        source = "txt_optimizer"
                    })
                end
                
                logger.info("TxtOptimizer: 已增强目录，添加", #index.chapters, "个章节")
            end
        end
    end
end

-- 性能统计和调试接口
local TxtOptimizer = {}

function TxtOptimizer:getStats()
    return {
        cache_stats = cache_stats,
        cache_size = #file_cache,
        config = TXT_CONFIG
    }
end

function TxtOptimizer:clearCache()
    file_cache = {}
    cache_stats = {hits = 0, misses = 0, total_files = 0}
    logger.info("TxtOptimizer: 缓存已清除")
end

function TxtOptimizer:setDebugMode(enabled)
    TXT_CONFIG.debug_mode = enabled
    logger.info("TxtOptimizer: 调试模式", enabled and "已启用" or "已禁用")
end

-- 导出模块
return TxtOptimizer

-- AIGC END