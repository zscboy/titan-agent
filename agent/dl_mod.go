package agent

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	log "github.com/sirupsen/logrus"

	lua "github.com/yuin/gopher-lua"
)

// 30 seconds
const downloadTimeout = 30

type DownloadEvent struct {
	tag      string
	callback string
	filePath string
	md5      string
	err      string
}

func (de *DownloadEvent) evtType() string {
	return "download"
}

type DownloadModule struct {
	owner *Script

	downloaderMap map[string]*Downloader
}

func newDownloaderModule(s *Script) *DownloadModule {
	dm := &DownloadModule{
		owner:         s,
		downloaderMap: make(map[string]*Downloader),
	}

	return dm
}

func (dm *DownloadModule) loader(L *lua.LState) int {
	// register functions to the table
	var exports = map[string]lua.LGFunction{
		"createDownloader": dm.createDownloadStub,
		"deleteDownloader": dm.deleteDownloadStub,
	}

	mod := L.SetFuncs(L.NewTable(), exports)

	// returns the module
	L.Push(mod)
	return 1
}

func (dm *DownloadModule) createDownloadStub(L *lua.LState) int {
	tag := L.CheckString(1)
	filePath := L.CheckString(2)
	url := L.CheckString(3)
	timeout := L.CheckInt64(4)
	callback := L.CheckString(5)
	// fmt.Println("tag ", tag, " filePath ", filePath, " url ", url, " timeout ", timeout, " callback ", callback)
	if !dm.owner.hasLuaFunction(callback) {
		return 0
	}

	if len(tag) < 1 {
		return 0
	}

	if timeout <= 0 {
		timeout = downloadTimeout
	}

	_, exist := dm.downloaderMap[tag]
	if exist {
		log.Infof("downloader %s already exit", tag)
		return 0
	}

	ctx, ctxCancelFn := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Second)
	downloader := &Downloader{
		tag:         tag,
		callback:    callback,
		ctx:         ctx,
		ctxCancelFn: ctxCancelFn,
	}

	go func() {
		err := downloader.donwloadFile(filePath, url)
		dv := &DownloadEvent{
			tag:      downloader.tag,
			callback: downloader.callback,
			filePath: filePath,
		}

		if err != nil {
			dv.err = err.Error()
		} else {
			md5, err := fileMD5(filePath)
			if err == nil {
				dv.md5 = md5
			}
		}

		// remove downlaoder
		dm.owner.pushEvt(dv)
	}()

	dm.downloaderMap[tag] = downloader
	return 0
}

func (dm *DownloadModule) deleteDownloadStub(L *lua.LState) int {
	// extract tag
	tag := L.ToString(1)
	downloader, exist := dm.downloaderMap[tag]
	if !exist {
		return 0
	}

	downloader.ctxCancelFn()

	delete(dm.downloaderMap, tag)

	return 0
}

func (dm *DownloadModule) clear() {
	for _, v := range dm.downloaderMap {
		v.ctxCancelFn()
	}

	dm.downloaderMap = make(map[string]*Downloader)
}

func (dm *DownloadModule) hasDownloader(tag string) bool {
	_, ok := dm.downloaderMap[tag]
	return ok
}

type Downloader struct {
	tag         string
	callback    string
	ctx         context.Context
	ctxCancelFn context.CancelFunc
}

func (downloader *Downloader) donwloadFile(filePath, url string) error {
	req, err := http.NewRequestWithContext(downloader.ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("Downloader.downloadFile status code: %d, msg: %s, url: %s", resp.StatusCode, string(body), url)
	}

	file, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	_, err = io.Copy(file, resp.Body)
	if err != nil {
		return err
	}

	return nil
}
