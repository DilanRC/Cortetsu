pragma Singleton

import QtQml
import Quickshell

QtObject {
    function launchPersistent(command: var, workingDirectory: var, label: var): bool {
        const argv = Array.from(command ?? []);
        if (!argv.length)
            return false;

        const launch = ["cortetsu-launch-persistent", "--label", String(label || argv[0])];
        if (workingDirectory)
            launch.push("--working-directory", String(workingDirectory));
        launch.push("--", ...argv);
        Quickshell.execDetached(launch);
        return true;
    }
}
