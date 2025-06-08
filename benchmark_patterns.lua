#!/usr/bin/env lua

-- AIGC START
-- 章节匹配规则性能基准测试脚本
-- 用于测试patches/txt_chapter_patterns.lua模块的性能表现
-- AIGC END

-- 加载章节匹配规则模块
local function loadChapterPatterns()
    local success, result = pcall(function()
        return require("patches/txt_chapter_patterns")
    end)
    
    if success then
        print("✓ 成功加载独立章节匹配模块")
        return result
    else
        print("✗ 无法加载独立模块:", result)
        os.exit(1)
    end
end

local chapter_patterns = loadChapterPatterns()

-- 测试数据集
local test_titles = {
    -- 高优先级匹配（应该快速匹配）
    "第1章 开始的故事",
    "第2章 继续的冒险", 
    "第3章 新的挑战",
    "第十章 重要转折",
    "第二十五章 高潮部分",
    "Chapter 1 The Beginning",
    "Chapter 15 The Middle",
    "第1节 基础知识",
    "第2节 进阶内容",
    
    -- 中优先级匹配
    "第1回 古典小说",
    "第二回 传统章节",
    "1. 列表格式",
    "2. 另一个列表",
    "第1话 漫画章节",
    "第1集 电视剧集",
    "第1卷 书籍分卷",
    "第1部分 文档章节",
    
    -- 低优先级匹配
    "★ 特殊章节 ★",
    "◆ 装饰章节 ◆", 
    "【重要通知】",
    "《书名标题》",
    "VIP章节内容",
    "番外篇章",
    "---分隔线---",
    "=========",
    
    -- 非章节内容（应该不匹配）
    "这是普通的文本内容",
    "没有章节标记的段落",
    "一些随机的文字",
    "包含数字123但不是章节",
    "第章 缺少数字",
    "章节 缺少第字",
    "",
    "   ",
    "a" .. string.rep("很长的标题", 20), -- 超长标题
}

