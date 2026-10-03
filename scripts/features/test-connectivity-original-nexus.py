#!/usr/bin/env python3
"""Load restored Nexus layouts in an isolated runtime without connecting or scanning."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', required=True, type=Path)
args = parser.parse_args()
assert os.environ.get('WAYLAND_DISPLAY'), 'Requires the live Wayland backend'
runtime = args.runtime.resolve()
with tempfile.TemporaryDirectory(prefix='cortetsu-original-nexus-') as temporary:
    folder = Path(temporary)
    for name in ('modules', 'components', 'services', 'utils', 'assets'):
        if (runtime / name).exists():
            (folder / name).symlink_to(runtime / name, target_is_directory=True)
    (folder / 'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.services
import qs.modules.nexus as Nexus
import qs.modules.nexus.pages as Pages
import qs.modules.nexus.pages.network as Network
import qs.modules.settings as Settings
ShellRoot {
    settings.watchFiles: false
    Nexus.NexusState { id: nexusSession }
    FloatingWindow {
        visible: false
        implicitWidth: 700
        implicitHeight: 700
        Loader { id: mainPage; visible:false; sourceComponent: Pages.NetworkPage { nState:nexusSession; visible:false; width:700 } }
        Loader { id: allPage; visible:false; sourceComponent: Network.AllNetworksPage { nState:nexusSession; visible:false; width:700 } }
        Loader { id: savedPage; visible:false; sourceComponent: Network.SavedNetworksPage { nState:nexusSession; visible:false; width:700 } }
        Loader { id: addPage; visible:false; sourceComponent: Network.AddNetworkPage { nState:nexusSession; visible:false; width:700 } }
        Loader { id: wifiDetails; visible:false; sourceComponent: Network.NetworkDetailPage { nState:nexusSession; visible:false; width:700 } }
        Loader { id: wiredDetails; visible:false; sourceComponent: Network.EthernetDetailPage { nState:nexusSession; visible:false; width:700 } }
        Loader { id: btSettings; visible:false; sourceComponent: Settings.SystemPage { screen:null; screenState:null; section:"bluetooth"; visible:false; width:700 } }
    }
    Timer {
        interval:1800; running:true
        onTriggered: {
            const pages = [mainPage,allPage,savedPage,addPage,wifiDetails,wiredDetails,btSettings];
            if (pages.every(page => page.status === Loader.Ready)
                && Object.keys(Connectivity.wifi.scanOwners).length === 0)
                console.log("ORIGINAL_NEXUS_PASS", pages.length);
            else console.error("ORIGINAL_NEXUS_FAIL");
            Qt.quit();
        }
    }
}
''')
    result = subprocess.run(['quickshell', '-p', str(folder / 'shell.qml')], capture_output=True, text=True,
        env={**os.environ, 'QT_QPA_PLATFORM':'wayland'}, timeout=10)
    output = result.stdout + result.stderr
    print(output)
    assert result.returncode == 0 and 'ORIGINAL_NEXUS_PASS 7' in output
    assert not any(error in output for error in ('TypeError', 'ReferenceError', 'Binding loop', ' ERROR:'))
