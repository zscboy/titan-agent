package controller

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	httpTimeout = 10 * time.Second
)

type ProjectConfig struct {
	MD5       string `json:"md5"`
	URL       string `json:"url"`
	ProjectID string `json:"projectID"`
}

type ConrollerArgs struct {
	ScriptUpdateInvterval int
	ServerURL             string
}

type Controller struct {
	args     ConrollerArgs
	projects []*Project
}

func NewController(args ConrollerArgs) *Controller {
	return &Controller{projects: make([]*Project, 0)}
}

func (c *Controller) Run(ctx context.Context) error {
	c.loadLocal()
	c.updateScrptFromServer()
	// a.renewScript()

	scriptUpdateinterval := time.Second * time.Duration(c.args.ScriptUpdateInvterval)
	ticker := time.NewTicker(scriptUpdateinterval)
	scriptUpdateTime := time.Now()
	for {
		select {
		case <-ticker.C:
			elapsed := time.Since(scriptUpdateTime)
			if elapsed > scriptUpdateinterval {
				c.updateScrptFromServer()
				scriptUpdateTime = time.Now()
			}
		case <-ctx.Done():
			return nil
		}

	}

}

func (c *Controller) loadLocal() {

}

func (c *Controller) updateScrptFromServer() {
	// load config from server
	projectConfigs, err := c.getUpdateConfigFromServer()
	if err != nil {
		return
	}
	_ = projectConfigs
	// check config
	// 有几种情况要更新：
	// 1. 配置中没有的要删除
	// 2. 配置中多的要添加
	// 3. 配置中md5已经改变的要更新
}

func (c *Controller) getUpdateConfigFromServer() ([]*ProjectConfig, error) {
	// devInfoQuery := a.devInfo.ToURLQuery()
	// devInfoQuery.Add("version", a.agentVersion)
	// queryString := devInfoQuery.Encode()
	// TODO: add query string
	queryString := ""

	url := fmt.Sprintf("%s?%s", c.args.ServerURL, queryString)

	ctx, cancel := context.WithTimeout(context.Background(), httpTimeout)
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

	projectConfigs := make([]*ProjectConfig, 0)
	err = json.Unmarshal(body, &projectConfigs)
	if err != nil {
		return nil, nil
	}
	return projectConfigs, nil
}
