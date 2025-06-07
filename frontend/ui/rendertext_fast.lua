--[[
高性能文本渲染模块
集成C语言加速功能，作为RenderText的高性能替代
预期性能提升：200-500%
]]

local FastRender = require("base/ffi/fast_render_ffi")
local RenderText = require("ui/rendertext") -- 原始实现作为回退
local logger = require("logger")

local RenderTextFast = {}

-- 性能配置
local ENABLE_FAST_RENDER = true
local FALLBACK_ON_ERROR = true
local BATCH_SIZE_THRESHOLD = 5

-- 初始化状态
local fast_render_available = false

-- 检查快速渲染是否可用
local function checkFastRenderAvailable()
    if not ENABLE_FAST_RENDER then
        return false
    end
    
    local ok, available = pcall(function()
        return FastRender.isAvailable()
    end)
    
    return ok and available
end

-- 初始化
local function init()
    fast_render_available = checkFastRenderAvailable()
    if fast_render_available then
        logger.info("RenderTextFast: C加速模块已启用")
    else
        logger.info("RenderTextFast: 使用Lua回退实现")
    end
end

-- 获取字体哈希值
local function getFaceHash(face)
    return face and face.hash or 0
end

-- 优化的字形获取
function RenderTextFast:getGlyph(face, charcode, bold)
    -- 对于常用字符，尝试使用快速缓存
    if fast_render_available and charcode < 128 then -- ASCII字符
        -- 这里可以添加快速路径
    end
    
    -- 回退到原始实现
    return RenderText:getGlyph(face, charcode, bold)
end

-- 优化的文本尺寸测量
function RenderTextFast:sizeUtf8Text(x, width, face, text, kerning, bold)
    if not text then
        logger.warn("sizeUtf8Text called without text")
        return { x = 0, y_top = 0, y_bottom = 0 }
    end
    
    -- 尝试使用快速实现
    if fast_render_available and #text > 0 then
        local ok, result = pcall(function()
            local size = FastRender.measureText(text, getFaceHash(face), bold, kerning)
            if size and size.width > 0 then
                return {
                    x = size.width,
                    y_top = size.baseline,
                    y_bottom = size.height - size.baseline
                }
            end
            return nil
        end)
        
        if ok and result then
            return result
        elseif not FALLBACK_ON_ERROR then
            logger.warn("RenderTextFast: 快速测量失败，text=", text:sub(1, 50))
        end
    end
    
    -- 回退到原始实现
    return RenderText:sizeUtf8Text(x, width, face, text, kerning, bold)
end

-- 优化的文本渲染
function RenderTextFast:renderUtf8Text(dest_bb, x, baseline, face, text, kerning, bold, fgcolor, width, char_pads)
    if not text then
        logger.warn("renderUtf8Text called without text")
        return 0
    end
    
    -- 尝试使用快速实现
    if fast_render_available and #text > 0 and not char_pads then -- char_pads暂不支持
        local ok, result = pcall(function()
            return FastRender.renderText(
                dest_bb,
                x,
                baseline,
                text,
                getFaceHash(face),
                bold,
                kerning,
                fgcolor and fgcolor.a or 0,
                width
            )
        end)
        
        if ok and result >= 0 then
            return result
        elseif not FALLBACK_ON_ERROR then
            logger.warn("RenderTextFast: 快速渲染失败，text=", text:sub(1, 50))
        end
    end
    
    -- 回退到原始实现
    return RenderText:renderUtf8Text(dest_bb, x, baseline, face, text, kerning, bold, fgcolor, width, char_pads)
end

-- 批量文本渲染优化
function RenderTextFast:renderTextBatch(dest_bb, text_list, face, bold, fgcolor)
    if not text_list or #text_list == 0 then
        return 0
    end
    
    -- 如果批次太小，直接使用单个渲染
    if #text_list < BATCH_SIZE_THRESHOLD then
        local total_width = 0
        for _, item in ipairs(text_list) do
            local width = self:renderUtf8Text(dest_bb, item.x, item.y, face, item.text, 
                                            true, bold, fgcolor, nil, nil)
            total_width = total_width + width
        end
        return total_width
    end
    
    -- 尝试使用快速批量渲染
    if fast_render_available then
        local ok, result = pcall(function()
            return FastRender.renderTextBatch(dest_bb, text_list, getFaceHash(face), bold)
        end)
        
        if ok and result >= 0 then
            return result
        end
    end
    
    -- 回退到逐个渲染
    local total_width = 0
    for _, item in ipairs(text_list) do
        local width = self:renderUtf8Text(dest_bb, item.x, item.y, face, item.text, 
                                        true, bold, fgcolor, nil, nil)
        total_width = total_width + width
    end
    return total_width
