// Package daemon owns one private coordinator socket per Wayland session.
// Observers remain useful with every automation domain disabled.
package daemon

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/activation"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/coordinator"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execclient"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/ipcv1"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/observehypr"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/status"
)

type domainStatus struct {
	Enabled      bool   `json:"enabled"`
	OwnerSession string `json:"owner_session"`
	Override     int64  `json:"manual_override_until_unix_ms"`
}
type summary struct {
	status.Summary
	Activations   map[string]domainStatus      `json:"activations"`
	Decisions     []policy.Decision            `json:"decisions"`
	Rules         []policy.Rule                `json:"rules"`
	System        map[string]map[string]string `json:"system"`
	RustAvailable bool                         `json:"rust_available"`
	ConfigValid   bool                         `json:"config_valid"`
}

// Hooks are owned by the native D-Bus adapter; no IPC request can replace them.
type SystemObserver interface {
	Run(context.Context, chan<- policy.Event) error
	Snapshot(context.Context, string) (map[string]string, error)
}
type Options struct {
	Session    string
	Observe    bool
	HyprSocket string
	Rules      []policy.Rule
	Rescue     string
	System     SystemObserver
}

func Serve(ctx context.Context, options Options) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	session := options.Session
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	unlock, err := lockSession(runtimeDir, session)
	if err != nil {
		return err
	}
	defer unlock()
	epoch, err := newEpoch()
	if err != nil {
		return errors.New("no entropy for session epoch")
	}
	state := status.NewStore()
	config := activation.DefaultStore()
	var runner *coordinator.Runner
	var rust *execclient.Client
	if options.Rescue != "" {
		rust = &execclient.Client{Binary: options.Rescue}
		if err := rust.CheckBinary(); err != nil {
			return err
		}
		stateHome := os.Getenv("XDG_STATE_HOME")
		if stateHome == "" {
			stateHome = filepath.Join(os.Getenv("HOME"), ".local/state")
		}
		runner, err = coordinator.New(session, options.Rules, config, rust, filepath.Join(stateHome, "cortetsu", "policy-audit"))
		if err != nil {
			return err
		}
	}
	ownerSocket := options.HyprSocket
	if options.Observe && ownerSocket == "" {
		ownerSocket, err = observehypr.DefaultSocket()
		if err != nil {
			return err
		}
	}
	commandSocket := ""
	if options.Observe {
		commandSocket, err = observehypr.CommandSocketFromEvent(ownerSocket)
		if err != nil {
			return err
		}
	}
	var hyprStreamAvailable atomic.Bool
	readHypr := func() (map[string]string, error) {
		if !hyprStreamAvailable.Load() {
			state.MarkOwnerUnavailable()
			return nil, errors.New("OWNER_UNAVAILABLE")
		}
		owner, err := observehypr.ReadOwner(commandSocket)
		if err != nil || !hyprStreamAvailable.Load() {
			state.MarkOwnerUnavailable()
			return nil, errors.New("OWNER_UNAVAILABLE")
		}
		state.SetOwner(owner)
		return map[string]string{"source": "hyprland", "monitor_count": strconv.Itoa(owner.MonitorCount), "focused_fullscreen": strconv.FormatBool(owner.FocusedFullscreen)}, nil
	}
	var systemMu sync.RWMutex
	systemState := map[string]map[string]string{}
	source := func(domains []string) (any, error) {
		if options.Observe {
			_, _ = readHypr()
		}
		value, err := state.Snapshot(domains)
		if err != nil {
			return nil, err
		}
		result := summary{Summary: value.(status.Summary), Activations: map[string]domainStatus{}, Rules: append([]policy.Rule(nil), options.Rules...), System: map[string]map[string]string{}, RustAvailable: rust != nil}
		result.Mode = "coordinator"
		result.Capabilities = []string{"snapshot", "policy.observe", "policy.simulate", "explain", "system.verify"}
		c, err := config.Read()
		result.ConfigValid = err == nil
		for domain := range activation.Domains {
			result.Activations[domain] = domainStatus{Enabled: err == nil && c.Owners[domain] == session, OwnerSession: c.Owners[domain], Override: c.Overrides[domain]}
		}
		if runner != nil {
			result.Decisions = runner.Last()
		}
		systemMu.RLock()
		for domain, fields := range systemState {
			copy := map[string]string{}
			for k, v := range fields {
				copy[k] = v
			}
			result.System[domain] = copy
		}
		systemMu.RUnlock()
		return result, nil
	}
	listener, err := ipcv1.OpenReadOnlySessionListener(runtimeDir, session, epoch, source)
	if err != nil {
		return err
	}
	defer listener.Close()
	if err = listener.SetRules(options.Rules); err != nil {
		return err
	}
	if rust != nil {
		if err = listener.SetVerifier(rust); err != nil {
			return err
		}
	}
	removeMetadata, err := PublishMetadata(filepath.Dir(listener.Path()), session, epoch, listener.Path())
	if err != nil {
		return err
	}
	defer removeMetadata()
	if options.Observe {
		events := make(chan policy.Event, 64)
		send := func(event policy.Event) {
			select {
			case events <- event:
			case <-ctx.Done():
			}
		}
		read, write := io.Pipe()
		context.AfterFunc(ctx, func() { _ = read.Close(); _ = write.Close() })
		go func() {
			defer write.Close()
			_ = (observehypr.Observer{Session: session, Socket: ownerSocket}).Run(ctx, write)
		}()
		go func() {
			defer read.Close()
			scanner := bufio.NewScanner(read)
			scanner.Buffer(make([]byte, 4096), observehypr.MaxEventBytes*2)
			for scanner.Scan() {
				var out observehypr.Output
				if json.Unmarshal(scanner.Bytes(), &out) != nil {
					continue
				}
				state.Apply(out)
				if out.Type == "resync_required" {
					hyprStreamAvailable.Store(true)
				} else if out.Type == "unavailable" {
					hyprStreamAvailable.Store(false)
				}
				fields, err := readHypr()
				if err != nil {
					fields = map[string]string{"state": "unavailable", "source": "hyprland"}
				}
				// The coordinator emits fresh owner snapshots, not event
				// payloads. Unknown/dropped source events cannot hide a gap.
				typ := "state.changed"
				if out.Type == "resync_required" {
					typ = "resync"
				}
				send(policy.Event{Producer: "hyprland", Session: session, Epoch: out.Epoch, Domain: "hyprland", Type: typ, Fields: fields, EmittedAtUnixMs: time.Now().UnixMilli()})
			}
			hyprStreamAvailable.Store(false)
			state.MarkOwnerUnavailable()
		}()
		if options.System != nil {
			go func() { _ = options.System.Run(ctx, events) }()
		}
		changes := make(chan struct{}, 1)
		go func() { _ = config.Watch(ctx, changes) }()
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case <-changes:
					fields, err := readHypr()
					if err == nil {
						send(policy.Event{Producer: "consent-hyprland", Session: session, Epoch: epoch, Domain: "hyprland", Type: "state.changed", Fields: fields, EmittedAtUnixMs: time.Now().UnixMilli()})
					}
					if options.System != nil {
						fields, err = options.System.Snapshot(ctx, "power")
						if err == nil {
							send(policy.Event{Producer: "consent-power", Session: session, Epoch: epoch, Domain: "power", Type: "state.changed", Fields: fields, EmittedAtUnixMs: time.Now().UnixMilli()})
						}
					}
				}
			}
		}()
		go func() {
			var sequence uint64
			timers := map[string]*time.Timer{}
			sourceEpochs := map[string]uint64{}
			streamEpochs := map[string]uint64{}
			defer func() {
				for _, timer := range timers {
					timer.Stop()
				}
			}()
			for {
				select {
				case <-ctx.Done():
					return
				case event := <-events:
					if event.Session != session {
						continue
					}
					if event.Domain == "hyprland" && !hyprStreamAvailable.Load() {
						event.Fields = map[string]string{"state": "unavailable", "source": "hyprland"}
					}
					sourceEpoch := event.Epoch
					if streamEpochs[event.Producer] == 0 || sourceEpochs[event.Producer] != sourceEpoch || event.Type == "resync" {
						next, epochErr := newEpoch()
						if epochErr != nil {
							return
						}
						streamEpochs[event.Producer] = next
						sourceEpochs[event.Producer] = sourceEpoch
					}
					sequence++
					event.Epoch = streamEpochs[event.Producer]
					event.Sequence = sequence
					if event.Type == "resync" {
						event.Type = "state.changed"
					}
					if event.Domain != "hyprland" {
						systemMu.Lock()
						systemState[event.Domain] = event.Fields
						systemMu.Unlock()
					}
					if timer := timers[event.Domain]; timer != nil {
						timer.Stop()
						delete(timers, event.Domain)
					}
					if runner == nil {
						continue
					}
					decisions, err := runner.Handle(ctx, event)
					if err != nil {
						continue
					}
					// Timers exist only while a matching rule is stabilizing.
					// A fresh authoritative read is mandatory on expiry.
					wait := int64(0)
					for _, d := range decisions {
						if d.Reason != "STABILIZING" {
							continue
						}
						for _, rule := range options.Rules {
							if rule.ID == d.RuleID && rule.HysteresisMs > wait {
								wait = rule.HysteresisMs
							}
						}
					}
					if wait > 0 {
						domain, producer := event.Domain, event.Producer
						timers[domain] = time.AfterFunc(time.Duration(wait+5)*time.Millisecond, func() {
							var fields map[string]string
							var err error
							if domain == "hyprland" {
								fields, err = readHypr()
							} else if options.System != nil {
								fields, err = options.System.Snapshot(ctx, domain)
							} else {
								return
							}
							if err != nil {
								fields = map[string]string{"state": "unavailable"}
							}
							send(policy.Event{Producer: producer, Session: session, Epoch: sourceEpoch, Domain: domain, Type: "state.changed", Fields: fields, EmittedAtUnixMs: time.Now().UnixMilli()})
						})
					}
				}
			}
		}()
	}
	return listener.Serve(ctx)
}

