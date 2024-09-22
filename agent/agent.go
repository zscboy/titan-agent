package agent

import (
	"context"
	"crypto/md5"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
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
	id           string

	args *AgentArguments

	devInfo *DevInfo
	script  *Script

	scriptFileMD5     string
	scriptFileContent []byte
}

type UpdateConfig struct {
	MD5 string `json:"md5"`
	URL string `json:"url"`
}

func New(args *AgentArguments) (*Agent, error) {
	agent := &Agent{
		agentVersion: version,
		args:         args,
		devInfo:      GetDevInfo(),
	}

	return agent, nil
}

func (a *Agent) Version() string {
	return a.agentVersion
}

func (a *Agent) ID() string {
	return a.id
}

func (a *Agent) Run(ctx context.Context) error {
	a.loadLocal()
	a.updateScriptFromServer()
	a.renewScript()

	scriptUpdateinterval := time.Second * time.Duration(a.args.ScriptInvterval)
	ticker := time.NewTicker(scriptUpdateinterval)
	scriptUpdateTime := time.Now()
	loop := true
	defer ticker.Stop()

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
	updateConfig, err := a.getUpdateConfigFromServer()
	if err != nil {
		log.Errorf("updateScriptFromServer get update config: %s", err.Error())
		return
	}

	if a.scriptFileMD5 == updateConfig.MD5 {
		return
	}

	buf, err := a.getScriptFromServer(updateConfig.URL)
	if err != nil {
		log.Errorf("updateScriptFromServer get script:%s", err.Error())
		return
	}

	newFileMD5 := fmt.Sprintf("%x", md5.Sum(buf))
	if newFileMD5 != updateConfig.MD5 {
		log.Errorf("Server script file md5 not match")
		return
	}

	a.scriptFileContent = buf
	a.scriptFileMD5 = updateConfig.MD5
	a.updateScriptFile(buf)

	log.Info("update script file, md5 ", updateConfig.MD5)
}

func (a *Agent) currentScript() *Script {
	return a.script
}

func (a *Agent) renewScript() {
	oldScript := a.script
	if oldScript != nil {
		oldScript.stop()
	}

	newScript := newScript(a, a.scriptFileMD5, a.scriptFileContent)
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

func (a *Agent) getUpdateConfigFromServer() (*UpdateConfig, error) {
	devInfoQuery := a.devInfo.ToURLQuery()
	devInfoQuery.Add("version", a.agentVersion)
	queryString := devInfoQuery.Encode()

	url := fmt.Sprintf("%s?%s", a.args.ServerURL, queryString)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("getScriptInfoFromServer status code: %d, msg: %s, url: %s", resp.StatusCode, string(body), url)
	}

	// Read and handle the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	updateConfig := &UpdateConfig{}
	err = json.Unmarshal(body, updateConfig)
	if err != nil {
		return nil, nil
	}
	return updateConfig, nil
}

func (a *Agent) getScriptFromServer(url string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("getScriptFromServer status code: %d, msg: %s, url: %s", resp.StatusCode, string(body), url)
	}

	// Read and handle the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	return body, nil
}

func (a *Agent) updateScriptFile(scriptContent []byte) error {
	filePath := path.Join(a.args.WorkingDir, a.args.ScriptFileName)
	f, err := os.OpenFile(filePath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = f.Write(scriptContent)
	return err
}
