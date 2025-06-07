-- AIGC START
--[[
设备自适应配置模块

功能：
1. 检测设备硬件信息（内存、CPU、存储等）
2. 根据设备能力动态生成优化参数
3. 提供设备性能等级评估
4. 支持用户自定义调整

版本: 1.0.0
作者: AI Assistant
日期: 2024
--]]

local logger = require("logger")
local util = require("util")
local Device = require("device")
local lfs = require("libs/libkoreader-lfs")

local DeviceAdaptiveConfig = {}

-- 设备性能等级定义
local PERFORMANCE_LEVELS = {
    ULTRA_LOW = 1,    -- 极低性能（<256MB RAM）
    LOW = 2,          -- 低性能（256MB-512MB RAM）
    MEDIUM = 3,       -- 中等性能（512MB-1GB RAM）
    HIGH = 4,         -- 高性能（1GB-2GB RAM）
    ULTRA_HIGH = 5,   -- 超高性能（>2GB RAM）
}

-- 设备信息检测
function DeviceAdaptiveConfig:detectDeviceInfo()
    local device_info = {
        -- 基础设备信息
        device_name = Device:getDeviceName() or "Unknown",
        is_kindle = Device:isKindle(),
        is_kobo = Device:isKobo(),
        is_android = Device:isAndroid(),
        is_emulator = Device:isEmulator(),
        
        -- 内存信息
        memory = self:detectMemoryInfo(),
        
        -- CPU信息
        cpu = self:detectCPUInfo(),
        
        -- 存储信息
        storage = self:detectStorageInfo(),
        
        -- 显示信息
        display = self:detectDisplayInfo(),
        
        -- 性能等级
        performance_level = nil, -- 将在后面计算
    }
    
    -- 计算性能等级
    device_info.performance_level = self:calculatePerformanceLevel(device_info)
    
    return device_info
end

-- 检测内存信息
function DeviceAdaptiveConfig:detectMemoryInfo()
    local memfree, memtotal = util.calcFreeMem()
    local memory_info = {
        total_bytes = memtotal or 0,
        free_bytes = memfree or 0,
        total_mb = memtotal and (memtotal / (1024 * 1024)) or 0,
        free_mb = memfree and (memfree / (1024 * 1024)) or 0,
        usage_percent = 0,
    }
    
    if memtotal and memfree then
        memory_info.usage_percent = ((memtotal - memfree) / memtotal) * 100
    end
    
    -- 尝试获取更详细的内存信息
    local meminfo_file = io.open("/proc/meminfo", "r")
    if meminfo_file then
        local meminfo_data = {}
        for line in meminfo_file:lines() do
            local key, value = line:match("^([^:]+):%s*(%d+)")
            if key and value then
                meminfo_data[key] = tonumber(value) * 1024 -- 转换为字节
            end
        end
        meminfo_file:close()
        
        memory_info.available_bytes = meminfo_data.MemAvailable
        memory_info.buffers_bytes = meminfo_data.Buffers
        memory_info.cached_bytes = meminfo_data.Cached
        memory_info.swap_total_bytes = meminfo_data.SwapTotal
        memory_info.swap_free_bytes = meminfo_data.SwapFree
    end
    
    return memory_info
end

