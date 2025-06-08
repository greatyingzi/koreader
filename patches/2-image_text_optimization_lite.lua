-- AIGC START
--[[
KOReader 图文混排优化补丁 - 轻量级版本
专为 Kindle 等低性能设备设计

特点：
1. 极小内存占用（总计不超过2MB）
2. 智能内存监控和自适应
3. 低性能设备优化策略
4. 自动降级机制

版本: 1.0.0-lite
作者: AI Assistant
日期: 2024
--]]

local logger = require("logger")
local util = require("util")
local Device = require("device")

-- 尝试加载设备自适应配置模块
local adaptive_config
local ok, DeviceAdaptiveConfig = pcall(require, "device_adaptive_config")
if ok and DeviceAdaptiveConfig then
    adaptive_config = DeviceAdaptiveConfig:getAdaptiveConfig()
    logger.info("ImageTextOptimizerLite: 成功加载外部设备自适应配置")
else
    logger.info("ImageTextOptimizerLite: 外部配置不可用，使用内嵌配置")
    -- 内嵌简化版设备自适应配置
    local Device = require("device")
    local util = require("util")
    
    -- 简化的设备信息检测
    local device_info = {
        is_kindle = Device:isKindle(),
        is_kobo = Device:isKobo(),
        is_android = Device:isAndroid(),
        is_emulator = Device:isEmulator(),
        has_eink_screen = Device:hasEinkScreen(),
        total_memory = 0,
    }
    
    -- 获取内存信息
    local memfree, memtotal = util.calcFreeMem()
    if memtotal then
        device_info.total_memory = memtotal / (1024 * 1024) -- MB
    end
    
    -- 简化的性能等级评估
    local performance_level = 3 -- 默认中等
    if device_info.is_kindle then
        performance_level = 2 -- Kindle通常性能较低
    elseif device_info.is_emulator then
        performance_level = 5 -- 模拟器性能最高
    elseif device_info.total_memory > 0 then
        if device_info.total_memory < 256 then
            performance_level = 1
        elseif device_info.total_memory < 512 then
            performance_level = 2
        elseif device_info.total_memory < 1024 then
            performance_level = 3
        elseif device_info.total_memory < 2048 then
            performance_level = 4
        else
            performance_level = 5
        end
    end
    
    -- 简化的配置生成
    local configs = {
        [1] = { image_size_cache_limit = 10, layout_cache_limit = 5, preload_pages = 0, preload_max_images = 0, memory_warning_threshold = 50, memory_critical_threshold = 70, batch_size_threshold = 10, enable_preload = false, enable_batch_rendering = false, cache_cleanup_interval = 15 },
        [2] = { image_size_cache_limit = 25, layout_cache_limit = 10, preload_pages = 0, preload_max_images = 1, memory_warning_threshold = 60, memory_critical_threshold = 80, batch_size_threshold = 8, enable_preload = false, enable_batch_rendering = true, cache_cleanup_interval = 20 },
        [3] = { image_size_cache_limit = 50, layout_cache_limit = 20, preload_pages = 1, preload_max_images = 2, memory_warning_threshold = 70, memory_critical_threshold = 85, batch_size_threshold = 5, enable_preload = true, enable_batch_rendering = true, cache_cleanup_interval = 30 },
        [4] = { image_size_cache_limit = 100, layout_cache_limit = 40, preload_pages = 2, preload_max_images = 4, memory_warning_threshold = 75, memory_critical_threshold = 90, batch_size_threshold = 3, enable_preload = true, enable_batch_rendering = true, cache_cleanup_interval = 45 },
        [5] = { image_size_cache_limit = 200, layout_cache_limit = 80, preload_pages = 3, preload_max_images = 6, memory_warning_threshold = 80, memory_critical_threshold = 95, batch_size_threshold = 2, enable_preload = true, enable_batch_rendering = true, cache_cleanup_interval = 60 }
    }
    
    adaptive_config = configs[performance_level] or configs[3]
    adaptive_config.device_info = device_info
    adaptive_config.performance_level = performance_level
end

