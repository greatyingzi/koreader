#!/usr/bin/env lua

-- AIGC START
-- 简单的BOM检测测试
-- 直接测试BOM检测逻辑
-- AIGC END

print("🔍 简单BOM检测测试")
print("=" .. string.rep("=", 40))

-- 手动实现BOM检测函数进行对比
local function detectBOM(data)
    if not data or #data < 2 then
        return nil
    end
    
    -- UTF-8 BOM: EF BB BF
    if #data >= 3 then
        local b1, b2, b3 = data:byte(1), data:byte(2), data:byte(3)
        if b1 == 0xEF and b2 == 0xBB and b3 == 0xBF then
            return "utf-8", "UTF-8 BOM"
        end
    end
    
    -- UTF-16 LE BOM: FF FE
    if #data >= 2 then
        local b1, b2 = data:byte(1), data:byte(2)
        if b1 == 0xFF and b2 == 0xFE then
            return "utf-16le", "UTF-16 LE BOM"
        end
    end
    
    -- UTF-16 BE BOM: FE FF
    if #data >= 2 then
        local b1, b2 = data:byte(1), data:byte(2)
        if b1 == 0xFE and b2 == 0xFF then
            return "utf-16be", "UTF-16 BE BOM"
        end
    end
    
    return nil
end

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
        name = "UTF-16 BE BOM",
        data = string.char(0xFE, 0xFF) .. "content",
        expected = "utf-16be"
    },
    {
        name = "无BOM",
        data = "no bom content",
        expected = nil
    },
    {
        name = "GBK数据",
        data = string.char(0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2),
        expected = nil
    }
}

print("\n🧪 手动BOM检测测试:")
for _, test in ipairs(test_cases) do
    local encoding, reason = detectBOM(test.data)
    local success = encoding == test.expected
    
    print(string.format("%-15s: %s %s", 
        test.name, 
        encoding or "无BOM", 
        success and "✅" or "❌"
    ))
    
    if reason then
        print(string.format("                 原因: %s", reason))
    end
end

-- 加载章节匹配模块进行对比
print("\n🔧 模块BOM检测测试:")
local chapter_patterns = require("patches/txt_chapter_patterns")

for _, test in ipairs(test_cases) do
    local encoding, reason = chapter_patterns.detectEncoding(test.data, "test.txt")
    
    print(string.format("%-15s: %s (%s)", 
        test.name, 
        encoding, 
        reason
    ))
    
    -- 显示前几个字节
    local hex_str = ""
    for i = 1, math.min(#test.data, 6) do
        hex_str = hex_str .. string.format("%02X ", test.data:byte(i))
    end
    print(string.format("                 字节: %s", hex_str))
end

print("\n✅ BOM检测测试完成")

-- AIGC END 