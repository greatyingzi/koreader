--[[
KOReader 简单启动界面热加载补丁
优先级：2 (UIManager就绪后加载)
功能：显示简单的启动界面，不干扰KOReader正常启动流程
]]--

-- AIGC START
local logger = require("logger")
local UIManager = require("ui/uimanager")

logger.info("正在应用简单启动界面补丁...")

-- 简单的启动界面
local SimpleStartupUI = {}

function SimpleStartupUI:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    
    o.startup_ui = nil
    o.is_shown = false
    
    return o
end

function SimpleStartupUI:createStartupUI()
    local VerticalGroup = require("ui/widget/verticalgroup")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Font = require("ui/font")
    local Size = require("ui/size")
    local Screen = require("device").screen
    
    local container_width = math.min(Screen:getWidth() * 0.6, 300)
    
    local main_container = FrameContainer:new{
        background = require("ffi/blitbuffer").COLOR_WHITE,
        bordersize = Size.border.window,
        margin = Size.margin.default,
        padding = Size.padding.large,
        CenterContainer:new{
            dimen = {w = container_width, h = 0},
            VerticalGroup:new{
                align = "center",
                TextWidget:new{
                    text = "📚 KOReader",
                    face = Font:getFace("cfont", 24),
                    bold = true,
                },
                VerticalSpan:new{width = Size.span.vertical_large},
                TextWidget:new{
                    text = "正在启动...",
                    face = Font:getFace("cfont", 16),
                },
                VerticalSpan:new{width = Size.span.vertical_default},
                TextWidget:new{
                    text = "请稍候",
                    face = Font:getFace("cfont", 14),
                },
            }
        }
    }
    
    return CenterContainer:new{
        dimen = Screen:getSize(),
        main_container
    }
end

function SimpleStartupUI:show()
    if self.is_shown then return end
    
    logger.info("SimpleStartupUI: 显示启动界面")
    self.startup_ui = self:createStartupUI()
    UIManager:show(self.startup_ui, "full")
    UIManager:forceRePaint()
    self.is_shown = true
    
    -- 简单的定时隐藏，不跟踪实际加载进度
    UIManager:scheduleIn(2.5, function()
        self:hide()
    end)
end

function SimpleStartupUI:hide()
    if not self.is_shown or not self.startup_ui then return end
    
    logger.info("SimpleStartupUI: 隐藏启动界面")
    UIManager:close(self.startup_ui)
    self.startup_ui = nil
    self.is_shown = false
end

-- 注册全局 SimpleStartupUI
_G.SimpleStartupUI = SimpleStartupUI

-- 在UIManager就绪后立即显示启动界面
local startup_ui = SimpleStartupUI:new()
UIManager:nextTick(function()
    startup_ui:show()
end)

logger.info("简单启动界面补丁加载完成！")
-- AIGC END 