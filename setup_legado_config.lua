#!/usr/bin/env lua
--[[
Legado桥接插件配置向导
帮助用户快速配置IP地址和测试连接
]]--

-- 配置文件路径
local CONFIG_FILE = "plugins/legado_bridge.koplugin/legado_config.json"

-- 颜色输出
local function colorPrint(text, color)
    local colors = {
        red = "\27[31m", green = "\27[32m", yellow = "\27[33m", 
        blue = "\27[34m", magenta = "\27[35m", cyan = "\27[36m",
        reset = "\27[0m"
    }
    print((colors[color] or "") .. text .. (colors.reset or ""))
end

-- 检查文件是否存在
local function fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- 测试连接
local function testConnection(host, port)
    local cmd = string.format("curl -s -m 5 'http://%s:%s/' > /dev/null 2>&1", host, port)
    local success = os.execute(cmd)
    return success == 0
end

-- 扫描常见IP地址
local function scanCommonIPs()
    colorPrint("🔍 正在扫描常见IP地址...", "blue")
    
    local common_ips = {
        "192.168.1.100", "192.168.1.101", "192.168.1.102", "192.168.1.103",
        "192.168.0.100", "192.168.0.101", "192.168.0.102", "192.168.0.103",
        "10.0.0.100", "10.0.0.101", "10.0.0.102", "10.0.0.103",
        "172.16.0.100", "172.16.0.101", "172.16.0.102", "172.16.0.103",
        "127.0.0.1"
    }
    
    local found_services = {}
    
    for _, ip in ipairs(common_ips) do
        if testConnection(ip, "1122") then
            table.insert(found_services, ip .. ":1122")
            colorPrint("✅ 发现服务: " .. ip .. ":1122", "green")
        end
    end
    
    return found_services
end

-- 创建配置文件
local function createConfig(host, port)
    local config = {
        api = {
            host = host,
            port = port,
            timeout = 30
        },
        cache = {
            search_ttl = 1800,
            content_ttl = 3600
        },
        ui = {
            max_search_results = 20,
            max_chapters_preview = 5
        }
    }
    
    -- 简单的JSON编码
    local function encodeJSON(obj)
        if type(obj) == "table" then
            local parts = {}
            for k, v in pairs(obj) do
                local key = '"' .. tostring(k) .. '"'
                local value
                if type(v) == "table" then
                    value = encodeJSON(v)
                elseif type(v) == "string" then
                    value = '"' .. v .. '"'
                else
                    value = tostring(v)
                end
                table.insert(parts, key .. ":" .. value)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        else
            return '"' .. tostring(obj) .. '"'
        end
    end
    
    -- 确保目录存在
    os.execute("mkdir -p plugins/legado_bridge.koplugin")
    
    local file = io.open(CONFIG_FILE, "w")
    if file then
        file:write(encodeJSON(config))
        file:close()
        return true
    else
        return false
    end
end

-- 显示当前配置
local function showCurrentConfig()
    if fileExists(CONFIG_FILE) then
        colorPrint("📋 当前配置:", "cyan")
        local file = io.open(CONFIG_FILE, "r")
        if file then
            local content = file:read("*all")
            file:close()
            print(content)
        end
    else
        colorPrint("📋 尚未配置", "yellow")
    end
end

-- 手动输入IP地址
local function manualInput()
    colorPrint("✏️  请输入Legado服务地址:", "blue")
    print("格式: IP:端口 (例如: 192.168.1.100:1122)")
    io.write("请输入 > ")
    local input = io.read()
    
    if input then
        local host, port = input:match("([^:]+):([^:]+)")
        if host and port then
            colorPrint("🧪 测试连接: " .. host .. ":" .. port, "blue")
            if testConnection(host, port) then
                colorPrint("✅ 连接成功!", "green")
                return host, port
            else
                colorPrint("❌ 连接失败", "red")
                colorPrint("请检查:", "yellow")
                colorPrint("• Legado应用是否正在运行", "yellow")
                colorPrint("• Web服务是否已开启", "yellow")
                colorPrint("• IP地址是否正确", "yellow")
                return nil, nil
            end
        else
            colorPrint("❌ 地址格式错误", "red")
            return nil, nil
        end
    end
    
    return nil, nil
end

