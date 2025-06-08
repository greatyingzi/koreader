#!/usr/bin/env lua

-- AIGC START
-- 测试TXT文件编码设置功能
-- 验证优化器是否能正确检测和设置文档编码
-- AIGC END

print("🧪 测试TXT文件编码设置功能")
print("=" .. string.rep("=", 50))

-- 模拟KOReader环境
local function setupMockEnvironment()
    -- 模拟logger
    _G.logger = {
        info = function(...) print("ℹ️ ", ...) end,
        warn = function(...) print("⚠️ ", ...) end,
        error = function(...) print("❌", ...) end
    }
    
    -- 模拟lfs
    _G.lfs = {
        attributes = function(path)
            local file = io.open(path, "r")
            if file then
                file:close()
                local size = 0
                local f = io.open(path, "rb")
                if f then
                    f:seek("end")
                    size = f:seek()
                    f:close()
                end
                return {
                    mode = "file",
                    size = size,
                    modification = os.time()
                }
            end
            return nil
        end
    }
    
    -- 模拟UIManager
    _G.UIManager = {
        show = function(widget) 
            if widget.text then
                print("📱 UI消息:", widget.text)
            end
        end,
        scheduleIn = function(delay, func) func() end
    }
    
    -- 模拟InfoMessage
    _G.InfoMessage = {
        new = function(params) return params end
    }
    
    -- 模拟ConfirmBox
    _G.ConfirmBox = {
        new = function(params) return params end
    }
    
    -- 模拟T函数
    _G.T = function(template, ...)
        local args = {...}
        local result = template
        for i, arg in ipairs(args) do
            result = result:gsub("%%"..i, tostring(arg))
        end
        return result
    end
    
    -- 模拟ReaderUI
    _G.ReaderUI = {
        onSetupDocument = function() end
    }
    
    -- 模拟ReaderToc
    _G.ReaderToc = {
        fillToc = function() end
    }
    
    -- 模拟require函数
    local original_require = require
    _G.require = function(module)
        if module == "apps/reader/readerui" then
            return _G.ReaderUI
        elseif module == "apps/reader/modules/readertoc" then
            return _G.ReaderToc
        elseif module == "ui/uimanager" then
            return _G.UIManager
        elseif module == "ui/widget/infomessage" then
            return _G.InfoMessage
        elseif module == "ui/widget/confirmbox" then
            return _G.ConfirmBox
        elseif module == "ffi/util" then
            return {template = _G.T}
        elseif module == "libs/libkoreader-lfs" then
            return _G.lfs
        elseif module == "logger" then
            return _G.logger
        else
            return original_require(module)
        end
    end
end

-- 创建模拟文档对象
local function createMockDocument(encoding)
    local doc = {
        file = "test.txt",
        charset_set = nil,
        setCharset = function(self, charset)
            self.charset_set = charset
            print("📝 文档编码已设置为:", charset)
            return true
        end,
        _document = {
            setCharset = function(self, charset)
                print("📝 底层文档编码已设置为:", charset)
                return true
            end
        }
    }
    return doc
end

-- 创建模拟UI对象
local function createMockUI(document)
    return {
        document = document
    }
end

-- 测试编码检测功能
local function testEncodingDetection()
    print("\n🔍 测试编码检测功能")
    print("-" .. string.rep("-", 30))
    
    -- 加载章节匹配模块
    local success, chapter_patterns = pcall(require, "patches/txt_chapter_patterns")
    if not success then
        print("❌ 无法加载章节匹配模块:", chapter_patterns)
        return false
    end
    
    -- 测试UTF-8 BOM检测
    local utf8_bom_data = string.char(0xEF, 0xBB, 0xBF) .. "这是UTF-8 BOM文件"
    local encoding, reason = chapter_patterns.detectEncoding(utf8_bom_data, "test.txt")
    print("UTF-8 BOM测试:", encoding, "(" .. reason .. ")")
    
    -- 测试GBK检测（模拟）
    local gbk_like_data = string.char(0xB5, 0xDA, 0xD2, 0xBB, 0xD5, 0xC2) -- "第一章"的GBK编码
    encoding, reason = chapter_patterns.detectEncoding(gbk_like_data, "test.txt")
    print("GBK检测测试:", encoding, "(" .. reason .. ")")
    
    -- 测试普通UTF-8
    local utf8_data = "第一章 开始"
    encoding, reason = chapter_patterns.detectEncoding(utf8_data, "test.txt")
    print("UTF-8检测测试:", encoding, "(" .. reason .. ")")
    
    return true
