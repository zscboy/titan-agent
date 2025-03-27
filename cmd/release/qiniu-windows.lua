local mod = {luaScriptName="qiniu-windows.lua"}

function mod.start()
    mod.print("mod.start qiniu")
    mod.timerInterval = 60

    mod.getBaseInfo()

    mod.sendMetrics({status="starting"})

    local err =  mod.run()
    if err then
        mod.print("Failed to prepare install script: "..err)
    end

    mod.startTimer()
end

function mod.stop()
    mod.print("mod.stop qiniu")
end


function mod.getBaseInfo()
    local agent = require 'agent'
    local info = agent.info()
    if info then
        mod.info = info
        mod.print(info)
    else
        mod.print("Failed to get base info")
    end
end


function mod.run()
    if not mod.installScriptPath then
        local err = mod.fetchInstallScript()
        if err then
            return err
        end
    end

    local _, err = mod.getBizId()
    if err then
        mod.print("Failed to get bizId, seems not installed: "..err)
        local installErr = mod.install()
        if installErr then
            return installErr
        end
    end
   
end

function mod.install()
    local agent = require("agent")

    local command = mod.installScriptPath .. ' install'

    mod.print("install script: "..command)

    local result, err = agent.exec(command, 1800)
    if err then
        return "Failed to execute install script: "..err
    end

    if result.status ~= 0 then
        return "Install script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return "Install script stderr: "..result.stderr
    end

    if result.stdout then
        mod.print("Install script output: "..result.stdout)
    end

    return nil
end

function mod.reinstall()
    local agent = require("agent")
    local command = mod.installScriptPath .. ' reinstall' 
    mod.print("reinstall script: "..command)

    local result, err = agent.exec(command, 1800) 
    if err then
        return "Failed to execute reinstall script: "..err
    end

    if result.status ~= 0 then
        return "Reinstall script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return "Reinstall script stderr: "..result.stderr
    end

    if result.stdout then
        mod.print("Reinstall script output: "..result.stdout)
    end

    return nil
end


function mod.fetchInstallScript()
    local scriptName = "install-qiniu.bat"
    local scriptURL = "https://gist.githubusercontent.com/gnasnik/f7d9f4c32feef5e5d3b4005675e47cc0/raw/d02eef182901a5e916b2c9aa075488546f3131aa/niulink-install.bat"
    -- local scriptPath = mod.info.appDir .. "/" .. scriptName

    -- check script path is absolute or relative to appDir
    local scriptPath
    if string.sub(mod.info.appDir, 1, 1) == "/" or string.sub(mod.info.appDir, 2, 2) == ":" then
        scriptPath = mod.info.appDir .. "/" .. scriptName
    else
        local cwd = io.popen("cd"):read("*l")
        scriptPath = cwd .. "/" .. mod.info.appDir .. "/" .. scriptName
    end
    mod.print("scriptPath: "..scriptPath)

    local err = mod.downloadScript(scriptURL, scriptPath)
    if err then
        mod.print("Failed to download install script: "..err)
        return err
    end

    local agent = require("agent")
    local chmodErr = agent.chmod(scriptPath, "0755")
    if chmodErr then
        mod.print("Failed to chmod install script: "..chmodErr)
        return err
    end

    mod.installScriptPath = scriptPath
end


function mod.downloadScript(url, filePath)
    local http = require("http")
    local client = http.client({timeout=30})

    local request = http.request("GET", url)
    local result, err = client:do_request(request)
    if err then
        return "HTTP request failed: "..err
    end

    if result.code ~= 200 then
        return "HTTP status code "..result.code..", URL: "..url
    end

    local ioutil = require("ioutil")
    local writeErr = ioutil.write_file(filePath, result.body)
    if writeErr then
        return "Failed to write file: "..writeErr
    end

    return nil
end


function mod.getBizId()
    local agent = require("agent")
    local command =  mod.installScriptPath .. ' info'
    mod.print("info script: "..command)
    
    local result, err = agent.exec(command, 30)
    if err then
        return nil, "Failed to execute info script: "..err
    end

    if result.status ~= 0 then
        return nil, "Info script error: "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return nil, "Info script stderr: "..result.stderr
    end

    if result.stdout then
        local bizId = mod.parseBizId(result.stdout)
        if bizId then
            return bizId, nil
        else
            return nil, "Failed to parse bizId from output: "..result.stdout
        end
    end

    return nil, "No output from info script"
end

function mod.parseBizId(output)
    local _, _, bizId = string.find(output, "BOX_ID: %s*(%w+)")
    return bizId
end


function mod.startTimer()
    local timer = require("timer")
    timer.createTimer('monitor', mod.timerInterval, 'onTimerMonitor')
end


function mod.onTimerMonitor()
    mod.print("onTimerMonitor qiniu.lua")

    if mod.monitorLastActivitTime then
        if os.difftime(os.time(), mod.monitorLastActivitTime) < mod.timerInterval then
            mod.print("Insufficient time to monitor")
            return
        end
    end
    mod.monitorLastActivitTime = os.time()

    local bizId, err = mod.getBizId()
    if err then
        mod.print("Failed to get bizId: "..err)
        mod.sendMetrics({status="failed", client_id="", err=err})

        local installErr = mod.install()
        if installErr then
            mod.print("Install failed again: "..installErr)
            mod.sendMetrics({status="failed", client_id="", err=installErr})
        else
            mod.print("Install succeeded, initiating reinstall.")
            mod.sendMetrics({status="re-creating", client_id=""})
            local reinstallErr = mod.reinstall()
            if reinstallErr then
                mod.print("Reinstall failed: "..reinstallErr)
                mod.sendMetrics({status="failed", client_id="", err=reinstallErr})
            else
                mod.print("Reinstall succeeded, will check bizId next cycle.")
                mod.sendMetrics({status="running", client_id=bizId or ""})
            end
        end
    else
        mod.print("Retrieved bizId: "..bizId)
        mod.sendMetrics({status="running", client_id=bizId})
    end
end


function mod.sendMetrics(metrics)
    local metric = require("metric")
    local json = require("json")
    local jsonString, err = json.encode(metrics)
    if err then
        mod.print("Failed to encode metrics: "..err)
        return
    end

    metric.send(jsonString)
end


function mod.print(msg)
    local logLevel = "info"
    if type(msg) == "table" then
        local tableMsg = "{\n"
        for key, value in pairs(msg) do
            tableMsg = string.format("%s  %s: %s\n", tableMsg, key, tostring(value))
        end
        tableMsg = tableMsg .. "}"
        msg = tableMsg
    end

    -- if type(msg) == "string" then
    --     local err
    --     msg, err = mod.convertToUtf8(msg)
    --     if err then
    --         mod.print("Failed to convert msg to utf8: "..err)
    --     end
    -- end

    print(string.format('time="%s" level=%s lua=%s msg="%s"', os.date("%Y-%m-%dT%H:%M:%S"), logLevel, mod.luaScriptName, tostring(msg)))
end

-- function mod.convertToUtf8(str)
--     local enc = require("iconv").new("UTF-8", "GBK")
--     local converted, err = enc:iconv(str)
--     if not converted then
--         return str
--     end
--     return converted
-- end

return mod
