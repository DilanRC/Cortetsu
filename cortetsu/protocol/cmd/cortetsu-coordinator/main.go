// cortetsu-coordinator observes owners and applies explicitly enabled policies.
package main

import (
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/daemon"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/observedbus"
)

func main() {
	daemon.Main(func(session string) daemon.SystemObserver { return observedbus.Observer{Session: session} })
}
