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
	url, fileMD5, err := a.getScriptURLAndMD5FromServer()
	if err != nil {
		log.Errorf("updateScriptFromServer get script url and md5:%s", err.Error())
		return
	}

	if a.scriptFileMD5 == fileMD5 {
		return
	}

	buf, err := a.getScriptFromServer(url)
	if err != nil {
		log.Errorf("updateScriptFromServer get script:%s", err.Error())
		return
	}

	newFileMD5 := fmt.Sprintf("%x", md5.Sum(buf))
	if newFileMD5 != fileMD5 {
		log.Errorf("Server file md5 not match")
		return
	}

	a.scriptFileContent = buf
	a.scriptFileMD5 = fileMD5
	a.updateScriptFile(buf)

	log.Info("update script file, md5 ", fileMD5)
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

func (a *Agent) getScriptURLAndMD5FromServer() (string, string, error) {
	// TODO: add id or more info
	url := fmt.Sprintf("%s?version=%s&id=%s", a.args.ServerURL, a.agentVersion, "")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return "", "", err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return "", "", fmt.Errorf("getScriptInfoFromServer status code: %d, msg: %s, url: %s", resp.StatusCode, string(body), url)
	}

	// Read and handle the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", "", err
	}

	type Ret struct {
		MD5 string `json:"md5"`
		URL string `json:"url"`
	}

	ret := Ret{}
	err = json.Unmarshal(body, &ret)
	if err != nil {
		return "", "", nil
	}
	return ret.URL, ret.MD5, nil
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
