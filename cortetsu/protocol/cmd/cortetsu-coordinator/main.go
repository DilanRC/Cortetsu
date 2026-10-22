// cortetsu-coordinator is currently a read-only event monitor. It is never
// autostarted by Cortetsu and has no route for mutating the desktop.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/observehypr"
)

func main() {
	session := flag.String("session", "", "Hyprland session identifier (required)")
	socket := flag.String("socket", "", "Explicit AF_UNIX Hyprland event socket (defaults to current session)")
	flag.Parse()
	if len(flag.Args()) != 0 || *session == "" {
		fmt.Fprintln(os.Stderr, "usage: cortetsu-coordinator --session ID [--socket PATH]")
		os.Exit(2)
	}
	path := *socket
	if path == "" {
		var err error
		path, err = observehypr.DefaultSocket()
		if err != nil {
			fmt.Fprintln(os.Stderr, "cannot resolve session socket")
			os.Exit(1)
		}
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if err := (observehypr.Observer{Session: *session, Socket: path}).Run(ctx, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "coordinator failed:", err)
		os.Exit(1)
	}
}
