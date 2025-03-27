local mod = {luaScriptName="script.lua"}

function mod.start()
    mod.print("mod.start")
    mod.downloadTimeout = 600
    mod.timerInterval = 60
    mod.processName = "controller"
    mod.serverURL = "https://www-test-api.titannet.io"
    mod.webUrl = "https://www-test4.titannet.io/api/network/bind_node"
    mod.controllerConfigURLPath = "/config/controller"
    mod.downloadPackageName = "controller.zip"
    mod.extraControllerDir = "controller-extra"
    mod.isUpdate = false
    -- init base info
    mod.getBaseInfo()

    if mod.info.os == "windows" then
        mod.processName = "controller.exe"
    end


    mod.loadLocal()

    local checkUpdate = function(isUpdating)
        if not isUpdating then
            mod.isUpdate = false
            mod.startBusinessJob()
        end
    end

    mod.isUpdate = true
    mod.updateFromServer(checkUpdate)

    mod.startTimer()

end


function mod.stop()
    mod.stopBusinessJob()

    if mod.logFile then
        mod.logFile:close()
    end
end

function mod.getBaseInfo()
    local agent = require 'agent'
    local info = agent.info()
    if info then
        mod.info = info
        mod.serverURL = info.serverURL
        mod.print(info)
    end
end

function mod.loadLocal()
    local agmod = require("agent")
    local processAPath = mod.info.workingDir .."/A/"..mod.processName
    local processA = mod.loadprocessInfo(processAPath)
    if processA then
        local downloadPackagePath = mod.info.workingDir .."/A/"..mod.downloadPackageName
        processA.md5 = agmod.fileMD5(downloadPackagePath)
        processA.ab = "A"
        processA.dir = mod.info.workingDir .."/A"
    end

    local processBPath = mod.info.workingDir .."/B/"..mod.processName
    local processB = mod.loadprocessInfo(processAPath)
    if processB then
        local downloadPackagePath = mod.info.workingDir .."/B/"..mod.downloadPackageName
        processA.md5 = agmod.fileMD5(downloadPackagePath)
        processB.ab = "B"
        processA.dir = mod.info.workingDir .."/B"
    end

    if processA and processB then
        if mod.compareVersion(processA, processB) >= 0 then 
            mod.process = processA
        else
            mod.process = processB
        end 

    elseif processA then
        mod.process = processA
    elseif processB then
        mod.process = processB
    end
end

function mod.loadprocessInfo(filePath)
    local goos = require("goos")
    local stat, err = goos.stat(filePath)
    if err then
        return nil
    end


    local process = {}
    process.filePath = filePath
    process.name = mod.processName

    local agmod = require("agent")
    local command = filePath.." version"
    local result, err = agmod.exec(command)
    if err then
        mod.print("get version failed "..err)
        return process
    end

    if result.status ~= 0 then
        mod.print("get version failed "..result.stderr)
        return process
    end

    if result.stdout then
        local strings = require("strings")
        local version = strings.trim_suffix(result.stdout, "\n")
        mod.print("mod.loadprocessInfo version "..version)
        process.version = version
    end
    return process
end

-- return 1 if prgressA.version > progresB.version
-- return 0 if prgressA.version == progresB.version
-- return -1 if prgressA.version < progresB.version
function mod.compareVersion(processA, processB)
    if processA.version == processB.version then
        return 0
    end

    if processA.version == "" then
        return -1
    end

    if processB.version == "" then
        return 1
    end

    local strings = require("strings")
    local resultA = strings.split(processA.version, ".")
    local resultB = strings.split(processB.version, ".")

    for i = 1, 3 do
        if resultA[i] > resultB[i] then
            return processA
        elseif resultA[i] < resultB[i] then
            return processB
        end
    end
    
end

