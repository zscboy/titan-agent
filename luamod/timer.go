package luamod

import (
	"context"
	"time"

	log "github.com/sirupsen/logrus"
	lua "github.com/yuin/gopher-lua"
)

type TimerEvent struct {
	tag      string
	callback string
}

func (te *TimerEvent) EventType() string {
	return "timer"
}

func (te *TimerEvent) Tag() string {
	return te.tag
}

func (te *TimerEvent) Callback() string {
	return te.callback
}

type Timer struct {
	tag      string
	callback string
	interval int

	ctxCancelFn context.CancelFunc
}

type TimerModule struct {
	owner Script

	timerMap map[string]*Timer
}

func NewTimerModule(s Script) *TimerModule {
	tm := &TimerModule{
		owner:    s,
		timerMap: make(map[string]*Timer),
	}

	return tm
}

func (tm *TimerModule) Loader(L *lua.LState) int {
	// register functions to the table
	var exports = map[string]lua.LGFunction{
		"createTimer": tm.createTimerStub,
		"deleteTimer": tm.deleteTimerStub,
	}

	mod := L.SetFuncs(L.NewTable(), exports)

	// returns the module
	L.Push(mod)
	return 1
}

func (tm *TimerModule) createTimerStub(L *lua.LState) int {
	// extract tag, interval, callback-name
	tag := L.ToString(1)
	interval := L.ToInt(2)
	callback := L.ToString(3)

	log.Infof("createTimerStub tag:%s, interval:%d, callback:%s", tag, interval, callback)

	if !tm.owner.HasLuaFunction(callback) {
		return 0
	}

	if len(tag) < 1 {
		return 0
	}

	_, exist := tm.timerMap[tag]
	if exist {
		return 0
	}

	ctx, ctxCancelFn := context.WithCancel(context.Background())
	timer := &Timer{
		tag:         tag,
		callback:    callback,
		interval:    interval,
		ctxCancelFn: ctxCancelFn,
	}

	go tm.serveTimer(timer, ctx)

	tm.timerMap[tag] = timer

	return 0
}

func (tm *TimerModule) deleteTimerStub(L *lua.LState) int {
	// extract tag
	tag := L.ToString(1)
	timer, exist := tm.timerMap[tag]
	if !exist {
		return 0
	}

	timer.ctxCancelFn()

	delete(tm.timerMap, tag)

	return 0
}

func (tm *TimerModule) Clear() {
	for _, v := range tm.timerMap {
		v.ctxCancelFn()
	}

	tm.timerMap = make(map[string]*Timer)
}

func (tm *TimerModule) serveTimer(timer *Timer, ctx context.Context) {
	loop := true
	interval := time.Second * time.Duration(timer.interval)
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for loop {
		select {
		case <-ticker.C:
			ev := &TimerEvent{
				tag:      timer.tag,
				callback: timer.callback,
			}

			tm.owner.PushEvent(ev)
		case <-ctx.Done():
			loop = false
		}
	}
}

func (tm *TimerModule) HasTimer(tag string) bool {
	_, ok := tm.timerMap[tag]
	return ok
}
