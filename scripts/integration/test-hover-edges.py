#!/usr/bin/env python3
"""The top edge opens the dashboard across its middle; the right edge the OSD.

Runs with and without a window on the workspace, since a window removes the
drag padding and leaves the input frame one pixel thick.
"""
import json, sys, tempfile, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H


def opened(session):
    data = json.loads(session.ipc("cortetsu-shell", "inspect").stdout)
    return sorted(entry["surface"] for entry in data["open_states"])


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="cz-edge-", dir="/tmp") as tmp:
        session = H.Session(Path(tmp))
        try:
            session.start()
            time.sleep(2)
            for client in (False, True):
                if client:
                    session.start_client()
                    time.sleep(1)
                m = session.monitors()[0]
                w, h = round(m["width"] / m["scale"]), round(m["height"] / m["scale"])
                # (point, surface, should it be open). The OSD fades on its own
                # timer, so each case only asserts the surface it targets.
                cases = {"top-centre": ((w // 2, 0), "dashboard", True),
                         "top-quarter": ((w // 4, 0), "dashboard", True),
                         "top-corner": ((40, 0), "dashboard", False),
                         "right-middle": ((w - 1, h // 2), "osd", True)}
                for name, ((x, y), surface, expected) in cases.items():
                    session.move(m["x"] + w // 2, m["y"] + h // 2)
                    time.sleep(0.6)
                    session.move(m["x"] + x, m["y"] + y)
                    time.sleep(0.9)
                    got = opened(session)
                    assert (surface in got) == expected, f"{name} client={client}: open={got}"
            print("HOVER_EDGES_PASS 8")
            return 0
        finally:
            session.stop()


if __name__ == "__main__":
    sys.exit(main())
