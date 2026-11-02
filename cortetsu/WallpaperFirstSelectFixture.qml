import QtQuick
import Quickshell
import "modules"

// Run by cortetsu/tests/test-wallpaper-first-select.sh, which points the XDG
// roots at an empty directory and puts a fake cortetsu-wallpaper-select first
// on PATH. On that fresh HOME there is no path.txt, so FileView watches
// nothing: the first selection must still be seen without a shell restart.
// Then a second selection (file now watched), and a failing helper that must
// report its stderr at once instead of waiting for the apply timeout.
ShellRoot {
    id: fixture

    readonly property string walls: Quickshell.env("CORTETSU_WALLPAPERS_DIR")
    property int step: 0
    property int ticks: 0
    property var successes: []
    property var failures: []

    function fail(message: string): void {
        console.error(`WALLPAPER_FIRST_SELECT_FAIL step=${step} ${message} current=${CortetsuWallpapers.actualCurrent} status=${CortetsuWallpapers.applyStatus} error=${CortetsuWallpapers.applyError}`);
        Qt.quit();
    }

    function next(): void {
        step += 1;
        ticks = 0;
    }

    Connections {
        target: CortetsuWallpapers
        function onWallpaperApplySucceeded(path: string): void { fixture.successes = fixture.successes.concat([path]); }
        function onWallpaperApplyFailed(path: string): void { fixture.failures = fixture.failures.concat([path]); }
    }

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            fixture.ticks += 1;
            // 3 s per step. A selection that hits the 1.92 s apply timeout
            // ends as "failed", which every step treats as a failure.
            if (fixture.ticks > 150)
                return fixture.fail("timed out");
            const w = CortetsuWallpapers;
            switch (fixture.step) {
            case 0:
                if (w.actualCurrent !== w.fallback)
                    return fixture.fail("a fresh HOME must start on the fallback");
                if (!w.apply(`${fixture.walls}/first.png`))
                    return fixture.fail("first apply refused");
                fixture.next();
                break;
            case 1:
                if (w.applyStatus === "failed")
                    return fixture.fail("first selection failed");
                if (w.applyStatus !== "applied")
                    return;
                if (w.actualCurrent !== `${fixture.walls}/first.png`)
                    return fixture.fail("first selection not read back");
                if (w.apply(`${fixture.walls}/first.png`))
                    return fixture.fail("re-applying the current wallpaper must be a no-op");
                if (!w.apply(`${fixture.walls}/second.png`))
                    return fixture.fail("second apply refused");
                fixture.next();
                break;
            case 2:
                if (w.applyStatus === "failed")
                    return fixture.fail("second selection failed");
                if (w.applyStatus !== "applied")
                    return;
                if (w.actualCurrent !== `${fixture.walls}/second.png`)
                    return fixture.fail("second selection not read back");
                if (!w.apply(`${fixture.walls}/broken.png`))
                    return fixture.fail("failing apply refused");
                fixture.next();
                break;
            case 3:
                if (w.applying)
                    return;
                if (w.applyStatus !== "failed" || w.applyError !== "fake select: broken.png")
                    return fixture.fail("a failing helper must report its stderr");
                // Well under the apply timeout: the failure came from the exit code.
                if (fixture.ticks > 50)
                    return fixture.fail("the failure waited for the timeout");
                if (w.actualCurrent !== `${fixture.walls}/second.png`)
                    return fixture.fail("a failed selection changed the wallpaper");
                if (JSON.stringify(fixture.successes) !== JSON.stringify([`${fixture.walls}/first.png`, `${fixture.walls}/second.png`]))
                    return fixture.fail(`one success per selection, got ${JSON.stringify(fixture.successes)}`);
                if (JSON.stringify(fixture.failures) !== JSON.stringify([`${fixture.walls}/broken.png`]))
                    return fixture.fail(`one failure, got ${JSON.stringify(fixture.failures)}`);
                console.log("WALLPAPER_FIRST_SELECT_PASS");
                Qt.quit();
                break;
            }
        }
    }
}
