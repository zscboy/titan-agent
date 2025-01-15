local mod = {luaScriptName="install-frp.lua"}

function mod.start()
    mod.print("mod.start")
    mod.timerInterval = 60

    mod.getBaseInfo()

    if not mod.isFrpClientInstall() then
        local err = mod.installFrpClient()
        if err then
            mod.print("install frp "..err)
            mod.installErr = err
        end
    end

    if not mod.isFrpClientRunning() then
        local err = mod.startFrpClient()
        if err then
            mod.print("start frp "..err)
            mod.runErr = err
        end
    end

    mod.startTimer()
end


function mod.stop()
    mod.print("mod.stop")
end

function mod.getBaseInfo()
    local dev = require 'agent'
    local info = dev.info()
    if info then
        mod.info = info
        mod.print(info)
    end
end

function mod.fetchFrpInstallScript()
    local scriptName = "install-frp.sh"
    local scriptURL = "https://agent.titannet.io/frp/install-frp.sh"
    local scriptPath = mod.info.appDir .."/"..scriptName
    local err = mod.downloadScript(scriptURL, scriptPath)
    if err then
        mod.print("get script error "..err)
        return err
    end
    local agmod = require("agent")
    local err = agmod.chmod(scriptPath, "0755")
    if err then
        mod.print("chmod failed "..err)
        return err
    end
    
    mod.installFrpScriptPath = scriptPath
end


function mod.downloadScript(url, filePath) 
    local http = require("http")
    local client = http.client({timeout= 300})

    -- local url = mod.serverURL.."?version="..mod.info.version.."&os="..mod.info.os.."&uuid="..mod.info.uuid
    local request = http.request("GET", url)
    local result, err = client:do_request(request)
    if err then
        return err
    end

    if not (result.code == 200) then
        return "status code "..result.code..", url:"..url
    end

    local ioutil = require("ioutil")
    local err = ioutil.write_file(filePath, result.body)
    if err then 
        return err
    end

    return nil
end

function mod.startTimer()
    local tmod = require("timer")
    tmod.createTimer('monitor', mod.timerInterval, 'onTimerMonitor')
end

function mod.onTimerMonitor()
    mod.print("mod.onTimerMonitor")
    mod.print("onTimerMonitor")
    if mod.monitorLastActivitTime then
        if os.difftime(os.time(), mod.monitorLastActivitTime) < mod.timerInterval then
            mod.print("insufficient time to monitor")
            return
        end
    end
    mod.monitorLastActivitTime = os.time()

    local metric = {}
    if not mod.isFrpClientInstall() then
        local err = mod.installFrpClient()
        if err then
            mod.print("install frp "..err)
            mod.installErr = err
        end
    end

    if not mod.isFrpClientRunning() then
        local err = mod.startFrpClient()
        if err then
            mod.print("start frp "..err)
            mod.runErr = err
        end
    else 
        metric.status="running"
        mod.installErr = nil
        mod.runErr = nil
    end

    if mod.installErr then
        metric.installErr = mod.installErr
    end

    if mod.runErr then
        metric.runErr = mod.runErr
    end

    local service = mod.getService()
    if service then
        metric.service = service
    end

    mod.sendMetrics(metric)
end

function mod.sendMetrics(metrics)
    local metric = require("metric")
    local json = require("json")
    local jsonString, err = json.encode(metrics)
    if err then
        mod.print("encode metrics failed:"..err)
        return
    end

    metric.send(jsonString)

end

function mod.getService()
    local agent = require("agent")
    local result, err = agent.runBashCmd("cat /usr/local/frp/frpc.service")
    if err then
       mod.print("cat:"..err)
       return err
   end

   if result.status ~= 0 then
    return "cat status:"..result.status
   end
   return result.stdout 
end

function mod.isFrpClientInstall()
    local appPath = "/usr/local/frp/frpc"
    local goos = require("goos")
    local stat, err = goos.stat(appPath)
    if err then
        mod.print("stat "..appPath.." "..err)
        return false
    end
    return true
end

function mod.isFrpClientRunning()
    local agent = require("agent")
    local result, err = agent.runBashCmd("pgrep frpc")
    if err then
        mod.print("pgrep  err:"..err)
        return false
    end

    if result.status ~= 0 then
        mod.print("pgrep  failed, status:"..result.status)
        return false
    end

    if result.stdout and result.stdout ~= "" then
        mod.print("pgrep  "..result.stdout)
        return true
    end
    
    return false
end

function mod.startFrpClient()
    local agmod = require("agent")
    local command = "systemctl start frpc"
    local result, err = agmod.runBashCmd(command)
    if err then
        return err
    end

    if result.status ~= 0 then
        return "exec command "..command.." status:"..result.status
    end

    if result.stderr and result.stderr ~= "" then
        return "exec command "..command.." :"..result.stderr
    end

    if result.stdout then
        mod.print(result.stdout)
    end

end

function mod.installFrpClient()
    if not mod.installFrpScriptPath then 
        local err = mod.fetchFrpInstallScript()
        if err then
            return err
        end
    end

    local agmod = require("agent")
    local result, err = agmod.runBashCmd(mod.installFrpScriptPath,600)
    if err then
        return err
    end
    
    if result.status ~= 0 then
        return "status "..result.status.." error "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return result.stderr
    end 

    if result.stdout then
        mod.print(result.stdout)
    end

    return nil
end


function mod.print(msg)
    local logLeve = "info"
    if type(msg) == "table" then
        local tableMsg = "{\n"
        for key, value in pairs(msg) do
            tableMsg = string.format("%s %s:%s\n", tableMsg, key, value)
        end
        msg = string.format("%s %s", tableMsg,"}")
         
    end
    
    print(string.format('time="%s" leve=%s lua=%s msg="%s"', os.date("%Y-%m-%dT%H:%M:%S"), logLeve, mod.luaScriptName, msg))
end


return mod
