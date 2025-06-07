--[[
    性能基准测试插件 - 专门针对 RenderTextFast 模块
    生成详细的性能对比报告，可在阅读器中直接查看
--]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local DataStorage = require("datastorage")

-- AIGC START
local BenchmarkPlugin = WidgetContainer:extend{
    name = "benchmark",
    is_doc_only = false,
}

function BenchmarkPlugin:init()
    self.ui.menu:registerToMainMenu(self)
end

function BenchmarkPlugin:addToMainMenu(menu_items)
    menu_items.benchmark = {
        text = _("渲染性能测试"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("切换优化开关"),
                checked_func = function()
                    local modules = self:getRenderModules()
                    if modules and modules.new and modules.new.isOptimizationsEnabled then
                        return modules.new:isOptimizationsEnabled()
                    end
                    return false
                end,
                callback = function()
                    local modules = self:getRenderModules()
                    if modules and modules.new and modules.new.setOptimizationsEnabled then
                        local current = modules.new:isOptimizationsEnabled()
                        modules.new:setOptimizationsEnabled(not current)
                        UIManager:show(InfoMessage:new{
                            text = _("RenderTextFast 优化已") .. (not current and "启用" or "禁用"),
                            timeout = 2,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("RenderTextFast 模块不可用"),
                            timeout = 2,
                        })
                    end
                end,
            },
            {
                text = _("查看优化状态"),
                callback = function()
                    self:showOptimizationStatus()
                end,
            },
            {
                text = _("快速测试 (15秒)"),
                callback = function()
                    self:runQuickBenchmark()
                end,
            },
            {
                text = _("完整性能测试 (60秒)"),
                callback = function()
                    self:runFullBenchmark()
                end,
            },
            {
                text = _("翻页速度测试"),
                callback = function()
                    self:runPageTurnBenchmark()
                end,
            },
            {
                text = _("批量渲染测试"),
                callback = function()
                    self:runBatchBenchmark()
                end,
            },
            {
                text = _("查看最新报告"),
                callback = function()
                    self:viewLatestReport()
                end,
            },
        }
    }
end

-- 获取渲染模块（延迟加载以避免启动问题）
function BenchmarkPlugin:getRenderModules()
    if not self.render_modules then
        local ok_old, RenderText = pcall(require, "ui/rendertext")
        local ok_new, RenderTextFast = pcall(require, "ui/rendertext_fast")
        
        if not ok_old then
            logger.err("无法加载 RenderText 模块: " .. tostring(RenderText))
            return nil
        end
        
        if not ok_new then
            logger.warn("无法加载 RenderTextFast 模块: " .. tostring(RenderTextFast))
            -- 创建一个虚拟的 RenderTextFast 包装器
            local DummyRenderTextFast = setmetatable({}, {__index = RenderText})
            function DummyRenderTextFast:isOptimizationsEnabled() return false end
            function DummyRenderTextFast:setOptimizationsEnabled() end
            function DummyRenderTextFast:getPerformanceStats() return {} end
            function DummyRenderTextFast:getMemoryUsage() return {total_kb = 0} end
            
            self.render_modules = {
                old = RenderText,
                new = DummyRenderTextFast
            }
        else
            self.render_modules = {
                old = RenderText,
                new = RenderTextFast
            }
        end
    end
    return self.render_modules
end

-- 获取测试所需组件（延迟加载）
function BenchmarkPlugin:getTestComponents()
    if not self.test_components then
        local ok_font, Font = pcall(require, "ui/font")
        local ok_bb, BlitBuffer = pcall(require, "ffi/blitbuffer")
        
        if not ok_font or not ok_bb then
            logger.err("无法加载测试组件")
            return nil
        end
        
        self.test_components = {
            Font = Font,
            BlitBuffer = BlitBuffer
        }
    end
    return self.test_components
end

