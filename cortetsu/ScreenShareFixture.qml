//@ pragma Env XDG_CONFIG_HOME=/nonexistent/cortetsu-screenshare-fixture
import QtQuick
import Quickshell
import Quickshell.Io
import "modules/screenshare"

// Plays cortetsu-share-picker's side of the socket protocol against the real
// ScreenShare controller, with its overlay window disabled so nothing maps on
// the running session: a valid request reaches "choosing" and answers with the
// token, a request with the wrong token is dropped without an answer, and a
// queued request starts once the first one is done.
ShellRoot {
    id: fixture

    property var replies: []
    property int connections: 0
    property string serverToken: "tok-1"
    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/cortetsu-share-fixture-${Quickshell.processId}.sock`

    function fail(message: string): void {
        console.error(`SCREENSHARE_FAIL ${message}`);
        Qt.quit();
    }

    ScreenShare {
        id: share
        pickerEnabled: false
    }

    SocketServer {
        active: true
        path: fixture.socketPath
        handler: Socket {
            id: client
            parser: SplitParser {
                onRead: line => fixture.replies = fixture.replies.concat([JSON.parse(line)])
            }
            function hello(): void {
                client.write(JSON.stringify({ token: fixture.serverToken,
                    windows: [{ handle: 7, class: "kitty", title: "notas", address: "0" }] }) + "\n");
                client.flush();
            }
            Component.onCompleted: {
                fixture.connections++;
                // A handler socket is not connected yet in onCompleted.
                Qt.callLater(client.hello);
            }
        }
    }

    // Each step waits for the previous one; the watchdog fails a stuck step.
    property int step: 0
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            switch (fixture.step) {
            case 0:
                share.request(fixture.socketPath, "tok-1");
                // Queued behind the first: same server, so it must wait its turn.
                share.request(fixture.socketPath, "tok-2");
                fixture.step = 1;
                break;
            case 1:
                if (share.phase !== "choosing")
                    return;
                if (share.windows.length !== 1 || share.windows[0].handle !== 7)
                    return fixture.fail(`windows=${JSON.stringify(share.windows)}`);
                fixture.serverToken = "wrong";
                share.shareWindow(7, true);
                fixture.step = 2;
                break;
            case 2: {
                if (fixture.replies.length !== 1)
                    return;
                const r = fixture.replies[0];
                if (r.token !== "tok-1" || r.type !== "window" || r.handle !== 7 || r.remember !== true)
                    return fixture.fail(`reply=${JSON.stringify(r)}`);
                fixture.step = 3;
                break;
            }
            case 3:
                // The queued request connected, got "wrong" and was dropped.
                if (fixture.connections < 2 || share.phase !== "idle" || share.queue.length !== 0)
                    return;
                if (fixture.replies.length !== 1)
                    return fixture.fail("a request with a foreign token was answered");
                console.log("SCREENSHARE_PASS choose, reply, queue and token check");
                Qt.quit();
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: fixture.fail(`stuck at step ${fixture.step} phase=${share.phase} connections=${fixture.connections}`)
    }
}
