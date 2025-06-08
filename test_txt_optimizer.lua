-- 测试TXT优化器
print("=== TXT优化器测试 ===")

-- 模拟logger
local logger = {
    info = function(...) print("INFO:", ...) end,
    warn = function(...) print("WARN:", ...) end,
    dbg = function(...) print("DEBUG:", ...) end
}

-- 模拟其他依赖
local UIManager = {
    show = function() end,
    scheduleIn = function() end
}

local InfoMessage = {
    new = function() return {} end
}

local DataStorage = {
    getDataDir = function() return "/tmp" end
}

local lfs = {
    attributes = function(path) 
        if path and path:match("%.txt$") then
            return {size = 1024*1024, mode = "file", modification = os.time()}
        end
        return nil
    end,
    mkdir = function() return true end
}

local util = {
    tableToString = function(t) return tostring(t) end,
    tableDeepCopy = function(t) return t end
}

-- 加载TXT优化器的核心部分（章节匹配功能）
local function createChapterPatterns()
    -- 高优先级模式（最常用）
    local HIGH_PRIORITY_PATTERNS = {
        {pattern = "第[0-9]+章", name = "阿拉伯数字章节", priority = 10, confidence_base = 0.95},
        {pattern = "第[一二三四五六七八九十百千万零]+章", name = "中文数字章节", priority = 10, confidence_base = 0.95},
        {pattern = "Chapter [0-9]+", name = "英文章节", priority = 9, confidence_base = 0.90},
        {pattern = "第[0-9]+节", name = "阿拉伯数字节", priority = 9, confidence_base = 0.90},
        {pattern = "第[一二三四五六七八九十百千万零]+节", name = "中文数字节", priority = 9, confidence_base = 0.90},
    }
    
    -- 中优先级模式
    local MEDIUM_PRIORITY_PATTERNS = {
        {pattern = "第[0-9]+回", name = "阿拉伯数字回", priority = 8, confidence_base = 0.85},
        {pattern = "第[一二三四五六七八九十百千万零]+回", name = "中文数字回", priority = 8, confidence_base = 0.85},
        {pattern = "[0-9]+%.", name = "数字点格式", priority = 7, confidence_base = 0.75},
        {pattern = "第[0-9]+话", name = "阿拉伯数字话", priority = 7, confidence_base = 0.80},
        {pattern = "第[0-9]+集", name = "阿拉伯数字集", priority = 7, confidence_base = 0.80},
        {pattern = "第[0-9]+卷", name = "阿拉伯数字卷", priority = 7, confidence_base = 0.80},
        {pattern = "第[0-9]+部分", name = "阿拉伯数字部分", priority = 6, confidence_base = 0.75},
    }
    
    -- 低优先级模式
    local LOW_PRIORITY_PATTERNS = {
        {pattern = "★[^★]*★", name = "星号装饰", priority = 5, confidence_base = 0.60},
        {pattern = "◆[^◆]*◆", name = "菱形装饰", priority = 5, confidence_base = 0.60},
        {pattern = "【[^】]*】", name = "方括号标题", priority = 6, confidence_base = 0.70},
        {pattern = "《[^》]*》", name = "书名号标题", priority = 6, confidence_base = 0.70},
        {pattern = "%-%-%-+", name = "分隔线", priority = 3, confidence_base = 0.40},
        {pattern = "===+", name = "等号分隔线", priority = 3, confidence_base = 0.40},
        {pattern = "VIP章节", name = "VIP章节", priority = 4, confidence_base = 0.50},
        {pattern = "番外", name = "番外章节", priority = 4, confidence_base = 0.50},
    }
    
    local CONFIG = {
        min_confidence = 0.3,
        max_title_length = 100,
        min_title_length = 2,
        enable_cache = true,
        early_exit_confidence = 0.95,
        max_patterns_per_line = 10,
    }
    
    local STATS = {
        total_patterns = #HIGH_PRIORITY_PATTERNS + #MEDIUM_PRIORITY_PATTERNS + #LOW_PRIORITY_PATTERNS,
        high_priority_count = #HIGH_PRIORITY_PATTERNS,
        medium_priority_count = #MEDIUM_PRIORITY_PATTERNS,
        low_priority_count = #LOW_PRIORITY_PATTERNS,
        cache_hits = 0,
        cache_misses = 0,
        early_exits = 0,
    }
    
    local match_cache = {}
    
    local function isValidTitleLength(title)
        local len = #title
        return len >= CONFIG.min_title_length and len <= CONFIG.max_title_length
    end
    
    local function calculateConfidence(title, pattern_info)
        local base_confidence = pattern_info.confidence_base or 0.5
        local title_len = #title
        
        local length_factor = 1.0
        if title_len < 10 then
            length_factor = 1.1
        elseif title_len > 50 then
            length_factor = 0.9
        end
        
        return math.min(1.0, base_confidence * length_factor)
    end
    
    local function matchPatterns(title)
        if match_cache[title] then
            STATS.cache_hits = STATS.cache_hits + 1
            return match_cache[title]
        end
        
        STATS.cache_misses = STATS.cache_misses + 1
        local best_match = nil
        local patterns_checked = 0
        
        -- 高优先级匹配
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
                    
                    if confidence >= CONFIG.early_exit_confidence then
                        STATS.early_exits = STATS.early_exits + 1
                        break
                    end
                end
            end
            
            patterns_checked = patterns_checked + 1
            if patterns_checked >= CONFIG.max_patterns_per_line then break end
        end
        
        -- 中优先级匹配
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
                if patterns_checked >= CONFIG.max_patterns_per_line then break end
            end
        end
        
        -- 低优先级匹配
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
                if patterns_checked >= CONFIG.max_patterns_per_line then break end
            end
        end
        
        match_cache[title] = best_match
        return best_match
    end
    
    return {
        matchChapter = function(title)
            if not isValidTitleLength(title) then return nil end
            return matchPatterns(title)
        end,
        getStats = function() return STATS end,
        clearCache = function() 
            match_cache = {}
            STATS.cache_hits = 0
            STATS.cache_misses = 0
            STATS.early_exits = 0
        end,
    }
