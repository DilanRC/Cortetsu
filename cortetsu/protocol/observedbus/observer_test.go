package observedbus

import (
	"context"
	"encoding/json"
	"math"
	"testing"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/godbus/dbus/v5"
)

func TestPowerBandsRejectUnknownAndOutOfRangeTelemetry(t *testing.T) {
	for _, test := range []struct {
		percentage float64
		band       string
	}{{0, "low"}, {25, "low"}, {25.1, "normal"}, {79.9, "normal"}, {80, "high"}, {100, "high"}} {
		fields, err := powerFields(true, true, test.percentage)
		if err != nil || fields["percentage_band"] != test.band || fields["ac_online"] != "false" || fields["source"] != "upower" || fields["state"] != "available" {
			t.Fatalf("%v %v", fields, err)
		}
	}
	for _, invalid := range []float64{-1, 101, math.NaN(), math.Inf(1)} {
		if _, err := powerFields(false, true, invalid); err == nil {
			t.Fatalf("accepted unproven percentage %v", invalid)
		}
	}
	desktop, err := powerFields(false, false, 0)
	if err != nil || desktop["ac_online"] != "true" || len(desktop) != 3 {
		t.Fatalf("invented battery metadata: %v %v", desktop, err)
	}
}
func TestSignalPayloadsCannotSupplyStateAndBurstsStayBounded(t *testing.T) {
	h := newSignalHandler()
	h.setOwner("power", ":1.1")
	h.setOwner("connectivity", ":1.2")
	forged := &dbus.Signal{Sender: ":1.999", Path: "/org/freedesktop/NetworkManager", Body: []any{uint32(70), "private title"}}
	h.DeliverSignal("org.freedesktop.NetworkManager", "StateChanged", forged)
	if h.take() != 0 {
		t.Fatal("accepted a signal from another bus peer")
	}
	real := &dbus.Signal{Sender: ":1.2", Path: "/org/freedesktop/NetworkManager", Body: []any{"SSID=secret", true}}
	for i := 0; i < 100000; i++ {
		h.DeliverSignal("org.freedesktop.NetworkManager", "StateChanged", real)
	}
	if len(h.wake) != 1 || h.take() != domainBit("connectivity") {
		t.Fatal("signal bursts were not coalesced")
	}
	if h.take() != 0 {
		t.Fatal("kept replayable signal data")
	}
	h.DeliverSignal("org.freedesktop.DBus", "NameOwnerChanged", &dbus.Signal{Sender: "org.freedesktop.DBus", Path: "/org/freedesktop/DBus", Body: []any{"org.freedesktop.UPower", ":1.old", ":1.new"}})
	if h.take() != domainBit("power") {
		t.Fatal("missed owner replacement")
	}
}
func TestUnavailableEventsNeverContainOldValues(t *testing.T) {
	for _, domain := range domains {
		fields := unavailable(domain)
		raw, _ := json.Marshal(fields)
		if len(fields) != 2 || fields["state"] != "unavailable" || fields["source"] == "" {
			t.Fatalf("%s: %s", domain, raw)
		}
	}
	if _, err := (Observer{Session: "../bad"}).Snapshot(context.Background(), "power"); err == nil {
		t.Fatal("invalid session accepted")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	started := time.Now()
	if err := (Observer{Session: "test"}).Run(ctx, make(chan policy.Event)); err != nil {
		t.Fatal(err)
	}
	if time.Since(started) > 100*time.Millisecond {
		t.Fatal("cancelled observer blocked")
	}
}