function mod.startBusinessJob()
    if not mod.process then
        mod.print("start process "..mod.processName.." not exit")
        return
    end

    local channel = ""
    if mod.info.channel then
        channel = mod.info.channel
    end

    local logFilePath = mod.process.dir.."/log"
    local filePath = mod.process.filePath

    local cmdString = filePath.." run --working-dir "..mod.info.workingDir.." --server-url "..mod.serverURL.." --channel="..channel.." --script-interval 60".." --web-url="..mod.webUrl.." --key="..mod.info.key
    
    mod.print("cmdString "..cmdString)

    local process = require("process")
    local err = process.createProcess(mod.processName, cmdString)
    if err then
        print("start "..filePath.." failed "..err)
        -- TODO: if A rollback to B, or A
        return
    end

    mod.print("start "..filePath.." success")
end

function mod.stopBusinessJob()
    if not mod.process then
        mod.print("stop process "..mod.processName.." not exit")
        return
    end


    local process = require("process")
    local p = process.getProcess(mod.processName)
    if p then
        local agmod = require("agent")
        local result =""
        local err = ""
        if mod.info.os == "windows" then
            result, err = agmod.exec("taskkill /PID "..p.pid.." /F")
        else
            result, err = agmod.exec("kill "..p.pid)
        end

        if err then
            mod.print("kill "..mod.processName.." failed:"..err)
        else 
            mod.print("stop process "..mod.processName)
        end
    end
end

function mod.startTimer()
    local tmod = require("timer")
    tmod.createTimer('monitor', mod.timerInterval, 'onTimerMonitor')
    tmod.createTimer('update', mod.timerInterval, 'onTimerUpdate')
end

-- function mod.restartBusinessJob()
--     mod.stopBusinessJob()
--     mod.startBusinessJob()
-- end

function mod.onTimerMonitor()
    mod.print("onTimerMonitor")
    if mod.monitorLastActivitTime then
        if os.difftime(os.time(), mod.monitorLastActivitTime) < mod.timerInterval then
            mod.print("insufficient time to monitor")
            return
        end
    end
    mod.monitorLastActivitTime = os.time()
    

    local process = require("process")
    if not mod.process then 
        mod.print("mod.onTimerMonitor process not load")
        return
    end

    local p = process.getProcess(mod.processName)
    if p then
        mod.print("process "..p.name.." "..p.pid.." running")

        local agmod = require("agent")
        local command = mod.process.filePath.." version"

        mod.print("command "..command)
        local result, err = agmod.exec(command)
        if err then
            mod.print("check version error "..err)
        else 
            if result.status ~= 0 then
                mod.print("check version err "..result.stderr)
            else
                local strings = require("strings")
                local version = strings.trim_suffix(result.stdout, "\n")
                mod.print("version "..version)
            end
        end
    else 
        mod.print("mod.onTimerMonitor process not start, start it")
        mod.startBusinessJob()
    end

    local process = require("process")
end


function mod.onTimerUpdate()
    mod.print("onTimerUpdate")
    if mod.updateLastActivitTime then
        if os.difftime(os.time(), mod.updateLastActivitTime) < mod.timerInterval then
            mod.print("insufficient time to update")
            return
        end
    end
    mod.updateLastActivitTime= os.time()

    if mod.isUpdate then
        mod.print("is updating")
        return
    end

    
    local checkUpdate = function(isUpdating)
        if not isUpdating then
            mod.isUpdate = false
        end
    end

    mod.isUpdate = true
    mod.updateFromServer(checkUpdate)
end

function mod.updateFromServer(callback)
    local result, err = mod.getControllerUpdateConfig()
    if err then
        mod.print("mod.updateFromServer get controller update config from server "..err)
        callback(false)
        return
    end

    if mod.process and mod.process.md5 == result.md5 then
        mod.print("mod.updateFromServer process already update")
        callback(false)
        return
    end

    mod.updateFileMD5 = result.md5 

    local filePath = mod.info.workingDir.."/"..mod.downloadPackageName
    local dmod = require 'downloader'
    local err = dmod.createDownloader("update", filePath, result.url, 'onDownloadCallback', mod.downloadTimeout)
    if err then
        mod.print("create downloader failed "..err)
        callback(false)
        return
    end
    mod.print("create downloader")
    callback(true)
