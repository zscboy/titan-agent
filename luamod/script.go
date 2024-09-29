package luamod

type Script interface {
	PushEvent(event interface{})
	HasLuaFunction(string) bool
}