end

-- 测试章节匹配
local chapter_patterns = createChapterPatterns()

print("\n=== 章节匹配测试 ===")
local test_titles = {
    "第1章 开始的故事",
    "第二章 继续前进", 
    "Chapter 3: The Adventure",
    "第4节 重要内容",
    "第五回 精彩回合",
    "★特殊章节★",
    "【重要通知】",
    "《书名测试》",
    "VIP章节内容",
    "番外篇",
    "普通文本行",
    "这是一个很长的标题，可能不是章节标题，只是普通的文本内容而已",
    "短",
    "1. 列表项目",
    "---分隔线---",
    "第999章 最终章"
}

local matched_count = 0
local total_count = #test_titles

print(string.format("测试 %d 个标题:", total_count))
print("----------------------------------------")

for i, title in ipairs(test_titles) do
    local match = chapter_patterns.matchChapter(title)
    if match then
        matched_count = matched_count + 1
        print(string.format("%2d. ✓ [%s] %s (置信度: %.2f)", 
              i, match.name, title, match.confidence))
    else
        print(string.format("%2d. ✗ %s", i, title))
    end
end

print("----------------------------------------")
print(string.format("匹配结果: %d/%d (%.1f%%)", matched_count, total_count, matched_count/total_count*100))

-- 性能测试
print("\n=== 性能测试 ===")
local start_time = os.clock()
local iterations = 1000

for i = 1, iterations do
    for _, title in ipairs(test_titles) do
        chapter_patterns.matchChapter(title)
    end
end

local end_time = os.clock()
local duration = end_time - start_time
local total_matches = iterations * #test_titles

print(string.format("处理 %d 次匹配，耗时 %.3f 秒", total_matches, duration))
print(string.format("平均每次匹配: %.6f 秒", duration / total_matches))
print(string.format("每秒可处理: %.0f 次匹配", total_matches / duration))

-- 统计信息
local stats = chapter_patterns.getStats()
print("\n=== 统计信息 ===")
print("总模式数:", stats.total_patterns)
print("高优先级模式:", stats.high_priority_count)
print("中优先级模式:", stats.medium_priority_count) 
print("低优先级模式:", stats.low_priority_count)
print("缓存命中:", stats.cache_hits)
print("缓存未命中:", stats.cache_misses)
print("早期退出:", stats.early_exits)
if stats.cache_hits + stats.cache_misses > 0 then
    print(string.format("缓存命中率: %.1f%%", stats.cache_hits / (stats.cache_hits + stats.cache_misses) * 100))
end

print("\n=== 测试完成 ===") 