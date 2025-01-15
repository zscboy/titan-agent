local mod = {luaScriptName="empty.lua"}

function mod.start()
    mod.print("mod.start")
    mod.timerInterval = 30
    mod.getBaseInfo()

    mod.startTimer()

end


function mod.stop()
    mod.print("mod.stop")
end

function mod.startTimer()
    local tmod = require("timer")
    tmod.createTimer('monitor', mod.timerInterval, 'onTimerMonitor')
end


function mod.onTimerMonitor()
    mod.print("mod.onTimerMonitor")
    if mod.monitorLastActivitTime then
        if os.difftime(os.time(), mod.monitorLastActivitTime) < mod.timerInterval then
            mod.print("insufficient time to monitor")
            return
        end
    end
    mod.monitorLastActivitTime = os.time()

    local metric = {status="running"}
    local apps = mod.listApps()
    if apps then
        metric.apps = apps
    end

    mod.sendMetrics(metric)
end

function mod.listApps() 
    local agent = require("agent")
    local cmd = "ls "..mod.info.workingDir.."/apps"
    mod.print("cmd: "..cmd)
    local result, err = agent.runBashCmd(cmd)
    if err then
       mod.print("ls:"..err)
       return err
   end

   if result.status ~= 0 then
    return "ls status:"..result.status
   end
   return result.stdout  
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


function mod.getBaseInfo()
    local agent = require 'agent'
    local info = agent.info()
    if info then
        mod.info = info
        mod.print("baseInfo:")
        mod.print(info)
    end
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
    
    print(string.format('time="%s" leve=%s lua=%s msg="%s"', os.date("%Y-%m-%dT%H:%M:%S"), logLeve,mod.luaScriptName, msg))
end

return mod
