import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: osdRoot

    property bool isShown: false
    property string osdType: "volume" // "volume" | "brightness"
    property int level: 50
    property bool isMuted: false

    WlrLayershell.namespace: "quickshell-osd"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

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

    Region { id: osdPillRegion; item: osdPill }

    // Ensures mouse clicks pass through completely when closed
    mask: isShown ? osdPillRegion : emptyRegion

    Timer {
        id: hideTimer
        interval: 1800
        repeat: false
        onTriggered: osdRoot.isShown = false
    }

    function showVolume(val, muted) {
        osdType = "volume"
        level = Math.max(0, Math.min(100, val))
        isMuted = muted !== undefined ? muted : false
        isShown = true
        hideTimer.restart()
    }

    function showBrightness(val) {
        osdType = "brightness"
        level = Math.max(0, Math.min(100, val))
        isShown = true
        hideTimer.restart()
    }

    // Centered OSD Pill Card near Screen Bottom
    Rectangle {
        id: osdPill

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 90

        width: 240
        height: 44
        radius: 22
        color: "#0a0a0c"
        border.color: "#222228"
        border.width: 1
        clip: true

        opacity: osdRoot.isShown ? 1.0 : 0.0
        scale: osdRoot.isShown ? 1.0 : 0.82
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: osdRoot.isShown ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 1.25
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            Text {
                text: {
                    if (osdRoot.osdType === "volume") {
                        if (osdRoot.isMuted || osdRoot.level === 0) return "󰝟"
                        return osdRoot.level > 50 ? "󰕾" : "󰖀"
                    } else {
                        return osdRoot.level > 50 ? "󰃠" : (osdRoot.level > 20 ? "󰃟" : "󰃞")
                    }
                }
                color: osdRoot.osdType === "volume"
                    ? (osdRoot.isMuted ? "#f38ba8" : "#a6e3a1")
                    : "#f9e2af"
                font.pixelSize: 16
                font.family: "JetBrainsMono Nerd Font"

                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: "#1a1a20"
                clip: true

                Rectangle {
                    width: parent.width * (osdRoot.level / 100.0)
                    height: parent.height
                    radius: parent.radius
                    color: osdRoot.osdType === "volume"
                        ? (osdRoot.isMuted ? "#f38ba8" : "#a6e3a1")
                        : "#f9e2af"

                    Behavior on width {
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
            }

            Text {
                text: osdRoot.isMuted && osdRoot.osdType === "volume" ? "MUTE" : (osdRoot.level + "%")
                color: "#cdd6f4"
                font.bold: true
                font.pixelSize: 11
                font.family: "JetBrainsMono Nerd Font"
            }
        }
    }
}
