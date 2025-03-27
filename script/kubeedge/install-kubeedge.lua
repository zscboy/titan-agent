local mod = {luaScriptName="install-kubeedge.lua"}

function mod.start()
    mod.print("mod.start")

    mod.timerInterval = 60
    mod.getBaseInfo()

    if not mod.isInstallKubeedge() and mod.isRoot() then
        -- install kube
        mod.print("install kubeedge..")
        local outputInfo, err = mod.installKubeedge()
        if err then
            mod.print("installKubeedge error "..err)
            mod.installErr = err
        else 
            mod.print("installKubeedge info:", outputInfo)
        end
    end

    if mod.isInstallKubeedge() and not mod.isKubeedgeStart() then
        local err= mod.startKubeAndJoinCluster()
        if err then
            mod.print("startKubeAndJoinCluster error "..err)
            mod.runErr = err
        end
    end

    mod.startTimer()
end

function mod.isInstallKubeedge()
    local agmod = require("agent")
    local result, err = agmod.runBashCmd("which containerd")
    if err then
        mod.print("which containerd:"..err)
        return false
    end

    if result.status ~= 0 then
        mod.print("which containerd:"..result.stderr)
        return false
    end

    if result.stdout =="" then
        return false
    end

    local result, err = agmod.runBashCmd("which keadm")
    if err then
        mod.print("which keadm:"..err)
        return false
    end

    if result.status ~= 0 then
        mod.print("which keadm:"..result.stderr)
        return false
    end

    if result.stdout =="" then
        return false
    end
    return true
end

function mod.isRoot()
    local agmod = require("agent")
    local result, err = agmod.runBashCmd("whoami")
    if err then
        mod.print("whoami:"..err)
        return false
    end
    if result.status ~= 0 then
        mod.print("whoami:"..result.stderr)
        return false
    end

    print("user:", result.stdout)

    local strings = require("strings")
    local user = strings.trim_suffix(result.stdout, "\n")
    if user == "root" then
        return true
    end
    return false
end

function mod.installKubeedge()
    if not mod.installKubeedgeScriptPath then
        local err = mod.fetchInstallKubeedgeScript()
        if err then
            return nil, err
        end
    end
    
    local agmod = require("agent")
    local result, err = agmod.exec(mod.installKubeedgeScriptPath,300)
    if err then
        return nil, err
    end

    
    if result.status ~= 0 then
        return nil, "status "..result.status.." error "..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return nil, result.stderr
    end

    return result.stdout, nil

end

function mod.fetchInstallKubeedgeScript()
    local scriptName = "install-kubeedge.sh"
    local scriptURL = "https://agent.titannet.io/install-kubeedge.sh"
    local scriptPath = mod.info.appDir .."/"..scriptName
    local err = mod.downloadScript(scriptURL, scriptPath)
    if err then
        return  err
    end
    local agmod = require("agent")
    local err = agmod.chmod(scriptPath, "0755")
    if err then
        return err
    end
    
    mod.installKubeedgeScriptPath = scriptPath
    return nil
end

function mod.downloadScript(url, filePath) 
    local http = require("http")
    local client = http.client({timeout= 10})

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

function mod.isKubeedgeStart()
    local agent = require("agent")
    local result, err = agent.runBashCmd("pgrep keadm")
    if err then
        mod.print("pgrep keadm err:"..err)
        return false
    end

    if result.status ~= 0 then
        mod.print("pgrep keadm failed:"..result.stderr)
        return false
    end

    if result.stdout and result.stdout ~= "" then
        return true
    end
    return false
end

function mod.startKubeAndJoinCluster()
    local agmod = require("agent")
    -- remove old config
    agmod.runBashCmd("rm /etc/kubeedge")
    -- must use root user to exec keadm
    local command = "sudo keadm join --kubeedge-version=1.19.0 --cloudcore-ipport=8.218.162.82:10000  --edgenode-name abc --token c7dfdc642e51dd377fb86f50ea138256ae232e2b3c2ccc07e90b1552a6b86946.eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MzE5OTE1MjZ9.MQNjP66MxOeTNafYM1sN2UaKWqVrYGh_S1i9kqH7-4c"
    local result, err = agmod.runBashCmd(command, 300)
    if err then
        return err
    end

    if result.status ~= 0 then
        return "start kube failed, status:"..result.stderr
    end

    if result.stderr and result.stderr ~= "" then
        return result.stderr
    end

    if result.stdout and result.stdout ~= "" then
        mod.print("start kube successed: ", result.stdout)
    end

    return nil
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
    if not mod.isInstallKubeedge() and mod.isRoot() then
        -- install kube
        local info, err = mod.installKubeedge()
        if err then
            mot.print("installKubeedge error "..err)
            mod.installErr = err
        else 
            mot.print("installKubeedge: "..info)
        end
    end

    local metric = {}
    if mod.isInstallKubeedge() and not mod.isKubeedgeStart() then
        local err = mod.startKubeAndJoinCluster()
        if err then
            mot.print("startKubeAndJoinCluster error "..err)
            mod.runErr = err
        end
        metric.status = "installing"
        mod.installErr = nil
    else 
        metric.status = "running"
    end

    if mod.installErr then
        metric.installErr = installErr
    end

    if mod.runErr then
        metric.runErr = runErr
    end

    sendMetrics(metric)

end

function mod.sendMetrics(metrics)
    local metric = require("metric")
    local json = require("json")
    local jsonString, err = json.encode(metrics)
    if err then
        mod.print("encode metrics  failed:"..err)
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
