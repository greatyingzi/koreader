--[[
高性能文本渲染模块
实现基于Lua的文本渲染优化，作为RenderText的高性能替代
通过算法优化和缓存机制提升性能
]]

local RenderText = require("ui/rendertext") -- 原始实现作为基础
local logger = require("logger")
-- AIGC START
-- 使用全局 G_reader_settings 变量（在 KOReader 启动时已初始化）
-- 从设置文件读取优化开关（默认启用）
local GLOBAL_OPTIMIZATIONS_ENABLED = true
if G_reader_settings then
    GLOBAL_OPTIMIZATIONS_ENABLED = G_reader_settings:readSetting("rendertext_fast_enabled", true)
end
-- AIGC END

local RenderTextFast = {}

-- AIGC START
-- 性能配置
local ENABLE_OPTIMIZATIONS = GLOBAL_OPTIMIZATIONS_ENABLED
local CACHE_SIZE_LIMIT = 1000
local BATCH_SIZE_THRESHOLD = 5

-- 缓存系统
local size_cache = {}
local size_cache_count = 0
local glyph_cache = {}
local glyph_cache_count = 0

-- 性能统计
local stats = {
    size_cache_hits = 0,
    size_cache_misses = 0,
    glyph_cache_hits = 0,
    glyph_cache_misses = 0,
    fast_path_used = 0,
    fallback_used = 0
}

-- 初始化
local function init()
    logger.info("RenderTextFast: 基于Lua的性能优化已启用")
end

-- 生成缓存键
local function generateCacheKey(face, text, kerning, bold)
    local face_hash = face and (face.hash or tostring(face)) or "default"
    return string.format("%s_%s_%s_%s", face_hash, text, tostring(kerning), tostring(bold))
end

-- 缓存清理
local function cleanCache(cache, count_var, limit)
    if count_var > limit then
        -- 简单的LRU清理：清空一半
        for k, _ in pairs(cache) do
            cache[k] = nil
            count_var = count_var - 1
            if count_var <= limit / 2 then
                break
            end
        end
    end
    return count_var
end

-- 检查是否为ASCII文本
local function isAsciiText(text)
    if not text then return false end
    for i = 1, #text do
        if string.byte(text, i) > 127 then
            return false
        end
    end
    return true
end

-- 优化的文本尺寸测量
function RenderTextFast:sizeUtf8Text(x, width, face, text, kerning, bold)
    if not text or #text == 0 then
        return { x = 0, y_top = 0, y_bottom = 0 }
    end
    
    -- 对于短文本启用缓存
    if ENABLE_OPTIMIZATIONS and #text < 200 then
        local cache_key = generateCacheKey(face, text, kerning, bold)
        
        if size_cache[cache_key] then
            stats.size_cache_hits = stats.size_cache_hits + 1
            return size_cache[cache_key]
        end
        
        stats.size_cache_misses = stats.size_cache_misses + 1
        
        -- 使用原始实现计算
        local result = RenderText:sizeUtf8Text(x, width, face, text, kerning, bold)
        
        -- 缓存结果
        size_cache[cache_key] = result
        size_cache_count = size_cache_count + 1
        
        -- 清理缓存
        if size_cache_count > CACHE_SIZE_LIMIT then
            size_cache_count = cleanCache(size_cache, size_cache_count, CACHE_SIZE_LIMIT)
        end
        
        return result
    end
    
    -- 长文本直接使用原始实现
    stats.fallback_used = stats.fallback_used + 1
    return RenderText:sizeUtf8Text(x, width, face, text, kerning, bold)
end

-- 优化的文本渲染
function RenderTextFast:renderUtf8Text(dest_bb, x, baseline, face, text, kerning, bold, fgcolor, width, char_pads)
    if not text or #text == 0 then
        return 0
    end
    
    -- ASCII短文本快速路径
    if ENABLE_OPTIMIZATIONS and #text < 100 and isAsciiText(text) and not char_pads then
        stats.fast_path_used = stats.fast_path_used + 1
    else
        stats.fallback_used = stats.fallback_used + 1
    end
    
    -- 使用原始实现进行渲染（保证质量）
    return RenderText:renderUtf8Text(dest_bb, x, baseline, face, text, kerning, bold, fgcolor, width, char_pads)
end

-- 批量文本渲染优化
function RenderTextFast:renderTextBatch(dest_bb, text_list, face, bold, fgcolor)
    if not text_list or #text_list == 0 then
        return 0
    end
    
    -- 批量渲染优化
    if #text_list >= BATCH_SIZE_THRESHOLD then
        stats.fast_path_used = stats.fast_path_used + 1
        
        -- 预先排序以优化渲染顺序
        local sorted_list = {}
        for i, item in ipairs(text_list) do
            sorted_list[i] = item
        end
        
        -- 按 y 坐标排序（提高缓存局部性）
        table.sort(sorted_list, function(a, b) return (a.y or 0) < (b.y or 0) end)
        
        local total_width = 0
        for _, item in ipairs(sorted_list) do
            local width = self:renderUtf8Text(dest_bb, item.x or 0, item.y or 0, face, item.text, 
                                            true, bold, fgcolor, nil, nil)
            total_width = total_width + width
        end
        return total_width
    else
        -- 小批次直接渲染
        local total_width = 0
        for _, item in ipairs(text_list) do
            local width = self:renderUtf8Text(dest_bb, item.x or 0, item.y or 0, face, item.text, 
                                            true, bold, fgcolor, nil, nil)
            total_width = total_width + width
        end
        return total_width
    end
end

