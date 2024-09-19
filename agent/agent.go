package agent

import (
	"context"
	"crypto/md5"
	"fmt"
	"os"
	"path"
	"time"

	log "github.com/sirupsen/logrus"
)

const (
	version = "0.1.0"
)

type AgentArguments struct {
	WorkingDir     string
	ScriptFileName string

	ScriptInvterval int

	ServerURL string
}

type Agent struct {
	agentVersion string

	args *AgentArguments

	script *Script

	scriptFileMD5     string
	scriptFileContent []byte
}

func New(args *AgentArguments) (*Agent, error) {
	agent := &Agent{
		agentVersion: version,

		args: args,
	}

	return agent, nil
}

func (a *Agent) Version() string {
	return a.agentVersion
}

func (a *Agent) Run(ctx context.Context) error {
	a.loadLocal()
	a.updateScriptFromServer()
	a.renewScript()

	scriptUpdateinterval := time.Second * time.Duration(a.args.ScriptInvterval)
	ticker := time.NewTicker(scriptUpdateinterval)
	scriptUpdateTime := time.Now()
	loop := true

	for loop {
		script := a.currentScript()
		select {
		case ev := <-script.events():
			script.handleEvent(ev)
		case <-ticker.C:
			elapsed := time.Since(scriptUpdateTime)
			if elapsed > scriptUpdateinterval {
				a.updateScriptFromServer()

				if a.scriptFileMD5 != script.fileMD5 {
					a.renewScript()
				}

				scriptUpdateTime = time.Now()
			}

		case <-ctx.Done():
			script.stop()
			log.Info("ctx done, Run() will quit")
			loop = false
		}
	}

	return nil
}

func (a *Agent) updateScriptFromServer() {
	log.Info("updateScriptFromServer")
	// TODO: http.get script from server
	// TODO: with our agent version, our device informations
	// TODO: with timeout
}

func (a *Agent) currentScript() *Script {
	return a.script
}

func (a *Agent) renewScript() {
	oldScript := a.script
	if oldScript != nil {
		oldScript.stop()
	}

	newScript := newScript(a.scriptFileMD5, a.scriptFileContent)
	newScript.start()

	a.script = newScript
}

func (a *Agent) loadLocal() {
	p := path.Join(a.args.WorkingDir, a.args.ScriptFileName)
	b, err := os.ReadFile(p)
	if err != nil {
		log.Errorf("loadLocal ReadFile file failed:%v", err)
		return
	}

	a.scriptFileContent = b
	a.scriptFileMD5 = fmt.Sprintf("%x", md5.Sum(b))
}
