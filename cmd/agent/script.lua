local mod = {}

function mod.start()
    mod.processName = "server.exe"
    mod.serverURL = "http://localhost:8080/update/business"
    mod.downloadPackageName = "business.zip"
    mod.isUpdate = false
    -- init base info
    mod.getBaseInfo()

    mod.loadLocal()


    local checkUpdate = function(isUpdating)
        if not isUpdating then
            mod.isUpdate = false
            mod.startBusinessJob()
        end
    end

    mod.isUpdate = true
    mod.updateFromServer(checkUpdate)

    -- mod.startBusinessJob()

    mod.startTimer()

end


function mod.stop()
    mod.stopBusinessJob()
end

function mod.getBaseInfo()
    local agent = require 'agent'
    local info = agent.info()
    if info then
        mod.info = info
    end
end

function mod.loadLocal()
    local agmod = require("agent")
    local processAPath = mod.info.wdir .."/A/"..mod.processName
    local processA = mod.loadprocessInfo(processAPath)
    if processA then
        local downloadPackagePath = mod.info.wdir .."/A/"..mod.downloadPackageName
        processA.md5 = agmod.fileMD5(downloadPackagePath)
        processA.ab = "A"
        processA.dir = mod.info.wdir .."/A"
    end

    local processBPath = mod.info.wdir .."/B/"..mod.processName
    local processB = mod.loadprocessInfo(processAPath)
    if progresB then
        local downloadPackagePath = mod.info.wdir .."/B/"..mod.downloadPackageName
        processA.md5 = agmod.fileMD5(downloadPackagePath)
        processB.ab = "B"
        processA.dir = mod.info.wdir .."/B"
    end

    if processA and processB then
        if mod.compareVersion(processA, processB) >= 0 then 
            mod.process = processA
        else
            mod.process = processB
        end 

    elseif processA then
        mod.process = processA
    elseif progresB then
        mod.process = processB
    end

    -- mod.printTable(mod.process)
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

    local cmd = require("cmd")
    local result, err = cmd.exec(filePath.." version")
    if err then
        print("get version failed "..err)
        return process
    end

    if result.status ~= 0 then
        print("get version failed "..result.stderr)
        return process
    end

    print("exec version stdout "..result.stdout)
    process.version = result.stdout
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
        print("start process "..mod.processName.." not exit")
        return
    end

    local process = require("process")
    local filePath = mod.process.filePath
    local cmdString = filePath.." -l 0.0.0.0:8000 -config "..mod.process.dir.."/config.json -fs "..mod.process.dir
    print("cmdString "..cmdString)
    local err = process.createProcess(mod.processName, cmdString)
    if err then
        print("start "..filePath.." failed "..err)
        -- TODO: if A rollback to B, or A
        return
    end

    print("start "..filePath.." success")
end

function mod.stopBusinessJob()
    if not mod.process then
        print("stop process "..mod.processName.." not exit")
        return
    end


    local process = require("process")
    local err = process.killProcess(mod.processName)
    if err then
        print("kill process "..mod.processName.." failed "..err)
        return
    end
    print("stop "..mod.processName.." success")
end


function mod.startTimer()
    local tmod = require 'timer'
    tmod.createTimer('monitor', 3, 'onTimerMonitor')
    tmod.createTimer('update', 3, 'onTimerUpdate')
end

function mod.restartBusinessJob()
    mod.stopBusinessJob()
    mod.startBusinessJob()
end

function mod.onTimerMonitor()
    print("onTimerMonitor")
end


function mod.onTimerUpdate()
    print("onTimerUpdate")
    if mod.isUpdate then
        print("is updating")
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
    local result, err = mod.getURLAndMD5()
    if err then
        print("mod.updateFromServer get url and md5 from server "..err)
        callback(false)
        return
    end

    if mod.process and mod.process.md5 == result.md5 then
        print("mod.updateFromServer process already update")
        callback(false)
        return
    end

    mod.updateFileMD5 = result.md5 

    local filePath = mod.info.wdir.."/"..mod.downloadPackageName
    local dmod = require 'downloader'
    dmod.createDownloader("update", filePath, result.url, 10, 'onDownloadCallback')
    print("create downloader")
    callback(true)
end

function mod.getURLAndMD5() 
    local http = require("http")
    local client = http.client({timeout= 10})

    local url = mod.serverURL.."?version="..mod.info.version.."&id="..mod.info.id
    local request = http.request("GET", url)
    local result, err = client:do_request(request)
    if err then
        return nil, err
    end

    if not (result.code == 200) then
        return nil, "status code "..result.code
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
    local agmod = require("downloader")
    agmod.deleteDownloader("update")

    print("onDownloadCallback")

    mod.printTable(result)

    if not result then
        mod.isUpdate = false
        print("result == nil")
        return
    end

    if result.err ~= "" then
        mod.isUpdate = false
        print(result.err)
        return
    end

    if result.md5 ~= mod.updateFileMD5 then
        print("download update file md5 not match")
        mod.isUpdate = false
        return
    end

    mod.updateProcess(result)
    print("process")
    mod.printTable(mod.process)
    mod.restartBusinessJob()

    mod.isUpdate = false
end

function mod.updateProcess(downloadResult)
    local agmod = require("agent")

    local outputDir = mod.info.wdir.."/business-extra"
    local err agmod.extractZip(downloadResult.filePath, outputDir)
    if err then
        print("extractZip "..err)
        return
    end

    if not mod.process or mod.process.ab == "B" then
        local dest = mod.info.wdir.."/A"
        local err = agmod.copyDir(outputDir, dest)
        if err then
            print("copy "..outputDir.." to "..dest.." failed "..err)
            return
        end

        local filePath = dest.."/"..mod.downloadPackageName
        local ok, err = os.rename(downloadResult.filePath, filePath)
        if err then
            print("rename failed "..err)
        end

        local processPath = dest.."/"..mod.processName
        local processA = mod.loadprocessInfo(processPath)
        processA.md5 = downloadResult.md5
        processA.ab = "A"
        processA.dir = dest
        mod.process = processA
    else 
        local dest = mod.info.wdir.."/B"
        local err = agmod.copyDir(outputDir, dest)
        if err then
            print("copy "..outputDir.." to "..dest.." failed "..err)
            return
        end

        local filePath = dest.."/"..mod.downloadPackageName
        local ok, err = os.rename(downloadResult.filePath, filePath)
        if err then
            print("rename failed "..err)
        end

        local processPath = dest.."/"..mod.processName
        local processB = mod.loadprocessInfo(processPath)
        processA.md5 = downloadResult.md5
        processB.ab = "A"
        processB.dir = dest
        mod.process = processB
    end

    local err = agmod.removeAll(outputDir)
    if err then
        print("remove failed "..err)
    end
end

function mod.printTable(t)
    if not t then
        print(t)
        return
    end

    for key, value in pairs(t) do
        print(key, value)
    end
end


return mod