-- 性能测试函数
local function runBenchmark()
    print("🚀 开始性能基准测试")
    print("=" .. string.rep("=", 50))
    
    -- 显示测试配置
    local all_patterns = chapter_patterns.getAllPatterns()
    print(string.format("📊 测试配置:"))
    print(string.format("   - 匹配模式数: %d", #all_patterns))
    print(string.format("   - 测试标题数: %d", #test_titles))
    print("")
    
    -- 清空缓存，确保公平测试
    chapter_patterns.clearCache()
    
    -- 单次匹配性能测试
    print("🔍 单次匹配性能测试:")
    local single_start = os.clock()
    local match_results = {}
    
    for i, title in ipairs(test_titles) do
        local match = chapter_patterns.matchChapter(title)
        table.insert(match_results, {
            title = title,
            match = match,
            index = i
        })
    end
    
    local single_end = os.clock()
    local single_duration = single_end - single_start
    
    print(string.format("   耗时: %.6f 秒", single_duration))
    print(string.format("   平均每次匹配: %.6f 秒", single_duration / #test_titles))
    print(string.format("   每秒可处理: %.0f 次匹配", #test_titles / single_duration))
    
    -- 统计匹配结果
    local matched_count = 0
    local high_confidence_count = 0
    local confidence_sum = 0
    
    for _, result in ipairs(match_results) do
        if result.match then
            matched_count = matched_count + 1
            confidence_sum = confidence_sum + result.match.confidence
            if result.match.confidence >= 0.9 then
                high_confidence_count = high_confidence_count + 1
            end
        end
    end
    
    print(string.format("   匹配成功: %d/%d (%.1f%%)", matched_count, #test_titles, (matched_count / #test_titles) * 100))
    if matched_count > 0 then
        print(string.format("   平均置信度: %.1f%%", (confidence_sum / matched_count) * 100))
        print(string.format("   高置信度(≥90%%): %d/%d", high_confidence_count, matched_count))
    end
    
    -- 批量性能测试（模拟大文件处理）
    print("\n📚 批量处理性能测试:")
    local batch_size = 1000
    local batch_titles = {}
    
    -- 生成批量测试数据
    for i = 1, batch_size do
        local title_index = ((i - 1) % #test_titles) + 1
        table.insert(batch_titles, test_titles[title_index])
    end
    
    chapter_patterns.clearCache() -- 清空缓存
    
    local batch_start = os.clock()
    local batch_results = chapter_patterns.benchmarkPatterns(batch_titles)
    local batch_end = os.clock()
    
    print(string.format("   批量大小: %d 个标题", batch_size))
    print(string.format("   总耗时: %.6f 秒", batch_results.duration))
    print(string.format("   平均每次: %.6f 秒", batch_results.avg_time_per_title))
    print(string.format("   处理速度: %.0f 次/秒", batch_size / batch_results.duration))
    
    -- 缓存性能测试
    print("\n💾 缓存性能测试:")
    
    -- 第一次运行（填充缓存）
    chapter_patterns.clearCache()
    local cache_start1 = os.clock()
    for _, title in ipairs(test_titles) do
        chapter_patterns.matchChapter(title)
    end
    local cache_end1 = os.clock()
    local cache_duration1 = cache_end1 - cache_start1
    
    -- 第二次运行（使用缓存）
    local cache_start2 = os.clock()
    for _, title in ipairs(test_titles) do
        chapter_patterns.matchChapter(title)
    end
    local cache_end2 = os.clock()
    local cache_duration2 = cache_end2 - cache_start2
    
    local speedup = cache_duration1 / cache_duration2
    
    print(string.format("   首次运行: %.6f 秒", cache_duration1))
    print(string.format("   缓存运行: %.6f 秒", cache_duration2))
    print(string.format("   性能提升: %.1fx", speedup))
    
    -- 显示详细统计
    local stats = chapter_patterns.getStats()
    if stats then
        print("\n📈 详细统计信息:")
        print(string.format("   总模式数: %d", stats.total_patterns))
        print(string.format("   高优先级: %d", stats.high_priority_count))
        print(string.format("   中优先级: %d", stats.medium_priority_count))
        print(string.format("   低优先级: %d", stats.low_priority_count))
        print(string.format("   缓存命中: %d", stats.cache_hits))
        print(string.format("   缓存未命中: %d", stats.cache_misses))
        print(string.format("   早期退出: %d", stats.early_exits))
        
        local total_requests = stats.cache_hits + stats.cache_misses
        if total_requests > 0 then
            local hit_rate = (stats.cache_hits / total_requests) * 100
            print(string.format("   缓存命中率: %.1f%%", hit_rate))
        end
        
        if stats.early_exits > 0 then
            local early_exit_rate = (stats.early_exits / stats.cache_misses) * 100
            print(string.format("   早期退出率: %.1f%%", early_exit_rate))
        end
    end
    
    -- 显示匹配示例
    print("\n📋 匹配结果示例:")
    print(string.rep("-", 70))
    print(string.format("%-25s %-15s %-8s %s", "标题", "匹配类型", "置信度", "模式"))
    print(string.rep("-", 70))
    
    local shown_count = 0
    for _, result in ipairs(match_results) do
        if result.match and shown_count < 10 then
            local title_display = result.title
            if #title_display > 22 then
                title_display = title_display:sub(1, 19) .. "..."
            end
            
            print(string.format("%-25s %-15s %-8.0f%% %s", 
                title_display,
                result.match.name,
                result.match.confidence * 100,
                result.match.pattern
            ))
            shown_count = shown_count + 1
        end
    end
    
    if matched_count > shown_count then
        print(string.format("... 还有 %d 个匹配结果", matched_count - shown_count))
    end
    
    print(string.rep("=", 50))
    print("✅ 性能基准测试完成！")
end

-- 运行基准测试
runBenchmark()
-- AIGC END 