-- 主菜单
local function showMainMenu()
    while true do
        colorPrint("\n🚀 Legado桥接插件配置向导", "cyan")
        colorPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", "blue")
        
        showCurrentConfig()
        
        colorPrint("\n📋 请选择操作:", "blue")
        colorPrint("1. 自动扫描Legado服务", "green")
        colorPrint("2. 手动输入服务地址", "green")
        colorPrint("3. 使用常见IP地址", "green")
        colorPrint("4. 测试当前配置", "green")
        colorPrint("5. 删除配置", "red")
        colorPrint("0. 退出", "yellow")
        
        io.write("\n请输入选项 (0-5): ")
        local choice = io.read()
        
        if choice == "1" then
            -- 自动扫描
            local services = scanCommonIPs()
            if #services > 0 then
                colorPrint("\n🎯 发现的服务:", "green")
                for i, service in ipairs(services) do
                    colorPrint(string.format("%d. %s", i, service), "green")
                end
                
                io.write("\n请选择服务 (1-" .. #services .. "): ")
                local service_choice = tonumber(io.read())
                
                if service_choice and service_choice >= 1 and service_choice <= #services then
                    local selected = services[service_choice]
                    local host, port = selected:match("([^:]+):([^:]+)")
                    
                    if createConfig(host, port) then
                        colorPrint("✅ 配置已保存: " .. selected, "green")
                    else
                        colorPrint("❌ 配置保存失败", "red")
                    end
                end
            else
                colorPrint("❌ 未发现任何Legado服务", "red")
            end
            
        elseif choice == "2" then
            -- 手动输入
            local host, port = manualInput()
            if host and port then
                if createConfig(host, port) then
                    colorPrint("✅ 配置已保存: " .. host .. ":" .. port, "green")
                else
                    colorPrint("❌ 配置保存失败", "red")
                end
            end
            
        elseif choice == "3" then
            -- 常见IP地址
            local common_addresses = {
                "192.168.1.100:1122",
                "192.168.1.101:1122",
                "192.168.0.100:1122",
                "192.168.0.101:1122",
                "10.0.0.100:1122",
                "127.0.0.1:1122"
            }
            
            colorPrint("\n📱 常见IP地址:", "blue")
            for i, addr in ipairs(common_addresses) do
                colorPrint(string.format("%d. %s", i, addr), "green")
            end
            
            io.write("\n请选择地址 (1-" .. #common_addresses .. "): ")
            local addr_choice = tonumber(io.read())
            
            if addr_choice and addr_choice >= 1 and addr_choice <= #common_addresses then
                local selected = common_addresses[addr_choice]
                local host, port = selected:match("([^:]+):([^:]+)")
                
                colorPrint("🧪 测试连接: " .. selected, "blue")
                if testConnection(host, port) then
                    colorPrint("✅ 连接成功!", "green")
                    if createConfig(host, port) then
                        colorPrint("✅ 配置已保存", "green")
                    else
                        colorPrint("❌ 配置保存失败", "red")
                    end
                else
                    colorPrint("❌ 连接失败，但仍可保存配置", "yellow")
                    io.write("是否仍要保存? (y/n): ")
                    local confirm = io.read()
                    if confirm:lower() == "y" then
                        if createConfig(host, port) then
                            colorPrint("✅ 配置已保存", "green")
                        else
                            colorPrint("❌ 配置保存失败", "red")
                        end
                    end
                end
            end
            
        elseif choice == "4" then
            -- 测试配置
            if fileExists(CONFIG_FILE) then
                -- 这里应该解析JSON，但为了简化，假设默认配置
                colorPrint("🧪 测试配置中的连接...", "blue")
                colorPrint("⚠️  请使用KOReader中的状态检查功能进行完整测试", "yellow")
            else
                colorPrint("❌ 尚未配置", "red")
            end
            
        elseif choice == "5" then
            -- 删除配置
            colorPrint("⚠️  确定要删除配置吗? (y/n): ", "yellow")
            local confirm = io.read()
            if confirm:lower() == "y" then
                os.remove(CONFIG_FILE)
                colorPrint("✅ 配置已删除", "green")
            end
            
        elseif choice == "0" then
            break
            
        else
            colorPrint("❌ 无效选项", "red")
        end
    end
end

-- 显示帮助信息
local function showHelp()
    colorPrint("🆘 使用帮助:", "cyan")
    colorPrint("", "reset")
    colorPrint("1. 确保Legado应用正在运行", "green")
    colorPrint("2. 在Legado中开启Web服务:", "green")
    colorPrint("   设置 → Web服务 → 开启", "blue")
    colorPrint("3. 记录Legado显示的IP地址", "green")
    colorPrint("4. 运行此配置向导", "green")
    colorPrint("5. 重启KOReader应用", "green")
    colorPrint("", "reset")
    colorPrint("📱 常见问题:", "cyan")
    colorPrint("• 连接失败: 检查防火墙设置", "yellow")
    colorPrint("• 找不到服务: 确保设备在同一网络", "yellow")
    colorPrint("• 配置无效: 删除配置文件重新设置", "yellow")
end

-- 程序入口
local function main()
    -- 检查参数
    if arg and arg[1] == "--help" then
        showHelp()
        return
    end
    
    -- 显示欢迎信息
    colorPrint("🌟 欢迎使用Legado桥接插件配置向导!", "magenta")
    colorPrint("此工具将帮助您配置KOReader与Legado的连接", "blue")
    
    -- 检查curl
    if os.execute("which curl > /dev/null 2>&1") ~= 0 then
        colorPrint("⚠️  未找到curl命令，某些功能可能不可用", "yellow")
    end
    
    showMainMenu()
    
    colorPrint("\n🎉 配置完成!", "green")
    colorPrint("请重启KOReader应用以应用新配置", "blue")
    colorPrint("在KOReader中使用: 📚 在线书源 → 📊 状态检查", "blue")
end

-- 运行主程序
main() 