-- 获取测试用文本样本
function BenchmarkPlugin:getTestSamples()
    return {
        {
            name = "英文短句",
            text = "The quick brown fox jumps over the lazy dog.",
            category = "ASCII"
        },
        {
            name = "英文长句",
            text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
            category = "ASCII"
        },
        {
            name = "中文短句",
            text = "君不见黄河之水天上来，奔流到海不复回。",
            category = "CJK"
        },
        {
            name = "中文长句",
            text = "天将降大任于斯人也，必先苦其心志，劳其筋骨，饿其体肤，空乏其身，行拂乱其所为，所以动心忍性，曾益其所不能。人恒过，然后能改；困于心，衡于虑，而后作；征于色，发于声，而后喻。",
            category = "CJK"
        },
        {
            name = "中英混合",
            text = "KOReader 是一个开源的电子书阅读器，支持多种格式如 PDF, EPUB, MOBI 等。Performance optimization is crucial for a smooth reading experience.",
            category = "Mixed"
        },
        {
            name = "特殊字符",
            text = "★☆♠♥♦♣♪♫♯♭αβγδεζηθικλμνξοπρστυφχψω№™®©",
            category = "Symbols"
        }
    }
end

-- 创建测试用的BitBuffer
function BenchmarkPlugin:createTestBitBuffer()
    local components = self:getTestComponents()
    if not components then
        return nil
    end
    return components.BlitBuffer.new(800, 600, components.BlitBuffer.TYPE_BB8)
end

-- 获取测试字体
function BenchmarkPlugin:getTestFont()
    local components = self:getTestComponents()
    if not components then
        return nil
    end
    return components.Font:getFace("cfont", 22)
end

-- 基于时间的性能测试 - 核心测试函数
function BenchmarkPlugin:runTimeBasedTest(impl_name, impl, sample, test_duration_sec)
    local face = self:getTestFont()
    local bb = self:createTestBitBuffer()
    
    if not face or not bb then
        logger.err("无法创建测试环境")
        return nil
    end
    
    local results = {
        impl_name = impl_name,
        sample_name = sample.name,
        sample_category = sample.category,
        text_length = #sample.text,
        test_duration_sec = test_duration_sec
    }
    
    -- 预热（固定5次）
    for i = 1, 5 do
        pcall(function()
            impl:sizeUtf8Text(0, false, face, sample.text, true, false)
            impl:renderUtf8Text(bb, 10, 30, face, sample.text, true, false, nil, nil, nil)
        end)
    end
    
    -- 测试文本尺寸计算
    local size_iterations = 0
    local size_chars_processed = 0
    local start_time = os.clock()
    local end_time = start_time + test_duration_sec
    
    while os.clock() < end_time do
        local success = pcall(function()
            impl:sizeUtf8Text(0, false, face, sample.text, true, false)
        end)
        if success then
            size_iterations = size_iterations + 1
            size_chars_processed = size_chars_processed + #sample.text
        end
    end
    local actual_size_time = os.clock() - start_time
    
    results.size_iterations = size_iterations
    results.size_chars_processed = size_chars_processed
    results.size_chars_per_sec = size_chars_processed / actual_size_time
    results.size_calls_per_sec = size_iterations / actual_size_time
    
    -- 测试文本渲染
    local render_iterations = 0
    local render_chars_processed = 0
    start_time = os.clock()
    end_time = start_time + test_duration_sec
    
    while os.clock() < end_time do
        local success = pcall(function()
            impl:renderUtf8Text(bb, 10, 30, face, sample.text, true, false, nil, nil, nil)
        end)
        if success then
            render_iterations = render_iterations + 1
            render_chars_processed = render_chars_processed + #sample.text
        end
    end
    local actual_render_time = os.clock() - start_time
    
    results.render_iterations = render_iterations
    results.render_chars_processed = render_chars_processed
    results.render_chars_per_sec = render_chars_processed / actual_render_time
    results.render_calls_per_sec = render_iterations / actual_render_time
    
    -- 测试子文本获取（仅对长文本）
    if #sample.text > 50 then
        local subtext_iterations = 0
        local subtext_chars_processed = 0
        start_time = os.clock()
        end_time = start_time + test_duration_sec
        
        while os.clock() < end_time do
            local success = pcall(function()
                impl:getSubTextByWidth(sample.text, face, 300, true, false)
            end)
            if success then
                subtext_iterations = subtext_iterations + 1
                subtext_chars_processed = subtext_chars_processed + #sample.text
            end
        end
        local actual_subtext_time = os.clock() - start_time
        
        results.subtext_iterations = subtext_iterations
        results.subtext_chars_processed = subtext_chars_processed
        results.subtext_chars_per_sec = subtext_chars_processed / actual_subtext_time
        results.subtext_calls_per_sec = subtext_iterations / actual_subtext_time
    end
    
    if bb then
        bb:free()
    end
    return results