// Main is shared by the stable coordinator and the compatibility bridge name.
func Main(system func(string) SystemObserver) {
	session := flag.String("session", os.Getenv("HYPRLAND_INSTANCE_SIGNATURE"), "exact Wayland session")
	observe := flag.Bool("observe", false, "observe Hyprland and system bus owners")
	hypr := flag.String("hypr-socket", "", "explicit Hyprland event socket")
	legacySocket := flag.String("socket", "", "alias for --hypr-socket")
	rulesPath := flag.String("rules", "", "trusted optional rule catalog")
	rescue := flag.String("rescue-binary", "", "pinned Rust owner entry point")
	flag.Parse()
	if *hypr == "" {
		*hypr = *legacySocket
	}
	if *session == "" || flag.NArg() != 0 || (!*observe && *hypr != "") {
		fmt.Fprintln(os.Stderr, "usage: cortetsu-coordinator [--session ID] [--observe] [--hypr-socket PATH] [--rules JSON] [--rescue-binary PATH]")
		os.Exit(2)
	}
	rules, err := coordinator.LoadRules(*rulesPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if *rescue == "" {
		if executable, err := os.Executable(); err == nil {
			candidate := filepath.Join(filepath.Dir(executable), "cortetsu-rescue")
			if m, err := os.Lstat(candidate); err == nil && m.Mode().IsRegular() {
				*rescue = candidate
			}
		}
	}
	options := Options{Session: *session, Observe: *observe, HyprSocket: *hypr, Rules: rules, Rescue: *rescue}
	if system != nil {
		options.System = system(*session)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if err = Serve(ctx, options); err != nil {
		fmt.Fprintln(os.Stderr, "cortetsu-coordinator:", err)
		os.Exit(1)
	}
}
