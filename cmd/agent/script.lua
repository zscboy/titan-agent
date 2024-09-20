local mod = {}

function mod.start()
    print('start from lua')

    -- mod.count = 0
    -- local tmod = require 'timer'
    -- tmod.createTimer('counter', 3, 'onTimer')
    mod.testDownloadModule()
    -- mod.testAgentModule()

    -- tag := L.CheckString(1)
	-- filePath := L.CheckString(2)
	-- url := L.CheckString(3)
	-- timeout := L.CheckInt64(4)
	-- callback := L.CheckString(4)
end

function mod.stop()
    print('stop from lua')
end

function mod.onTimer(tag)
    print('onTimer:', tag)

    if tag == 'counter' then
        if mod.count > 2 then
            print('delete timer counter')
            local tmod = require 'timer'
            tmod.deleteTimer('counter')
        end
        mod.count = mod.count + 1
    end
end


function mod.testAgentModule()
    local agmod = require 'agent'
    local info = agmod.info()
    mod.printTable(info)

    local md5 = agmod.md5("./workerd-proxy-js.zip")
    print("md5", md5)
end

function mod.testDownloadModule()
    local agmod = require 'agent'
    local dlmod = require 'downloader'

    local workingDir = ""
    local info = agmod.info()
    if info then
        workingDir = info.wdir 
    end
    dlmod.createDownloader("app_zip", workingDir.."/workerd-proxy-js.zip", "http://120.79.221.36:10088/file/workerd-proxy-js.zip", 10, 'onDownload')
end

function mod.onDownload(result)
    mod.printTable(result)
end

function mod.printTable(t)
    for key, value in pairs(t) do
        print(key, value)
    end
end

return mod
