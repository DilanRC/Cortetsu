// cortetsu-shadow is an inert, offline policy trace simulator. It reads only
// explicit local files and stdin; it does not start any services, connect to
// D-Bus or Hyprland, or run Rust actions. Not installed by Cortetsu yet.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/shadow"
)

func main() {
	rulePath := flag.String("rules", "", "Optional JSON rule fixture (read only)")
	flag.Parse()
	if len(flag.Args()) != 0 {
		fmt.Fprintln(os.Stderr, "usage: cortetsu-shadow [-rules fixture.json] < trace.ndjson")
		os.Exit(2)
	}
	var raw []byte
	if *rulePath != "" {
		var err error
		raw, err = os.ReadFile(*rulePath)
		if err != nil {
			fmt.Fprintln(os.Stderr, "cannot read rules")
			os.Exit(1)
		}
	} else {
		raw = []byte("[]")
	}
	rules, err := shadow.ReadRules(raw)
	if err != nil {
		fmt.Fprintln(os.Stderr, "invalid rules")
		os.Exit(1)
	}
	if err := shadow.Run(os.Stdin, os.Stdout, rules); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
