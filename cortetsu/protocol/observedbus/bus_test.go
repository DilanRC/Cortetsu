package observedbus

import (
	"bufio"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/godbus/dbus/v5"
)

type privateBus struct {
	t             *testing.T
	path, address string
	command       *exec.Cmd
}

func newPrivateBus(t *testing.T) *privateBus {
	t.Helper()
	if _, err := exec.LookPath("dbus-daemon"); err != nil {
		t.Skip("dbus-daemon is required for isolated service tests")
	}
	b := &privateBus{t: t, path: filepath.Join(t.TempDir(), "bus")}
	b.address = "unix:path=" + b.path
	b.start()
	t.Cleanup(b.stop)
	return b
}
func (b *privateBus) start() {
	b.t.Helper()
	_ = os.Remove(b.path)
	cmd := exec.Command("dbus-daemon", "--session", "--nofork", "--nopidfile", "--print-address=1", "--address="+b.address)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		b.t.Fatal(err)
	}
	if err = cmd.Start(); err != nil {
		b.t.Fatal(err)
	}
	b.command = cmd
	ready := make(chan string, 1)
	go func() { line, _ := bufio.NewReader(stdout).ReadString('\n'); ready <- strings.TrimSpace(line) }()
	select {
	case address := <-ready:
		if !strings.HasPrefix(address, b.address) {
			b.stop()
			b.t.Fatalf("private bus did not start: %q", address)
		}
	case <-time.After(2 * time.Second):
		b.stop()
		b.t.Fatal("private bus start timed out")
	}
}
func (b *privateBus) stop() {
	if b.command != nil {
		_ = b.command.Process.Kill()
		_ = b.command.Wait()
		b.command = nil
	}
}

type properties struct {
	mu      sync.RWMutex
	values  map[string]any
	calls   atomic.Uint32
	blocked atomic.Bool
	release chan struct{}
}

func (p *properties) Get(iface, key string) (dbus.Variant, *dbus.Error) {
	p.calls.Add(1)
	if p.blocked.Load() {
		<-p.release
	}
	p.mu.RLock()
	defer p.mu.RUnlock()
	value, ok := p.values[iface+"."+key]
	if !ok {
		return dbus.Variant{}, dbus.NewError("org.freedesktop.DBus.Error.UnknownProperty", nil)
	}
	return dbus.MakeVariant(value), nil
}
func (p *properties) set(key string, value any) { p.mu.Lock(); p.values[key] = value; p.mu.Unlock() }

type upower struct{}

