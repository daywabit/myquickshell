import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

ColumnLayout {
    id: root
    spacing: 12
    Layout.fillWidth: true
    Layout.fillHeight: true

    // Signal required by Sidebar.qml
    signal runCommand(var cmd)

    property string activePowerProfile: "balanced"
    property real batteryLevel: 100
    property bool isCharging: false

    // Dynamic notification count helper
    property int notiCount: (typeof NotificationServer !== "undefined" && NotificationServer.notifications) ? NotificationServer.notifications.length : 0

    function dismissNotification(item) {
        if (item && typeof item.dismiss === "function") {
            item.dismiss()
        }
    }

    function clearAllNotifications() {
        if (typeof NotificationServer !== "undefined" && NotificationServer.notifications) {
            let notifs = NotificationServer.notifications
            for (let i = notifs.length - 1; i >= 0; i--) {
                if (notifs[i] && typeof notifs[i].dismiss === "function") {
                    notifs[i].dismiss()
                }
            }
        }
        // Trigger swaync clear command if SwayNC is running on the system
        root.runCommand(["swaync-client", "-C"])
    }

    // ----------------------------------------------------
    // Hardware Polling: ASUS Battery Sysfs Listener
    // ----------------------------------------------------
    Process {
        id: batteryProc
        command: ["bash", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1; cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n")
                if (lines.length >= 1 && lines[0] !== "") {
                    root.batteryLevel = Math.max(0, Math.min(100, parseInt(lines[0]) || 0))
                }
                if (lines.length >= 2) {
                    let st = lines[1].toLowerCase()
                    root.isCharging = (st === "charging" || st === "full")
                }
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: batteryProc.running = true
    }

    // ----------------------------------------------------
    // Power Profiles Listener & Controller
    // ----------------------------------------------------
    Process {
        id: profileGetProc
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                let profile = this.text.trim()
                if (profile.length > 0) {
                    root.activePowerProfile = profile
                }
            }
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: profileGetProc.running = true
    }

    Process {
        id: profileSetProc
    }

    function setProfile(name) {
        root.activePowerProfile = name
        profileSetProc.command = ["powerprofilesctl", "set", name]
        profileSetProc.running = true
    }

    // ====================================================
    // 1. NOTIFICATION CENTER DECK (TOP - EXPANDS TO FILL SPACE)
    // ====================================================
    Rectangle {
        id: notificationCard
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: 200
        radius: 16
        color: "#1e1e1e"
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Header: Title + Badge Count + Clear All Button
            RowLayout {
                Layout.fillWidth: true

                RowLayout {
                    spacing: 6
                    Text {
                        text: "󰂚"
                        color: "#89b4fa"
                        font.pixelSize: 14
                        font.family: "JetBrainsMono Nerd Font"
                    }
                    Text {
                        text: "Notifications"
                        color: "#ffffff"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.family: "JetBrainsMono Nerd Font"
                    }

                    // Active counter badge
                    Rectangle {
                        visible: root.notiCount > 0
                        width: Math.max(18, countText.implicitWidth + 8)
                        height: 18
                        radius: 9
                        color: "#89b4fa"

                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: root.notiCount
                            color: "#11111b"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.family: "JetBrainsMono Nerd Font"
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Clear All Option
                Rectangle {
                    visible: root.notiCount > 0
                    width: 68
                    height: 24
                    radius: 8
                    color: clearAllArea.containsMouse ? "#f38ba8" : "#2a2a2a"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Clear All"
                        color: clearAllArea.containsMouse ? "#11111b" : "#a6adc8"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.family: "JetBrainsMono Nerd Font"
                    }

                    MouseArea {
                        id: clearAllArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearAllNotifications()
                    }
                }
            }

            // Case 1: Empty Placeholder State
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.notiCount === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󰂜"
                        color: "#44ffffff"
                        font.pixelSize: 26
                        font.family: "JetBrainsMono Nerd Font"
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No New Notifications"
                        color: "#44ffffff"
                        font.pixelSize: 11
                        font.family: "JetBrainsMono Nerd Font"
                    }
                }
            }

            // Case 2: Scrollable Stored Notification List
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.notiCount > 0
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: (typeof NotificationServer !== "undefined") ? NotificationServer.notifications : []

                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: itemContentLayout.implicitHeight + 16
                            radius: 12
                            color: itemHoverArea.containsMouse ? "#28283a" : "#111111"
                            border.color: "#1e1e2e"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 100 } }

                            MouseArea {
                                id: itemHoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            RowLayout {
                                id: itemContentLayout
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                // App / Notification Icon
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    width: 28
                                    height: 28
                                    radius: 8
                                    color: "#1e1e1e"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰂚"
                                        color: "#89b4fa"
                                        font.pixelSize: 13
                                        font.family: "JetBrainsMono Nerd Font"
                                    }
                                }

                                // Header Summary and Content Body
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData ? (modelData.summary || modelData.appName || "Notification") : "Notification"
                                            color: "#ffffff"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.family: "JetBrainsMono Nerd Font"
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: Boolean(modelData && modelData.appName && modelData.summary)
                                            text: modelData ? (modelData.appName || "") : ""
                                            color: "#6c7086"
                                            font.pixelSize: 9
                                            font.family: "JetBrainsMono Nerd Font"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: Boolean(modelData && modelData.body)
                                        text: modelData ? (modelData.body || "") : ""
                                        color: "#a6adc8"
                                        font.pixelSize: 10
                                        font.family: "JetBrainsMono Nerd Font"
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }
                                }

                                // 'X' Delete Sign for Individual Notification
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: deleteBtnArea.containsMouse ? "#f38ba8" : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        color: deleteBtnArea.containsMouse ? "#11111b" : "#6c7086"
                                        font.pixelSize: 12
                                        font.family: "JetBrainsMono Nerd Font"
                                    }

                                    MouseArea {
                                        id: deleteBtnArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.dismissNotification(modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ====================================================
    // 2. LIQUID BATTERY INDICATOR (ABOVE PROFILE DAEMON)
    // ====================================================
    Rectangle {
        id: batteryWidget
        Layout.fillWidth: true
        height: 54
        radius: 16
        color: "#1e1e1e"
        clip: true

        property real wavePhase: 0.0

        Timer {
            interval: 30
            running: true
            repeat: true
            onTriggered: {
                batteryWidget.wavePhase += 0.08
                batteryCanvas.requestPaint()
            }
        }

        Canvas {
            id: batteryCanvas
            anchors.fill: parent

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var fillHeight = height * (root.batteryLevel / 100.0)
                var liquidY = height - fillHeight

                ctx.fillStyle = root.batteryLevel <= 20 ? "#ff5555" : "#ffffff"

                ctx.beginPath()
                ctx.moveTo(0, height)
                ctx.lineTo(0, liquidY)

                for (var x = 0; x <= width; x += 4) {
                    var y = liquidY + Math.sin(x * 0.04 + batteryWidget.wavePhase) * 3.0
                    ctx.lineTo(x, y)
                }

                ctx.lineTo(width, height)
                ctx.closePath()
                ctx.fill()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Text {
                text: root.isCharging ? "󰂄" : (root.batteryLevel <= 20 ? "󰂃" : "󰁹")
                color: root.batteryLevel > 50 ? "#000000" : "#ffffff"
                font.pixelSize: 18
                font.family: "JetBrainsMono Nerd Font"

                Behavior on color { ColorAnimation { duration: 200 } }
            }

            Text {
                text: root.isCharging ? "Charging" : "Discharging"
                color: root.batteryLevel > 50 ? "#44000000" : "#88ffffff"
                font.pixelSize: 11
                font.family: "JetBrainsMono Nerd Font"

                Behavior on color { ColorAnimation { duration: 200 } }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: Math.round(root.batteryLevel) + "%"
                color: root.batteryLevel > 50 ? "#000000" : "#ffffff"
                font.weight: Font.ExtraBold
                font.pixelSize: 14
                font.family: "JetBrainsMono Nerd Font"

                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }
    }

    // ====================================================
    // 3. POWER PROFILE DAEMON (BOTTOM ANCHORED)
    // ====================================================
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        component ProfileButton : Rectangle {
            id: btn
            property string profileName: ""
            property string icon: ""
            property string labelText: ""

            Layout.fillWidth: true
            height: 52
            radius: 14

            property bool isActive: root.activePowerProfile === profileName

            color: isActive ? "#ffffff" : "#1e1e1e"
            scale: btnMouse.pressed ? 0.94 : (isActive ? 1.02 : 1.0)

            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: btn.icon
                    color: btn.isActive ? "#000000" : "#ffffff"
                    font.pixelSize: 16
                    font.family: "JetBrainsMono Nerd Font"

                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: btn.labelText
                    color: btn.isActive ? "#000000" : "#88ffffff"
                    font.pixelSize: 10
                    font.weight: btn.isActive ? Font.Bold : Font.Normal
                    font.family: "JetBrainsMono Nerd Font"

                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                onClicked: root.setProfile(btn.profileName)
            }
        }

        ProfileButton {
            profileName: "power-saver"
            icon: "󰾆"
            labelText: "Saver"
        }

        ProfileButton {
            profileName: "balanced"
            icon: "󰾅"
            labelText: "Balanced"
        }

        ProfileButton {
            profileName: "performance"
            icon: "󰓅"
            labelText: "Performance"
        }
    }
}
