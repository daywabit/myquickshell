import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: powerMenuRoot

    property bool isOpen: false

    WlrLayershell.namespace: "quickshell-powermenu"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Ignore top panel exclusion boundaries to eliminate top gap
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    Item { id: fullSurface; anchors.fill: parent }
    Item { id: emptySurface; width: 0; height: 0 }

    Region { id: fullRegion; item: fullSurface }
    Region { id: emptyRegion; item: emptySurface }

    mask: isOpen ? fullRegion : emptyRegion

    function open() {
        isOpen = true
        menuContent.forceActiveFocus()
    }

    function close() {
        isOpen = false
    }

    function toggle() {
        if (isOpen) close()
        else open()
    }

    Shortcut {
        sequence: "Escape"
        enabled: powerMenuRoot.isOpen
        onActivated: powerMenuRoot.close()
    }

    // Fullscreen Dark Backdrop
    Rectangle {
        anchors.fill: parent
        color: "#d9000000"
        opacity: powerMenuRoot.isOpen ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: powerMenuRoot.close()
        }
    }

    // Centered Power Card
    Rectangle {
        id: menuContent
        anchors.centerIn: parent
        width: 580
        height: 150
        radius: 26
        color: "#08080a"
        border.color: "#222228"
        border.width: 1
        clip: true

        scale: powerMenuRoot.isOpen ? 1.0 : 0.82
        opacity: powerMenuRoot.isOpen ? 1.0 : 0.0
        visible: opacity > 0

        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutBack
                easing.overshoot: 1.15
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        // Direct Keybind Listeners
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_S || event.key === Qt.Key_1) {
                execCmd(["systemctl", "poweroff"])
            } else if (event.key === Qt.Key_R || event.key === Qt.Key_2) {
                execCmd(["systemctl", "reboot"])
            } else if (event.key === Qt.Key_L || event.key === Qt.Key_3) {
                execCmd(["loginctl", "lock-session"])
            } else if (event.key === Qt.Key_Z || event.key === Qt.Key_4) {
                execCmd(["systemctl", "suspend"])
            } else if (event.key === Qt.Key_E || event.key === Qt.Key_5) {
                execCmd(["hyprctl", "dispatch", "exit"])
            }
        }

        Component {
            id: cmdRunner
            Process { onExited: destroy() }
        }

        function execCmd(args) {
            powerMenuRoot.close()
            var p = cmdRunner.createObject(powerMenuRoot, { command: args })
            p.running = true
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            PowerTile {
                icon: "󰐥"
                label: "Shutdown"
                onTriggered: menuContent.execCmd(["systemctl", "poweroff"])
            }

            PowerTile {
                icon: "󰜉"
                label: "Reboot"
                onTriggered: menuContent.execCmd(["systemctl", "reboot"])
            }

            PowerTile {
                icon: "󰌾"
                label: "Lock"
                onTriggered: menuContent.execCmd(["loginctl", "lock-session"])
            }

            PowerTile {
                icon: "󰤄"
                label: "Sleep"
                onTriggered: menuContent.execCmd(["systemctl", "suspend"])
            }

            PowerTile {
                icon: "󰍃"
                label: "Logout"
                onTriggered: menuContent.execCmd(["hyprctl", "dispatch", "exit"])
            }
        }
    }
}
