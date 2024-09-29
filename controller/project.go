package controller

import (
	"context"
	"os"

	log "github.com/sirupsen/logrus"
)

// const (
// 	version     = "0.1.0"
// 	httpTimeout = 10 * time.Second
// )

type ProjectArguments struct {
	WorkingDir     string
	ScriptFileName string

	ScriptInvterval int

	ServerURL string
}

type Project struct {
	// agentVersion string

	args *ProjectArguments

	// devInfo *DevInfo
	script *Script

	scriptFileMD5     string
	scriptFileContent []byte
	updateCh          chan ScriptUpdate
}

type ScriptUpdate struct {
	scriptFileMD5     string
	scriptFileContent []byte
}

func NewProject(args *ProjectArguments) (*Project, error) {
	p := &Project{
		// agentVersion: version,
		args: args,
		// devInfo: GetDevInfo(),
	}

	err := os.MkdirAll(args.WorkingDir, os.ModePerm)
	if err != nil {
		return nil, err
	}

	return p, nil
}

func (p *Project) Run(ctx context.Context) error {
	p.renewScript()
	loop := true

	for loop {
		script := p.currentScript()
		select {
		case ev := <-script.events():
			script.handleEvent(ev)
		case update := <-p.updateCh:
			if p.scriptFileMD5 != update.scriptFileMD5 {
				p.scriptFileMD5 = update.scriptFileMD5
				p.scriptFileContent = update.scriptFileContent
			}

		case <-ctx.Done():
			script.stop()
			log.Info("ctx done, Run() will quit")
			loop = false
		}
	}

	return nil
}

func (p *Project) currentScript() *Script {
	return p.script
}

func (p *Project) renewScript() {
	oldScript := p.script
	if oldScript != nil {
		oldScript.stop()
	}

	newScript := newScript(p.scriptFileMD5, p.scriptFileContent)
	newScript.start()

	p.script = newScript
}

func (p *Project) UpdateScript(script ScriptUpdate) {
	p.updateCh <- script
}