-- 检测CPU信息
function DeviceAdaptiveConfig:detectCPUInfo()
    local cpu_info = {
        cores = 1,
        architecture = "unknown",
        model_name = "unknown",
        max_frequency = 0,
        features = {},
    }
    
    local cpuinfo_file = io.open("/proc/cpuinfo", "r")
    if cpuinfo_file then
        local core_count = 0
        for line in cpuinfo_file:lines() do
            -- 处理器核心数
            if line:match("^processor") then
                core_count = core_count + 1
            end
            
            -- CPU架构
            local arch = line:match("^Architecture%s*:%s*(.+)")
            if arch then
                cpu_info.architecture = arch:gsub("%s+", "")
            end
            
            -- CPU型号
            local model = line:match("^model name%s*:%s*(.+)")
            if model then
                cpu_info.model_name = model
            end
            
            -- 硬件信息（ARM设备）
            local hardware = line:match("^Hardware%s*:%s*(.+)")
            if hardware then
                cpu_info.hardware = hardware
            end
            
            -- CPU特性
            local features = line:match("^Features%s*:%s*(.+)")
            if features then
                for feature in features:gmatch("%S+") do
                    table.insert(cpu_info.features, feature)
                end
            end
        end
        cpuinfo_file:close()
        cpu_info.cores = math.max(1, core_count)
    end
    
    -- 尝试获取CPU频率信息
    local freq_file = io.open("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq", "r")
    if freq_file then
        local freq = freq_file:read("*number")
        if freq then
            cpu_info.max_frequency = freq / 1000 -- 转换为MHz
        end
        freq_file:close()
    end
    
    return cpu_info
end

-- 检测存储信息
function DeviceAdaptiveConfig:detectStorageInfo()
    local storage_info = {
        total_space = 0,
        free_space = 0,
        filesystem_type = "unknown",
    }
    
    -- 获取当前目录的存储信息
    local current_path = lfs.currentdir() or "."
    
    -- 获取文件系统类型
    storage_info.filesystem_type = util.getFilesystemType(current_path) or "unknown"
    
    return storage_info
end

-- 检测显示信息
function DeviceAdaptiveConfig:detectDisplayInfo()
    local display_info = {
        width = 0,
        height = 0,
        dpi = 0,
        color_depth = 8,
        has_color = false,
        is_eink = false,
    }
    
    if Device.screen then
        display_info.width = Device.screen:getWidth() or 0
        display_info.height = Device.screen:getHeight() or 0
        display_info.dpi = Device.screen:getDPI() or 0
    end
    
    -- 检测显示特性
    display_info.has_color = Device:hasColorScreen() or false
    display_info.is_eink = Device:isEInk() or false
    
    -- 估算颜色深度
    if display_info.has_color then
        display_info.color_depth = 24 -- 假设24位彩色
    else
        display_info.color_depth = 8  -- 假设8位灰度
    end
    
    return display_info
end

-- 计算设备性能等级
function DeviceAdaptiveConfig:calculatePerformanceLevel(device_info)
    local score = 0
    local memory_mb = device_info.memory.total_mb
    
    -- 内存评分（权重：50%）
    if memory_mb >= 2048 then
        score = score + 50
    elseif memory_mb >= 1024 then
        score = score + 40
    elseif memory_mb >= 512 then
        score = score + 30
    elseif memory_mb >= 256 then
        score = score + 20
    else
        score = score + 10
    end
    
    -- CPU评分（权重：30%）
    local cpu_score = 0
    if device_info.cpu.cores >= 4 then
        cpu_score = cpu_score + 15
    elseif device_info.cpu.cores >= 2 then
        cpu_score = cpu_score + 10
    else
        cpu_score = cpu_score + 5
    end
    
    if device_info.cpu.max_frequency >= 1500 then
        cpu_score = cpu_score + 15
    elseif device_info.cpu.max_frequency >= 1000 then
        cpu_score = cpu_score + 10
    else
        cpu_score = cpu_score + 5
    end
    
    score = score + cpu_score
    
    -- 显示评分（权重：20%）
    local pixel_count = device_info.display.width * device_info.display.height
    if pixel_count >= 2073600 then -- 1920x1080+
        score = score + 20
    elseif pixel_count >= 1024000 then -- 1024x1000+
        score = score + 15
    elseif pixel_count >= 480000 then -- 800x600+
        score = score + 10
    else
        score = score + 5
    end
    
    -- 根据总分确定性能等级
    if score >= 85 then
        return PERFORMANCE_LEVELS.ULTRA_HIGH
    elseif score >= 70 then
        return PERFORMANCE_LEVELS.HIGH
    elseif score >= 55 then
        return PERFORMANCE_LEVELS.MEDIUM
    elseif score >= 40 then
        return PERFORMANCE_LEVELS.LOW
    else
        return PERFORMANCE_LEVELS.ULTRA_LOW
    end
