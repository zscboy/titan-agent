package main

import (
	"agent/agent"
	"context"
	"time"

	log "github.com/sirupsen/logrus"
)

func main() {
	agrs := &agent.AgentArguments{
		WorkingDir:     ".",
		ScriptFileName: "script.lua",

		ScriptInvterval: 60,
		ServerURL:       "https://baobei.llwant.com/test/script.lua",
	}

	agent, err := agent.New(agrs)
	if err != nil {
		log.Fatal(err)
	}

	ctx, fn := context.WithTimeout(context.TODO(), time.Second*60)
	defer fn()

	agent.Run(ctx)
}
