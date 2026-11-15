pragma ComponentBehavior: Bound

import "./kblayout"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.components
import qs.modules
import qs.services
// The same file BottomHubTray.js imports (the runtime keeps it under base/):
// one URL is one library, so the Hub's icons and these menus share one
// `tray-instance-N` registry. By another URL the two counters drifted
// apart when an app came and went before the first popout opened.
import "../../../base/modules/bar/SystemTrayIdentity.js" as TrayIdentity
import "../../../modules/WindowPreview.js" as WindowPreview

Item {
    id: root

    required property PopoutState popouts
    readonly property Popout currentPopout: content.children.find(c => c.shouldBeActive) ?? null
    readonly property Item current: currentPopout?.item ?? null

    implicitWidth: (currentPopout?.implicitWidth ?? 0) + CortetsuTokens.padding.extraLargeIncreased
    implicitHeight: (currentPopout?.implicitHeight ?? 0) + CortetsuTokens.padding.extraLargeIncreased

    Item {
        id: content

        anchors.fill: parent
        anchors.margins: CortetsuTokens.padding.large

        Popout {
            name: "activewindow"
            sourceComponent: CortetsuActiveWindowPopup {
                popouts: root.popouts
            }
        }

        Popout {
            id: networkPopout

            name: "network"
            sourceComponent: CortetsuNetworkPopup {
                // Cortetsu owns the presentation; the native service contract remains unchanged.
                popouts: root.popouts
            }
        }

        Popout {
            id: passwordPopout

            name: "wirelesspassword"
            sourceComponent: CortetsuWifiPasswordPopup {
                id: passwordComponent

                popouts: root.popouts
                network: (networkPopout.item as CortetsuNetworkPopup)?.passwordNetwork ?? null
            }

            Connections {
                function onCurrentNameChanged() {
                    // Update network immediately when password popout becomes active
                    if (root.popouts.currentName === "wirelesspassword") {
                        // Set network immediately if available
                        if ((networkPopout.item as CortetsuNetworkPopup)?.passwordNetwork) {
                            if (passwordPopout.item) {
                                (passwordPopout.item as CortetsuWifiPasswordPopup).network = (networkPopout.item as CortetsuNetworkPopup).passwordNetwork;
                            }
                        }
                        // Defer to the next event loop turn in case networkPopout.item
                        // has not finished updating yet.
                        Qt.callLater(() => {
                            if (passwordPopout.item && (networkPopout.item as CortetsuNetworkPopup)?.passwordNetwork) {
                                (passwordPopout.item as CortetsuWifiPasswordPopup).network = (networkPopout.item as CortetsuNetworkPopup).passwordNetwork;
                            }
                        });
                    }
                }

                target: root.popouts
            }

            Connections {
                function onItemChanged() {
                    // When network popout loads, update password popout if it's active
                    if (root.popouts.currentName === "wirelesspassword" && passwordPopout.item) {
                        Qt.callLater(() => {
                            if ((networkPopout.item as CortetsuNetworkPopup)?.passwordNetwork) {
                                (passwordPopout.item as CortetsuWifiPasswordPopup).network = (networkPopout.item as CortetsuNetworkPopup).passwordNetwork;
                            }
                        });
                    }
                }

                target: networkPopout
            }
        }

        Popout {
            name: "bluetooth"
            sourceComponent: CortetsuBluetoothPopup {
                popouts: root.popouts
            }
        }

        Popout {
            name: "battery"
            sourceComponent: CortetsuBatteryPopup {}
        }

        Popout {
            name: "audio"
            sourceComponent: CortetsuAudioPopup {
                popouts: root.popouts
            }
        }

        Popout {
            name: "kblayout"
            sourceComponent: CortetsuKeyboardPopup {}
        }

        Popout {
            name: "lockstatus"
            sourceComponent: CortetsuLockStatusPopup {}
        }

        // One loader for every app of the rail: moving from one icon to the
        // next keeps the popout and changes what it shows.
        Popout {
            name: "apppreview"
            prefix: WindowPreview.prefix
            sourceComponent: CortetsuWindowPreview {
                popouts: root.popouts
            }
        }

        Repeater {
            model: ScriptModel {
                // Keys come from the full list: a filtered call would drop the keys
                // other trays still use for the filtered-out items.
                values: TrayIdentity.entries(SystemTray.items.values).filter(e => e.item.status !== Status.Passive && !CortetsuConfig.hiddenTrayIcons.includes(e.item.id))
                objectProp: "key"
            }

            Popout {
                id: trayMenu

                required property var modelData
                readonly property var menuHandle: modelData?.item?.menu ?? null

                name: TrayIdentity.popupName(modelData.key)
                sourceComponent: menuHandle ? trayMenuComp : null

                Component.onDestruction: {
                    if (shouldBeActive)
                        root.popouts.close();
                }

                onMenuHandleChanged: {
                    if (!menuHandle && shouldBeActive)
                        root.popouts.close();
                }

                // The menu only outlives its popout while it fades out. Opened
                // again then, it starts over in place. It used to be rebuilt
                // on every hasCurrent change, and closing by key or action
                // flips hasCurrent off and on (Wrapper keeps it for the close
                // animation): each such close destroyed the menu on screen.
                // With the software renderer's render thread that crashed Qt
                // now and then (QQuickShapeSoftwareRenderNode::render reads
                // the destroyed panel's window; Qt 6.12, REGISTRO fase 4).
                onShouldBeActiveChanged: if (shouldBeActive)
                    (item as CortetsuTrayMenu)?.reset()

                Component {
                    id: trayMenuComp

                    CortetsuTrayMenu {
                        popouts: root.popouts
                        trayItem: trayMenu.menuHandle // qmllint disable unresolved-type
                    }
                }
            }
        }
    }

    component Popout: Loader {
        id: popout

        required property string name
        // Set: every popout name that starts with it opens this one.
        property string prefix: ""
        readonly property bool shouldBeActive: prefix.length > 0
            ? root.popouts.currentName.startsWith(prefix)
            : root.popouts.currentName === name

        anchors.centerIn: parent

        opacity: 0
        active: false

        states: State {
            name: "active"
            when: popout.shouldBeActive

            PropertyChanges {
                popout.active: true
                popout.opacity: 1
            }
        }

        transitions: [
            Transition {
                from: "active"
                to: ""

                SequentialAnimation {
                    Anim {
                        property: "opacity"
                        type: Anim.DefaultEffects
                    }
                    PropertyAction {
                        property: "active"
                    }
                }
            },
            Transition {
                from: ""
                to: "active"

                SequentialAnimation {
                    PropertyAction {
                        property: "active"
                    }
                    Anim {
                        property: "opacity"
                        type: Anim.SlowEffects
                    }
                }
            }
        ]
    }
}
