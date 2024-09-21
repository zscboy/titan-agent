package agent

import (
	"fmt"
	"os/exec"
	"runtime"

	log "github.com/sirupsen/logrus"
	lua "github.com/yuin/gopher-lua"
)

// type ProcessEvent struct {
// 	tag      string
// 	callback string
// }

// func (te *ProcessEvent) evtType() string {
// 	return "process"
// }

type Process struct {
	name string
	cmd  *exec.Cmd
}

type ProcessModule struct {
	owner      *Script
	processMap map[string]*Process
}

func newProcessModule(s *Script) *ProcessModule {
	pm := &ProcessModule{
		owner:      s,
		processMap: make(map[string]*Process),
	}

	return pm
}

func (pm *ProcessModule) loader(L *lua.LState) int {
	// register functions to the table
	var exports = map[string]lua.LGFunction{
		"createProcess": pm.createProcessStub,
		"killProcess":   pm.killProcessStub,
		"listProcess":   pm.listProcessStub,
	}

	mod := L.SetFuncs(L.NewTable(), exports)

	// returns the module
	L.Push(mod)
	return 1
}

func (pm *ProcessModule) createProcessStub(L *lua.LState) int {
	// extract tag, interval, callback-name
	name := L.ToString(1)
	command := L.ToString(2)
	// callback := L.ToString(3)

	log.Infof("createProcessStub name:%s", name)

	if len(name) < 1 {
		L.Push(lua.LString("Must set process name"))
		return 1
	}

	_, exist := pm.processMap[name]
	if exist {
		return 0
	}

	cmd, err := pm.createProcess(command)
	if err != nil {
		L.Push(lua.LString(err.Error()))
		return 1
	}

	process := &Process{
		name: name,
		cmd:  cmd,
	}

	cmd.Start()

	go pm.waitProcess(process)

	pm.processMap[name] = process

	return 0
}

func (tm *ProcessModule) killProcessStub(L *lua.LState) int {
	name := L.ToString(1)
	process, exist := tm.processMap[name]
	if !exist {
		return 0
	}

	process.cmd.Process.Kill()

	delete(tm.processMap, name)

	return 0
}

func (pm *ProcessModule) listProcessStub(L *lua.LState) int {
	if len(pm.processMap) == 0 {
		return 0
	}

	t := L.NewTable()
	for _, v := range pm.processMap {
		process := L.NewTable()
		process.RawSet(lua.LString("name"), lua.LString(v.name))
		process.RawSet(lua.LString("pid"), lua.LNumber(v.cmd.Process.Pid))
		t.Append(process)
	}

	L.Push(t)
	return 1
}

func (pm *ProcessModule) waitProcess(process *Process) {
	process.cmd.Wait()
	delete(pm.processMap, process.name)
}

func (pm *ProcessModule) clear() {
	for _, v := range pm.processMap {
		v.cmd.Process.Kill()
	}

	pm.processMap = make(map[string]*Process)
}

// func (tm *ProcessModule) hasProcess(tag string) bool {
// 	_, ok := tm.processMap[tag]
// 	return ok
// }

func (tm *ProcessModule) createProcess(command string) (*exec.Cmd, error) {
	var cmd *exec.Cmd

	switch runtime.GOOS {
	case "linux", "darwin":
		cmd = exec.Command("sh", "-c", command)
	case "windows":
		cmd = exec.Command("cmd.exe", "/C", command)
	default:
		return nil, fmt.Errorf("not support os")
	}

	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd, nil
}
