-- AIGC START
--[[
KOReader 优化状态检查器
优先级：9 (退出前运行，用于验证优化效果)
功能：检查和报告所有优化补丁的状态和效果
]]--

local logger = require("logger")

logger.info("OptimizationStatusChecker: 启动优化状态检查器...")

-- 延迟执行状态检查
local function performStatusCheck()
    logger.info("=== KOReader 优化状态检查报告 ===")
    
    -- 1. 检查安全优化加载器状态
    local safe_loader_active = false
    local text_optimization_active = false
    local image_optimization_active = false
    
    -- 检查RenderText是否被Hook
    local ok, RenderText = pcall(require, "ui/rendertext")
    if ok and RenderText then
        -- 检查sizeUtf8Text方法是否被修改
        local func_str = tostring(RenderText.sizeUtf8Text)
        if func_str:find("text_stats") or func_str:find("cache_key") then
            text_optimization_active = true
            logger.info("✅ 文本渲染优化: 已激活")
        else
            logger.info("❌ 文本渲染优化: 未激活")
        end
    else
        logger.info("❌ RenderText模块: 无法访问")
    end
    
    -- 检查ImageWidget是否被Hook
    local ok2, ImageWidget = pcall(require, "ui/widget/imagewidget")
    if ok2 and ImageWidget then
        local func_str = tostring(ImageWidget.setImage)
        if func_str:find("image_stats") or func_str:find("cache_key") then
            image_optimization_active = true
            logger.info("✅ 图像缓存优化: 已激活")
        else
            logger.info("❌ 图像缓存优化: 未激活")
        end
    else
        logger.info("❌ ImageWidget模块: 无法访问")
    end
    
    -- 2. 检查轻量级图文优化状态
    local lite_optimizer_active = false
    local lite_textbox_hooked = false
    
    -- 检查全局实例
    if _G.ImageTextOptimizerLite then
        lite_optimizer_active = true
        logger.info("✅ 轻量级图文优化器: 已加载")
        
        -- 检查是否启用
        if _G.ImageTextOptimizerLite.enabled then
            logger.info("✅ 轻量级优化: 已启用")
        else
            logger.info("⚠️  轻量级优化: 已加载但未启用")
        end
        
        -- 检查全局控制函数
        local lite_control_functions = {
            "ImageTextOptimizerLite_toggle",
            "ImageTextOptimizerLite_enable", 
            "ImageTextOptimizerLite_disable",
            "ImageTextOptimizerLite_stats",
            "ImageTextOptimizerLite_clear"
        }
        
        local available_lite_functions = 0
        for _, func_name in ipairs(lite_control_functions) do
            if _G[func_name] then
                available_lite_functions = available_lite_functions + 1
            end
        end
        
        logger.info("✅ 轻量级控制函数: " .. available_lite_functions .. "/" .. #lite_control_functions .. " 可用")
        
        -- 尝试获取性能统计
        if _G.ImageTextOptimizerLite_stats then
            local ok_stats, stats_result = pcall(_G.ImageTextOptimizerLite_stats)
            if ok_stats then
                logger.info("✅ 轻量级性能统计: 可获取")
            end
        end
    else
        logger.info("❌ 轻量级图文优化器: 未加载")
    end
    
    -- 检查TextBoxWidget是否被Hook
    local ok3, TextBoxWidget = pcall(require, "ui/widget/textboxwidget")
    if ok3 and TextBoxWidget then
        if TextBoxWidget._original_paintTo_lite then
            lite_textbox_hooked = true
            logger.info("✅ TextBoxWidget Hook: 已应用")
        else
            logger.info("❌ TextBoxWidget Hook: 未应用")
        end
    else
        logger.info("❌ TextBoxWidget模块: 无法访问")
    end
    
    -- 3. 检查完整版文本优化状态
    local rendertext_fast_active = false
    if _G.RenderTextFast then
        rendertext_fast_active = true
        logger.info("✅ RenderTextFast模块: 已加载")
        
        -- 检查全局控制函数
        local control_functions = {
            "RenderTextFast_status",
            "RenderTextFast_toggle", 
            "RenderTextFast_enable",
            "RenderTextFast_disable",
            "RenderTextFast_clear_cache"
        }
        
        local available_functions = 0
        for _, func_name in ipairs(control_functions) do
            if _G[func_name] then
                available_functions = available_functions + 1
            end
        end
        
        logger.info("✅ 控制函数: " .. available_functions .. "/" .. #control_functions .. " 可用")
        
        -- 尝试获取性能统计
        if _G.RenderTextFast_status then
            local ok_status, status_result = pcall(_G.RenderTextFast_status)
            if ok_status and status_result then
                logger.info("✅ 性能统计: 可获取")
            end
        end
    else
        logger.info("❌ RenderTextFast模块: 未加载")
    end
    
    -- 4. 检查补丁执行状态
    local userpatch = require("userpatch")
    if userpatch and userpatch.execution_status then
        logger.info("📊 补丁执行状态:")
        local executed_count = 0
        local failed_count = 0
        
        for patch_name, status in pairs(userpatch.execution_status) do
            if status == true then
                executed_count = executed_count + 1
                logger.info("  ✅ " .. patch_name .. ": 执行成功")
            elseif status == false then
                failed_count = failed_count + 1
                logger.info("  ❌ " .. patch_name .. ": 执行失败")
            end
        end
        
        logger.info("📈 总计: " .. executed_count .. " 成功, " .. failed_count .. " 失败")
    end
    
    -- 5. 生成总体状态报告
    local total_optimizations = 0
    local active_optimizations = 0
    
    if text_optimization_active then active_optimizations = active_optimizations + 1 end
    if image_optimization_active then active_optimizations = active_optimizations + 1 end
    if rendertext_fast_active then active_optimizations = active_optimizations + 1 end
    if lite_optimizer_active and lite_textbox_hooked then active_optimizations = active_optimizations + 1 end
    total_optimizations = 4  -- 增加轻量级优化
    
    logger.info("🎯 优化状态总结:")
    logger.info("  激活的优化: " .. active_optimizations .. "/" .. total_optimizations)
    
    if active_optimizations == 0 then
        logger.warn("⚠️  警告: 没有检测到任何优化模块激活!")
        logger.info("💡 建议检查:")
        logger.info("  1. 补丁文件是否在正确的目录")
        logger.info("  2. 补丁文件命名是否正确")
        logger.info("  3. 查看启动日志中的错误信息")
    elseif active_optimizations < total_optimizations then
        logger.info("⚠️  部分优化未激活，这可能是正常的")
    else
        logger.info("🎉 所有优化模块都已激活!")
    end
    
    -- 6. 提供用户操作指南
    logger.info("🔧 用户操作指南:")
    if rendertext_fast_active then
        logger.info("  • 查看详细状态: RenderTextFast_status()")
        logger.info("  • 切换优化: RenderTextFast_toggle()")
        logger.info("  • 清理缓存: RenderTextFast_clear_cache()")
    end
    
    if lite_optimizer_active then
        logger.info("  • 轻量级优化统计: ImageTextOptimizerLite_stats()")
        logger.info("  • 切换轻量级优化: ImageTextOptimizerLite_toggle()")
        logger.info("  • 清理轻量级缓存: ImageTextOptimizerLite_clear()")
    end
    
    if text_optimization_active or image_optimization_active then
        logger.info("  • 优化效果会在使用过程中通过Toast通知显示")
        logger.info("  • 文本优化: 每100次缓存命中显示一次")
        logger.info("  • 图像优化: 每20次缓存命中显示一次")
    end
    
    logger.info("================================")
end

-- 安排状态检查
local function scheduleStatusCheck()
    local ok, UIManager = pcall(require, "ui/uimanager")
    if ok and UIManager then
        -- 在启动后5秒执行检查
        UIManager:scheduleIn(5, performStatusCheck)
        logger.info("OptimizationStatusChecker: 已安排5秒后执行状态检查")
    else
        -- 备用方案：立即执行
        logger.info("OptimizationStatusChecker: UIManager不可用，立即执行检查")
        performStatusCheck()
    end
end

-- 启动检查
scheduleStatusCheck()

-- 同时在退出时也执行一次检查
local orig_exit = os.exit
os.exit = function(...)
    logger.info("OptimizationStatusChecker: 应用退出时执行最终状态检查")
    performStatusCheck()
    return orig_exit(...)
end

logger.info("OptimizationStatusChecker: 状态检查器已启动")

-- AIGC END 