func (u upower) GetDisplayDevice() (dbus.ObjectPath, *dbus.Error) {
	return "/org/freedesktop/UPower/devices/DisplayDevice", nil
}
func fakeServices(t *testing.T, b *privateBus) (*dbus.Conn, *properties) {
	t.Helper()
	conn, err := dbus.Connect(b.address, dbus.WithAuth(dbus.AuthExternal(osUID())))
	if err != nil {
		t.Fatal(err)
	}
	p := &properties{release: make(chan struct{}), values: map[string]any{
		"org.freedesktop.UPower.OnBattery":                 false,
		"org.freedesktop.UPower.Device.IsPresent":          true,
		"org.freedesktop.UPower.Device.Percentage":         85.0,
		"org.freedesktop.NetworkManager.State":             uint32(70),
		"org.freedesktop.login1.Manager.PreparingForSleep": false,
	}}
	for _, path := range []dbus.ObjectPath{"/org/freedesktop/UPower", "/org/freedesktop/UPower/devices/DisplayDevice", "/org/freedesktop/NetworkManager", "/org/freedesktop/login1"} {
		if err = conn.Export(p, path, "org.freedesktop.DBus.Properties"); err != nil {
			t.Fatal(err)
		}
	}
	if err = conn.Export(upower{}, "/org/freedesktop/UPower", "org.freedesktop.UPower"); err != nil {
		t.Fatal(err)
	}
	for _, domain := range domains {
		reply, err := conn.RequestName(busName(domain), dbus.NameFlagDoNotQueue)
		if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
			t.Fatalf("cannot own fixture service: %v %v", reply, err)
		}
	}
	t.Cleanup(func() { conn.Close() })
	return conn, p
}
func osUID() string { return strconv.Itoa(os.Geteuid()) }
func receive(t *testing.T, events <-chan policy.Event, sequence *uint64, predicate func(policy.Event) bool) policy.Event {
	t.Helper()
	timeout := time.NewTimer(3 * time.Second)
	defer timeout.Stop()
	for {
		select {
		case event := <-events:
			if event.Sequence <= *sequence || event.Sequence > maxSafeInteger || event.Epoch == 0 || event.Epoch > maxSafeInteger {
				t.Fatalf("nonmonotonic event: %+v", event)
			}
			*sequence = event.Sequence
			if event.Type != "state.changed" || event.Producer != "dbus" || event.Session != "test" {
				t.Fatalf("bad event header: %+v", event)
			}
			encoded, _ := json.Marshal(event)
			if strings.Contains(string(encoded), "secret") || strings.Contains(string(encoded), "SSID") {
				t.Fatalf("signal payload escaped: %s", encoded)
			}
			if predicate(event) {
				return event
			}
		case <-timeout.C:
			t.Fatal("timed out waiting for authoritative event")
			return policy.Event{}
		}
	}
}
func TestPrivateBusSnapshotsSignalsOutageAndReconnect(t *testing.T) {
	b := newPrivateBus(t)
	service, p := fakeServices(t, b)
	observer := Observer{Session: "test", BusAddress: b.address, CallTimeout: 500 * time.Millisecond, ReconnectDelay: 20 * time.Millisecond}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan policy.Event, 64)
	finished := make(chan error, 1)
	go func() { finished <- observer.Run(ctx, events) }()
	var sequence uint64
	initial := map[string]policy.Event{}
	for len(initial) < 3 {
		event := receive(t, events, &sequence, func(e policy.Event) bool { return e.Fields["state"] != "unavailable" })
		initial[event.Domain] = event
	}
	epoch := initial["power"].Epoch
	if initial["power"].Fields["percentage_band"] != "high" || initial["power"].Fields["ac_online"] != "true" || initial["connectivity"].Fields["connected"] != "true" || initial["session"].Fields["state"] != "awake" {
		t.Fatal(initial)
	}
	// No recurring property calls while the owners are idle.
	time.Sleep(60 * time.Millisecond)
	before := p.calls.Load()
	time.Sleep(120 * time.Millisecond)
	if p.calls.Load() != before {
		t.Fatal("observer polls properties without signals")
	}
	p.set("org.freedesktop.NetworkManager.State", uint32(20))
	// This signal falsely claims connected; only the owner's property is used.
	if err := service.Emit("/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager.StateChanged", uint32(70)); err != nil {
		t.Fatal(err)
	}
	network := receive(t, events, &sequence, func(e policy.Event) bool { return e.Domain == "connectivity" })
	if network.Fields["connected"] != "false" {
		t.Fatalf("trusted signal body: %+v", network)
	}
	p.set("org.freedesktop.UPower.OnBattery", true)
	p.set("org.freedesktop.UPower.Device.Percentage", 18.0)
	if err := service.Emit("/org/freedesktop/UPower", "org.freedesktop.DBus.Properties.PropertiesChanged", "org.freedesktop.UPower", map[string]dbus.Variant{"OnBattery": dbus.MakeVariant(false), "SSID": dbus.MakeVariant("secret")}, []string{}); err != nil {
		t.Fatal(err)
	}
	power := receive(t, events, &sequence, func(e policy.Event) bool { return e.Domain == "power" })
	if power.Fields["ac_online"] != "false" || power.Fields["percentage_band"] != "low" {
		t.Fatalf("did not read current owner: %+v", power)
	}
	// An explicit refresh reads new data even when no signal has arrived.
	p.set("org.freedesktop.login1.Manager.PreparingForSleep", true)
	fresh, err := observer.Snapshot(context.Background(), "session")
	if err != nil || fresh["state"] != "sleeping" {
		t.Fatalf("%v %v", fresh, err)
	}
	if err := service.Emit("/org/freedesktop/login1", "org.freedesktop.login1.Manager.PrepareForSleep", false); err != nil {
		t.Fatal(err)
	}
	sleep := receive(t, events, &sequence, func(e policy.Event) bool { return e.Domain == "session" })
	if sleep.Fields["state"] != "sleeping" {
		t.Fatal(sleep)
	}
	// A service disappearing clears all old values instead of publishing cache.
	service.Close()
	gone := map[string]bool{}
	for len(gone) < 3 {
		event := receive(t, events, &sequence, func(e policy.Event) bool { return e.Fields["state"] == "unavailable" })
		if len(event.Fields) != 2 {
			t.Fatalf("stale fields in unavailable: %+v", event)
		}
		gone[event.Domain] = true
	}
	b.stop()
	b.start()
	_, _ = fakeServices(t, b)
	restarted := map[string]bool{}
	for len(restarted) < 3 {
		event := receive(t, events, &sequence, func(e policy.Event) bool { return e.Epoch > epoch && e.Fields["state"] != "unavailable" })
		restarted[event.Domain] = true
	}
	cancel()
	select {
	case err := <-finished:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("observer did not cancel")
	}
}
func TestSnapshotPropertyDeadlineIsBounded(t *testing.T) {
	b := newPrivateBus(t)
	_, p := fakeServices(t, b)
	p.blocked.Store(true)
	defer close(p.release)
	observer := Observer{Session: "test", BusAddress: b.address, CallTimeout: 50 * time.Millisecond}
	started := time.Now()
	fields, err := observer.Snapshot(context.Background(), "session")
	if err == nil || fields != nil || time.Since(started) > 400*time.Millisecond {
		t.Fatalf("unbounded property read: %v %v %v", fields, err, time.Since(started))
	}
}