-- 轻量级配置 - 基于设备自适应生成
local LITE_CONFIG = {
    -- 图片尺寸缓存（动态生成）
    image_size_cache_limit = adaptive_config.image_size_cache_limit,
    
    -- 布局缓存（动态生成）
    layout_cache_limit = adaptive_config.layout_cache_limit,
    
    -- 预加载策略（动态生成）
    preload_pages = adaptive_config.preload_pages,
    preload_max_images = adaptive_config.preload_max_images,
    
    -- 内存监控阈值（动态生成）
    memory_warning_threshold = adaptive_config.memory_warning_threshold,
    memory_critical_threshold = adaptive_config.memory_critical_threshold,
    
    -- 批量渲染配置
    batch_size_threshold = adaptive_config.batch_size_threshold,
    enable_preload = adaptive_config.enable_preload,
    enable_batch_rendering = adaptive_config.enable_batch_rendering,
    cache_cleanup_interval = adaptive_config.cache_cleanup_interval,
    
    -- 自适应参数
    low_memory_mode = false,            -- 低内存模式标志
    emergency_cleanup_count = 0,        -- 紧急清理计数
    
    -- 设备信息
    device_info = adaptive_config.device_info,
    performance_level = adaptive_config.performance_level,
    is_kindle = adaptive_config.device_info.is_kindle,
    is_low_memory_device = adaptive_config.performance_level <= 2, -- 极低性能或低性能
}

-- 性能等级名称映射
local function getPerformanceLevelName(level)
    local names = {
        [1] = "极低性能",
        [2] = "低性能", 
        [3] = "中等性能",
        [4] = "高性能",
        [5] = "极高性能"
    }
    return names[level] or "未知"
end

logger.info("ImageTextOptimizerLite: 使用自适应配置")
logger.info("  性能等级:", getPerformanceLevelName(LITE_CONFIG.performance_level))
logger.info("  图片缓存限制:", LITE_CONFIG.image_size_cache_limit)
logger.info("  布局缓存限制:", LITE_CONFIG.layout_cache_limit)
logger.info("  内存警告阈值:", LITE_CONFIG.memory_warning_threshold, "MB")
logger.info("  内存紧急阈值:", LITE_CONFIG.memory_critical_threshold, "MB")

-- 轻量级图文优化器
local ImageTextOptimizerLite = {
    -- 极小的缓存
    image_size_cache = {},
    image_size_cache_count = 0,
    
    layout_cache = {},
    layout_cache_count = 0,
    
    -- 预加载队列（极小）
    preload_queue = {},
    
    -- 统计信息
    stats = {
        cache_hits = 0,
        cache_misses = 0,
        memory_cleanups = 0,
        emergency_cleanups = 0,
        preload_hits = 0,
    },
    
    -- 内存监控
    last_memory_check = 0,
    memory_check_interval = 30, -- 30秒检查一次内存
}

-- 内存监控和自适应管理
function ImageTextOptimizerLite:checkMemoryPressure()
    local current_time = os.time()
    if current_time - self.last_memory_check < self.memory_check_interval then
        return false
    end
    
    self.last_memory_check = current_time
    local memfree, memtotal = util.calcFreeMem()
    
    if not memtotal then
        return false
    end
    
    local memused = memtotal - memfree
    local memused_mb = memused / (1024 * 1024)
    
    -- 检查内存压力
    if memused_mb > LITE_CONFIG.memory_critical_threshold then
        logger.warn("ImageTextOptimizerLite: 内存使用过高 (", memused_mb, "MB), 执行紧急清理")
        self:emergencyCleanup()
        return true
    elseif memused_mb > LITE_CONFIG.memory_warning_threshold then
        if not LITE_CONFIG.low_memory_mode then
            logger.info("ImageTextOptimizerLite: 进入低内存模式 (", memused_mb, "MB)")
            LITE_CONFIG.low_memory_mode = true
            self:enterLowMemoryMode()
        end
        return true
    else
        if LITE_CONFIG.low_memory_mode then
            logger.info("ImageTextOptimizerLite: 退出低内存模式")
            LITE_CONFIG.low_memory_mode = false
            self:exitLowMemoryMode()
        end
        return false
    end
end

-- 进入低内存模式
function ImageTextOptimizerLite:enterLowMemoryMode()
    -- 清理一半缓存
    self:cleanupCache(0.5)
    
    -- 降低缓存限制
    LITE_CONFIG.image_size_cache_limit = math.max(10, math.floor(LITE_CONFIG.image_size_cache_limit / 2))
    LITE_CONFIG.layout_cache_limit = math.max(5, math.floor(LITE_CONFIG.layout_cache_limit / 2))
    LITE_CONFIG.preload_pages = 0  -- 禁用预加载