end

-- 快速测试
function BenchmarkPlugin:runQuickBenchmark()
    UIManager:show(InfoMessage:new{
        text = "正在初始化快速性能测试...",
        timeout = 1,
    })
    
    local modules = self:getRenderModules()
    if not modules then
        UIManager:show(InfoMessage:new{
            text = "无法加载渲染模块，测试取消"
        })
        return
    end
    
    UIManager:show(InfoMessage:new{
        text = "正在运行快速性能测试...\n每项测试 2.5 秒",
        timeout = 2,
    })
    
    local samples = {self:getTestSamples()[1], self:getTestSamples()[3]} -- 英文和中文短句
    local test_duration = 2.5  -- 每个测试2.5秒
    local all_results = {}
    
    for _, sample in ipairs(samples) do
        -- 测试原始实现
        local old_result = self:runTimeBasedTest("RenderText (原版)", modules.old, sample, test_duration)
        if old_result then
            table.insert(all_results, old_result)
        end
        
        -- 测试新实现
        local new_result = self:runTimeBasedTest("RenderTextFast (新版)", modules.new, sample, test_duration)
        if new_result then
            table.insert(all_results, new_result)
        end
    end
    
    if #all_results > 0 then
        local report = self:generateReport("快速性能测试报告", all_results)
        self:saveReport(report)
        self:showReportSummary(all_results)
    else
        UIManager:show(InfoMessage:new{
            text = "测试失败，请检查日志"
        })
    end
end

-- 完整性能测试
function BenchmarkPlugin:runFullBenchmark()
    UIManager:show(InfoMessage:new{
        text = "正在初始化完整性能测试...",
        timeout = 1,
    })
    
    local modules = self:getRenderModules()
    if not modules then
        UIManager:show(InfoMessage:new{
            text = "无法加载渲染模块，测试取消"
        })
        return
    end
    
    UIManager:show(InfoMessage:new{
        text = "正在运行完整性能测试...\n每项测试 5 秒，预计 60 秒完成",
        timeout = 2,
    })
    
    local samples = self:getTestSamples()
    local test_duration = 5  -- 每个测试5秒
    local all_results = {}
    
    for _, sample in ipairs(samples) do
        -- 测试原始实现
        local old_result = self:runTimeBasedTest("RenderText (原版)", modules.old, sample, test_duration)
        if old_result then
            table.insert(all_results, old_result)
        end
        
        -- 测试新实现
        local new_result = self:runTimeBasedTest("RenderTextFast (新版)", modules.new, sample, test_duration)
        if new_result then
            table.insert(all_results, new_result)
        end
    end
    
    if #all_results > 0 then
        local report = self:generateReport("完整性能测试报告", all_results)
        self:saveReport(report)
        self:showReportSummary(all_results)
    else
        UIManager:show(InfoMessage:new{
            text = "测试失败，请检查日志"
        })
    end
end

-- 翻页速度测试
function BenchmarkPlugin:runPageTurnBenchmark()
    UIManager:show(InfoMessage:new{
        text = "正在初始化翻页速度测试...",
        timeout = 1,
    })
    
    local modules = self:getRenderModules()
    if not modules then
        UIManager:show(InfoMessage:new{
            text = "无法加载渲染模块，测试取消"
        })
        return
    end
    
    UIManager:show(InfoMessage:new{
        text = "正在运行翻页速度测试...\n模拟真实翻页操作",
        timeout = 2,
    })
    
    -- 创建模拟页面内容
    local page_content = self:createSimulatedPageContent()
    local test_duration = 3  -- 每个测试3秒
    local all_results = {}
    
    for scenario_name, content in pairs(page_content) do
        -- 测试原始实现
        local old_result = self:runPageTurnTest("RenderText (原版)", modules.old, scenario_name, content, test_duration)
        if old_result then
            table.insert(all_results, old_result)
        end
        
        -- 测试新实现
        local new_result = self:runPageTurnTest("RenderTextFast (新版)", modules.new, scenario_name, content, test_duration)
        if new_result then
            table.insert(all_results, new_result)
        end
    end
    
    if #all_results > 0 then
        local report = self:generatePageTurnReport("翻页速度测试报告", all_results)
        self:saveReport(report, "pageturn")
        self:showPageTurnSummary(all_results)
    else
        UIManager:show(InfoMessage:new{
            text = "测试失败，请检查日志"
        })
    end
