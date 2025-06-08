--[[
-- AIGC START
TXT文件章节匹配规则模块（性能优化版 + 编码处理）
用于KOReader大型TXT文件优化器的章节识别
独立模块，可被测试脚本和补丁代码调用
支持UTF-8、GBK、GB2312等常见中文编码格式
-- AIGC END
]]--

-- AIGC START
-- 编码检测和处理模块
local EncodingDetector = {}

-- 常见的中文编码BOM标记
local BOM_SIGNATURES = {
    {bytes = {0xEF, 0xBB, 0xBF}, encoding = "utf-8", name = "UTF-8 BOM"},
    {bytes = {0xFF, 0xFE}, encoding = "utf-16le", name = "UTF-16 LE BOM"},
    {bytes = {0xFE, 0xFF}, encoding = "utf-16be", name = "UTF-16 BE BOM"},
    {bytes = {0xFF, 0xFE, 0x00, 0x00}, encoding = "utf-32le", name = "UTF-32 LE BOM"},
    {bytes = {0x00, 0x00, 0xFE, 0xFF}, encoding = "utf-32be", name = "UTF-32 BE BOM"},
}

-- 检测BOM标记
function EncodingDetector.detectBOM(data)
    if not data or #data < 2 then
        return nil
    end
    
    for _, bom in ipairs(BOM_SIGNATURES) do
        local match = true
        if #data >= #bom.bytes then
            for i, byte_val in ipairs(bom.bytes) do
                if data:byte(i) ~= byte_val then
                    match = false
                    break
                end
            end
            if match then
                return {
                    encoding = bom.encoding,
                    name = bom.name,
                    bom_length = #bom.bytes
                }
            end
        end
    end
    
    return nil
end