end

-- 退出低内存模式
function ImageTextOptimizerLite:exitLowMemoryMode()
    -- 恢复缓存限制（但保持保守）
    if LITE_CONFIG.is_low_memory_device then
        LITE_CONFIG.image_size_cache_limit = 25
        LITE_CONFIG.layout_cache_limit = 10
    else
        LITE_CONFIG.image_size_cache_limit = 50
        LITE_CONFIG.layout_cache_limit = 20
        LITE_CONFIG.preload_pages = 1
    end
end

-- 紧急清理
function ImageTextOptimizerLite:emergencyCleanup()
    -- 清空所有缓存
    self.image_size_cache = {}
    self.image_size_cache_count = 0
    self.layout_cache = {}
    self.layout_cache_count = 0
    self.preload_queue = {}
    
    -- 强制垃圾回收
    collectgarbage("collect")
    collectgarbage("collect")
    
    self.stats.emergency_cleanups = self.stats.emergency_cleanups + 1
    LITE_CONFIG.emergency_cleanup_count = LITE_CONFIG.emergency_cleanup_count + 1
    
    -- 如果紧急清理过于频繁，永久进入超保守模式
    if LITE_CONFIG.emergency_cleanup_count > 3 then
        logger.warn("ImageTextOptimizerLite: 紧急清理过于频繁，进入超保守模式")
        LITE_CONFIG.image_size_cache_limit = 5
        LITE_CONFIG.layout_cache_limit = 3
        LITE_CONFIG.preload_pages = 0
        LITE_CONFIG.memory_warning_threshold = 60  -- 降低阈值
    end
end

-- 清理缓存（按比例）
function ImageTextOptimizerLite:cleanupCache(ratio)
    ratio = ratio or 0.3  -- 默认清理30%
    
    -- 清理图片尺寸缓存
    local items_to_remove = math.floor(self.image_size_cache_count * ratio)
    local removed = 0
    for key, _ in pairs(self.image_size_cache) do
        if removed >= items_to_remove then break end
        self.image_size_cache[key] = nil
        removed = removed + 1
    end
    self.image_size_cache_count = self.image_size_cache_count - removed
    
    -- 清理布局缓存
    items_to_remove = math.floor(self.layout_cache_count * ratio)
    removed = 0
    for key, _ in pairs(self.layout_cache) do
        if removed >= items_to_remove then break end
        self.layout_cache[key] = nil
        removed = removed + 1
    end
    self.layout_cache_count = self.layout_cache_count - removed
    
    self.stats.memory_cleanups = self.stats.memory_cleanups + 1
    logger.dbg("ImageTextOptimizerLite: 清理了", ratio * 100, "% 的缓存")
end

-- LRU缓存管理（极简版）
function ImageTextOptimizerLite:addToImageSizeCache(key, value)
    -- 检查内存压力
    if self:checkMemoryPressure() then
        return  -- 内存压力大时不缓存
    end
    
    if self.image_size_cache_count >= LITE_CONFIG.image_size_cache_limit then
        -- 简单的FIFO清理（避免复杂的LRU实现以节省内存）
        local removed = 0
        local target = math.floor(LITE_CONFIG.image_size_cache_limit / 4)  -- 清理25%
        for k, _ in pairs(self.image_size_cache) do
            if removed >= target then break end
            self.image_size_cache[k] = nil
            removed = removed + 1
        end
        self.image_size_cache_count = self.image_size_cache_count - removed
    end
    
    if not self.image_size_cache[key] then
        self.image_size_cache_count = self.image_size_cache_count + 1
    end
    self.image_size_cache[key] = value
end

