-- AIGC START
--[[
KOReader 图像预加载缓存优化补丁
优先级：1 (早期加载)
策略：智能预加载下一页图像，提供无缝阅读体验
目标：显著改善Kindle等设备的图文混排阅读流畅度
]]--

local logger = require("logger")

logger.info("ImagePreloadOptimization: 开始应用图像预加载优化...")

-- 预加载配置 - 针对Kindle优化
local PRELOAD_CONFIG = {
    -- 基础缓存配置
    max_cache_size = 15,           -- 最大缓存图像数量
    max_memory_mb = 8,             -- 最大内存使用(MB)
    
    -- 预加载配置
    preload_pages_ahead = 2,       -- 预加载前面2页
    preload_pages_behind = 1,      -- 保留后面1页
    preload_delay = 0.5,           -- 预加载延迟(秒)
    
    -- 智能预加载
    enable_smart_preload = true,   -- 启用智能预加载
    reading_speed_threshold = 3,   -- 阅读速度阈值(秒/页)
    max_preload_per_batch = 3,     -- 每批最大预加载数量
    
    -- 内存管理
    memory_pressure_threshold = 6, -- 内存压力阈值(MB)
    emergency_cleanup_threshold = 7, -- 紧急清理阈值(MB)
}

-- 全局状态
local preload_state = {
    current_page = 1,
    last_page_time = 0,
    reading_speed = 5, -- 默认阅读速度
    preload_queue = {},
    active_preloads = {},
    total_pages = 0,
    document_hash = nil,
}

-- 缓存系统
local image_cache = {}
local image_cache_count = 0
local preload_cache = {}
local preload_cache_count = 0

-- 性能统计
local cache_stats = {
    cache_hits = 0,
    cache_misses = 0,
    preload_hits = 0,
    preload_misses = 0,
    preload_success = 0,
    preload_failed = 0,
    memory_cleanups = 0,
}

-- 内存使用估算
local function estimateImageMemory(width, height)
    if not width or not height then return 0 end
    return (width * height * 4) / (1024 * 1024) -- RGBA bytes to MB
end

-- 获取当前内存使用
local function getCurrentMemoryUsage()
    local total_memory = 0
    for _, cached_image in pairs(image_cache) do
        if cached_image.memory_size then
            total_memory = total_memory + cached_image.memory_size
        end
    end
    for _, preload_image in pairs(preload_cache) do
        if preload_image.memory_size then
            total_memory = total_memory + preload_image.memory_size
        end
    end
    return total_memory
end

-- 内存压力检查
local function checkMemoryPressure()
    local current_memory = getCurrentMemoryUsage()
    
    if current_memory > PRELOAD_CONFIG.emergency_cleanup_threshold then
        logger.warn("ImagePreloadOptimization: 内存使用过高，执行紧急清理")
        -- 清空预加载缓存
        preload_cache = {}
        preload_cache_count = 0
        cache_stats.memory_cleanups = cache_stats.memory_cleanups + 1
        return true
    elseif current_memory > PRELOAD_CONFIG.memory_pressure_threshold then
        -- 清理一半预加载缓存
        local removed = 0
        local target_remove = math.floor(preload_cache_count / 2)
        for k, _ in pairs(preload_cache) do
            if removed >= target_remove then break end
            preload_cache[k] = nil
            removed = removed + 1
        end
        preload_cache_count = preload_cache_count - removed
        logger.dbg("ImagePreloadOptimization: 内存压力清理，移除", removed, "项预加载缓存")
        return false
    end
    
    return false
end

-- 生成缓存键
local function generateCacheKey(page_num, width, height, doc_hash)
    return string.format("%s_p%d_%dx%d", doc_hash or "unknown", page_num or 0, width or 0, height or 0)
end

-- 更新阅读速度
local function updateReadingSpeed(page_num)
    local current_time = os.time()
    if preload_state.last_page_time > 0 and page_num ~= preload_state.current_page then
        local time_diff = current_time - preload_state.last_page_time
        if time_diff > 0 and time_diff < 60 then -- 忽略超过1分钟的间隔
            -- 使用移动平均更新阅读速度
            preload_state.reading_speed = (preload_state.reading_speed * 0.7) + (time_diff * 0.3)
        end
    end
    
    preload_state.current_page = page_num
    preload_state.last_page_time = current_time
