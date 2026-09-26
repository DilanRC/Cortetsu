import Quickshell
import Quickshell.Io

// A soft reload reparses the promoted generation while keeping the Quickshell
// process and reusable windows alive. This is the safe adoption path for
// visual changes while desktop tray applications remain open.
Scope {
    IpcHandler {
        target: "cortetsu-shell"

        function reload(): void {
            Quickshell.reload(false);
        }
    }
}