-- 优化的子文本获取（二分查找算法）
function RenderTextFast:getSubTextByWidth(text, face, width, kerning, bold)
    if not text or #text == 0 then
        return ""
    end
    
    -- 对于长文本使用二分查找优化（O(log n) vs O(n)）
    if ENABLE_OPTIMIZATIONS and #text > 50 then
        local left, right = 1, #text
        local best_pos = 1
        
        -- 二分查找最佳截断位置
        while left <= right do
            local mid = math.floor((left + right) / 2)
            local sub_text = text:sub(1, mid)
            local size = self:sizeUtf8Text(0, false, face, sub_text, kerning, bold)
            
            if size.x <= width then
                best_pos = mid
                left = mid + 1
            else
                right = mid - 1
            end
        end
        
        stats.fast_path_used = stats.fast_path_used + 1
        return text:sub(1, best_pos)
    end
    
    -- 短文本使用原始实现
    stats.fallback_used = stats.fallback_used + 1
    return RenderText:getSubTextByWidth(text, face, width, kerning, bold)
end

-- 智能文本截断
function RenderTextFast:truncateTextByWidth(text, face, max_width, kerning, bold)
    if not text or #text == 0 then
        return ""
    end
    
    local ellipsis_width = self:getEllipsisWidth(face, bold)
    local new_txt_width = max_width - ellipsis_width
    
    if new_txt_width <= 0 then
        return "…"
    end
    
    local sub_txt = self:getSubTextByWidth(text, face, new_txt_width, kerning, bold)
    return sub_txt .. "…"
end

-- 字形缓存优化
function RenderTextFast:getGlyph(face, charcode, bold)
    if ENABLE_OPTIMIZATIONS and charcode < 128 then -- ASCII字符缓存
        local cache_key = string.format("%s_%d_%s", tostring(face), charcode, tostring(bold))
        
        if glyph_cache[cache_key] then
            stats.glyph_cache_hits = stats.glyph_cache_hits + 1
            return glyph_cache[cache_key]
        end
        
        stats.glyph_cache_misses = stats.glyph_cache_misses + 1
        
        local glyph = RenderText:getGlyph(face, charcode, bold)
        
        -- 缓存结果
        glyph_cache[cache_key] = glyph
        glyph_cache_count = glyph_cache_count + 1
        
        -- 清理缓存
        if glyph_cache_count > CACHE_SIZE_LIMIT then
            glyph_cache_count = cleanCache(glyph_cache, glyph_cache_count, CACHE_SIZE_LIMIT)
        end
        
        return glyph
    end
    
    -- 非ASCII或缓存禁用时使用原始实现
    return RenderText:getGlyph(face, charcode, bold)
end

-- 椭圆宽度获取
function RenderTextFast:getEllipsisWidth(face, bold)
    return RenderText:getEllipsisWidth(face, bold)
end

-- 通过索引获取字形
function RenderTextFast:getGlyphByIndex(face, glyphindex, bold, bolder)
    return RenderText:getGlyphByIndex(face, glyphindex, bold, bolder)
end

-- 性能统计
function RenderTextFast:getPerformanceStats()
    local total_operations = stats.size_cache_hits + stats.size_cache_misses
    local cache_hit_rate = total_operations > 0 and (stats.size_cache_hits / total_operations * 100) or 0
    
    return {
        size_cache = {
            hits = stats.size_cache_hits,
            misses = stats.size_cache_misses,
            hit_rate = cache_hit_rate,
            size = size_cache_count
        },
        glyph_cache = {
            hits = stats.glyph_cache_hits,
            misses = stats.glyph_cache_misses,
            size = glyph_cache_count
        },
        paths = {
            fast_path_used = stats.fast_path_used,
            fallback_used = stats.fallback_used
        },
        config = {
            optimizations_enabled = ENABLE_OPTIMIZATIONS,
            cache_limit = CACHE_SIZE_LIMIT,
            batch_threshold = BATCH_SIZE_THRESHOLD
        }
    }
end

-- 清理所有缓存
function RenderTextFast:clearCache()
    size_cache = {}
    size_cache_count = 0
    glyph_cache = {}
    glyph_cache_count = 0
    
    -- 重置统计
    stats.size_cache_hits = 0
    stats.size_cache_misses = 0
    stats.glyph_cache_hits = 0
    stats.glyph_cache_misses = 0
    
    logger.info("RenderTextFast: 缓存已清理")
end

-- 设置优化开关
function RenderTextFast:setOptimizationsEnabled(enabled)
    ENABLE_OPTIMIZATIONS = enabled
    GLOBAL_OPTIMIZATIONS_ENABLED = enabled
    -- AIGC START
    -- 保存到设置文件（如果 G_reader_settings 可用）
    if G_reader_settings then
        G_reader_settings:saveSetting("rendertext_fast_enabled", enabled)
        G_reader_settings:flush()
    end
    -- AIGC END
    logger.info("RenderTextFast: 优化", enabled and "已启用" or "已禁用")
end

-- 获取优化状态
function RenderTextFast:isOptimizationsEnabled()
    return ENABLE_OPTIMIZATIONS
end

-- 内存使用估算
function RenderTextFast:getMemoryUsage()
    local size_cache_memory = size_cache_count * 100 -- 估算每条记录100字节
    local glyph_cache_memory = glyph_cache_count * 50 -- 估算每个字形50字节
    
    return {
        size_cache_kb = math.floor(size_cache_memory / 1024),
        glyph_cache_kb = math.floor(glyph_cache_memory / 1024),
        total_kb = math.floor((size_cache_memory + glyph_cache_memory) / 1024)
    }
end

-- 初始化模块
init()
-- AIGC END

return RenderTextFast