end

-- 创建模拟页面内容
function BenchmarkPlugin:createSimulatedPageContent()
    return {
        ["纯文本页面"] = {
            "这是一个普通的段落，包含了常见的中文文本内容。",
            "Another paragraph with English text content for testing.",
            "混合段落包含 Chinese 和 English 文本 content together.",
            "短段。",
            "A longer paragraph that contains more text to simulate real book content with various sentence structures and different lengths of text content that readers might encounter.",
            "这是一个较长的中文段落，用来模拟真实书籍中可能出现的各种句子结构和不同长度的文本内容，读者在阅读过程中经常会遇到这样的段落。"
        },
        ["对话密集页面"] = {
            "「你好，今天天气怎么样？」小明问道。",
            "「很好啊，阳光明媚。」小红回答。",
            "\"How are you today?\" John asked.",
            "\"I'm fine, thank you!\" Mary replied.",
            "「我们去公园散步吧。」",
            "\"That sounds like a great idea.\""
        },
        ["技术文档页面"] = {
            "// 文本渲染性能测试代码示例",
            "function measureText(text, font, kerning) {",
            "    const startTime = performance.now();",
            "    return measureText(text, font, kerning);",
            "}",
            "local result = RenderText:sizeUtf8Text(x, y, face, text, true, false)",
            "-- 性能优化：使用缓存机制",
            "performance.measure('text-rendering', startTime, endTime);"
        }
    }
end

-- 翻页操作测试
function BenchmarkPlugin:runPageTurnTest(impl_name, impl, scenario_name, content, test_duration)
    local face = self:getTestFont()
    local bb = self:createTestBitBuffer()
    
    if not face or not bb then
        return nil
    end
    
    local results = {
        impl_name = impl_name,
        scenario_name = scenario_name,
        test_duration_sec = test_duration,
        total_operations = 0,
        layout_time = 0,
        render_time = 0
    }
    
    -- 预热
    for i = 1, 3 do
        self:simulatePageLayout(impl, content, face, 600) -- 模拟600px宽度
        self:simulatePageRender(impl, content, face, bb, 600)
    end
    
    -- 测试页面布局性能
    local start_time = os.clock()
    local end_time = start_time + test_duration
    local layout_operations = 0
    
    while os.clock() < end_time do
        self:simulatePageLayout(impl, content, face, 600)
        layout_operations = layout_operations + 1
    end
    results.layout_time = os.clock() - start_time
    results.layout_operations = layout_operations
    
    -- 测试页面渲染性能
    start_time = os.clock()
    end_time = start_time + test_duration
    local render_operations = 0
    
    while os.clock() < end_time do
        self:simulatePageRender(impl, content, face, bb, 600)
        render_operations = render_operations + 1
    end
    results.render_time = os.clock() - start_time
    results.render_operations = render_operations
    
    -- 综合翻页测试
    start_time = os.clock()
    end_time = start_time + test_duration
    local page_operations = 0
    
    while os.clock() < end_time do
        -- 模拟完整的翻页操作：布局 + 渲染
        self:simulatePageLayout(impl, content, face, 600)
        self:simulatePageRender(impl, content, face, bb, 600)
        page_operations = page_operations + 1
    end
    results.page_time = os.clock() - start_time
    results.page_operations = page_operations
    results.pages_per_sec = page_operations / results.page_time
    
    if bb then
        bb:free()
    end
    return results
end

