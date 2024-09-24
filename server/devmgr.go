package server

import (
	"context"
	"sync"
	"time"
)

const (
	keepaliveInterval = 30 * time.Second
	offlineTime       = 60 * time.Second
)

type DevMgr struct {
	devices sync.Map
}

func newDevMgr(ctx context.Context) *DevMgr {
	dm := &DevMgr{}
	go dm.startTicker(ctx)

	return dm
}

func (dm *DevMgr) startTicker(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop() // 确保在程序结束时停止 ticker

	for {
		select {
		case <-ticker.C:
			dm.keepalive()
		case <-ctx.Done():
			return
		}
	}
}

func (dm *DevMgr) keepalive() {
	offlineDevices := make([]*Device, 0)
	dm.devices.Range(func(key, value any) bool {
		d := value.(*Device)
		if d != nil && time.Since(d.LastActivityTime) > offlineTime {
			offlineDevices = append(offlineDevices, d)
		}
		return true
	})

	for _, d := range offlineDevices {
		dm.removeDevice(d)
	}
}

func (dm *DevMgr) addDevice(device *Device) {
	dm.devices.Store(device.UUID, device)
}

func (dm *DevMgr) removeDevice(device *Device) {
	dm.devices.Delete(device.UUID)
}

func (dm *DevMgr) getDevice(uuid string) *Device {
	v, ok := dm.devices.Load(uuid)
	if !ok {
		return nil
	}
	return v.(*Device)
}

func (dm *DevMgr) getAll() []*Device {
	devices := make([]*Device, 0)
	dm.devices.Range(func(key, value any) bool {
		d := value.(*Device)
		if d != nil {
			devices = append(devices, d)
		}
		return true
	})

	return devices
}

func (dm *DevMgr) updateDevice(d *Device) {
	if len(d.UUID) == 0 {
		return
	}

	device := dm.getDevice(d.UUID)
	if device == nil {
		dm.addDevice(d)
		return
	}

	device.LastActivityTime = d.LastActivityTime
}