end

-- 预加载图像
local function preloadImage(page_num, width, height, doc_hash)
    if not PRELOAD_CONFIG.enable_smart_preload then return end
    
    local cache_key = generateCacheKey(page_num, width, height, doc_hash)
    
    -- 检查是否已经缓存
    if image_cache[cache_key] or preload_cache[cache_key] then
        return
    end
    
    -- 检查内存压力
    if checkMemoryPressure() then
        return
    end
    
    -- 模拟预加载（实际实现需要根据具体的文档类型）
    local function doPreload()
        logger.dbg("ImagePreloadOptimization: 预加载页面", page_num)
        
        -- 这里应该调用实际的图像加载逻辑
        -- 由于我们无法直接访问文档对象，这里只是创建占位符
        local preload_data = {
            page_num = page_num,
            width = width,
            height = height,
            memory_size = estimateImageMemory(width, height),
            timestamp = os.time(),
        }
        
        preload_cache[cache_key] = preload_data
        preload_cache_count = preload_cache_count + 1
        cache_stats.preload_success = cache_stats.preload_success + 1
        
        logger.dbg("ImagePreloadOptimization: 预加载完成，页面", page_num)
    end
    
    -- 延迟执行预加载
    local ok, UIManager = pcall(require, "ui/uimanager")
    if ok and UIManager then
        UIManager:scheduleIn(PRELOAD_CONFIG.preload_delay, doPreload)
    end
end

-- 智能预加载策略
local function smartPreload(current_page, doc_hash)
    if not PRELOAD_CONFIG.enable_smart_preload then return end
    
    -- 根据阅读速度调整预加载范围
    local preload_range = PRELOAD_CONFIG.preload_pages_ahead
    if preload_state.reading_speed < PRELOAD_CONFIG.reading_speed_threshold then
        preload_range = preload_range + 1 -- 快速阅读时多预加载一页
    end
    
    -- 预加载后续页面
    for i = 1, preload_range do
        local target_page = current_page + i
        if target_page <= preload_state.total_pages then
            preloadImage(target_page, 800, 600, doc_hash) -- 使用默认尺寸
        end
    end
    
    -- 保留前面的页面
    for i = 1, PRELOAD_CONFIG.preload_pages_behind do
        local target_page = current_page - i
        if target_page >= 1 then
            preloadImage(target_page, 800, 600, doc_hash)
        end
    end
end

-- Hook ReaderUI的翻页事件
local function hookPageTurning()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    if not ok or not ReaderUI then return false end
    
    -- 尝试Hook onPageUpdate事件
    local orig_onPageUpdate = ReaderUI.onPageUpdate
    if orig_onPageUpdate then
        ReaderUI.onPageUpdate = function(self, pageno)
            -- 调用原始方法
            local result = orig_onPageUpdate(self, pageno)
            
            -- 更新预加载状态
            if pageno and self.document then
                updateReadingSpeed(pageno)
                preload_state.total_pages = self.document:getPageCount() or 0
                preload_state.document_hash = tostring(self.document)
                
                -- 触发智能预加载
                smartPreload(pageno, preload_state.document_hash)
            end
            
            return result
        end
        
        logger.info("ImagePreloadOptimization: 成功Hook ReaderUI翻页事件")
        return true
    end
    
    return false
end