end

function mod.getControllerUpdateConfig() 
    local http = require("http")
    local client = http.client({timeout= 10})

    local url = mod.serverURL..mod.controllerConfigURLPath.."?version="..mod.info.version.."&os="..mod.info.os.."&uuid="..mod.info.uuid
    local request = http.request("GET", url)
    local result, err = client:do_request(request)
    if err then
        return nil, err
    end

    if not (result.code == 200) then
        return nil, "status code "..result.code..", url:"..url
    end

    local json = require("json")
    local result, err = json.decode(result.body)
    if err then
        return nil, err
    end

    return result, nil
end


-- unzip file
-- move file to A or B
-- update mod.process
-- restart businessJob
function mod.onDownloadCallback(result)
    mod.print("onDownloadCallback, result:")

    mod.print(result)

    if not result then
        mod.isUpdate = false
        mod.print("result == nil")
        return
    end

    if result.err ~= "" then
        mod.isUpdate = false
        mod.print(result.err)
        return
    end

    if result.md5 ~= mod.updateFileMD5 then
        mod.print("download update file md5 not match")
        mod.isUpdate = false
        return
    end

    mod.updateProcess(result)
    mod.print("update process to new:")
    mod.print(mod.process)
    mod.stopBusinessJob()

    mod.isUpdate = false
end

function mod.updateProcess(downloadResult)
    local agmod = require("agent")
    local goos = require("goos")

    local outputDir = mod.info.workingDir.."/"..mod.extraControllerDir
    local err = agmod.removeAll(outputDir)
    if err then
        mod.print("mod.updateProcess, removeAll failed "..err)
        return
    end

    -- extractZip will create outputDir if not exist
    local err agmod.extractZip(downloadResult.filePath, outputDir)
    if err then
        mod.print("extractZip "..err)
        return
    end

    local dest = mod.info.workingDir.."/B"
    local ab = "B"
    if not mod.process or mod.process.ab == "B" then
        dest = mod.info.workingDir.."/A"
        ab = "A"
    end

    -- local dest = mod.info.workingDir.."/A"
    local err = agmod.removeAll(dest)
    if err then
        mod.print("remove dir "..dest.." failed "..err)
        return
    end

    -- copyDir will create dest dir if not exist 
    local err = agmod.copyDir(outputDir, dest)
    if err then
        mod.print("copy "..outputDir.." to "..dest.." failed "..err)
        return
    end


    local filePath = dest.."/"..mod.downloadPackageName
    local ok, err = os.rename(downloadResult.filePath, filePath)
    if err then
        mod.print("rename failed "..err)
        return
    end

    local processPath = dest.."/"..mod.processName
    local err = agmod.chmod(processPath, "0755")
    if err then
        mod.print("chmod failed "..err)
        return
    end

    local process = mod.loadprocessInfo(processPath)
    if not process then
        mod.print("file "..processPath.." not exist")
        return
    end

    process.md5 = downloadResult.md5
    process.ab = ab
    process.dir = dest
    process.filePath = processPath
    mod.process = process

    err = agmod.removeAll(outputDir)
    if err then
        mod.print("remove failed "..err)
    end
end

function mod.urlencode(str)
    if (str) then
        str = string.gsub(str, "([^%w%.%- ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

function mod.tableToQueryString(tbl)
    local queryString = {}

    for k, v in pairs(tbl) do
        local encodedKey = mod.urlencode(tostring(k))
        local encodedValue = mod.urlencode(tostring(v))
        table.insert(queryString, encodedKey .. "=" .. encodedValue)
    end

    return table.concat(queryString, "&")
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