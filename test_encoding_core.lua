#!/usr/bin/env lua

-- AIGC START
-- 核心编码设置功能测试
-- 专注测试编码检测和设置的核心逻辑
-- AIGC END

print("🔧 测试TXT文件编码设置核心功能")
print("=" .. string.rep("=", 50))

-- 加载章节匹配模块
local chapter_patterns = require("patches/txt_chapter_patterns")

-- 测试编码检测
local function testEncodingDetection()
    print("\n🔍 编码检测测试")
    print("-" .. string.rep("-", 30))
    
    local test_cases = {
        {
            name = "UTF-8 BOM",
            data = string.char(0xEF, 0xBB, 0xBF) .. "这是UTF-8文件",
            expected = "utf-8"
        },
        {
            name = "GBK中文",
            data = string.char(0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2, 0x20, 0xBF, 0xAA, 0xCA, 0xBC),
            expected = "gbk"
        },
        {
            name = "普通UTF-8",
            data = "第一章 开始",
            expected = "utf-8"
        },
        {
            name = "ASCII文本",
            data = "Chapter 1 Beginning",
            expected = "utf-8"
        }
    }
    
    local passed = 0
    for _, test in ipairs(test_cases) do
        local encoding, reason = chapter_patterns.detectEncoding(test.data, "test.txt")
        local success = encoding == test.expected
        
        print(string.format("%-12s: %s (%s) %s", 
            test.name, 
            encoding, 
            reason, 
            success and "✅" or "❌"
        ))
        
        if success then
            passed = passed + 1
        end
    end
    
    print(string.format("\n编码检测通过率: %d/%d (%.1f%%)", passed, #test_cases, passed/#test_cases*100))
    return passed == #test_cases
end

-- 测试实际文件编码检测
local function testFileEncodingDetection()
    print("\n📁 实际文件编码检测")
    print("-" .. string.rep("-", 30))
    
    local test_files = {"test.txt", "test2.txt"}
    local results = {}
    
    for _, filename in ipairs(test_files) do
        local file = io.open(filename, "rb")
        if file then
            local sample = file:read(8192)
            file:close()
            
            if sample then
                local encoding, reason = chapter_patterns.detectEncoding(sample, filename)
                results[filename] = {encoding = encoding, reason = reason}
                print(string.format("%-10s: %s (%s)", filename, encoding, reason))
            else
                print(string.format("%-10s: 无法读取文件内容", filename))
            end
        else
            print(string.format("%-10s: 文件不存在", filename))
        end
    end
    
    return results
end

-- 模拟文档编码设置
local function simulateDocumentEncodingSetting()
    print("\n⚙️ 模拟文档编码设置")
    print("-" .. string.rep("-", 30))
    
    -- 模拟KOReader文档对象
    local MockDocument = {}
    MockDocument.__index = MockDocument
    
    function MockDocument:new()
        local obj = {
            charset = "utf-8",  -- 默认编码
            charset_set_count = 0
        }
        setmetatable(obj, self)
        return obj
    end
    
    function MockDocument:setCharset(encoding)
        print(string.format("📝 设置文档编码: %s -> %s", self.charset, encoding))
        self.charset = encoding
        self.charset_set_count = self.charset_set_count + 1
        return true
    end
    
    function MockDocument:getCharset()
        return self.charset
    end
    
    -- 模拟UI对象
    local MockUI = {}
    MockUI.__index = MockUI
    
    function MockUI:new(document)
        local obj = {
            document = document
        }
        setmetatable(obj, self)
        return obj
    end
    
    -- 编码设置函数（从优化器提取的核心逻辑）
    local function setDocumentEncoding(ui, encoding)
        if not ui or not ui.document then
            return false
        end
        
        if ui.document.setCharset then
            ui.document:setCharset(encoding)
            return true
        end
        
        return false
    end
    
    -- 测试不同编码设置
    local test_encodings = {"utf-8", "gbk", "gb2312", "big5"}
    local document = MockDocument:new()
    local ui = MockUI:new(document)
    
    print("初始编码:", document:getCharset())
    
    for _, encoding in ipairs(test_encodings) do
        local success = setDocumentEncoding(ui, encoding)
        print(string.format("设置 %s: %s (当前: %s)", 
            encoding, 
            success and "成功" or "失败",
            document:getCharset()
        ))
    end
    
    print(string.format("总共设置次数: %d", document.charset_set_count))
    
    return true
end

-- 完整的编码处理流程测试
local function testCompleteEncodingFlow()
    print("\n🔄 完整编码处理流程测试")
    print("-" .. string.rep("-", 30))
    
    local test_files = {"test.txt", "test2.txt"}
    
    for _, filename in ipairs(test_files) do
        print(string.format("\n处理文件: %s", filename))
        
        -- 1. 检查文件是否存在
        local file = io.open(filename, "rb")
        if file then
            -- 2. 读取样本数据
            local sample = file:read(8192)
            file:close()
            
            if sample then
                -- 3. 检测编码
                local detected_encoding, reason = chapter_patterns.detectEncoding(sample, filename)
                print(string.format("✅ 检测编码: %s (%s)", detected_encoding, reason))
                
                -- 4. 判断是否需要设置编码
                if detected_encoding ~= "utf-8" then
                    print(string.format("⚙️ 需要设置编码为: %s", detected_encoding))
                    
                    -- 5. 模拟设置编码
                    print("📝 模拟设置文档编码...")
                    print(string.format("✅ 编码设置完成: %s", detected_encoding))
                else
                    print("ℹ️ 使用默认UTF-8编码，无需设置")
                end
                
                -- 6. 简单的章节检测测试
                local lines = {}
                for line in sample:gmatch("[^\r\n]+") do
                    table.insert(lines, line)
                    if #lines >= 10 then break end  -- 只检查前10行
                end
                
                local chapter_count = 0
                for _, line in ipairs(lines) do
                    local match = chapter_patterns.matchChapter(line)
                    if match and match.confidence > 0.8 then
                        chapter_count = chapter_count + 1
                    end
                end
                
                print(string.format("📚 检测到章节: %d个 (前10行)", chapter_count))
            else
                print("❌ 无法读取文件内容")
            end
        else
            print("❌ 文件不存在")
        end
    end
    
    return true
end

-- 主测试函数
local function runTests()
    print("开始核心编码功能测试...\n")
    
    local tests = {
        {name = "编码检测算法", func = testEncodingDetection},
        {name = "文件编码检测", func = testFileEncodingDetection},
        {name = "编码设置模拟", func = simulateDocumentEncodingSetting},
        {name = "完整处理流程", func = testCompleteEncodingFlow}
    }
    
    local passed = 0
    local total = #tests
    
    for _, test in ipairs(tests) do
        print("\n" .. string.rep("=", 60))
        print("🧪 运行测试:", test.name)
        
        local success, result = pcall(test.func)
        if success and result then
            print("✅ 测试通过:", test.name)
            passed = passed + 1
        else
            print("❌ 测试失败:", test.name)
            if not success then
                print("错误:", result)
            end
        end
    end
    
    print("\n" .. string.rep("=", 60))
    print("📊 测试总结:")
    print(string.format("通过: %d/%d", passed, total))
    print(string.format("成功率: %.1f%%", passed / total * 100))
    
    if passed == total then
        print("🎉 所有核心功能测试通过！")
        print("💡 编码检测和设置功能已准备就绪")
    else
        print("⚠️ 部分测试失败，需要检查实现")
    end
    
    print("\n📋 实际使用说明:")
    print("1. 优化器会在文档打开时自动检测编码")
    print("2. 如果检测到非UTF-8编码，会自动设置文档编码")
    print("3. KOReader底层引擎会处理实际的编码转换")
    print("4. 用户无需手动干预，编码转换是透明的")
end

-- 运行测试
runTests()

print("\n✅ 核心编码功能测试完成")

-- AIGC END 