package agent

import (
	"bytes"
	"fmt"
	"net/url"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/jaypipes/ghw"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
	lua "github.com/yuin/gopher-lua"
)

type DevInfo struct {
	HostName        string
	OS              string
	Platform        string
	PlatformVersion string
	BootTime        int64
	Arch            string

	Macs string

	CPUModuleName   string
	CPUCores        int
	CPUMhz          float64
	TotalMemory     int64
	UsedMemory      int64
	AvailableMemory int64
	Baseboard       string

	UUID                string
	AndroidID           string
	AndroidSerialNumber string
}

func GetDevInfo() *DevInfo {
	info, _ := host.Info()

	devInfo := &DevInfo{}
	// host info
	devInfo.HostName = info.Hostname
	devInfo.OS = info.OS
	devInfo.Platform = info.Platform
	devInfo.PlatformVersion = info.PlatformVersion
	devInfo.BootTime = int64(info.BootTime)
	devInfo.Arch = info.KernelArch

	var macs = ""
	interfaces, _ := net.Interfaces()
	for _, interf := range interfaces {
		macs += fmt.Sprintf("%s:%s,", interf.Name, interf.HardwareAddr)
	}
	devInfo.Macs = strings.TrimSuffix(macs, ",")

	// cpu info
	cpuInfo, err := cpu.Info()
	if err == nil && len(cpuInfo) > 0 {
		devInfo.CPUModuleName = cpuInfo[0].ModelName
		devInfo.CPUMhz = cpuInfo[0].Mhz
		devInfo.CPUCores = int(cpuInfo[0].Cores)
		if devInfo.CPUCores == 1 {
			devInfo.CPUCores = len(cpuInfo)
		}
	}

	// memory info
	v, _ := mem.VirtualMemory()
	devInfo.TotalMemory = int64(v.Total)
	devInfo.UsedMemory = int64(v.Used)
	devInfo.AvailableMemory = int64(v.Available)

	baseboard, _ := ghw.Baseboard()
	devInfo.Baseboard = fmt.Sprintf("Vendor:%s,Product:%s", baseboard.Vendor, baseboard.Product)

	devInfo.getAndroidID()
	devInfo.getUUID()
	devInfo.getAndroidSerialNumber()

	if len(devInfo.AndroidSerialNumber) != 0 || len(devInfo.AndroidID) != 0 {
		devInfo.OS = "android"
	}

	return devInfo
}

func (devInfo *DevInfo) getAndroidID() {
	if runtime.GOOS != "linux" {
		return
	}

	id, err := runCmd("settings get secure android_id")
	if err != nil {
		return
	}

	devInfo.AndroidID = id

}

func (devInfo *DevInfo) getUUID() {
	if runtime.GOOS != "linux" {
		return
	}

	serialno, err := runCmd("cat /proc/sys/kernel/random/uuid")
	if err != nil {
		return
	}

	devInfo.UUID = serialno
}

func (devInfo *DevInfo) getAndroidSerialNumber() {
	if runtime.GOOS != "linux" {
		return
	}

	uuid, err := runCmd("getprop ro.serialno")
	if err != nil {
		return
	}

	devInfo.AndroidSerialNumber = uuid
}

func runCmd(command string) (string, error) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "linux", "darwin":
		cmd = exec.Command("sh", "-c", command)
	case "windows":
		cmd = exec.Command("cmd.exe", "/C", command)
	default:
		return "", fmt.Errorf("unsupported os")
	}

	stdout, stderr := bytes.Buffer{}, bytes.Buffer{}
	cmd.Stderr = &stderr
	cmd.Stdout = &stdout

	if err := cmd.Start(); err != nil {
		return "", err
	}

	done := make(chan error)
	go func() {
		done <- cmd.Wait()
	}()

	select {
	case <-time.After(3 * time.Second):
		cmd.Process.Kill()
		return "", fmt.Errorf("timeout")
	case err := <-done:
		if err != nil {
			return "", fmt.Errorf("%s,%s", err.Error(), stderr.String())
		}
		return strings.Trim(stdout.String(), "\n"), nil
	}
}

func (devInfo *DevInfo) ToURLQuery() url.Values {
	query := url.Values{}
	query.Add("hostname", devInfo.HostName)
	query.Add("os", devInfo.OS)
	query.Add("platform", devInfo.Platform)
	query.Add("platformVersion", devInfo.PlatformVersion)
	query.Add("bootTime", fmt.Sprintf("%d", devInfo.BootTime))
	query.Add("arch", devInfo.Arch)

	query.Add("macs", devInfo.Macs)

	query.Add("cpuModuleName", devInfo.CPUModuleName)
	query.Add("cpuCores", fmt.Sprintf("%d", devInfo.CPUCores))
	query.Add("cpuMhz", fmt.Sprintf("%f", devInfo.CPUMhz))

	query.Add("totalmemory", fmt.Sprintf("%d", devInfo.TotalMemory))
	query.Add("usedMemory", fmt.Sprintf("%d", devInfo.UsedMemory))
	query.Add("availableMemory", fmt.Sprintf("%d", devInfo.AvailableMemory))

	query.Add("baseboard", devInfo.Baseboard)

	query.Add("uuid", devInfo.UUID)
	query.Add("androidID", devInfo.AndroidID)
	query.Add("androidSerialNumber", devInfo.AndroidSerialNumber)
	return query
}

func (devInfo *DevInfo) ToLuaTable(L *lua.LState) *lua.LTable {
	t := L.NewTable()
	t.RawSet(lua.LString("hostname"), lua.LString(devInfo.HostName))
	t.RawSet(lua.LString("os"), lua.LString(devInfo.OS))
	t.RawSet(lua.LString("platform"), lua.LString(devInfo.Platform))
	t.RawSet(lua.LString("platformVersion"), lua.LString(devInfo.PlatformVersion))
	t.RawSet(lua.LString("bootTime"), lua.LNumber(devInfo.BootTime))
	t.RawSet(lua.LString("arch"), lua.LString(devInfo.Arch))

	t.RawSet(lua.LString("macs"), lua.LString(devInfo.Macs))

	t.RawSet(lua.LString("cpuModuleName"), lua.LString(devInfo.CPUModuleName))
	t.RawSet(lua.LString("cpuCores"), lua.LNumber(devInfo.CPUCores))
	t.RawSet(lua.LString("cpuMhz"), lua.LNumber(devInfo.CPUMhz))

	t.RawSet(lua.LString("totalmemory"), lua.LNumber(devInfo.TotalMemory))
	t.RawSet(lua.LString("usedMemory"), lua.LNumber(devInfo.UsedMemory))
	t.RawSet(lua.LString("availableMemory"), lua.LNumber(devInfo.AvailableMemory))

	t.RawSet(lua.LString("baseboard"), lua.LString(devInfo.Baseboard))

	t.RawSet(lua.LString("uuid"), lua.LString(devInfo.UUID))
	t.RawSet(lua.LString("androidID"), lua.LString(devInfo.AndroidID))
	t.RawSet(lua.LString("androidSerialNumber"), lua.LString(devInfo.AndroidSerialNumber))
	return t
}