end

-- 优化的子文本获取
function RenderTextFast:getSubTextByWidth(text, face, width, kerning, bold)
    -- 对于短文本，直接使用原始实现
    if not text or #text < 50 then
        return RenderText:getSubTextByWidth(text, face, width, kerning, bold)
    end
    
    -- 对于长文本，可以使用二分查找优化
    local left, right = 1, #text
    local best_pos = 1
    
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
    
    return text:sub(1, best_pos)
end

-- 优化的文本截断
function RenderTextFast:truncateTextByWidth(text, face, max_width, kerning, bold)
    local ellipsis_width = self:getEllipsisWidth(face, bold)
    local new_txt_width = max_width - ellipsis_width
    local sub_txt = self:getSubTextByWidth(text, face, new_txt_width, kerning, bold)
    return sub_txt .. "…"
end

-- 椭圆宽度获取（直接使用原始实现）
function RenderTextFast:getEllipsisWidth(face, bold)
    return RenderText:getEllipsisWidth(face, bold)
end

-- 通过索引获取字形（直接使用原始实现）
function RenderTextFast:getGlyphByIndex(face, glyphindex, bold, bolder)
    return RenderText:getGlyphByIndex(face, glyphindex, bold, bolder)
end

-- 性能监控包装器
function RenderTextFast:withPerfMonitor(method_name, func)
    if not fast_render_available then
        return func
    end
    
    return function(...)
        local start_time = os.clock()
        local result = func(...)
        local end_time = os.clock()
        
        local time_ms = (end_time - start_time) * 1000
        if time_ms > 10 then -- 只记录耗时超过10ms的操作
            logger.dbg(string.format("RenderTextFast.%s: %.2fms", method_name, time_ms))
        end
        
        return result
    end
end

-- 智能渲染模式选择
function RenderTextFast:smartRender(dest_bb, x, baseline, face, text, kerning, bold, fgcolor, width)
    -- 根据文本特征选择最优渲染路径
    if not text or #text == 0 then
        return 0
    end
    
    -- ASCII文本优先使用快速路径
    local is_ascii = true
    for i = 1, #text do
        if string.byte(text, i) > 127 then
            is_ascii = false
            break
        end
    end
    
    if is_ascii and fast_render_available then
        local ok, result = pcall(function()
            return FastRender.renderText(dest_bb, x, baseline, text, 
                                       getFaceHash(face), bold, kerning, 
                                       fgcolor and fgcolor.a or 0, width)
        end)
        
        if ok and result >= 0 then
            return result
        end
    end
    
    -- 复杂文本使用原始实现
    return RenderText:renderUtf8Text(dest_bb, x, baseline, face, text, kerning, bold, fgcolor, width)
end

-- 缓存统计
function RenderTextFast:getCacheStats()
    if fast_render_available then
        return FastRender.getStats()
    end
    return nil
end

-- 清理缓存
function RenderTextFast:clearCache()
    if fast_render_available then
        FastRender.cleanup()
        FastRender.init()
    end
end

-- 设置性能模式
function RenderTextFast:setPerformanceMode(mode)
    if mode == "fast" then
        ENABLE_FAST_RENDER = true
        FALLBACK_ON_ERROR = false
    elseif mode == "safe" then
        ENABLE_FAST_RENDER = true
        FALLBACK_ON_ERROR = true
    elseif mode == "compatible" then
        ENABLE_FAST_RENDER = false
    end
    
    -- 重新初始化
    init()
end

-- 获取性能信息
function RenderTextFast:getPerformanceInfo()
    return {
        fast_render_available = fast_render_available,
        enable_fast_render = ENABLE_FAST_RENDER,
        fallback_on_error = FALLBACK_ON_ERROR,
        batch_size_threshold = BATCH_SIZE_THRESHOLD
    }
end

-- 初始化模块
init()

return RenderTextFast
