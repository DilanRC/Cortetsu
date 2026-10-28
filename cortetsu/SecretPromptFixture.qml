//@ pragma Env XDG_CONFIG_HOME=/nonexistent/cortetsu-secretprompt-fixture
import QtQuick
import Quickshell
import Quickshell.Io
import "modules"

// Plays cortetsu-prompter's side of the socket against the real
// SecretPromptHost, with its window off so nothing maps on the session:
// a prompt line shows, the answer carries the token and password, a second
// prompt on the same dialog (a wrong password) clears `waiting`, Escape while
// the client checks refuses its next prompt, closing the socket ends the dialog, the queued request then starts, and a line with a
// foreign token ends that dialog without an answer.
ShellRoot {
    id: fixture

    property var replies: []
    property int connections: 0
    property var current: null
    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/cortetsu-secretprompt-fixture-${Quickshell.processId}.sock`

    function fail(message: string): void {
        console.error(`SECRETPROMPT_FAIL ${message}`);
        Qt.quit();
    }

    function send(token: string, extra: var): void {
        fixture.current.write(JSON.stringify(Object.assign({ token, kind: "password", title: "",
            message: "Desbloquear llavero", description: "", warning: "", choiceLabel: "",
            choiceChosen: false, passwordNew: false, continueLabel: "", cancelLabel: "" }, extra)) + "\n");
        fixture.current.flush();
    }

    SecretPromptHost {
        id: host
        dialogEnabled: false
    }

    SocketServer {
        active: true
        path: fixture.socketPath
        handler: Socket {
            id: client
            parser: SplitParser {
                onRead: line => fixture.replies = fixture.replies.concat([JSON.parse(line)])
            }
            Component.onCompleted: {
                fixture.connections++;
                fixture.current = client;
            }
        }
    }

    property int step: 0
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            switch (fixture.step) {
            case 0:
                host.request(fixture.socketPath, "tok-1");
                host.request(fixture.socketPath, "tok-2");
                fixture.step = 1;
                break;
            case 1:
                if (fixture.connections !== 1 || !fixture.current?.connected)
                    return;
                fixture.send("tok-1", {});
                fixture.step = 2;
                break;
            case 2:
                if (!host.prompt)
                    return;
                if (host.prompt.message !== "Desbloquear llavero" || host.waiting)
                    return fixture.fail(`prompt=${JSON.stringify(host.prompt)} waiting=${host.waiting}`);
                host.answer(true, "mal", false);
                if (!host.waiting)
                    return fixture.fail("waiting not set after answering");
                host.answer(true, "otra", false);
                fixture.step = 3;
                break;
            case 3: {
                if (fixture.replies.length < 1)
                    return;
                const r = fixture.replies[0];
                if (r.token !== "tok-1" || r.reply !== "yes" || r.password !== "mal" || r.choice !== false)
                    return fixture.fail(`reply=${JSON.stringify(r)}`);
                fixture.send("tok-1", { warning: "La contraseña no es correcta" });
                fixture.step = 4;
                break;
            }
            case 4:
                if (host.waiting || host.prompt?.warning !== "La contraseña no es correcta")
                    return;
                if (fixture.replies.length !== 1)
                    return fixture.fail("a second answer was sent while waiting");
                host.answer(true, "otra-vez", false);
                // Escape while the client checks: no answer now, a refusal
                // of the next prompt instead, which never shows.
                host.answer(false, "", false);
                if (!host.cancelPending || fixture.replies.length !== 1)
                    return fixture.fail(`cancel while waiting pending=${host.cancelPending}`);
                fixture.send("tok-1", { warning: "Otra vez" });
                fixture.step = 5;
                break;
            case 5: {
                if (fixture.replies.length < 2)
                    return;
                const r = fixture.replies[1];
                if (r.reply !== "yes" || r.password !== "otra-vez")
                    return fixture.fail(`second answer=${JSON.stringify(r)}`);
                if (fixture.replies.length < 3)
                    return;
                const c = fixture.replies[2];
                if (c.reply !== "no" || c.password !== "" || host.cancelPending || !host.waiting)
                    return fixture.fail(`pending cancel=${JSON.stringify(c)} waiting=${host.waiting}`);
                fixture.current.connected = false;
                fixture.step = 6;
                break;
            }
            case 6:
                // The host closed the dialog and connected for the queued request.
                if (fixture.connections !== 2 || !fixture.current?.connected)
                    return;
                if (host.prompt !== null || host.token !== "tok-2")
                    return fixture.fail(`after close prompt=${JSON.stringify(host.prompt)} token=${host.token}`);
                fixture.send("wrong", {});
                fixture.step = 7;
                break;
            case 7:
                if (host.token !== "" || host.prompt !== null || host.queue.length !== 0)
                    return;
                if (fixture.replies.length !== 3)
                    return fixture.fail("a foreign token was answered");
                console.log("SECRETPROMPT_PASS prompt, answer, retry, cancel while checking, close, queue and token check");
                Qt.quit();
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: fixture.fail(`stuck at step ${fixture.step} connections=${fixture.connections} token=${host.token}`)
    }
}
