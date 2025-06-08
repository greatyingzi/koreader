#!/usr/bin/env lua
-- 验证test.txt文件的TXT优化器效果

print("=== TXT优化器 - test.txt文件验证 ===")

-- 模拟KOReader环境
local logger = {
    info = function(...) print("INFO:", ...) end,
    warn = function(...) print("WARN:", ...) end,
    dbg = function(...) print("DEBUG:", ...) end
}

-- 获取文件信息
local function getFileInfo(filepath)
    local file = io.open(filepath, "rb")
    if not file then
        return nil, "无法打开文件"
    end
    
    -- 获取文件大小
    file:seek("end")
    local size = file:seek()
    file:seek("set", 0)
    
    return {
        size = size,
        size_mb = size / (1024 * 1024)
    }, file
end

-- 加载章节匹配规则模块
local function loadChapterPatterns()
    -- 尝试加载独立的章节匹配模块
    local success, result = pcall(function()
        return require("patches/txt_chapter_patterns")
    end)
    
    if success then
        print("✓ 成功加载独立章节匹配模块")
        return result
    else
        print("✗ 无法加载独立模块:", result)
        print("请确保patches/txt_chapter_patterns.lua文件存在")
        os.exit(1)
    end
end

local chapter_patterns = loadChapterPatterns()

-- 章节检测函数（模拟主优化器的detectChapters函数）
local function detectChapters(content, max_lines)
    local chapters = {}
    local line_count = 0
    local byte_offset = 0
    
    max_lines = max_lines or 3000
    
    for line in content:gmatch("[^\r\n]*[\r\n]?") do
        line_count = line_count + 1
        local clean_line = line:gsub("^%s+", ""):gsub("%s+$", "")
        
        if #clean_line > 0 then
            local match_result = chapter_patterns.matchChapter(clean_line)
            
            if match_result then
                table.insert(chapters, {
                    title = clean_line,
                    line = line_count,
                    offset = byte_offset,
                    pattern = match_result.pattern,
                    pattern_name = match_result.name,
                    confidence = match_result.confidence,
                    priority = match_result.priority
                })
            end
        end
        
        byte_offset = byte_offset + #line
        
        if line_count > max_lines then
            break
        end
    end
    
    -- 按置信度和优先级排序
    table.sort(chapters, function(a, b)
        if a.confidence == b.confidence then
            return a.priority > b.priority
        end
        return a.confidence > b.confidence
    end)
    
    return chapters, chapter_patterns.getStats()
end

-- 编码检测测试
local function testEncodingDetection(filename)
    print("🔍 编码检测测试:")
    
    if not chapter_patterns.testEncoding then
        print("   ⚠️  编码检测功能不可用")
        return
    end
    
    local file = io.open(filename, "rb")
    if not file then
        print("   ✗ 无法打开文件进行编码检测")
        return
    end
    
    -- 读取文件开头进行编码检测
    local sample_data = file:read(8192)
    file:close()
    
    if not sample_data then
        print("   ✗ 无法读取文件数据")
        return
    end
    
    local result = chapter_patterns.testEncoding(sample_data, filename)
    
    print(string.format("   检测结果: %s", result.encoding))
    print(string.format("   检测原因: %s", result.reason))
    print(string.format("   检测耗时: %.6f 秒", result.detection_time))
    print(string.format("   样本大小: %d 字节", result.sample_size))
    
    -- 检测BOM
    if #sample_data >= 3 then
        local bom_detected = false
        if sample_data:byte(1) == 0xEF and sample_data:byte(2) == 0xBB and sample_data:byte(3) == 0xBF then
            print("   BOM标记: UTF-8 BOM")
            bom_detected = true
        elseif sample_data:byte(1) == 0xFF and sample_data:byte(2) == 0xFE then
            print("   BOM标记: UTF-16 LE BOM")
            bom_detected = true
        elseif sample_data:byte(1) == 0xFE and sample_data:byte(2) == 0xFF then
            print("   BOM标记: UTF-16 BE BOM")
            bom_detected = true
        end
        
        if not bom_detected then
            print("   BOM标记: 无")
        end
    end
    
    print("")
end