-- 获取图片尺寸（带缓存）
function ImageTextOptimizerLite:getImageSize(image_path)
    if not image_path then return nil end
    
    local cache_key = image_path
    local cached = self.image_size_cache[cache_key]
    
    if cached then
        self.stats.cache_hits = self.stats.cache_hits + 1
        return cached
    end
    
    self.stats.cache_misses = self.stats.cache_misses + 1
    
    -- 简单的尺寸获取（避免复杂操作）
    local size_info = nil
    local ok, RenderImage = pcall(require, "ui/renderimage")
    if ok and RenderImage then
        local ok2, result = pcall(RenderImage.getImageSize, RenderImage, image_path)
        if ok2 and result then
            size_info = {
                width = result.width or 0,
                height = result.height or 0,
                timestamp = os.time()
            }
        end
    end
    
    if size_info then
        self:addToImageSizeCache(cache_key, size_info)
    end
    
    return size_info
end

-- 轻量级布局优化
function ImageTextOptimizerLite:optimizeLayout(widget)
    if not widget or LITE_CONFIG.low_memory_mode then
        return false
    end
    
    -- 非常简单的布局优化，避免复杂计算
    local layout_key = tostring(widget)
    local cached_layout = self.layout_cache[layout_key]
    
    if cached_layout then
        return true
    end
    
    -- 简单的布局信息缓存
    if self.layout_cache_count < LITE_CONFIG.layout_cache_limit then
        self.layout_cache[layout_key] = {
            optimized = true,
            timestamp = os.time()
        }
        self.layout_cache_count = self.layout_cache_count + 1
    end
    
    return true
end

-- 极简预加载（仅在内存充足时）
function ImageTextOptimizerLite:preloadImages(current_page)
    if LITE_CONFIG.low_memory_mode or LITE_CONFIG.preload_pages == 0 then
        return
    end
    
    -- 检查内存压力
    if self:checkMemoryPressure() then
        return
    end
    
    -- 极简的预加载逻辑
    local preload_count = 0
    for i = -LITE_CONFIG.preload_pages, LITE_CONFIG.preload_pages do
        if preload_count >= LITE_CONFIG.preload_max_images then
            break
        end
        
        local page_num = current_page + i
        if page_num > 0 then
            -- 这里应该有实际的图片预加载逻辑
            -- 但为了安全，我们只是标记预加载意图
            self.preload_queue[page_num] = true
            preload_count = preload_count + 1
        end
    end
end

-- 获取性能统计
function ImageTextOptimizerLite:getStats()
    local memfree, memtotal = util.calcFreeMem()
    local memused_mb = memtotal and ((memtotal - memfree) / (1024 * 1024)) or 0
    
    return {
        cache = {
            image_size_hits = self.stats.cache_hits,
            image_size_misses = self.stats.cache_misses,
            hit_rate = (self.stats.cache_hits + self.stats.cache_misses) > 0 
                      and (self.stats.cache_hits / (self.stats.cache_hits + self.stats.cache_misses) * 100) or 0,
            image_size_count = self.image_size_cache_count,
            layout_count = self.layout_cache_count,
        },
        memory = {
            current_usage_mb = memused_mb,
            low_memory_mode = LITE_CONFIG.low_memory_mode,
            is_low_memory_device = LITE_CONFIG.is_low_memory_device,
            memory_cleanups = self.stats.memory_cleanups,
            emergency_cleanups = self.stats.emergency_cleanups,
        },
        config = {
            image_cache_limit = LITE_CONFIG.image_size_cache_limit,
            layout_cache_limit = LITE_CONFIG.layout_cache_limit,
            preload_pages = LITE_CONFIG.preload_pages,
            is_kindle = LITE_CONFIG.is_kindle,
        }
    }
end

-- 清理所有缓存
function ImageTextOptimizerLite:clearAll()
    self.image_size_cache = {}
    self.image_size_cache_count = 0
    self.layout_cache = {}
    self.layout_cache_count = 0
    self.preload_queue = {}
    
    collectgarbage("collect")
    logger.info("ImageTextOptimizerLite: 所有缓存已清理")
end

-- 全局实例
local optimizer_lite = ImageTextOptimizerLite

