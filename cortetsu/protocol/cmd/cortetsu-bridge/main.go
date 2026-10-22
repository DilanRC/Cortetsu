// Compatibility name for the per-session native coordinator.
package main

import (
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/daemon"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/observedbus"
)

type metadata = daemon.Metadata

func publishMetadata(dir, session string, epoch uint64, socket string) (func(), error) {
	return daemon.PublishMetadata(dir, session, epoch, socket)
}
func main() {
	daemon.Main(func(session string) daemon.SystemObserver { return observedbus.Observer{Session: session} })
}
