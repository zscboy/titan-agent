package luamod

import (
	lua "github.com/yuin/gopher-lua"
)

type InfoModule struct {
	inf *lua.LTable
}

func NewInfoModule(info *lua.LTable) *InfoModule {
	im := &InfoModule{inf: info}

	return im
}

func (im *InfoModule) Loader(L *lua.LState) int {
	// register functions to the table
	var exports = map[string]lua.LGFunction{
		"info": im.info,
	}

	mod := L.SetFuncs(L.NewTable(), exports)

	// returns the module
	L.Push(mod)
	return 1
}

func (im *InfoModule) info(L *lua.LState) int {
	L.Push(im.inf)
	return 1
}
