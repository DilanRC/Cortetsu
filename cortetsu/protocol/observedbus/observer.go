// Package observedbus observes system D-Bus owners without polling or writes.
// Signals only invalidate a domain: every emitted value comes from a fresh,
// bounded property read addressed to the bus's current unique owner. No signal
// payload, device name, network identifier, or credentials enter policy events.
package observedbus

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"maps"
	"math"
	"net"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/godbus/dbus/v5"
)

const maxSafeInteger uint64 = 9007199254740991

var domains = []string{"power", "connectivity", "session"}
var sessionName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$`)
var errUnavailable = errors.New("OWNER_UNAVAILABLE")
var errConfiguration = errors.New("INVALID_OBSERVER_CONFIGURATION")

// Observer maintains one system-bus connection. BusAddress permits an isolated
// private bus in tests. CallTimeout and ReconnectDelay are bounded overrides;
// zero values use two seconds and 250 milliseconds respectively.
type Observer struct {
	Session        string
	BusAddress     string
	CallTimeout    time.Duration
	ReconnectDelay time.Duration
}

func (o Observer) timeout() time.Duration {
	if o.CallTimeout <= 0 {
		return 2 * time.Second
	}
	if o.CallTimeout > 10*time.Second {
		return 10 * time.Second
	}
	return o.CallTimeout
}
func (o Observer) delay() time.Duration {
	d := o.ReconnectDelay
	if d <= 0 {
		return 250 * time.Millisecond
	}
	if d < 10*time.Millisecond {
		return 10 * time.Millisecond
	}
	if d > 5*time.Second {
		return 5 * time.Second
	}
	return d
}
func busName(domain string) string {
	switch domain {
	case "power":
		return "org.freedesktop.UPower"
	case "connectivity":
		return "org.freedesktop.NetworkManager"
	case "session":
		return "org.freedesktop.login1"
	}
	return ""
}
func source(domain string) string {
	switch domain {
	case "power":
		return "upower"
	case "connectivity":
		return "networkmanager"
	case "session":
		return "logind"
	}
	return ""
}
func unavailable(domain string) map[string]string {
	return map[string]string{"source": source(domain), "state": "unavailable"}
}
func domainBit(domain string) uint32 {
	for index, name := range domains {
		if name == domain {
			return 1 << index
		}
	}
	return 0
}

// Only local Unix transports are supported; a configuration cannot turn this
// desktop observer into a remote D-Bus client. D-Bus percent escaping is decoded.
func (o Observer) socket() (string, error) {
	address := o.BusAddress
	if address == "" {
		address = os.Getenv("DBUS_SYSTEM_BUS_ADDRESS")
	}
	if address == "" {
		address = "unix:path=/run/dbus/system_bus_socket"
	}
	rest, ok := strings.CutPrefix(address, "unix:")
	if !ok || strings.ContainsAny(rest, ";\r\n") {
		return "", errConfiguration
	}
	path := ""
	for _, field := range strings.Split(rest, ",") {
		key, value, ok := strings.Cut(field, "=")
		if !ok {
			return "", errConfiguration
		}
		switch key {
		case "path", "abstract":
			if path != "" {
				return "", errConfiguration
			}
			decoded, err := url.PathUnescape(value)
			if err != nil || decoded == "" || strings.ContainsRune(decoded, 0) {
				return "", errConfiguration
			}
			if key == "path" && !strings.HasPrefix(decoded, "/") {
				return "", errConfiguration
			}
			if key == "abstract" {
				decoded = "@" + decoded
			}
			path = decoded
		case "guid": // Address metadata; the local socket is authenticated with EXTERNAL.
			if len(value) != 32 {
				return "", errConfiguration
			}
		default:
			return "", errConfiguration
		}
	}
	if path == "" || len(path) > 106 {
		return "", errConfiguration
	}
	return path, nil
}
func (o Observer) validate() error {
	if !sessionName.MatchString(o.Session) {
		return errConfiguration
	}
	_, err := o.socket()
	return err
}

// A three-bit invalidation set bounds memory even during signal storms. Unlike
// godbus's default delivery queue it never spawns one goroutine per signal and
// never retains signal bodies. Only the bus owner may trigger a domain read.
type signalHandler struct {
	wake    chan struct{}
	pending atomic.Uint32
	mu      sync.RWMutex
	owners  map[string]string
}

func newSignalHandler() *signalHandler {
	return &signalHandler{wake: make(chan struct{}, 1), owners: make(map[string]string)}
}
func (h *signalHandler) setOwner(domain, owner string) {
	h.mu.Lock()
	h.owners[domain] = owner
	h.mu.Unlock()
}
func (h *signalHandler) mark(domain string) {
	bit := domainBit(domain)
	if bit == 0 {
		return
	}
	for {
		old := h.pending.Load()
		if h.pending.CompareAndSwap(old, old|bit) {
			break
		}
	}
	select {
	case h.wake <- struct{}{}:
	default:
	}
}
func (h *signalHandler) take() uint32 { return h.pending.Swap(0) }
func (h *signalHandler) DeliverSignal(iface, member string, s *dbus.Signal) {
	if s == nil {
		return
	}
	if iface == "org.freedesktop.DBus" && member == "NameOwnerChanged" && s.Sender == "org.freedesktop.DBus" && s.Path == "/org/freedesktop/DBus" {
		if len(s.Body) != 3 {
			return
		}
		name, ok := s.Body[0].(string)
		if !ok {
			return
		}
		for _, domain := range domains {
			if name == busName(domain) {
				h.mark(domain)
				return
			}
		}
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, domain := range domains {
		if h.owners[domain] == "" || s.Sender != h.owners[domain] {
			continue
		}
		path := string(s.Path)
		switch domain {
		case "power":
			if iface == "org.freedesktop.DBus.Properties" && member == "PropertiesChanged" && (path == "/org/freedesktop/UPower" || strings.HasPrefix(path, "/org/freedesktop/UPower/devices/")) {
				h.mark(domain)
			}
			if iface == "org.freedesktop.UPower" && path == "/org/freedesktop/UPower" && (member == "DeviceAdded" || member == "DeviceRemoved" || member == "DeviceChanged") {
				h.mark(domain)
			}
		case "connectivity":
			if path == "/org/freedesktop/NetworkManager" && ((iface == "org.freedesktop.DBus.Properties" && member == "PropertiesChanged") || (iface == "org.freedesktop.NetworkManager" && member == "StateChanged")) {
				h.mark(domain)
			}
		case "session":
			if path == "/org/freedesktop/login1" && ((iface == "org.freedesktop.DBus.Properties" && member == "PropertiesChanged") || (iface == "org.freedesktop.login1.Manager" && member == "PrepareForSleep")) {
				h.mark(domain)
			}
		}
	}
}
func (o Observer) connect(ctx context.Context, h *signalHandler) (*dbus.Conn, error) {
	path, err := o.socket()
	if err != nil {
		return nil, err
	}
	dialCtx, cancel := context.WithTimeout(ctx, o.timeout())
	defer cancel()
	raw, err := (&net.Dialer{}).DialContext(dialCtx, "unix", path)
	if err != nil {
		return nil, errUnavailable
	}
	unix, ok := raw.(*net.UnixConn)
	if !ok {
		raw.Close()
		return nil, errUnavailable
	}
	deadline, _ := dialCtx.Deadline()
	if err = unix.SetDeadline(deadline); err != nil {
		unix.Close()
		return nil, errUnavailable
	}
	conn, err := dbus.DialUnix(unix, dbus.WithContext(ctx), dbus.WithSignalHandler(h))
	if err != nil {
		unix.Close()
		return nil, errUnavailable
	}
	// EXTERNAL uses the local transport's UID; no cookie/password file is read.
	if err = conn.Auth([]dbus.Auth{dbus.AuthExternal(strconv.Itoa(os.Geteuid()))}); err != nil {
		conn.Close()
		return nil, errUnavailable
	}
	if err = conn.Hello(); err != nil {
		conn.Close()
		return nil, errUnavailable
	}
	if err = unix.SetDeadline(time.Time{}); err != nil {
		conn.Close()
		return nil, errUnavailable
	}
	return conn, nil
}
func subscribe(ctx context.Context, conn *dbus.Conn) error {
	for _, domain := range domains {
		if err := conn.AddMatchSignalContext(ctx, dbus.WithMatchSender("org.freedesktop.DBus"), dbus.WithMatchInterface("org.freedesktop.DBus"), dbus.WithMatchMember("NameOwnerChanged"), dbus.WithMatchArg(0, busName(domain))); err != nil {
			return errUnavailable
		}
	}
	rules := [][]dbus.MatchOption{
		{dbus.WithMatchSender(busName("power")), dbus.WithMatchInterface("org.freedesktop.DBus.Properties"), dbus.WithMatchMember("PropertiesChanged"), dbus.WithMatchPathNamespace("/org/freedesktop/UPower")},
		{dbus.WithMatchSender(busName("power")), dbus.WithMatchInterface("org.freedesktop.UPower"), dbus.WithMatchObjectPath("/org/freedesktop/UPower")},
		{dbus.WithMatchSender(busName("connectivity")), dbus.WithMatchInterface("org.freedesktop.DBus.Properties"), dbus.WithMatchMember("PropertiesChanged"), dbus.WithMatchObjectPath("/org/freedesktop/NetworkManager")},
		{dbus.WithMatchSender(busName("connectivity")), dbus.WithMatchInterface("org.freedesktop.NetworkManager"), dbus.WithMatchMember("StateChanged"), dbus.WithMatchObjectPath("/org/freedesktop/NetworkManager")},
		{dbus.WithMatchSender(busName("session")), dbus.WithMatchInterface("org.freedesktop.DBus.Properties"), dbus.WithMatchMember("PropertiesChanged"), dbus.WithMatchObjectPath("/org/freedesktop/login1")},
		{dbus.WithMatchSender(busName("session")), dbus.WithMatchInterface("org.freedesktop.login1.Manager"), dbus.WithMatchMember("PrepareForSleep"), dbus.WithMatchObjectPath("/org/freedesktop/login1")},
	}
	for _, rule := range rules {
		if err := conn.AddMatchSignalContext(ctx, rule...); err != nil {
			return errUnavailable
		}
	}
	return nil
}
func getOwner(ctx context.Context, conn *dbus.Conn, domain string) (string, error) {
	var owner string
	if err := conn.BusObject().CallWithContext(ctx, "org.freedesktop.DBus.GetNameOwner", 0, busName(domain)).Store(&owner); err != nil || !strings.HasPrefix(owner, ":") || len(owner) > 255 {
		return "", errUnavailable
	}
	return owner, nil
}
func property(ctx context.Context, conn *dbus.Conn, owner string, path dbus.ObjectPath, iface, key string) (any, error) {
	var value dbus.Variant
	if err := conn.Object(owner, path).CallWithContext(ctx, "org.freedesktop.DBus.Properties.Get", 0, iface, key).Store(&value); err != nil {
		return nil, errUnavailable
	}
	return value.Value(), nil
}
func powerFields(onBattery, present bool, percentage float64) (map[string]string, error) {
	fields := map[string]string{"source": "upower", "state": "available", "ac_online": strconv.FormatBool(!onBattery)}
	if !present {
		return fields, nil
	}
	if math.IsNaN(percentage) || math.IsInf(percentage, 0) || percentage < 0 || percentage > 100 {
		return nil, errUnavailable
	}
	band := "normal"
	if percentage <= 25 {
		band = "low"
	} else if percentage >= 80 {
		band = "high"
	}
	fields["percentage_band"] = band
	return fields, nil
}
func readPower(ctx context.Context, conn *dbus.Conn, owner string) (map[string]string, error) {
	value, err := property(ctx, conn, owner, "/org/freedesktop/UPower", "org.freedesktop.UPower", "OnBattery")
	onBattery, ok := value.(bool)
	if err != nil || !ok {
		return nil, errUnavailable
	}
	var display dbus.ObjectPath
	if err = conn.Object(owner, "/org/freedesktop/UPower").CallWithContext(ctx, "org.freedesktop.UPower.GetDisplayDevice", 0).Store(&display); err != nil || !strings.HasPrefix(string(display), "/org/freedesktop/UPower/devices/") {
		return nil, errUnavailable
	}
	value, err = property(ctx, conn, owner, display, "org.freedesktop.UPower.Device", "IsPresent")
	present, ok := value.(bool)
	if err != nil || !ok {
		return nil, errUnavailable
	}
	percentage := 0.0
	if present {
		value, err = property(ctx, conn, owner, display, "org.freedesktop.UPower.Device", "Percentage")
		percentage, ok = value.(float64)
		if err != nil || !ok {
			return nil, errUnavailable
		}
	}
	// The two objects must describe the same supply transition.
	again, err := property(ctx, conn, owner, "/org/freedesktop/UPower", "org.freedesktop.UPower", "OnBattery")
	if err != nil || again != onBattery {
		return nil, errUnavailable
	}
	return powerFields(onBattery, present, percentage)
}
func snapshot(ctx context.Context, conn *dbus.Conn, h *signalHandler, domain string) (map[string]string, error) {
	owner, err := getOwner(ctx, conn, domain)
	if err != nil {
		h.setOwner(domain, "")
		return nil, err
	}
	h.setOwner(domain, owner)
	var fields map[string]string
	switch domain {
	case "power":
		fields, err = readPower(ctx, conn, owner)
	case "connectivity":
		value, e := property(ctx, conn, owner, "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager", "State")
		state, ok := value.(uint32)
		if e != nil || !ok || state < 10 || state > 70 || state%10 != 0 {
			return nil, errUnavailable
		}
		fields = map[string]string{"source": "networkmanager", "state": "available", "connected": strconv.FormatBool(state >= 50)}
	case "session":
		value, e := property(ctx, conn, owner, "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PreparingForSleep")
		sleeping, ok := value.(bool)
		if e != nil || !ok {
			return nil, errUnavailable
		}
		state := "awake"
		if sleeping {
			state = "sleeping"
		}
		fields = map[string]string{"source": "logind", "state": state}
	default:
		return nil, errConfiguration
	}
	if err != nil {
		return nil, errUnavailable
	}
	latest, err := getOwner(ctx, conn, domain)
	if err != nil || latest != owner {
		return nil, errUnavailable
	}
	return fields, nil
}

// Snapshot performs one fresh, bounded read for a hysteresis timer or explicit
// resynchronization. It never returns state cached by Run or a signal payload.
func (o Observer) Snapshot(ctx context.Context, domain string) (map[string]string, error) {
	if ctx == nil || o.validate() != nil || busName(domain) == "" {
		return nil, errConfiguration
	}
	limited, cancel := context.WithTimeout(ctx, o.timeout())
	defer cancel()
	h := newSignalHandler()
	conn, err := o.connect(limited, h)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	return snapshot(limited, conn, h, domain)
}
func wait(ctx context.Context, duration time.Duration) bool {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
func seedEpoch() (uint64, error) {
	var bytes [8]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return 0, errors.New("OBSERVER_EPOCH_UNAVAILABLE")
	}
	return (binary.LittleEndian.Uint64(bytes[:]) & ((1 << 52) - 1)) + 1, nil
}

// Run uses signals and owner changes, with bounded backoff only while a bus is
// unavailable. A reconnect starts a new epoch and emits initial authoritative
// snapshots before any event deltas. Connection loss emits only unavailable.
func (o Observer) Run(ctx context.Context, out chan<- policy.Event) error {
	if ctx == nil || out == nil || o.validate() != nil {
		return errConfiguration
	}
	if ctx.Err() != nil {
		return nil
	}
	epoch, err := seedEpoch()
	if err != nil {
		return err
	}
	var sequence uint64
	last := make(map[string]map[string]string)
	emit := func(domain string, fields map[string]string, force bool) error {
		if !force && maps.Equal(last[domain], fields) {
			return nil
		}
		if sequence == maxSafeInteger {
			return errors.New("OBSERVER_SEQUENCE_EXHAUSTED")
		}
		sequence++
		event := policy.Event{Producer: "dbus", Session: o.Session, Epoch: epoch, Sequence: sequence, EmittedAtUnixMs: time.Now().UnixMilli(), Domain: domain, Type: "state.changed", Fields: maps.Clone(fields)}
		select {
		case out <- event:
			last[domain] = maps.Clone(fields)
			return nil
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	unavailableAll := func(force bool) error {
		for _, domain := range domains {
			if err := emit(domain, unavailable(domain), force); err != nil {
				return err
			}
		}
		return nil
	}
	delay := o.delay()
	for ctx.Err() == nil {
		h := newSignalHandler()
		conn, connectErr := o.connect(ctx, h)
		if connectErr == nil {
			limited, cancel := context.WithTimeout(ctx, o.timeout())
			connectErr = subscribe(limited, conn)
			cancel()
		}
		if connectErr != nil {
			if conn != nil {
				conn.Close()
			}
			if ctx.Err() != nil {
				return nil
			}
			if err := unavailableAll(false); err != nil {
				if ctx.Err() != nil {
					return nil
				}
				return err
			}
			if !wait(ctx, delay) {
				return nil
			}
			delay *= 2
			if delay > 5*time.Second {
				delay = 5 * time.Second
			}
			continue
		}
		if epoch == maxSafeInteger {
			conn.Close()
			return errors.New("OBSERVER_EPOCH_EXHAUSTED")
		}
		epoch++
		delay = o.delay()
		refresh := func(domain string, force bool) error {
			limited, cancel := context.WithTimeout(ctx, o.timeout())
			fields, readErr := snapshot(limited, conn, h, domain)
			cancel()
			if readErr != nil {
				fields = unavailable(domain)
			}
			return emit(domain, fields, force)
		}
		for _, domain := range domains {
			if err := refresh(domain, true); err != nil {
				conn.Close()
				if ctx.Err() != nil {
					return nil
				}
				return err
			}
		}
		connected := true
		for connected && ctx.Err() == nil {
			select {
			case <-ctx.Done():
				connected = false
			case <-conn.Context().Done():
				connected = false
			case <-h.wake:
				// One-shot coalescing delay; no recurring property polling.
				if !wait(ctx, 25*time.Millisecond) {
					connected = false
					break
				}
				mask := h.take()
				for _, domain := range domains {
					if mask&domainBit(domain) == 0 {
						continue
					}
					if err := refresh(domain, false); err != nil {
						conn.Close()
						if ctx.Err() != nil {
							return nil
						}
						return err
					}
				}
			}
		}
		conn.Close()
		if ctx.Err() != nil {
			return nil
		}
		if err := unavailableAll(true); err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		if !wait(ctx, delay) {
			return nil
		}
	}
	return nil
}