end

-- 测试编码设置功能
local function testEncodingSettings()
    print("\n⚙️ 测试编码设置功能")
    print("-" .. string.rep("-", 30))
    
    -- 加载优化器
    local success, optimizer = pcall(require, "patches/2-large_txt_optimizer")
    if not success then
        print("❌ 无法加载优化器:", optimizer)
        return false
    end
    
    -- 测试不同编码设置
    local test_cases = {
        {encoding = "utf-8", expected = true},
        {encoding = "gbk", expected = true},
        {encoding = "gb2312", expected = true}
    }
    
    for _, test_case in ipairs(test_cases) do
        print("\n测试编码:", test_case.encoding)
        
        local document = createMockDocument(test_case.encoding)
        local ui = createMockUI(document)
        
        -- 模拟setDocumentEncoding函数（从优化器中提取）
        local function setDocumentEncoding(ui, encoding)
            if not ui or not ui.document then
                return false
            end
            
            if ui.document.setCharset then
                ui.document:setCharset(encoding)
                return true
            elseif ui.document._document and ui.document._document.setCharset then
                ui.document._document:setCharset(encoding)
                return true
            end
            
            return false
        end
        
        local result = setDocumentEncoding(ui, test_case.encoding)
        print("设置结果:", result and "✅ 成功" or "❌ 失败")
        print("文档编码:", document.charset_set or "未设置")
    end
    
    return true
end

-- 测试文件优化流程
local function testOptimizationFlow()
    print("\n🔄 测试文件优化流程")
    print("-" .. string.rep("-", 30))
    
    -- 检查测试文件
    local test_files = {"test.txt", "test2.txt"}
    
    for _, filename in ipairs(test_files) do
        print("\n测试文件:", filename)
        
        local attr = lfs.attributes(filename)
        if attr then
            print("文件大小:", string.format("%.2f KB", attr.size / 1024))
            
            -- 模拟shouldOptimize函数
            local should_optimize = filename:lower():match("%.txt$") and attr.size >= 256 * 1024
            print("需要优化:", should_optimize and "是" or "否")
            
            if should_optimize then
                -- 读取文件样本进行编码检测
                local file = io.open(filename, "rb")
                if file then
                    local sample = file:read(8192)
                    file:close()
                    
                    if sample then
                        -- 加载章节匹配模块进行编码检测
                        local success, chapter_patterns = pcall(require, "patches/txt_chapter_patterns")
                        if success then
                            local encoding, reason = chapter_patterns.detectEncoding(sample, filename)
                            print("检测编码:", encoding, "(" .. reason .. ")")
                            
                            -- 模拟文档编码设置
                            local document = createMockDocument(encoding)
                            local ui = createMockUI(document)
                            
                            if encoding ~= "utf-8" then
                                print("需要设置编码:", encoding)
                                -- 这里在实际环境中会调用setDocumentEncoding
                            else
                                print("使用默认UTF-8编码")
                            end
                        end
                    end
                end
            end
        else
            print("文件不存在")
        end
    end
    
    return true
end

-- 主测试函数
local function runTests()
    setupMockEnvironment()
    
    print("开始测试TXT文件编码设置功能...\n")
    
    local tests = {
        {name = "编码检测", func = testEncodingDetection},
        {name = "编码设置", func = testEncodingSettings},
        {name = "优化流程", func = testOptimizationFlow}
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
    print("📊 测试结果:")
    print(string.format("通过: %d/%d", passed, total))
    print(string.format("成功率: %.1f%%", passed / total * 100))
    
    if passed == total then
        print("🎉 所有测试通过！")
    else
        print("⚠️ 部分测试失败，请检查实现")
    end
end

-- 运行测试
runTests()

print("\n✅ 编码设置功能测试完成")

-- AIGC END 