#!/usr/bin/env lua

-- AIGC START
-- GBK编码转换测试脚本
-- 测试我们的编码检测和转换功能
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

-- 测试文件
local test_file = "test2.txt"

print("🔍 GBK编码转换测试")
print("=" .. string.rep("=", 50))

-- 1. 读取文件样本
local file = io.open(test_file, "rb")
if not file then
    print("❌ 无法打开文件:", test_file)
    os.exit(1)
end

local sample_size = 8192
local sample_data = file:read(sample_size)
file:close()

if not sample_data then
    print("❌ 无法读取文件数据")
    os.exit(1)
end

print(string.format("📄 文件: %s", test_file))
print(string.format("📊 样本大小: %d 字节", #sample_data))

-- 2. 编码检测
print("\n🔍 编码检测:")
local encoding_result = chapter_patterns.testEncoding(sample_data, test_file)
print(string.format("   检测结果: %s", encoding_result.encoding))
print(string.format("   检测原因: %s", encoding_result.reason))
print(string.format("   检测耗时: %.6f 秒", encoding_result.detection_time))

-- 3. 显示原始数据（前100字节的十六进制）
print("\n📋 原始数据 (前100字节):")
local hex_display = ""
for i = 1, math.min(100, #sample_data) do
    hex_display = hex_display .. string.format("%02x ", sample_data:byte(i))
    if i % 16 == 0 then
        hex_display = hex_display .. "\n"
    end
end
print(hex_display)

-- 4. 尝试解析前几行
print("\n📝 前几行内容解析:")
local lines = {}
local current_line = ""
local line_count = 0

for i = 1, #sample_data do
    local byte = sample_data:byte(i)
    if byte == 0x0D then  -- CR
        -- 跳过，等待LF
    elseif byte == 0x0A then  -- LF
        if #current_line > 0 then
            table.insert(lines, current_line)
            line_count = line_count + 1
            if line_count >= 10 then break end
        end
        current_line = ""
    else
        current_line = current_line .. string.char(byte)
    end
end

-- 添加最后一行（如果没有换行符结尾）
if #current_line > 0 and line_count < 10 then
    table.insert(lines, current_line)
end

print(string.format("解析到 %d 行:", #lines))
for i, line in ipairs(lines) do
    -- 显示原始字节和尝试的UTF-8解释
    local line_bytes = ""
    for j = 1, math.min(50, #line) do
        line_bytes = line_bytes .. string.format("%02x ", line:byte(j))
    end
    
    print(string.format("第%d行 (%d字节):", i, #line))
    print(string.format("  原始: %s", line))
    print(string.format("  十六进制: %s", line_bytes))
    
    -- 尝试章节匹配（即使是乱码状态）
    local match = chapter_patterns.matchChapter(line)
    if match then
        print(string.format("  匹配: %s (置信度: %.2f)", match.name, match.confidence))
    else
        print("  匹配: 无")
    end
    print("")
end

-- 5. 建议
print("💡 建议:")
if encoding_result.encoding == "gbk" then
    print("   1. 文件确实是GBK编码")
    print("   2. 需要在KOReader层面进行编码转换")
    print("   3. 可以使用系统命令验证: iconv -f gbk -t utf-8 test2.txt | head -n 5")
    print("   4. 在实际应用中，KOReader的底层引擎会处理编码转换")
else
    print("   1. 文件可能不是GBK编码")
    print("   2. 检查编码检测逻辑")
end

print("\n✅ 测试完成")
-- AIGC END 