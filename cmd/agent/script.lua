local mod = {}

function mod.start()
    print('start from lua')

    mod.count = 0
    local tmod = require 'timer'
    tmod.createTimer('counter', 3, 'onTimer')
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

return mod