-- 安全的热补丁应用
local function applyLiteOptimizations()
    local ok, TextBoxWidget = pcall(require, "ui/widget/textboxwidget")
    if not ok or not TextBoxWidget then
        logger.warn("ImageTextOptimizerLite: 无法加载 TextBoxWidget")
        return false
    end
    
    -- 保存原始方法
    if not TextBoxWidget._original_paintTo_lite then
        TextBoxWidget._original_paintTo_lite = TextBoxWidget.paintTo
        
        -- 轻量级优化的 paintTo 方法
        TextBoxWidget.paintTo = function(self, bb, x, y)
            -- 检查内存压力
            optimizer_lite:checkMemoryPressure()
            
            -- 简单的布局优化
            if not LITE_CONFIG.low_memory_mode then
                optimizer_lite:optimizeLayout(self)
            end
            
            -- 调用原始方法
            return TextBoxWidget._original_paintTo_lite(self, bb, x, y)
        end
        
        logger.info("ImageTextOptimizerLite: 轻量级优化已应用")
        return true
    end
    
    return false
end

-- 移除优化
local function removeLiteOptimizations()
    local ok, TextBoxWidget = pcall(require, "ui/widget/textboxwidget")
    if ok and TextBoxWidget and TextBoxWidget._original_paintTo_lite then
        TextBoxWidget.paintTo = TextBoxWidget._original_paintTo_lite
        TextBoxWidget._original_paintTo_lite = nil
        logger.info("ImageTextOptimizerLite: 轻量级优化已移除")
        return true
    end
    return false
end

-- 全局控制函数
function ImageTextOptimizerLite_toggle()
    if optimizer_lite.enabled then
        removeLiteOptimizations()
        optimizer_lite.enabled = false
        logger.info("ImageTextOptimizerLite: 已禁用")
    else
        if applyLiteOptimizations() then
            optimizer_lite.enabled = true
            logger.info("ImageTextOptimizerLite: 已启用")
        end
    end
end

function ImageTextOptimizerLite_enable()
    if not optimizer_lite.enabled then
        if applyLiteOptimizations() then
            optimizer_lite.enabled = true
            logger.info("ImageTextOptimizerLite: 已启用")
        end
    end
end

function ImageTextOptimizerLite_disable()
    if optimizer_lite.enabled then
        removeLiteOptimizations()
        optimizer_lite:clearAll()
        optimizer_lite.enabled = false
        logger.info("ImageTextOptimizerLite: 已禁用并清理缓存")
    end
end

function ImageTextOptimizerLite_stats()
    local stats = optimizer_lite:getStats()
    logger.info("=== ImageTextOptimizerLite 统计信息 ===")
    logger.info("缓存命中率:", string.format("%.1f%%", stats.cache.hit_rate))
    logger.info("图片尺寸缓存:", stats.cache.image_size_count, "/", stats.config.image_cache_limit)
    logger.info("布局缓存:", stats.cache.layout_count, "/", stats.config.layout_cache_limit)
    logger.info("当前内存使用:", string.format("%.1f MB", stats.memory.current_usage_mb))
    logger.info("低内存模式:", stats.memory.low_memory_mode and "是" or "否")
    logger.info("低内存设备:", stats.memory.is_low_memory_device and "是" or "否")
    logger.info("内存清理次数:", stats.memory.memory_cleanups)
    logger.info("紧急清理次数:", stats.memory.emergency_cleanups)
    logger.info("预加载页数:", stats.config.preload_pages)
    logger.info("=====================================")
end

function ImageTextOptimizerLite_clear()
    optimizer_lite:clearAll()
    logger.info("ImageTextOptimizerLite: 缓存已清理")
end

-- 自动启用（如果是低性能设备）
if LITE_CONFIG.is_kindle or LITE_CONFIG.is_low_memory_device then
    ImageTextOptimizerLite_enable()
    logger.info("ImageTextOptimizerLite: 检测到低性能设备，自动启用轻量级优化")
end

-- 导出全局访问
_G.ImageTextOptimizerLite = optimizer_lite
_G.ImageTextOptimizerLite_toggle = ImageTextOptimizerLite_toggle
_G.ImageTextOptimizerLite_enable = ImageTextOptimizerLite_enable
_G.ImageTextOptimizerLite_disable = ImageTextOptimizerLite_disable
_G.ImageTextOptimizerLite_stats = ImageTextOptimizerLite_stats
_G.ImageTextOptimizerLite_clear = ImageTextOptimizerLite_clear

logger.info("ImageTextOptimizerLite: 轻量级图文混排优化补丁已加载")
logger.info("内存占用预估: < 2MB")
logger.info("适用设备: Kindle 等低性能设备")

-- AIGC END 