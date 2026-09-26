pragma ComponentBehavior: Bound

import "./kblayout"
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.components
import qs.modules
import qs.services

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
                        // Also try after a short delay in case networkPopout.item wasn't ready
                        Qt.callLater(() => {
                            if (passwordPopout.item && (networkPopout.item as CortetsuNetworkPopup)?.passwordNetwork) {
                                (passwordPopout.item as CortetsuWifiPasswordPopup).network = (networkPopout.item as CortetsuNetworkPopup).passwordNetwork;
                            }
                        }, 100);
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

        Repeater {
            model: ScriptModel {
                values: SystemTray.items.values.filter(i => !CortetsuConfig.hiddenTrayIcons.includes(i.id))
            }

            Popout {
                id: trayMenu

                required property SystemTrayItem modelData
                required property int index
                readonly property var menuHandle: modelData?.menu ?? null
                property bool menuReady: true

                name: `traymenu${index}`
                sourceComponent: menuHandle && menuReady ? trayMenuComp : null

                Timer {
                    id: menuReload
                    interval: 0
                    repeat: false
                    onTriggered: trayMenu.menuReady = true
                }

                Connections {
                    function onHasCurrentChanged(): void {
                        if (root.popouts.hasCurrent && trayMenu.shouldBeActive) {
                            trayMenu.menuReady = false;
                            menuReload.restart();
                        }
                    }

                    target: root.popouts
                }

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
        readonly property bool shouldBeActive: root.popouts.currentName === name

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
