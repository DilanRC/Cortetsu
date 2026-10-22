// cortetsu-bridge is opt-in, read-only and scoped to one Wayland session.
// It neither starts as a service nor makes mutation requests to Rust.
package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execclient"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/ipcv1"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/observehypr"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/shadow"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/status"
)

type metadata struct {
	Protocol     string `json:"protocol"`
	SessionID    string `json:"session_id"`
	SessionEpoch uint64 `json:"session_epoch"`
	Socket       string `json:"socket"`
	Mode         string `json:"mode"`
}

func publishMetadata(dir string, session string, epoch uint64, socket string) (func(), error) {
	meta := metadata{Protocol: "cortetsu.ipc", SessionID: session, SessionEpoch: epoch, Socket: socket, Mode: "observe"}
	dest := filepath.Join(dir, "bridge-"+session+".json")
	if old, err := os.Lstat(dest); err == nil && (!old.Mode().IsRegular() || old.Mode()&os.ModeSymlink != 0) {
		return nil, errors.New("unsafe metadata path")
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, errors.New("cannot inspect metadata")
	}
	tmp := dest + fmt.Sprintf(".%d.tmp", os.Getpid())
	file, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return nil, err
	}
	bytes, err := json.Marshal(meta)
	if err == nil {
		_, err = file.Write(append(bytes, '\n'))
	}
	if err == nil {
		err = file.Sync()
	}
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(tmp)
		return nil, errors.New("metadata write failed")
	}
	if err = os.Rename(tmp, dest); err != nil {
		_ = os.Remove(tmp)
		return nil, errors.New("metadata replace failed")
	}
	if parent, err := os.Open(dir); err == nil {
		_ = parent.Sync()
		_ = parent.Close()
	}
	cleanup := func() {
		current, err := os.ReadFile(dest)
		if err != nil {
			return
		}
		var recorded metadata
		if json.Unmarshal(current, &recorded) == nil && recorded.SessionEpoch == epoch && recorded.SessionID == session && recorded.Socket == socket {
			_ = os.Remove(dest)
		}
	}
	return cleanup, nil
}

func serve(ctx context.Context, session string, observe bool, sourceSocket string, rules []policy.Rule, rescue string) error {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	var epoch uint64
	if err := binary.Read(rand.Reader, binary.BigEndian, &epoch); err != nil {
		return errors.New("no entropy for session epoch")
	}
	if epoch == 0 {
		epoch = 1
	}
	state := status.NewStore()
	ownerSocket := sourceSocket
	if observe && ownerSocket == "" {
		var err error
		ownerSocket, err = observehypr.DefaultSocket()
		if err != nil {
			return errors.New("cannot resolve Hyprland event socket")
		}
	}
	source := func(domains []string) (any, error) {
		if observe {
			commandSocket, err := observehypr.CommandSocketFromEvent(ownerSocket)
			if err == nil {
				var owner observehypr.OwnerState
				owner, err = observehypr.ReadOwner(commandSocket)
				if err == nil {
					state.SetOwner(owner)
				}
			}
			if err != nil {
				state.MarkOwnerUnavailable()
			}
		}
		return state.Snapshot(domains)
	}
	listener, err := ipcv1.OpenReadOnlySessionListener(runtimeDir, session, epoch, source)
	if err != nil {
		return fmt.Errorf("cannot start private session bridge: %w", err)
	}
	defer listener.Close()
	if rescue != "" {
		if err := listener.SetVerifier(&execclient.Client{Binary: rescue}); err != nil {
			return err
		}
	}
	if err := listener.SetRules(rules); err != nil {
		return fmt.Errorf("invalid policy catalog: %w", err)
	}
	done, err := publishMetadata(filepath.Dir(listener.Path()), session, epoch, listener.Path())
	if err != nil {
		return err
	}
	defer done()
	if observe {
		path := ownerSocket
		read, write := io.Pipe()
		go func() {
			defer write.Close()
			if err := (observehypr.Observer{Session: session, Socket: path}).Run(ctx, write); err != nil {
				_ = write.CloseWithError(errors.New("observer stopped"))
			}
		}()
		go func() {
			defer read.Close()
			scanner := bufio.NewScanner(read)
			scanner.Buffer(make([]byte, 4096), observehypr.MaxEventBytes*2)
			for scanner.Scan() {
				var event observehypr.Output
				if json.Unmarshal(scanner.Bytes(), &event) == nil {
					state.Apply(event)
				}
			}
		}()
	}
	return listener.Serve(ctx)
}

func main() {
	session := flag.String("session", os.Getenv("HYPRLAND_INSTANCE_SIGNATURE"), "exact session identifier")
	events := flag.Bool("observe", false, "opt in to redacted Hyprland event observation")
	hyprSocket := flag.String("hypr-socket", "", "explicit Hyprland event socket; requires --observe")
	rulesFile := flag.String("rules", "", "optional read-only JSON catalog for policy.list")
	rescueFile := flag.String("rescue-binary", "", "optional pinned Rust cortetsu-rescue executable for read-only system.verify")
	flag.Parse()
	if *session == "" || flag.NArg() != 0 || (!*events && *hyprSocket != "") {
		fmt.Fprintln(os.Stderr, "usage: cortetsu-bridge [--session ID] [--observe [--hypr-socket PATH]] [--rules READONLY_JSON] [--rescue-binary TRUSTED_ABSOLUTE_EXECUTABLE]")
		os.Exit(2)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	var rules []policy.Rule
	if *rulesFile != "" {
		info, err := os.Lstat(*rulesFile)
		if err != nil || !info.Mode().IsRegular() || info.Size() > shadow.MaxLineBytes || info.Mode().Perm()&0022 != 0 {
			fmt.Fprintln(os.Stderr, "policy catalog must be a private regular file")
			os.Exit(2)
		}
		content, err := os.ReadFile(*rulesFile)
		if err != nil {
			fmt.Fprintln(os.Stderr, "cannot read policy catalog")
			os.Exit(2)
		}
		rules, err = shadow.ReadRules(content)
		if err != nil || len(rules) > 128 {
			fmt.Fprintln(os.Stderr, "invalid policy catalog")
			os.Exit(2)
		}
	}
	if err := serve(ctx, *session, *events, *hyprSocket, rules, *rescueFile); err != nil {
		fmt.Fprintln(os.Stderr, "cortetsu-bridge:", err)
		os.Exit(1)
	}
}