end

-- 根据性能等级生成优化配置
function DeviceAdaptiveConfig:generateOptimizationConfig(device_info)
    local perf_level = device_info.performance_level
    local memory_mb = device_info.memory.total_mb
    local config = {}
    
    if perf_level == PERFORMANCE_LEVELS.ULTRA_LOW then
        -- 极低性能设备配置
        config = {
            image_size_cache_limit = math.max(5, math.floor(memory_mb * 0.02)),
            layout_cache_limit = math.max(3, math.floor(memory_mb * 0.01)),
            preload_pages = 0,
            preload_max_images = 0,
            memory_warning_threshold = math.max(40, memory_mb * 0.6),
            memory_critical_threshold = math.max(50, memory_mb * 0.7),
            batch_size_threshold = 5,
            enable_preload = false,
            enable_batch_rendering = false,
            cache_cleanup_interval = 15, -- 15秒清理一次
        }
    elseif perf_level == PERFORMANCE_LEVELS.LOW then
        -- 低性能设备配置
        config = {
            image_size_cache_limit = math.max(25, math.floor(memory_mb * 0.05)),
            layout_cache_limit = math.max(10, math.floor(memory_mb * 0.02)),
            preload_pages = 0,
            preload_max_images = 1,
            memory_warning_threshold = math.max(60, memory_mb * 0.65),
            memory_critical_threshold = math.max(80, memory_mb * 0.75),
            batch_size_threshold = 10,
            enable_preload = false,
            enable_batch_rendering = true,
            cache_cleanup_interval = 30,
        }
    elseif perf_level == PERFORMANCE_LEVELS.MEDIUM then
        -- 中等性能设备配置
        config = {
            image_size_cache_limit = math.max(50, math.floor(memory_mb * 0.08)),
            layout_cache_limit = math.max(20, math.floor(memory_mb * 0.04)),
            preload_pages = 1,
            preload_max_images = 3,
            memory_warning_threshold = math.max(80, memory_mb * 0.7),
            memory_critical_threshold = math.max(120, memory_mb * 0.8),
            batch_size_threshold = 20,
            enable_preload = true,
            enable_batch_rendering = true,
            cache_cleanup_interval = 60,
        }
    elseif perf_level == PERFORMANCE_LEVELS.HIGH then
        -- 高性能设备配置
        config = {
            image_size_cache_limit = math.max(200, math.floor(memory_mb * 0.1)),
            layout_cache_limit = math.max(100, math.floor(memory_mb * 0.05)),
            preload_pages = 2,
            preload_max_images = 5,
            memory_warning_threshold = math.max(150, memory_mb * 0.75),
            memory_critical_threshold = math.max(200, memory_mb * 0.85),
            batch_size_threshold = 50,
            enable_preload = true,
            enable_batch_rendering = true,
            cache_cleanup_interval = 120,
        }
    else -- ULTRA_HIGH
        -- 超高性能设备配置
        config = {
            image_size_cache_limit = math.max(1000, math.floor(memory_mb * 0.15)),
            layout_cache_limit = math.max(500, math.floor(memory_mb * 0.08)),
            preload_pages = 3,
            preload_max_images = 10,
            memory_warning_threshold = math.max(300, memory_mb * 0.8),
            memory_critical_threshold = math.max(400, memory_mb * 0.9),
            batch_size_threshold = 100,
            enable_preload = true,
            enable_batch_rendering = true,
            cache_cleanup_interval = 300,
        }
    end
    
    -- 设备特定调整
    if device_info.is_kindle then
        -- Kindle设备通常内存较紧张，适当降低配置
        config.image_size_cache_limit = math.floor(config.image_size_cache_limit * 0.8)
        config.layout_cache_limit = math.floor(config.layout_cache_limit * 0.8)
        config.memory_warning_threshold = config.memory_warning_threshold * 0.9
        config.memory_critical_threshold = config.memory_critical_threshold * 0.9
    end
    
    if device_info.display.is_eink then
        -- E-ink设备刷新较慢，可以增加缓存
        config.image_size_cache_limit = math.floor(config.image_size_cache_limit * 1.2)
        config.layout_cache_limit = math.floor(config.layout_cache_limit * 1.2)
    end
    
    -- 添加设备信息到配置中
    config.device_info = device_info
    config.performance_level = perf_level
    config.generated_at = os.time()
    
    return config