-- 模拟页面布局计算
function BenchmarkPlugin:simulatePageLayout(impl, content, face, width)
    local total_height = 0
    local line_height = 30
    
    for _, text in ipairs(content) do
        -- 模拟文本尺寸计算
        local size = impl:sizeUtf8Text(0, false, face, text, true, false)
        
        -- 模拟换行计算
        if size.x > width then
            local sub_text = impl:getSubTextByWidth(text, face, width, true, false)
            total_height = total_height + line_height * 2 -- 假设需要两行
        else
            total_height = total_height + line_height
        end
    end
    
    return total_height
end

-- 模拟页面渲染
function BenchmarkPlugin:simulatePageRender(impl, content, face, bb, width)
    local y_offset = 30
    local line_height = 30
    
    for _, text in ipairs(content) do
        local size = impl:sizeUtf8Text(0, false, face, text, true, false)
        
        if size.x > width then
            -- 分行渲染
            local sub_text = impl:getSubTextByWidth(text, face, width, true, false)
            impl:renderUtf8Text(bb, 10, y_offset, face, sub_text, true, false, nil, nil, nil)
            y_offset = y_offset + line_height
            
            local remaining = text:sub(#sub_text + 1)
            if #remaining > 0 then
                impl:renderUtf8Text(bb, 10, y_offset, face, remaining, true, false, nil, nil, nil)
                y_offset = y_offset + line_height
            end
        else
            -- 单行渲染
            impl:renderUtf8Text(bb, 10, y_offset, face, text, true, false, nil, nil, nil)
            y_offset = y_offset + line_height
        end
    end
end

-- 生成翻页测试报告
function BenchmarkPlugin:generatePageTurnReport(title, results)
    local report = {}
    table.insert(report, title)
    table.insert(report, string.rep("=", #title))
    table.insert(report, "")
    table.insert(report, "生成时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(report, "")
    
    table.insert(report, "测试说明:")
    table.insert(report, "- 模拟真实翻页操作的性能测试")
    table.insert(report, "- 包含页面布局计算和文本渲染")
    table.insert(report, "- 统计指标: 页/秒, 操作/秒")
    table.insert(report, "")
    
    -- 按场景分组显示结果
    local scenarios = {}
    for _, result in ipairs(results) do
        if not scenarios[result.scenario_name] then
            scenarios[result.scenario_name] = {}
        end
        table.insert(scenarios[result.scenario_name], result)
    end
    
    for scenario_name, scenario_results in pairs(scenarios) do
        table.insert(report, "测试场景: " .. scenario_name)
        table.insert(report, string.rep("-", 50))
        
        local old_result, new_result
        for _, result in ipairs(scenario_results) do
            if string.find(result.impl_name, "原版") then
                old_result = result
            else
                new_result = result
            end
        end
        
        if old_result and new_result then
            table.insert(report, string.format("测试时长: %.1f 秒/项", old_result.test_duration_sec))
            table.insert(report, "")
            
            -- 页面布局性能
            table.insert(report, "页面布局计算:")
            table.insert(report, string.format("  原版: %.1f 操作/秒 (%d 次操作)",
                old_result.layout_operations / old_result.layout_time, old_result.layout_operations))
            table.insert(report, string.format("  新版: %.1f 操作/秒 (%d 次操作)",
                new_result.layout_operations / new_result.layout_time, new_result.layout_operations))
            local layout_improvement = (new_result.layout_operations / new_result.layout_time) / 
                                     (old_result.layout_operations / old_result.layout_time)
            table.insert(report, string.format("  性能比率: %.2fx", layout_improvement))
            table.insert(report, "")
            
            -- 页面渲染性能
            table.insert(report, "页面渲染:")
            table.insert(report, string.format("  原版: %.1f 操作/秒 (%d 次操作)",
                old_result.render_operations / old_result.render_time, old_result.render_operations))
            table.insert(report, string.format("  新版: %.1f 操作/秒 (%d 次操作)",
                new_result.render_operations / new_result.render_time, new_result.render_operations))
            local render_improvement = (new_result.render_operations / new_result.render_time) / 
                                      (old_result.render_operations / old_result.render_time)
            table.insert(report, string.format("  性能比率: %.2fx", render_improvement))
            table.insert(report, "")
            
            -- 综合翻页性能
            table.insert(report, "完整翻页操作:")
            table.insert(report, string.format("  原版: %.2f 页/秒 (%d 次翻页)",
                old_result.pages_per_sec, old_result.page_operations))
            table.insert(report, string.format("  新版: %.2f 页/秒 (%d 次翻页)",
                new_result.pages_per_sec, new_result.page_operations))
            local page_improvement = new_result.pages_per_sec / old_result.pages_per_sec
            table.insert(report, string.format("  翻页速度提升: %.2fx", page_improvement))
            table.insert(report, "")
        end
        
        table.insert(report, "")
    end
    
    table.insert(report, "翻页性能总结")
    table.insert(report, string.rep("=", 14))
    table.insert(report, "")
    table.insert(report, "注: 翻页速度提升 = 新版页/秒 / 原版页/秒")
    table.insert(report, "数值 > 1.0 表示翻页更快，< 1.0 表示翻页变慢")
    
    return table.concat(report, "\n")
end

-- 显示翻页测试摘要
function BenchmarkPlugin:showPageTurnSummary(results)
    if #results < 2 then
        UIManager:show(InfoMessage:new{
            text = "测试结果不足，无法生成摘要"
        })
        return
    end
    
    local summary_lines = {"翻页速度测试完成！\n"}
    
    -- 计算平均翻页速度提升
    local page_improvements = {}
    
    for i = 1, #results, 2 do
        local old_result = results[i]
        local new_result = results[i + 1]
        
        if old_result and new_result then
            table.insert(page_improvements, new_result.pages_per_sec / old_result.pages_per_sec)
        end
    end
    
    if #page_improvements > 0 then
        local avg_improvement = 0
        for _, improvement in ipairs(page_improvements) do
            avg_improvement = avg_improvement + improvement
        end
        avg_improvement = avg_improvement / #page_improvements
        
        local speed_increase_percent = (avg_improvement - 1) * 100
        
        table.insert(summary_lines, string.format("平均翻页速度提升: %.2fx", avg_improvement))
        table.insert(summary_lines, string.format("速度增加: %.1f%%", speed_increase_percent))
        table.insert(summary_lines, "\n详细报告已保存")
        
        -- 给出用户友好的解释
        if speed_increase_percent > 20 then
            table.insert(summary_lines, "\n🚀 翻页速度显著提升！")
        elseif speed_increase_percent > 10 then
            table.insert(summary_lines, "\n✅ 翻页速度明显改善")
        elseif speed_increase_percent > 5 then
            table.insert(summary_lines, "\n📈 翻页速度略有提升")
        else
            table.insert(summary_lines, "\n📊 翻页速度基本无变化")
        end
    end
    
    UIManager:show(InfoMessage:new{
        text = table.concat(summary_lines, "\n"),
        timeout = 10,
    })
end

-- 批量渲染测试
function BenchmarkPlugin:runBatchBenchmark()
    UIManager:show(InfoMessage:new{
        text = "批量渲染测试功能开发中...",
        timeout = 2,
    })
end

-- 生成性能测试报告
function BenchmarkPlugin:generateReport(title, results)
    local report = {}
    table.insert(report, title)
    table.insert(report, string.rep("=", #title))
    table.insert(report, "")
    table.insert(report, "生成时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(report, "")
    
    -- 系统信息
    table.insert(report, "测试方法:")
    table.insert(report, "- 基于固定时间的吞吐量测试")
    table.insert(report, "- 统计指标: 字符/秒, 调用/秒")
    table.insert(report, "- 设备: KOReader")
    table.insert(report, "")
    
    -- 按样本分组显示结果
    local samples = {}
    for _, result in ipairs(results) do
        if not samples[result.sample_name] then
            samples[result.sample_name] = {}
        end
        table.insert(samples[result.sample_name], result)
    end
    
    for sample_name, sample_results in pairs(samples) do
        table.insert(report, "测试样本: " .. sample_name)
        table.insert(report, string.rep("-", 50))
        
        local old_result, new_result
        for _, result in ipairs(sample_results) do
            if string.find(result.impl_name, "原版") then
                old_result = result
            else
                new_result = result
            end
        end
        
        if old_result and new_result then
            table.insert(report, string.format("文本类别: %s", old_result.sample_category))
            table.insert(report, string.format("文本长度: %d 字符", old_result.text_length))
            table.insert(report, string.format("测试时长: %.1f 秒", old_result.test_duration_sec))
            table.insert(report, "")
            
            -- 尺寸计算性能
            table.insert(report, "文本尺寸计算:")
            table.insert(report, string.format("  原版: %.0f 字符/秒 (%d 次调用，%d 字符)",
                old_result.size_chars_per_sec, old_result.size_iterations, old_result.size_chars_processed))
            table.insert(report, string.format("  新版: %.0f 字符/秒 (%d 次调用，%d 字符)",
                new_result.size_chars_per_sec, new_result.size_iterations, new_result.size_chars_processed))
            local size_improvement = new_result.size_chars_per_sec / math.max(old_result.size_chars_per_sec, 1)
            table.insert(report, string.format("  性能比率: %.2fx", size_improvement))
            table.insert(report, "")
            
            -- 渲染性能
            table.insert(report, "文本渲染:")
            table.insert(report, string.format("  原版: %.0f 字符/秒 (%d 次调用，%d 字符)",
                old_result.render_chars_per_sec, old_result.render_iterations, old_result.render_chars_processed))
            table.insert(report, string.format("  新版: %.0f 字符/秒 (%d 次调用，%d 字符)",
                new_result.render_chars_per_sec, new_result.render_iterations, new_result.render_chars_processed))
            local render_improvement = new_result.render_chars_per_sec / math.max(old_result.render_chars_per_sec, 1)
            table.insert(report, string.format("  性能比率: %.2fx", render_improvement))
            table.insert(report, "")
            
            -- 子文本获取性能（如果有的话）
            if old_result.subtext_chars_per_sec and new_result.subtext_chars_per_sec then
                table.insert(report, "子文本获取:")
                table.insert(report, string.format("  原版: %.0f 字符/秒 (%d 次调用，%d 字符)",
                    old_result.subtext_chars_per_sec, old_result.subtext_iterations, old_result.subtext_chars_processed))
                table.insert(report, string.format("  新版: %.0f 字符/秒 (%d 次调用，%d 字符)",
                    new_result.subtext_chars_per_sec, new_result.subtext_iterations, new_result.subtext_chars_processed))
                local subtext_improvement = new_result.subtext_chars_per_sec / math.max(old_result.subtext_chars_per_sec, 1)
                table.insert(report, string.format("  性能比率: %.2fx", subtext_improvement))
                table.insert(report, "")
            end
        end
        
        table.insert(report, "")
    end
    
    -- 总结
    table.insert(report, "性能测试总结")
    table.insert(report, string.rep("=", 14))
    table.insert(report, "")
    table.insert(report, "注: 性能比率 = 新版吞吐量 / 原版吞吐量")
    table.insert(report, "数值 > 1.0 表示性能提升，< 1.0 表示性能下降")
    
    return table.concat(report, "\n")
end

-- 保存报告到文件
function BenchmarkPlugin:saveReport(report, suffix)
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = string.format("rendertext_benchmark_%s%s.txt", 
        suffix and (suffix .. "_") or "", timestamp)
    local filepath = DataStorage:getDataDir() .. "/" .. filename
    
    local file = io.open(filepath, "w")
    if file then
        file:write(report)
        file:close()
        logger.info("基准测试报告已保存至: " .. filepath)
        self.last_report_path = filepath
        return true
    else
        logger.err("无法保存基准测试报告至: " .. filepath)
        return false
    end
end

-- 显示报告摘要
function BenchmarkPlugin:showReportSummary(results)
    if #results < 2 then
        UIManager:show(InfoMessage:new{
            text = "测试结果不足，无法生成摘要"
        })
        return
    end
    
    local summary_lines = {"基于时间的性能测试完成！\n"}
    
    -- 计算平均性能比率
    local size_ratios = {}
    local render_ratios = {}
    
    for i = 1, #results, 2 do
        local old_result = results[i]
        local new_result = results[i + 1]
        
        if old_result and new_result then
            table.insert(size_ratios, new_result.size_chars_per_sec / math.max(old_result.size_chars_per_sec, 1))
            table.insert(render_ratios, new_result.render_chars_per_sec / math.max(old_result.render_chars_per_sec, 1))
        end
    end
    
    if #size_ratios > 0 then
        local avg_size = 0
        local avg_render = 0
        
        for _, ratio in ipairs(size_ratios) do
            avg_size = avg_size + ratio
        end
        avg_size = avg_size / #size_ratios
        
        for _, ratio in ipairs(render_ratios) do
            avg_render = avg_render + ratio
        end
        avg_render = avg_render / #render_ratios
        
        table.insert(summary_lines, string.format("尺寸计算吞吐量: %.2fx", avg_size))
        table.insert(summary_lines, string.format("渲染吞吐量: %.2fx", avg_render))
        table.insert(summary_lines, string.format("平均性能: %.2fx", (avg_size + avg_render) / 2))
        table.insert(summary_lines, "\n详细报告已保存")
    end
    
    UIManager:show(InfoMessage:new{
        text = table.concat(summary_lines, "\n"),
        timeout = 8,
    })
end

-- 查看最新报告
function BenchmarkPlugin:viewLatestReport()
    local report_path = DataStorage:getDataDir() .. "/render_benchmark_latest.txt"
    local file = io.open(report_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        UIManager:show(InfoMessage:new{
            text = content,
            timeout = 10,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("未找到测试报告文件"),
            timeout = 3,
        })
    end
end

-- 显示优化状态
function BenchmarkPlugin:showOptimizationStatus()
    local modules = self:getRenderModules()
    local status_text = "RenderTextFast 状态报告\n\n"
    
    -- 尝试直接加载模块进行诊断
    local load_ok, RenderTextFast = pcall(require, "ui/rendertext_fast")
    status_text = status_text .. "🔍 诊断信息:\n"
    status_text = status_text .. string.format("  模块加载: %s\n", load_ok and "成功" or "失败")
    
    if load_ok and RenderTextFast then
        status_text = status_text .. "  模块类型: " .. type(RenderTextFast) .. "\n"
        if type(RenderTextFast.isOptimizationsEnabled) == "function" then
            local enabled_ok, enabled = pcall(RenderTextFast.isOptimizationsEnabled, RenderTextFast)
            status_text = status_text .. string.format("  状态查询: %s\n", enabled_ok and "成功" or "失败")
            if enabled_ok then
                status_text = status_text .. string.format("  优化状态: %s\n", enabled and "启用" or "禁用")
            end
        else
            status_text = status_text .. "  状态查询方法: 不存在\n"
        end
    else
        local error_msg = tostring(RenderTextFast or "未知错误")
        status_text = status_text .. "  错误信息: " .. error_msg .. "\n"
    end
    status_text = status_text .. "\n"
    
    if not modules or not modules.new then
        status_text = status_text .. "❌ RenderTextFast 模块不可用\n"
    else
        if modules.new.isOptimizationsEnabled then
            local enabled = modules.new:isOptimizationsEnabled()
            status_text = status_text .. "✅ RenderTextFast 模块已加载\n"
            status_text = status_text .. "🔧 优化状态: " .. (enabled and "已启用" or "已禁用") .. "\n\n"
            
            if enabled and modules.new.getPerformanceStats then
                local stats = modules.new:getPerformanceStats()
                status_text = status_text .. "📊 性能统计:\n"
                status_text = status_text .. string.format("  尺寸缓存命中率: %.1f%%\n", stats.size_cache.hit_rate)
                status_text = status_text .. string.format("  尺寸缓存大小: %d 条记录\n", stats.size_cache.size)
                status_text = status_text .. string.format("  字形缓存大小: %d 条记录\n", stats.glyph_cache.size)
                status_text = status_text .. string.format("  快速路径使用: %d 次\n", stats.paths.fast_path_used)
                status_text = status_text .. string.format("  回退使用: %d 次\n", stats.paths.fallback_used)
                
                if modules.new.getMemoryUsage then
                    local memory = modules.new:getMemoryUsage()
                    status_text = status_text .. string.format("\n💾 内存使用: %d KB\n", memory.total_kb)
                end
            end
        else
            status_text = status_text .. "❌ RenderTextFast 不支持状态查询\n"
        end
    end
    
    UIManager:show(InfoMessage:new{
        text = status_text,
        timeout = 10,
    })
end
-- AIGC END

return BenchmarkPlugin 