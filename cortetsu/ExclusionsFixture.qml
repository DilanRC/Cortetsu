//@ pragma Env XDG_CONFIG_HOME=/nonexistent/cortetsu-exclusions-fixture
import QtQuick
import Quickshell
import "modules/drawers"

// Every layer window costs a GL context (about 11 MiB and 4 threads per
// window on the reference laptop), so an exclusion window that reserves 0 px
// must not exist. Only top, right and bottom reserve the border; the left
// edge has no bar since the top bar was retired.
ShellRoot {
    Exclusions {
        id: none
        screen: Quickshell.screens[0]
        thickness: 0
    }
    Exclusions {
        id: some
        screen: Quickshell.screens[0]
        thickness: 1
    }

    Timer {
        interval: 50
        running: true
        onTriggered: {
            const zones = some.instances.map(w => w.exclusiveZone).join(",");
            if (none.instances.length === 0 && some.instances.length === 3 && zones === "1,1,1")
                console.log("EXCLUSIONS_PASS none=0 some=3");
            else
                console.error(`EXCLUSIONS_FAIL none=${none.instances?.length} some=${some.instances?.length} zones=${zones}`);
            Qt.quit();
        }
    }
}
