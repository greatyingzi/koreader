#!/usr/bin/env lua

-- AIGC START
-- 编码检测调试测试
-- 详细分析编码检测过程
-- AIGC END

print("🔍 编码检测调试测试")
print("=" .. string.rep("=", 50))

-- 加载章节匹配模块
local chapter_patterns = require("patches/txt_chapter_patterns")

-- 调试函数：显示字节序列
local function showBytes(data, label)
    print(string.format("\n%s (%d字节):", label, #data))
    local hex_str = ""
    local char_str = ""
    
    for i = 1, math.min(#data, 20) do
        local byte = data:byte(i)
        hex_str = hex_str .. string.format("%02X ", byte)
        char_str = char_str .. (byte >= 32 and byte <= 126 and string.char(byte) or ".")
    end
    
    print("HEX: " .. hex_str)
    print("CHR: " .. char_str)
    if #data > 20 then
        print("... (还有" .. (#data - 20) .. "字节)")
    end
end

-- 测试不同的编码数据
local function testEncodingDetection()
    print("\n🧪 测试编码检测算法")
    print("-" .. string.rep("-", 40))
    
    local test_cases = {
        {
            name = "UTF-8 BOM",
            data = string.char(0xEF, 0xBB, 0xBF) .. "这是UTF-8 BOM文件\n第一章 开始",
            expected = "utf-8"
        },
        {
            name = "纯UTF-8",
            data = "这是纯UTF-8文件\n第一章 开始\n没有BOM标记",
            expected = "utf-8"
        },
        {
            name = "ASCII文本",
            data = "This is ASCII text\nChapter 1 Beginning\nNo Chinese characters",
            expected = "utf-8"
        },
        {
            name = "模拟GBK",
            -- 创建一些看起来像GBK的字节序列
            data = string.char(0xB5, 0xDA) .. string.char(0xD2, 0xBB) .. string.char(0xD5, 0xC2) .. 
                   string.char(0x20, 0x20) .. string.char(0xBF, 0xAA) .. string.char(0xCA, 0xBC),
            expected = "gbk"
        }
    }
    
    for _, test in ipairs(test_cases) do
        print(string.format("\n测试: %s", test.name))
        showBytes(test.data, "数据内容")
        
        local encoding, reason = chapter_patterns.detectEncoding(test.data, "test.txt")
        local success = encoding == test.expected
        
        print(string.format("检测结果: %s", encoding))
        print(string.format("检测原因: %s", reason))
        print(string.format("期望结果: %s", test.expected))
        print(string.format("测试结果: %s", success and "✅ 通过" or "❌ 失败"))
    end
end

-- 测试实际文件的编码检测
local function testRealFileEncoding()
    print("\n\n📁 测试实际文件编码检测")
    print("-" .. string.rep("-", 40))
    
    local test_files = {"test.txt", "test2.txt"}
    
    for _, filename in ipairs(test_files) do
        print(string.format("\n文件: %s", filename))
        
        local file = io.open(filename, "rb")
        if file then
            local sample = file:read(1024)  -- 读取更小的样本用于调试
            file:close()
            
            if sample then
                showBytes(sample, "文件开头")
                
                local encoding, reason = chapter_patterns.detectEncoding(sample, filename)
                print(string.format("检测编码: %s", encoding))
                print(string.format("检测原因: %s", reason))
                
                -- 手动检查BOM
                if #sample >= 3 then
                    local b1, b2, b3 = sample:byte(1), sample:byte(2), sample:byte(3)
                    if b1 == 0xEF and b2 == 0xBB and b3 == 0xBF then
                        print("✅ 确认存在UTF-8 BOM")
                    else
                        print("❌ 无UTF-8 BOM")
                    end
                end
                
                -- 检查中文字符密度
                local chinese_count = 0
                local total_bytes = #sample
                local i = 1
                
                while i <= total_bytes - 1 do
                    local byte1 = sample:byte(i)
                    local byte2 = sample:byte(i + 1)
                    
                    if byte1 and byte2 then
                        -- 检查是否为GBK中文字符
                        if (byte1 >= 0xA1 and byte1 <= 0xFE and byte2 >= 0xA1 and byte2 <= 0xFE) or
                           (byte1 >= 0x81 and byte1 <= 0xFE and byte2 >= 0x40 and byte2 <= 0xFE and byte2 ~= 0x7F) then
                            chinese_count = chinese_count + 2
                            i = i + 2
                        else
                            i = i + 1
                        end
                    else
                        i = i + 1
                    end
                end
                
                local chinese_density = chinese_count / total_bytes
                print(string.format("中文字符密度: %.1f%% (%d/%d字节)", 
                    chinese_density * 100, chinese_count, total_bytes))
                
            else
                print("❌ 无法读取文件内容")
            end
        else
            print("❌ 文件不存在")
        end
    end
end

-- 测试BOM检测函数
local function testBOMDetection()
    print("\n\n🏷️ 测试BOM检测功能")
    print("-" .. string.rep("-", 40))
    
    local bom_tests = {
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
        }
    }
    
    for _, test in ipairs(bom_tests) do
        print(string.format("\n测试: %s", test.name))
        showBytes(test.data, "数据")
        
        -- 直接调用BOM检测函数（需要访问内部函数）
        local encoding, reason = chapter_patterns.detectEncoding(test.data, "test.txt")
        
        if test.expected then
            local success = encoding == test.expected
            print(string.format("检测结果: %s (%s)", encoding, reason))
            print(string.format("期望结果: %s", test.expected))
            print(string.format("测试结果: %s", success and "✅ 通过" or "❌ 失败"))
        else
            print(string.format("检测结果: %s (%s)", encoding, reason))
            print("期望结果: 非BOM编码")
        end
    end
end

-- 主测试函数
local function runDebugTests()
    print("开始编码检测调试测试...\n")
    
    local tests = {
        {name = "编码检测算法", func = testEncodingDetection},
        {name = "实际文件编码", func = testRealFileEncoding},
        {name = "BOM检测功能", func = testBOMDetection}
    }
    
    for _, test in ipairs(tests) do
        local success, result = pcall(test.func)
        if not success then
            print(string.format("❌ 测试失败: %s", test.name))
            print(string.format("错误: %s", result))
        end
    end
    
    print("\n" .. string.rep("=", 60))
    print("🎯 调试总结:")
    print("1. 检查BOM检测是否正确识别UTF-8 BOM")
    print("2. 验证中文字符密度计算是否准确")
    print("3. 确认编码检测优先级是否合理")
    print("4. 分析实际文件的编码特征")
end

-- 运行调试测试
runDebugTests()

print("\n✅ 编码检测调试测试完成")

-- AIGC END 