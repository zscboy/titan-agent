package agent

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"os"

	lua "github.com/yuin/gopher-lua"
)

type AgentModule struct {
	agent *Agent
}

func newAgentModule(agent *Agent) *AgentModule {
	am := &AgentModule{agent: agent}

	return am
}

func (am *AgentModule) loader(L *lua.LState) int {
	// register functions to the table
	var exports = map[string]lua.LGFunction{
		"md5":  am.md5,
		"info": am.info,
	}

	mod := L.SetFuncs(L.NewTable(), exports)

	// returns the module
	L.Push(mod)
	return 1
}

func (ag *AgentModule) md5(L *lua.LState) int {
	filePath := L.CheckString(1)
	if len(filePath) == 0 {
		L.Push(lua.LNil)
		L.Push(lua.LString("File path can not empty"))
	}

	md5, err := fileMD5(filePath)
	if err != nil {
		L.Push(lua.LNil)
		L.Push(lua.LString(fmt.Sprintf("%s", err)))
		return 2
	}

	L.Push(lua.LString(md5))
	return 1
}

func fileMD5(filePath string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer file.Close()

	hash := md5.New()

	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}

	md5Bytes := hash.Sum(nil)
	return hex.EncodeToString(md5Bytes), nil
}

func (am *AgentModule) info(L *lua.LState) int {
	t := L.NewTable()
	t.RawSet(lua.LString("WorkingDir"), lua.LString(am.agent.args.WorkingDir))
	t.RawSet(lua.LString("Version"), lua.LString(am.agent.Version()))

	L.Push(t)
	return 1
}