-- 检测是否为有效的UTF-8
function EncodingDetector.isValidUTF8(data)
    if not data then return false end
    
    local i = 1
    local len = #data
    local valid_utf8_chars = 0
    local total_chars = 0
    
    while i <= len do
        local byte = data:byte(i)
        local char_len = 1
        
        if byte <= 0x7F then
            -- ASCII字符 (0xxxxxxx)
            char_len = 1
        elseif byte >= 0xC2 and byte <= 0xDF then
            -- 2字节UTF-8 (110xxxxx 10xxxxxx)
            char_len = 2
        elseif byte >= 0xE0 and byte <= 0xEF then
            -- 3字节UTF-8 (1110xxxx 10xxxxxx 10xxxxxx)
            char_len = 3
        elseif byte >= 0xF0 and byte <= 0xF4 then
            -- 4字节UTF-8 (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
            char_len = 4
        else
            -- 无效的UTF-8起始字节
            return false
        end
        
        -- 检查后续字节
        if i + char_len - 1 > len then
            return false
        end
        
        for j = 2, char_len do
            local next_byte = data:byte(i + j - 1)
            if not next_byte or next_byte < 0x80 or next_byte > 0xBF then
                return false
            end
        end
        
        if char_len > 1 then
            valid_utf8_chars = valid_utf8_chars + 1
        end
        total_chars = total_chars + 1
        i = i + char_len
    end
    
    -- 如果有多字节字符且比例合理，认为是UTF-8
    return total_chars > 0 and (valid_utf8_chars > 0 or total_chars < 100)
end

-- 检测中文字符密度（用于判断GBK/GB2312）
function EncodingDetector.detectChineseDensity(data)
    if not data or #data < 10 then
        return 0
    end
    
    local chinese_like_bytes = 0
    local total_bytes = #data
    local i = 1
    
    while i <= total_bytes - 1 do
        local byte1 = data:byte(i)
        local byte2 = data:byte(i + 1)
        
        -- GBK/GB2312中文字符范围检测
        if byte1 and byte2 then
            -- GB2312: A1A1-FEFE
            -- GBK: 8140-FEFE (扩展了GB2312)
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
    
    return chinese_like_bytes / total_bytes
end

-- 智能编码检测
function EncodingDetector.detectEncoding(data, filename)
    if not data or #data == 0 then
        return "utf-8", "默认UTF-8"
    end
    
    -- 1. 检测BOM
    local bom_result = EncodingDetector.detectBOM(data)
    if bom_result then
        return bom_result.encoding, "BOM检测: " .. bom_result.name
    end
    
    -- 2. 检测中文编码（在UTF-8检测之前，因为UTF-8检测可能误判）
    local chinese_density = EncodingDetector.detectChineseDensity(data)
    
    if chinese_density > 0.3 then
        -- 高中文字符密度，可能是GBK或GB2312
        return "gbk", string.format("中文编码检测 (密度: %.1f%%)", chinese_density * 100)
    elseif chinese_density > 0.1 then
        -- 中等密度，尝试GBK
        return "gbk", string.format("可能的中文编码 (密度: %.1f%%)", chinese_density * 100)
    end
    
    -- 3. 检测UTF-8
    if EncodingDetector.isValidUTF8(data) then
        return "utf-8", "UTF-8检测"
    end
    
    -- 4. 根据文件名推测
    if filename then
        local lower_name = filename:lower()
        if lower_name:match("%.txt$") then
            -- 对于TXT文件，在中国地区默认尝试GBK
            return "gbk", "TXT文件默认GBK"
        end
    end
    
    -- 5. 默认UTF-8
    return "utf-8", "默认UTF-8编码"
end

-- 编码转换函数（简化版，主要处理常见情况）
function EncodingDetector.convertToUTF8(data, from_encoding)
    if not data or from_encoding == "utf-8" then
        return data
    end
    
    -- 这里应该调用KOReader的编码转换功能
    -- 由于我们在Lua层面，暂时返回原数据
    -- 实际使用时，KOReader的底层会处理编码转换
    return data
end

-- 性能优化的章节匹配规则配置

-- 高优先级模式（最常用，优先匹配）
local HIGH_PRIORITY_PATTERNS = {
    -- 最常见的中文章节格式
    {
        pattern = "第[0-9]+章",
        name = "阿拉伯数字章节",
        priority = 10,
        confidence_base = 0.95
    },
    {
        pattern = "第[一二三四五六七八九十百千万零]+章",
        name = "中文数字章节",
        priority = 10,
        confidence_base = 0.95
    },
    {
        pattern = "Chapter [0-9]+",
        name = "英文章节",
        priority = 9,
        confidence_base = 0.90
    },
    {
        pattern = "第[0-9]+节",
        name = "阿拉伯数字节",
        priority = 9,
        confidence_base = 0.90
    },
    {
        pattern = "第[一二三四五六七八九十百千万零]+节",
        name = "中文数字节",
        priority = 9,
        confidence_base = 0.90
    },
}

-- 中优先级模式（较常用）
local MEDIUM_PRIORITY_PATTERNS = {
    {
        pattern = "第[0-9]+回",
        name = "阿拉伯数字回",
        priority = 8,
        confidence_base = 0.85
    },
    {
        pattern = "第[一二三四五六七八九十百千万零]+回",
        name = "中文数字回",
        priority = 8,
        confidence_base = 0.85
    },
    {
        pattern = "[0-9]+%.",
        name = "数字点格式",
        priority = 7,
        confidence_base = 0.75
    },
    {
        pattern = "第[0-9]+话",
        name = "阿拉伯数字话",
        priority = 7,
        confidence_base = 0.80
    },
    {
        pattern = "第[0-9]+集",
        name = "阿拉伯数字集",
        priority = 7,
        confidence_base = 0.80
    },
    {
        pattern = "第[0-9]+卷",
        name = "阿拉伯数字卷",
        priority = 7,
        confidence_base = 0.80
    },
    {
        pattern = "第[0-9]+部分",
        name = "阿拉伯数字部分",
        priority = 6,
        confidence_base = 0.75
    },
}

-- 低优先级模式（不常用，最后匹配）
local LOW_PRIORITY_PATTERNS = {
    {
        pattern = "★[^★]*★",
        name = "星号装饰",
        priority = 5,
        confidence_base = 0.60
    },
    {
        pattern = "◆[^◆]*◆",
        name = "菱形装饰",
        priority = 5,
        confidence_base = 0.60
    },
    {
        pattern = "【[^】]*】",
        name = "方括号标题",
        priority = 6,
        confidence_base = 0.70
    },
    {
        pattern = "《[^》]*》",
        name = "书名号标题",
        priority = 6,
        confidence_base = 0.70
    },
    {
        pattern = "%-%-%-+",
        name = "分隔线",
        priority = 3,
        confidence_base = 0.40
    },
    {
        pattern = "===+",
        name = "等号分隔线",
        priority = 3,
        confidence_base = 0.40
    },
    {
        pattern = "VIP章节",
        name = "VIP章节",
        priority = 4,
        confidence_base = 0.50
    },
    {
        pattern = "番外",
        name = "番外章节",
        priority = 4,
        confidence_base = 0.50
    },
}

-- 配置参数
local CONFIG = {
    min_confidence = 0.3,           -- 最低置信度阈值
    max_title_length = 100,         -- 最大标题长度
    min_title_length = 2,           -- 最小标题长度
    enable_cache = true,            -- 启用匹配缓存
    early_exit_confidence = 0.95,   -- 早期退出置信度阈值
    max_patterns_per_line = 10,     -- 每行最多检查的模式数
    enable_encoding_detection = true, -- 启用编码检测
    encoding_sample_size = 8192,    -- 编码检测样本大小
}

-- 统计信息
local STATS = {
    total_patterns = 0,
    high_priority_count = 0,
    medium_priority_count = 0,
    low_priority_count = 0,
    cache_hits = 0,
    cache_misses = 0,
    early_exits = 0,
    encoding_detections = 0,
    encoding_conversions = 0,
}

-- 匹配缓存
local match_cache = {}

-- 编码检测缓存
local encoding_cache = {}

-- 初始化统计信息
local function initStats()
    STATS.high_priority_count = #HIGH_PRIORITY_PATTERNS
    STATS.medium_priority_count = #MEDIUM_PRIORITY_PATTERNS
    STATS.low_priority_count = #LOW_PRIORITY_PATTERNS
    STATS.total_patterns = STATS.high_priority_count + STATS.medium_priority_count + STATS.low_priority_count
end

-- 检查标题长度是否有效
local function isValidTitleLength(title)
    local len = #title
    return len >= CONFIG.min_title_length and len <= CONFIG.max_title_length
end

-- 快速置信度计算（优化版）
local function calculateConfidence(title, pattern_info)
    local base_confidence = pattern_info.confidence_base or 0.5
    local title_len = #title
    
    -- 长度调整（简化计算）
    local length_factor = 1.0
    if title_len < 10 then
        length_factor = 1.1  -- 短标题加分
    elseif title_len > 50 then
        length_factor = 0.9  -- 长标题减分
    end
    
    return math.min(1.0, base_confidence * length_factor)
end

-- 分层匹配函数（性能优化核心）
local function matchPatterns(title)
    -- 检查缓存
    if CONFIG.enable_cache and match_cache[title] then
        STATS.cache_hits = STATS.cache_hits + 1
        return match_cache[title]
    end
    
    STATS.cache_misses = STATS.cache_misses + 1
    local best_match = nil
    local patterns_checked = 0
    
    -- 第一层：高优先级模式
    for _, pattern_info in ipairs(HIGH_PRIORITY_PATTERNS) do
        if title:match(pattern_info.pattern) then
            local confidence = calculateConfidence(title, pattern_info)
            if confidence >= CONFIG.min_confidence then
                best_match = {
                    pattern = pattern_info.pattern,
                    name = pattern_info.name,
                    priority = pattern_info.priority,
                    confidence = confidence
                }
                
                -- 早期退出：如果置信度足够高，直接返回
                if confidence >= CONFIG.early_exit_confidence then
                    STATS.early_exits = STATS.early_exits + 1
                    break
                end
            end
        end
        
        patterns_checked = patterns_checked + 1
        if patterns_checked >= CONFIG.max_patterns_per_line then
            break
        end
    end
    
    -- 如果高优先级没有找到满意结果，继续检查中优先级
    if not best_match or best_match.confidence < 0.8 then
        for _, pattern_info in ipairs(MEDIUM_PRIORITY_PATTERNS) do
            if title:match(pattern_info.pattern) then
                local confidence = calculateConfidence(title, pattern_info)
                if confidence >= CONFIG.min_confidence then
                    if not best_match or confidence > best_match.confidence then
                        best_match = {
                            pattern = pattern_info.pattern,
                            name = pattern_info.name,
                            priority = pattern_info.priority,
                            confidence = confidence
                        }
                    end
                end
            end
            
            patterns_checked = patterns_checked + 1
            if patterns_checked >= CONFIG.max_patterns_per_line then
                break
            end
        end
    end
    
    -- 如果中优先级也没有找到满意结果，最后检查低优先级
    if not best_match or best_match.confidence < 0.6 then
        for _, pattern_info in ipairs(LOW_PRIORITY_PATTERNS) do
            if title:match(pattern_info.pattern) then
                local confidence = calculateConfidence(title, pattern_info)
                if confidence >= CONFIG.min_confidence then
                    if not best_match or confidence > best_match.confidence then
                        best_match = {
                            pattern = pattern_info.pattern,
                            name = pattern_info.name,
                            priority = pattern_info.priority,
                            confidence = confidence
                        }
                    end
                end
            end
            
            patterns_checked = patterns_checked + 1
            if patterns_checked >= CONFIG.max_patterns_per_line then
                break
            end
        end
    end
    
    -- 缓存结果
    if CONFIG.enable_cache then
        match_cache[title] = best_match
        
        -- 限制缓存大小
        local cache_size = 0
        for _ in pairs(match_cache) do
            cache_size = cache_size + 1
        end
        
        if cache_size > 1000 then  -- 限制缓存大小
            match_cache = {}  -- 简单清空缓存
        end
    end
    
    return best_match
end

-- 获取所有模式（兼容性接口）
local function getAllPatterns()
    local all_patterns = {}
    
    for _, pattern in ipairs(HIGH_PRIORITY_PATTERNS) do
        table.insert(all_patterns, pattern)
    end
    for _, pattern in ipairs(MEDIUM_PRIORITY_PATTERNS) do
        table.insert(all_patterns, pattern)
    end
    for _, pattern in ipairs(LOW_PRIORITY_PATTERNS) do
        table.insert(all_patterns, pattern)
    end
    
    return all_patterns
end

-- 公共接口
local M = {}

-- 主要匹配接口（优化版）
function M.matchChapter(title)
    if not isValidTitleLength(title) then
        return nil
    end
    
    return matchPatterns(title)
end

-- 编码检测接口
function M.detectEncoding(data, filename)
    if not CONFIG.enable_encoding_detection then
        return "utf-8", "编码检测已禁用"
    end
    
    -- 检查编码缓存
    local cache_key = filename or "unknown"
    if encoding_cache[cache_key] then
        return encoding_cache[cache_key].encoding, encoding_cache[cache_key].reason
    end
    
    STATS.encoding_detections = STATS.encoding_detections + 1
    
    -- 限制检测样本大小以提高性能
    local sample_data = data
    if #data > CONFIG.encoding_sample_size then
        sample_data = data:sub(1, CONFIG.encoding_sample_size)
    end
    
    local encoding, reason = EncodingDetector.detectEncoding(sample_data, filename)
    
    -- 缓存结果
    encoding_cache[cache_key] = {
        encoding = encoding,
        reason = reason
    }
    
    return encoding, reason
end

-- 编码转换接口
function M.convertToUTF8(data, from_encoding)
    if from_encoding == "utf-8" then
        return data
    end
    
    STATS.encoding_conversions = STATS.encoding_conversions + 1
    return EncodingDetector.convertToUTF8(data, from_encoding)
end

-- 兼容性接口
function M.getAllPatterns()
    return getAllPatterns()
end

function M.isValidTitleLength(title)
    return isValidTitleLength(title)
end

function M.calculateConfidence(title, pattern_info)
    return calculateConfidence(title, pattern_info)
end

function M.getConfig()
    return CONFIG
end

function M.updateConfig(new_config)
    for key, value in pairs(new_config) do
        if CONFIG[key] ~= nil then
            CONFIG[key] = value
        end
    end
end

function M.getStats()
    return STATS
end

function M.clearCache()
    match_cache = {}
    encoding_cache = {}
    STATS.cache_hits = 0
    STATS.cache_misses = 0
    STATS.early_exits = 0
    STATS.encoding_detections = 0
    STATS.encoding_conversions = 0
end

-- 性能测试接口
function M.benchmarkPatterns(test_titles)
    local start_time = os.clock()
    local results = {}
    
    for _, title in ipairs(test_titles) do
        local match = M.matchChapter(title)
        table.insert(results, {
            title = title,
            match = match
        })
    end
    
    local end_time = os.clock()
    local duration = end_time - start_time
    
    return {
        results = results,
        duration = duration,
        titles_count = #test_titles,
        avg_time_per_title = duration / #test_titles,
        stats = M.getStats()
    }
end

-- 编码测试接口
function M.testEncoding(test_data, filename)
    local start_time = os.clock()
    local encoding, reason = M.detectEncoding(test_data, filename)
    local end_time = os.clock()
    
    return {
        encoding = encoding,
        reason = reason,
        detection_time = end_time - start_time,
        sample_size = math.min(#test_data, CONFIG.encoding_sample_size)
    }
end

-- 初始化
initStats()

return M
-- AIGC END 