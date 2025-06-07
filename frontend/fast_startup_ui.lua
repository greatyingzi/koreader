--[[--
快速启动界面 - 立即显示主界面框架，后台加载内容
解决点击后卡住等待的问题，提供更好的用户体验
]]

-- AIGC START
local UIManager = require("ui/uimanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextWidget = require("ui/widget/textwidget")
local ProgressWidget = require("ui/widget/progresswidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Font = require("ui/font")
local Device = require("device")
local Screen = Device.screen
local Size = require("ui/size")
local Blitbuffer = require("ffi/blitbuffer")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")

local FastStartupUI = {}

-- 启动状态定义
FastStartupUI.LOADING_STAGES = {
    {id = "init", text = _("初始化应用..."), weight = 0.1},
    {id = "document", text = _("加载文档..."), weight = 0.3}, 
    {id = "modules", text = _("加载阅读模块..."), weight = 0.4},
    {id = "plugins", text = _("加载插件..."), weight = 0.15},
    {id = "ready", text = _("准备完成"), weight = 0.05}
}

function FastStartupUI:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    
    o.current_stage = 1
    o.start_time = time.now()
    o.stage_callbacks = {}
    
    return o
end

-- 创建启动界面
function FastStartupUI:createStartupUI()
    local loading_text = TextWidget:new{
        text = _("KOReader"),
        face = Font:getFace("cfont", 28),
        bold = true,
    }
    
    local stage_text = TextWidget:new{
        text = self.LOADING_STAGES[1].text,
        face = Font:getFace("cfont", 18),
    }
    
    local progress_bar = ProgressWidget:new{
        width = Screen:scaleBySize(300),
        height = Screen:scaleBySize(20),
        percentage = 0,
        margin_h = 0,
        margin_v = 0,
    }
    
    local loading_group = VerticalGroup:new{
        align = "center",
        loading_text,
        VerticalSpan:new{ width = Size.span.vertical_default },
        stage_text,
        VerticalSpan:new{ width = Size.span.vertical_default },
        progress_bar,
    }
    
    local container = CenterContainer:new{
        dimen = Screen:getSize(),
        loading_group,
    }
    
    local main_container = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        margin = 0,
        padding = 0,
        container,
    }
    
    -- 保存界面组件引用
    self.stage_text = stage_text
    self.progress_bar = progress_bar
    self.main_container = main_container
    
    return main_container
end

-- 显示启动界面
function FastStartupUI:show()
    logger.info("FastStartupUI: showing startup interface")
    self.startup_ui = self:createStartupUI() 
    UIManager:show(self.startup_ui, "full")
    UIManager:forceRePaint()
    return self
end

-- 更新加载进度
function FastStartupUI:updateProgress(stage_id, custom_text)
    -- 查找当前阶段
    local stage_index = nil
    for i, stage in ipairs(self.LOADING_STAGES) do
        if stage.id == stage_id then
            stage_index = i
            break
        end
    end
    
    if not stage_index then
        logger.warn("FastStartupUI: unknown stage", stage_id)
        return
    end
    
    self.current_stage = stage_index
    local stage = self.LOADING_STAGES[stage_index]
    
    -- 计算总进度
    local total_progress = 0
    for i = 1, stage_index - 1 do
        total_progress = total_progress + self.LOADING_STAGES[i].weight
    end
    local percentage = math.min(100, total_progress * 100)
    
    -- 更新界面
    local display_text = custom_text or stage.text
    self.stage_text:setText(display_text)
    self.progress_bar:setPercentage(percentage)
    
    -- 立即刷新界面
    UIManager:setDirty(self.startup_ui, "ui")
    UIManager:forceRePaint()
    
    logger.info("FastStartupUI: updated to stage", stage_id, "progress:", percentage .. "%")
end

-- 完成启动，隐藏界面
function FastStartupUI:complete()
    local elapsed = time.now() - self.start_time
    logger.info("FastStartupUI: startup completed in", elapsed, "seconds")
    
    self:updateProgress("ready", _("启动完成！"))
    
    -- 短暂显示完成状态
    UIManager:scheduleIn(0.2, function()
        if self.startup_ui then
            UIManager:close(self.startup_ui)
            self.startup_ui = nil
        end
    end)
end

-- 设置阶段完成回调
function FastStartupUI:onStageComplete(stage_id, callback)
    self.stage_callbacks[stage_id] = callback
end

-- 模拟分阶段加载（用于测试）
function FastStartupUI:simulateLoading()
    local stages = {"init", "document", "modules", "plugins", "ready"}
    local current = 1
    
    local function nextStage()
        if current <= #stages then
            self:updateProgress(stages[current])
            current = current + 1
            UIManager:scheduleIn(0.5, nextStage)
        else
            self:complete()
        end
    end
    
    UIManager:scheduleIn(0.2, nextStage)
end

return FastStartupUI
-- AIGC END 