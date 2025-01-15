local mod = {luaScriptName="linux-vmbox.lua"}

function mod.start()
    mod.print("mod.start painetos")
    mod.timerInterval = 60
    mod.VMConfigFile="config.json"

    mod.getBaseInfo()

    mod.startTimer()
end


function mod.stop()
    mod.print("mod.stop painetos")
end

function mod.getBaseInfo()
    local agent = require 'agent'
    local info = agent.info()
    if info then
        mod.info = info
        mod.print(info)
    end
end

function mod.startTimer()
    local tmod = require("timer")
    tmod.createTimer('monitor', mod.timerInterval, 'onTimerMonitor')
end

function mod.onTimerMonitor()
    mod.print("mod.onTimerMonitor painetos.lua")
    mod.print("onTimerMonitor")
    if mod.monitorLastActivitTime then
        if os.difftime(os.time(), mod.monitorLastActivitTime) < mod.timerInterval then
            mod.print("insufficient time to monitor")
            return
        end
    end
    mod.monitorLastActivitTime = os.time()


    local config = mod.readVMConfig()
    if not config then
        mod.sendMetrics({error = "Vm config "..mod.VMConfigFile.." not exist, maybe not install"})
        return
    end

    mod.print(config)

    config.status = mod.getVMStatus(config.vm_name)

    mod.sendMetrics(config)
end

function mod.readVMConfig()
    local ioutil = require("ioutil")
    local configFilePath = mod.info.appDir.."/"..mod.VMConfigFile
    local configString, err = ioutil.read_file(configFilePath)
    if err then
        return nil
    end

    local json = require("json")
    local config, err = json.decode(configString)
    if err then
        mod.print("Failed to encode config: "..err.." configString:"..configString)
        return nil
    end

    return config
end

function mod.getVMStatus(vmName)
    local agmod = require("agent")
    local command = "virsh domstate "..vmName
    local result, err = agmod.runBashCmd(command)
    if err then
        return err
    end

    if result.status ~= 0 then
        if result.stderr and result.stderr ~= "" then
            return result.stderr
        end
        return "exec command "..command.." status:"..result.status
    end

    if result.stderr and result.stderr ~= "" then
        return result.stderr
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