-- 主验证函数
local function validateTestTxt()
    local filepath = "test2.txt"
    
    print("📁 文件路径:", filepath)
    
    -- 测试编码检测
    testEncodingDetection(filepath)
    
    -- 获取文件信息
    local file_info, file = getFileInfo(filepath)
    if not file_info then
        print("❌ 错误:", file)
        return
    end
    
    print(string.format("📊 文件大小: %.2f MB (%d 字节)", file_info.size_mb, file_info.size))
    
    -- 检查是否符合优化条件
    local min_size = 256 * 1024  -- 256KB
    if file_info.size < min_size then
        print("⚠️  文件小于256KB，不会触发优化")
    else
        print("✅ 文件大于256KB，会触发TXT优化")
    end
    
    -- 读取预览内容进行分析
    local preview_size = 512 * 1024  -- 512KB
    local content = file:read(preview_size)
    file:close()
    
    if not content then
        print("❌ 无法读取文件内容")
        return
    end
    
    print(string.format("🔍 分析内容大小: %.2f KB", #content / 1024))
    
    -- 开始章节检测
    print("\n=== 开始章节检测 ===")
    local start_time = os.clock()
    
    local chapters, stats = detectChapters(content)
    
    local end_time = os.clock()
    local detection_time = end_time - start_time
    
    print(string.format("⏱️  检测耗时: %.3f 秒", detection_time))
    print(string.format("📖 检测到章节数量: %d", #chapters))
    
    -- 显示检测到的章节（前20个）
    if #chapters > 0 then
        print("\n=== 检测到的章节详情 ===")
        print(string.format("📖 总共检测到 %d 个章节", #chapters))
        print(string.rep("=", 60))
        
        -- 显示所有章节（不限制数量）
        for i = 1, #chapters do
            local chapter = chapters[i]
            -- 计算字节位置对应的百分比
            local position_percent = (chapter.offset / #content) * 100
            
            print(string.format("%2d. 📍 第%d行 (%.1f%%) | [%s] | 置信度:%.2f", 
                  i, chapter.line, position_percent, chapter.pattern_name, chapter.confidence))
            print(string.format("    📝 标题: %s", chapter.title))
            print(string.format("    📊 字节偏移: %d", chapter.offset))
            print("    " .. ("-"):rep(50))
        end
        
        -- 章节分布统计
        print("\n=== 章节分布分析 ===")
        
        -- 按行号排序找到真正的首末章节
        local chapters_by_line = {}
        for _, chapter in ipairs(chapters) do
            table.insert(chapters_by_line, chapter)
        end
        table.sort(chapters_by_line, function(a, b) return a.line < b.line end)
        
        local first_chapter = chapters_by_line[1]      -- 行号最小的章节
        local last_chapter = chapters_by_line[#chapters_by_line]  -- 行号最大的章节
        
        print(string.format("📍 首个章节: 第%d行 - %s", first_chapter.line, first_chapter.title))
        print(string.format("📍 末个章节: 第%d行 - %s", last_chapter.line, last_chapter.title))
        print(string.format("📏 章节跨度: %d 行", last_chapter.line - first_chapter.line))
        
        if #chapters > 1 then
            local avg_interval = (last_chapter.line - first_chapter.line) / (#chapters - 1)
            print(string.format("📊 平均间隔: %.0f 行/章节", avg_interval))
        end
        
        -- 按模式类型统计
        print("\n=== 章节类型统计 ===")
        local pattern_count = {}
        local pattern_examples = {}
        
        for _, chapter in ipairs(chapters) do
            local pattern_name = chapter.pattern_name
            pattern_count[pattern_name] = (pattern_count[pattern_name] or 0) + 1
            
            -- 保存每种模式的示例
            if not pattern_examples[pattern_name] then
                pattern_examples[pattern_name] = chapter.title
            end
        end
        
        for pattern_name, count in pairs(pattern_count) do
            print(string.format("• %s: %d 个", pattern_name, count))
            print(string.format("  示例: %s", pattern_examples[pattern_name]))
        end
        
        -- 章节编号连续性检查（针对数字章节）
        print("\n=== 章节编号分析 ===")
        local numbered_chapters = {}
        
        for _, chapter in ipairs(chapters) do
            local chapter_num = chapter.title:match("第([0-9]+)章")
            if chapter_num then
                table.insert(numbered_chapters, {
                    num = tonumber(chapter_num),
                    title = chapter.title,
                    line = chapter.line
                })
            end
        end
        
        if #numbered_chapters > 0 then
            -- 按章节号排序
            table.sort(numbered_chapters, function(a, b) return a.num < b.num end)
            
            print(string.format("📊 数字章节: %d 个", #numbered_chapters))
            print(string.format("📍 章节范围: 第%d章 - 第%d章", 
                  numbered_chapters[1].num, numbered_chapters[#numbered_chapters].num))
            
            -- 检查连续性
            local missing_chapters = {}
            for i = numbered_chapters[1].num, numbered_chapters[#numbered_chapters].num do
                local found = false
                for _, ch in ipairs(numbered_chapters) do
                    if ch.num == i then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(missing_chapters, i)
                end
            end
            
            if #missing_chapters > 0 then
                print("⚠️  缺失章节: " .. table.concat(missing_chapters, ", "))
            else
                print("✅ 章节编号连续")
            end
            
            -- 显示数字章节列表
            print("\n📋 数字章节列表:")
            for i, ch in ipairs(numbered_chapters) do
                print(string.format("  第%d章 (第%d行): %s", ch.num, ch.line, ch.title))
            end
        end
    else
        print("❌ 未检测到任何章节")
    end
    
    -- 性能统计
    print("\n=== 性能统计 ===")
    print("总模式数:", stats.total_patterns)
    print("缓存命中:", stats.cache_hits)
    print("缓存未命中:", stats.cache_misses)
    print("早期退出:", stats.early_exits)
    
    if stats.cache_hits + stats.cache_misses > 0 then
        local hit_rate = stats.cache_hits / (stats.cache_hits + stats.cache_misses) * 100
        print(string.format("缓存命中率: %.1f%%", hit_rate))
    end
    
    -- 预估全文处理时间
    local lines_analyzed = 0
    for _ in content:gmatch("[^\r\n]*[\r\n]?") do
        lines_analyzed = lines_analyzed + 1
    end
    
    if lines_analyzed > 0 then
        local estimated_total_lines = file_info.size / (#content / lines_analyzed)
        local estimated_total_time = detection_time * (estimated_total_lines / lines_analyzed)
        
        print(string.format("\n📈 预估全文分析:"))
        print(string.format("• 预估总行数: %.0f", estimated_total_lines))
        print(string.format("• 预估总耗时: %.2f 秒", estimated_total_time))
    end
    
    return chapters, stats
end

-- 运行验证
validateTestTxt()

print("\n=== 验证完成 ===") 