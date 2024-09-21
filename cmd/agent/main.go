package main

import (
	"agent/agent"
	"context"
	"time"

	log "github.com/sirupsen/logrus"
)

func main() {
	agrs := &agent.AgentArguments{
		WorkingDir:     "d:/golua-agent-test/test",
		ScriptFileName: "script.lua",

		ScriptInvterval: 60,
		ServerURL:       "http://localhost:8080/update/lua",
	}

	agent, err := agent.New(agrs)
	if err != nil {
		log.Fatal(err)
	}

	ctx, fn := context.WithTimeout(context.TODO(), time.Second*10000)
	defer fn()

	agent.Run(ctx)
}
