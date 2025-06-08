#!/usr/bin/env lua

-- AIGC START
-- 直接测试BOM检测函数
-- 绕过缓存和其他逻辑
-- AIGC END

print("🔍 直接BOM检测测试")
print("=" .. string.rep("=", 40))

-- 加载模块
local chapter_patterns = require("patches/txt_chapter_patterns")

-- 清除缓存
chapter_patterns.clearCache()

-- 测试数据
local test_cases = {
    {
        name = "UTF-8 BOM",
        data = string.char(0xEF, 0xBB, 0xBF) .. "content",
        expected = "utf-8"
    },
    {
        name = "UTF-16 LE BOM",
        data = string.char(0xFF, 0xFE) .. "content",
        expected = "utf-16le"
    },
    {
        name = "无BOM ASCII",
        data = "no bom content",
        expected = "utf-8"  -- 应该通过UTF-8检测
    },
    {
        name = "GBK数据",
        data = string.char(0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2),
        expected = "gbk"  -- 应该通过中文密度检测
    }
}

print("\n🧪 直接编码检测测试:")
for i, test in ipairs(test_cases) do
    -- 使用不同的文件名避免缓存
    local filename = "test" .. i .. ".txt"
    
    local encoding, reason = chapter_patterns.detectEncoding(test.data, filename)
    local success = encoding == test.expected
    
    print(string.format("%-15s: %s (%s) %s", 
        test.name, 
        encoding, 
        reason,
        success and "✅" or "❌"
    ))
    
    -- 显示字节
    local hex_str = ""
    for j = 1, math.min(#test.data, 6) do
        hex_str = hex_str .. string.format("%02X ", test.data:byte(j))
    end
    print(string.format("                 字节: %s", hex_str))
end

-- 测试配置
print("\n⚙️ 当前配置:")
local config = chapter_patterns.getConfig()
print("编码检测启用:", config.enable_encoding_detection)
print("样本大小:", config.encoding_sample_size)

-- 测试统计
print("\n📊 统计信息:")
local stats = chapter_patterns.getStats()
print("编码检测次数:", stats.encoding_detections)
print("编码转换次数:", stats.encoding_conversions)

print("\n✅ 直接BOM检测测试完成")

-- AIGC END 