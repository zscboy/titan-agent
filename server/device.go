package server

import (
	"net/url"
	"strconv"
	"time"
)

type Device struct {
	UUID                string
	AndroidID           string
	AndroidSerialNumber string

	OS              string
	Platform        string
	PlatformVersion string
	Arch            string
	BootTime        int64

	Macs string

	CPUModuleName   string
	CPUCores        int
	CPUMhz          float64
	TotalMemory     int64
	UsedMemory      int64
	AvailableMemory int64
	Baseboard       string

	LastActivityTime time.Time
}

func NewDeviceFromURLQuery(values url.Values) *Device {
	d := &Device{LastActivityTime: time.Now()}
	d.UUID = values.Get("uuid")
	d.AndroidID = values.Get("androidID")
	d.AndroidSerialNumber = values.Get("androidSerialNumber")

	d.OS = values.Get("os")
	d.Platform = values.Get("platform")
	d.PlatformVersion = values.Get("platformVersion")
	d.Arch = values.Get("arch")
	d.BootTime = stringToInt64(values.Get("bootTime"))

	d.Macs = values.Get("macs")
	d.CPUModuleName = values.Get("cpuModuleName")
	d.CPUCores = stringToInt(values.Get("cpuCores"))
	d.CPUMhz = stringToFloat64(values.Get("cpuMhz"))

	d.TotalMemory = stringToInt64(values.Get("totalmemory"))
	d.UsedMemory = stringToInt64(values.Get("usedMemory"))
	d.AvailableMemory = stringToInt64(values.Get("availableMemory"))

	d.Baseboard = values.Get("baseboard")

	return d
}

func stringToInt(v string) int {
	i, _ := strconv.Atoi(v)
	return i
}

func stringToInt64(v string) int64 {
	i, _ := strconv.ParseInt(v, 10, 64)
	return i
}

func stringToFloat64(v string) float64 {
	i, _ := strconv.ParseFloat(v, 64)
	return i
}