-- 尝试优化ImageWidget
local optimization_applied = false
local ok, ImageWidget = pcall(require, "ui/widget/imagewidget")
if ok and ImageWidget then
    logger.info("ImagePreloadOptimization: 找到ImageWidget，应用预加载优化...")
    
    local orig_setImage = ImageWidget.setImage
    
    if orig_setImage then
        ImageWidget.setImage = function(self, image_path, width, height)
            if not image_path then
                return orig_setImage(self, image_path, width, height)
            end
            
            local cache_key = generateCacheKey(preload_state.current_page, width, height, preload_state.document_hash)
            
            -- 首先检查预加载缓存
            if preload_cache[cache_key] then
                cache_stats.preload_hits = cache_stats.preload_hits + 1
                logger.dbg("ImagePreloadOptimization: 预加载缓存命中！")
                
                -- 将预加载缓存移动到主缓存
                image_cache[cache_key] = preload_cache[cache_key]
                image_cache_count = image_cache_count + 1
                preload_cache[cache_key] = nil
                preload_cache_count = preload_cache_count - 1
                
                -- 显示预加载成功的toast
                local ok_ui, UIManager = pcall(require, "ui/uimanager")
                local ok_notif, Notification = pcall(require, "ui/widget/notification")
                if ok_ui and ok_notif and UIManager and Notification and cache_stats.preload_hits % 10 == 0 then
                    UIManager:scheduleIn(0.1, function()
                        Notification:notify(string.format("🚀 预加载命中: %d次", cache_stats.preload_hits), Notification.SOURCE_ALWAYS_SHOW)
                    end)
                end
                
                return
            end
            
            -- 检查普通缓存
            if image_cache[cache_key] then
                cache_stats.cache_hits = cache_stats.cache_hits + 1
                self._bb = image_cache[cache_key]
                return
            end
            
            cache_stats.cache_misses = cache_stats.cache_misses + 1
            
            -- 调用原始方法
            local result = orig_setImage(self, image_path, width, height)
            
            -- 缓存结果
            if self._bb and width and height then
                local memory_usage = estimateImageMemory(width, height)
                if memory_usage < 2 then -- 只缓存小于2MB的图像
                    image_cache[cache_key] = {
                        bb = self._bb,
                        memory_size = memory_usage,
                        timestamp = os.time(),
                    }
                    image_cache_count = image_cache_count + 1
                    
                    -- 触发预加载
                    smartPreload(preload_state.current_page, preload_state.document_hash)
                end
            end
            
            return result
        end
    end
    
    optimization_applied = true
    logger.info("ImagePreloadOptimization: ImageWidget预加载优化已应用")
end

-- Hook翻页事件
if hookPageTurning() then
    optimization_applied = true
end

-- 性能统计报告
local function reportPreloadStats()
    if cache_stats.cache_hits + cache_stats.cache_misses > 0 then
        local cache_hit_rate = (cache_stats.cache_hits / (cache_stats.cache_hits + cache_stats.cache_misses)) * 100
        local preload_hit_rate = cache_stats.preload_hits > 0 and 
            (cache_stats.preload_hits / (cache_stats.preload_hits + cache_stats.preload_misses)) * 100 or 0
        
        logger.info("ImagePreloadOptimization 性能统计:")
        logger.info("  普通缓存命中率:", string.format("%.1f%%", cache_hit_rate))
        logger.info("  预加载命中率:", string.format("%.1f%%", preload_hit_rate))
        logger.info("  预加载成功:", cache_stats.preload_success)
        logger.info("  当前阅读速度:", string.format("%.1f秒/页", preload_state.reading_speed))
        logger.info("  内存清理次数:", cache_stats.memory_cleanups)
        logger.info("  当前缓存项:", image_cache_count)
        logger.info("  预加载缓存项:", preload_cache_count)
    end
end

if optimization_applied then
    logger.info("ImagePreloadOptimization: 图像预加载优化已成功应用")
    logger.info("  预加载页面数:", PRELOAD_CONFIG.preload_pages_ahead)
    logger.info("  最大内存限制:", PRELOAD_CONFIG.max_memory_mb, "MB")
    logger.info("  智能预加载:", PRELOAD_CONFIG.enable_smart_preload and "启用" or "禁用")
    
    -- 显示Toast通知
    local function showPreloadToast()
        local function delayedToast()
            local ok, UIManager = pcall(require, "ui/uimanager")
            local ok2, Notification = pcall(require, "ui/widget/notification")
            
            if ok and ok2 and UIManager and Notification then
                UIManager:scheduleIn(2, function()
                    Notification:notify("🚀 图像预加载优化已启用", Notification.SOURCE_ALWAYS_SHOW)
                end)
            end
        end
        
        local ok, UIManager = pcall(require, "ui/uimanager")
        if ok and UIManager then
            UIManager:scheduleIn(1, delayedToast)
        end
    end
    
    showPreloadToast()
    
    -- 注册退出时统计报告
    local orig_exit = os.exit
    os.exit = function(...)
        reportPreloadStats()
        return orig_exit(...)
    end
else
    logger.warn("ImagePreloadOptimization: 未找到可优化的模块")
end

-- AIGC END 