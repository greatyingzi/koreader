
local logger = require("logger")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local NetUtils = WidgetContainer:extend{

}


-- describe("Lua Spore modules with async http request #notest #nocov", function()
--     local client, UIManager

--     setup(function()
--         require("commonrequire")
--         UIManager = require("ui/uimanager")
--         local HTTPClient = require("httpclient")
--         local Spore = require("Spore")
--         client = Spore.new_from_string(service)
--         local async_http_client = HTTPClient:new()
--         package.loaded['Spore.Middleware.AsyncHTTP'] = {}
--         require('Spore.Middleware.AsyncHTTP').call = function(args, req)
--             req:finalize()
--             local result
--             async_http_client:request({
--                 url = req.url,
--                 method = req.method,
--                 body = req.env.spore.payload,
--                 on_headers = function(headers)
--                     for header, value in pairs(req.headers) do
--                         if type(header) == 'string' then
--                             headers:add(header, value)
--                         end
--                     end
--                 end,
--             }, function(res)
--                 result = res
--                 -- Turbo HTTP client uses code instead of status
--                 -- change to status so that Spore can understand
--                 result.status = res.code
--                 coroutine.resume(args.thread)
--                 UIManager.INPUT_TIMEOUT = 100 -- no need in production
--             end)
--             return coroutine.create(function() coroutine.yield(result) end)
--         end
--     end)

--     it("should complete GET request", function()
--         UIManager:quit()
--         local co = coroutine.create(function()
--             local info = {user = 'john', age = '25'}
--             local res = client:get_info(info)
--             UIManager:quit()
--             assert.are.same(res.body.args, info)
--         end)
--         client:reset_middlewares()
--         client:enable("Format.JSON")
--         client:enable("AsyncHTTP", {thread = co})
--         coroutine.resume(co)
--         UIManager:setRunForeverMode()
--         UIManager:run()
--     end)

--     it("should complete POST request", function()
--         UIManager:quit()
--         local co = coroutine.create(function()
--             local info = {user = 'sam', age = '26'}
--             local res = client:post_info(info)
--             UIManager:quit()
--             assert.are.same(res.body.json, info)
--         end)
--         client:reset_middlewares()
--         client:enable("Format.JSON")
--         client:enable("AsyncHTTP", {thread = co})
--         coroutine.resume(co)
--         UIManager:setRunForeverMode()
--         UIManager:run()
--     end)
-- end)


-- Get URL content
function NetUtils:getUrlContent(url, timeout, maxtime)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local socket_url = require("socket.url")

    logger.dbg("NetUtils start1","")

    local parsed = socket_url.parse(url)
    if parsed.scheme ~= "http" and parsed.scheme ~= "https" then
        return false, "Unsupported protocol"
    end
    if not timeout then timeout = 10 end
    logger.dbg("NetUtils start2","")
    local sink = {}
    socketutil:set_timeout(timeout, maxtime or 30)
    local request = {
        url     = url,
        method  = "GET",
        sink    = maxtime and socketutil.table_sink(sink) or ltn12.sink.table(sink),
    }
    logger.dbg("NetUtils start3","")
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local content = table.concat(sink) -- empty or content accumulated till now
    -- logger.dbg("code:", code)
    -- logger.dbg("headers:", headers)
    -- logger.dbg("status:", status)
    -- logger.dbg("#content:", #content)

    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE
    then
        logger.warn("request interrupted:", code)
        return false, code
    end
    logger.dbg("NetUtils start4","")
    if headers == nil then
        logger.warn("No HTTP headers:", status or code or "network unreachable")
        return false, "Network or remote server unavailable"
    end
    if not code or code < 200 or code > 299 then -- all 200..299 HTTP codes are OK
        logger.warn("HTTP status not okay:", status or code or "network unreachable")
        logger.dbg("Response headers:", headers)
        return false, "Remote server error or unavailable"
    end
    logger.dbg("NetUtils start5","")
    if headers and headers["content-length"] then
        -- Check we really got the announced content size
        local content_length = tonumber(headers["content-length"])
        if #content ~= content_length then
            return false, "Incomplete content received"
        end
    end
    return true, content
end

return NetUtils;