end

-- 获取性能等级名称
function DeviceAdaptiveConfig:getPerformanceLevelName(level)
    local names = {
        [PERFORMANCE_LEVELS.ULTRA_LOW] = "极低性能",
        [PERFORMANCE_LEVELS.LOW] = "低性能", 
        [PERFORMANCE_LEVELS.MEDIUM] = "中等性能",
        [PERFORMANCE_LEVELS.HIGH] = "高性能",
        [PERFORMANCE_LEVELS.ULTRA_HIGH] = "超高性能",
    }
    return names[level] or "未知"
end

-- 打印设备信息
function DeviceAdaptiveConfig:printDeviceInfo(device_info)
    logger.info("=== 设备信息检测结果 ===")
    logger.info("设备名称:", device_info.device_name)
    logger.info("设备类型:", device_info.is_kindle and "Kindle" or 
                            device_info.is_kobo and "Kobo" or
                            device_info.is_android and "Android" or "其他")
    
    logger.info("内存信息:")
    logger.info("  总内存:", string.format("%.1f MB", device_info.memory.total_mb))
    logger.info("  可用内存:", string.format("%.1f MB", device_info.memory.free_mb))
    logger.info("  使用率:", string.format("%.1f%%", device_info.memory.usage_percent))
    
    logger.info("CPU信息:")
    logger.info("  核心数:", device_info.cpu.cores)
    logger.info("  架构:", device_info.cpu.architecture)
    logger.info("  型号:", device_info.cpu.model_name)
    if device_info.cpu.max_frequency > 0 then
        logger.info("  最大频率:", string.format("%.0f MHz", device_info.cpu.max_frequency))
    end
    
    logger.info("显示信息:")
    logger.info("  分辨率:", device_info.display.width .. "x" .. device_info.display.height)
    logger.info("  DPI:", device_info.display.dpi)
    logger.info("  彩色屏幕:", device_info.display.has_color and "是" or "否")
    logger.info("  E-ink屏幕:", device_info.display.is_eink and "是" or "否")
    
    logger.info("性能等级:", self:getPerformanceLevelName(device_info.performance_level))
    logger.info("========================")
end

-- 打印优化配置
function DeviceAdaptiveConfig:printOptimizationConfig(config)
    logger.info("=== 自适应优化配置 ===")
    logger.info("性能等级:", self:getPerformanceLevelName(config.performance_level))
    logger.info("图片尺寸缓存限制:", config.image_size_cache_limit)
    logger.info("布局缓存限制:", config.layout_cache_limit)
    logger.info("预加载页数:", config.preload_pages)
    logger.info("预加载图片数:", config.preload_max_images)
    logger.info("内存警告阈值:", string.format("%.0f MB", config.memory_warning_threshold))
    logger.info("内存紧急阈值:", string.format("%.0f MB", config.memory_critical_threshold))
    logger.info("批量渲染阈值:", config.batch_size_threshold)
    logger.info("启用预加载:", config.enable_preload and "是" or "否")
    logger.info("启用批量渲染:", config.enable_batch_rendering and "是" or "否")
    logger.info("缓存清理间隔:", config.cache_cleanup_interval .. "秒")
    logger.info("=====================")
end

-- 主要接口：获取自适应配置
function DeviceAdaptiveConfig:getAdaptiveConfig()
    local device_info = self:detectDeviceInfo()
    local config = self:generateOptimizationConfig(device_info)
    
    -- 打印信息（可选）
    self:printDeviceInfo(device_info)
    self:printOptimizationConfig(config)
    
    return config
end

-- 导出模块
return DeviceAdaptiveConfig

-- AIGC END 