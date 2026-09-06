import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris

PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell-island"
    WlrLayershell.layer: WlrLayershell.Top

    // Keyboard focus when island is open
    WlrLayershell.keyboardFocus: island.isControlCenter
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None

    focusable: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Standalone Region instance for the island
    Region {
        id: islandRegion
        item: island
    }

    // Dynamic Mask
    mask: island.isControlCenter ? null : islandRegion

    // Global Key Listener for ESC key dismissal
    Item {
        anchors.fill: parent
        focus: island.isControlCenter
        Keys.onEscapePressed: {
            swipeView.currentIndex = 0
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // --- Dynamic System State Variables ---
    property bool wifiEnabled: true
    property bool btEnabled: false
    property bool caffeineEnabled: false
    property int volumeLevel: 50
    property int brightnessLevel: 70

    // --- Native MPRIS Active Player Tracker ---
    property var activePlayer: {
        if (!Mpris.players || !Mpris.players.values) return null
        let players = Mpris.players.values
        for (let i = 0; i < players.length; i++) {
            if (players[i] && players[i].isPlaying) return players[i]
        }
        return players.length > 0 ? players[0] : null
    }

    property real mediaPosition: 0
    property bool isSeeking: false
    property real cachedTrackLength: 0

    property real effectiveLength: {
        if (!activePlayer) return 0
        let len = activePlayer.length
        if (cachedTrackLength > 0 && len < cachedTrackLength) {
            return cachedTrackLength
        }
        return Math.max(len, cachedTrackLength)
    }

    function formatTime(sec) {
        if (isNaN(sec) || sec <= 0) return "0:00"
        let m = Math.floor(sec / 60)
        let s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    Component {
        id: cmdRunner
        Process { onExited: destroy() }
    }

    function runCmd(args) {
        var p = cmdRunner.createObject(root, { command: args })
        p.running = true
    }

    Component {
        id: cmdExec
        Process {
            id: proc
            property var callback
            stdout: StdioCollector {
                onStreamFinished: {
                    let last = this.text.trim().split("\n").pop() || ""
                    if (proc.callback) proc.callback(last)
                }
            }
            onExited: destroy()
        }
    }

    function exec(args, callback) {
        var p = cmdExec.createObject(root, { command: args, callback: callback })
        p.running = true
    }

    Timer {
        id: seekDebounceTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.isSeeking = false
            if (root.activePlayer) {
                root.mediaPosition = root.activePlayer.position
            }
        }
    }

    Connections {
        target: root.activePlayer

        function onTrackTitleChanged() {
            if (root.activePlayer) {
                root.cachedTrackLength = root.activePlayer.length
                root.mediaPosition = root.activePlayer.position
            }
        }

        function onLengthChanged() {
            if (root.activePlayer && root.activePlayer.length > root.cachedTrackLength) {
                root.cachedTrackLength = root.activePlayer.length
            }
        }

        function onPositionChanged() {
            if (!root.isSeeking && root.activePlayer) {
                root.mediaPosition = root.activePlayer.position
            }
        }
    }

    Timer {
        interval: 200
        running: root.activePlayer && root.activePlayer.isPlaying
        repeat: true
        onTriggered: {
            if (!root.activePlayer || root.isSeeking) return

            if (root.activePlayer.length > root.cachedTrackLength) {
                root.cachedTrackLength = root.activePlayer.length
            }

            let dbusPos = root.activePlayer.position

            if (Math.abs(root.mediaPosition - dbusPos) > 0.8) {
                root.mediaPosition = dbusPos
            } else if (root.effectiveLength > 0 && root.mediaPosition < root.effectiveLength) {
                root.mediaPosition = Math.min(root.effectiveLength, root.mediaPosition + 0.2)
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.exec(["nmcli", "radio", "wifi"], (last) => { root.wifiEnabled = (last === "enabled") })
            root.exec(["bluetoothctl", "show"], (last) => { root.btEnabled = last.includes("Powered: yes") })
            root.exec(["pamixer", "--get-volume"], (last) => {
                let val = parseInt(last)
                if (!isNaN(val)) root.volumeLevel = val
            })
            root.exec(["brightnessctl", "-m"], (last) => {
                let parts = last.split(",")
                if (parts.length >= 4) {
                    let val = parseInt(parts[3].replace("%", ""))
                    if (!isNaN(val)) root.brightnessLevel = val
                }
            })
        }
    }

    // Tap-away backdrop
    MouseArea {
        anchors.fill: parent
        enabled: island.isControlCenter
        onClicked: swipeView.currentIndex = 0
    }

    Rectangle {
        id: island

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        // Added 8px top margin for normal island state so it sits neatly in bar space
        anchors.topMargin: isControlCenter ? 2 : 8

        property bool isHovered: hoverHandler.hovered
        property bool isControlCenter: swipeView.currentIndex > 0

        property real targetWidth: {
            if (isControlCenter) return 360
            return isHovered ? 240 : 105
        }

        property real targetHeight: {
            if (isControlCenter) return 230
            return isHovered ? 44 : 28
        }

        width: targetWidth
        height: targetHeight
        radius: isControlCenter ? 24 : height / 2

        color: "#000000"
        border.width: 0

        Behavior on width { SpringAnimation { spring: 3.5; damping: 0.28; epsilon: 0.25 } }
        Behavior on height { SpringAnimation { spring: 3.5; damping: 0.28; epsilon: 0.25 } }
        Behavior on radius { SpringAnimation { spring: 3.5; damping: 0.28; epsilon: 0.25 } }

        HoverHandler { id: hoverHandler }

        WheelHandler {
            id: wheelHandler
            onWheel: (event) => {
                if (event.angleDelta.y < 0 || event.angleDelta.x > 0) {
                    swipeView.incrementCurrentIndex()
                } else if (event.angleDelta.y > 0 || event.angleDelta.x < 0) {
                    swipeView.decrementCurrentIndex()
                }
            }
        }

        SwipeView {
            id: swipeView
            anchors.fill: parent
            clip: true
            interactive: true

            // PAGE 1: Clock
            Item {
                id: page1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: Qt.formatDateTime(clock.date, "hh:mm A")
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: island.isHovered ? 13 : 12
                        font.family: "JetBrainsMono Nerd Font"
                        antialiasing: true

                        Behavior on font.pixelSize { SpringAnimation { spring: 3; damping: 0.3 } }
                    }

                    Rectangle {
                        width: 1
                        height: 12
                        color: "#222222"
                        visible: island.isHovered && !island.isControlCenter
                    }

                    Text {
                        text: Qt.formatDateTime(clock.date, "ddd MMM d")
                        color: "#ffffff"
                        font.pixelSize: 11
                        font.family: "JetBrainsMono Nerd Font"
                        antialiasing: true
                        visible: island.isHovered && !island.isControlCenter
                    }
                }
            }

            // PAGE 2: Control Center
            Item {
                id: page2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "CONTROL CENTER"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 10
                            font.letterSpacing: 2
                            font.family: "JetBrainsMono Nerd Font"
                            opacity: 0.4
                        }

                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 12
                            color: root.wifiEnabled ? "#ffffff" : "#141414"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: root.wifiEnabled ? "󰤨" : "󰤭"
                                    color: root.wifiEnabled ? "#000000" : "#ffffff"
                                    font.pixelSize: 14
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                Text {
                                    text: "Wi-Fi"
                                    color: root.wifiEnabled ? "#000000" : "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.family: "JetBrainsMono Nerd Font"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    let target = root.wifiEnabled ? "off" : "on"
                                    root.wifiEnabled = !root.wifiEnabled
                                    root.runCmd(["nmcli", "radio", "wifi", target])
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 12
                            color: root.btEnabled ? "#ffffff" : "#141414"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: root.btEnabled ? "󰂯" : "󰂲"
                                    color: root.btEnabled ? "#000000" : "#ffffff"
                                    font.pixelSize: 14
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                Text {
                                    text: "Bluetooth"
                                    color: root.btEnabled ? "#000000" : "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.family: "JetBrainsMono Nerd Font"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    let target = root.btEnabled ? "off" : "on"
                                    root.btEnabled = !root.btEnabled
                                    root.runCmd(["bluetoothctl", "power", target])
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 12
                            color: root.caffeineEnabled ? "#ffffff" : "#141414"

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: root.caffeineEnabled ? "󰅶" : "󰾆"
                                    color: root.caffeineEnabled ? "#000000" : "#ffffff"
                                    font.pixelSize: 14
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                Text {
                                    text: "Caffeine"
                                    color: root.caffeineEnabled ? "#000000" : "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.family: "JetBrainsMono Nerd Font"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.caffeineEnabled = !root.caffeineEnabled
                                    if (root.caffeineEnabled) {
                                        root.runCmd(["systemd-inhibit", "--what=idle", "--who=QuickShell", "--why=Caffeine", "sleep", "infinity"])
                                    } else {
                                        root.runCmd(["pkill", "-f", "systemd-inhibit --what=idle --who=QuickShell"])
                                    }
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            radius: 12
                            color: "#141414"
                            clip: true

                            Rectangle {
                                width: parent.width * (root.volumeLevel / 100.0)
                                height: parent.height
                                radius: parent.radius
                                color: "#ffffff"

                                Behavior on width { NumberAnimation { duration: 60 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Text {
                                    text: root.volumeLevel === 0 ? "󰝟" : (root.volumeLevel > 50 ? "󰕾" : "󰖀")
                                    color: root.volumeLevel > 15 ? "#000000" : "#ffffff"
                                    font.pixelSize: 14
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.volumeLevel + "%"
                                    color: root.volumeLevel > 85 ? "#000000" : "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.family: "JetBrainsMono Nerd Font"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                function setVol(mouse) {
                                    let pct = Math.max(0, Math.min(100, Math.round((mouse.x / width) * 100)))
                                    root.volumeLevel = pct
                                    root.runCmd(["pamixer", "--set-volume", pct.toString()])
                                }
                                onClicked: (mouse) => setVol(mouse)
                                onPositionChanged: (mouse) => { if (pressed) setVol(mouse) }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            radius: 12
                            color: "#141414"
                            clip: true

                            Rectangle {
                                width: parent.width * (root.brightnessLevel / 100.0)
                                height: parent.height
                                radius: parent.radius
                                color: "#ffffff"

                                Behavior on width { NumberAnimation { duration: 60 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Text {
                                    text: root.brightnessLevel > 50 ? "󰃠" : "󰃟"
                                    color: root.brightnessLevel > 15 ? "#000000" : "#ffffff"
                                    font.pixelSize: 14
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.brightnessLevel + "%"
                                    color: root.brightnessLevel > 85 ? "#000000" : "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 11
                                    font.family: "JetBrainsMono Nerd Font"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                function setBright(mouse) {
                                    let pct = Math.max(1, Math.min(100, Math.round((mouse.x / width) * 100)))
                                    root.brightnessLevel = pct
                                    root.runCmd(["brightnessctl", "set", pct + "%"])
                                }
                                onClicked: (mouse) => setBright(mouse)
                                onPositionChanged: (mouse) => { if (pressed) setBright(mouse) }
                            }
                        }
                    }
                }
            }

            // PAGE 3: Native MPRIS Media Player
            Item {
                id: page3

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "MEDIA PLAYER"
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 10
                            font.letterSpacing: 2
                            font.family: "JetBrainsMono Nerd Font"
                            opacity: 0.4
                        }

                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Rectangle {
                            width: 54
                            height: 54
                            radius: 12
                            color: "#141414"
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: root.activePlayer ? root.activePlayer.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: root.activePlayer && root.activePlayer.trackArtUrl !== ""
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "󰎆"
                                color: "#ffffff"
                                font.pixelSize: 22
                                font.family: "JetBrainsMono Nerd Font"
                                opacity: 0.3
                                visible: !root.activePlayer || root.activePlayer.trackArtUrl === ""
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: root.activePlayer ? (root.activePlayer.trackTitle || "Unknown Title") : "No Media Playing"
                                color: "#ffffff"
                                font.bold: true
                                font.pixelSize: 13
                                font.family: "JetBrainsMono Nerd Font"
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.activePlayer ? (root.activePlayer.trackArtist || "Idle") : "Idle"
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.family: "JetBrainsMono Nerd Font"
                                opacity: 0.6
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }

                    // Scrubber / Progress Bar
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Rectangle {
                            id: progressTrack
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: "#181818"
                            clip: true

                            Rectangle {
                                property real progressRatio: root.effectiveLength > 0 ? Math.min(1.0, Math.max(0.0, root.mediaPosition / root.effectiveLength)) : 0
                                width: parent.width * progressRatio
                                height: parent.height
                                radius: parent.radius
                                color: "#ffffff"

                                Behavior on width { NumberAnimation { duration: 100 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                function seekTo(mouse) {
                                    if (!root.activePlayer || root.effectiveLength <= 0) return
                                    let pct = Math.max(0, Math.min(1, mouse.x / width))
                                    let sec = pct * root.effectiveLength

                                    root.isSeeking = true
                                    root.mediaPosition = sec

                                    if (root.activePlayer.canSeek) {
                                        root.activePlayer.position = sec
                                    }

                                    seekDebounceTimer.restart()
                                }
                                onClicked: (mouse) => seekTo(mouse)
                                onPositionChanged: (mouse) => { if (pressed) seekTo(mouse) }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: root.formatTime(root.mediaPosition)
                                color: "#ffffff"
                                font.pixelSize: 9
                                font.family: "JetBrainsMono Nerd Font"
                                opacity: 0.5
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: root.formatTime(root.effectiveLength)
                                color: "#ffffff"
                                font.pixelSize: 9
                                font.family: "JetBrainsMono Nerd Font"
                                opacity: 0.5
                            }
                        }
                    }

                    // Media Playback Controls
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: 10
                            color: prevArea.containsMouse ? "#222222" : "#141414"

                            Text {
                                anchors.centerIn: parent
                                text: "󰒮"
                                color: "#ffffff"
                                font.pixelSize: 15
                                font.family: "JetBrainsMono Nerd Font"
                                scale: prevArea.pressed ? 0.85 : 1.0
                                Behavior on scale { NumberAnimation { duration: 80 } }
                            }

                            MouseArea {
                                id: prevArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (root.activePlayer && root.activePlayer.canGoPrevious) {
                                        root.activePlayer.previous()
                                    }
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: 10
                            color: playArea.containsMouse ? "#ffffff" : "#e0e0e0"

                            Text {
                                anchors.centerIn: parent
                                text: (root.activePlayer && root.activePlayer.isPlaying) ? "󰏤" : "󰐊"
                                color: "#000000"
                                font.pixelSize: 15
                                font.family: "JetBrainsMono Nerd Font"
                                scale: playArea.pressed ? 0.85 : 1.0
                                Behavior on scale { NumberAnimation { duration: 80 } }
                            }

                            MouseArea {
                                id: playArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (root.activePlayer && root.activePlayer.canTogglePlaying) {
                                        root.activePlayer.togglePlaying()
                                    }
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: 10
                            color: nextArea.containsMouse ? "#222222" : "#141414"

                            Text {
                                anchors.centerIn: parent
                                text: "󰒭"
                                color: "#ffffff"
                                font.pixelSize: 15
                                font.family: "JetBrainsMono Nerd Font"
                                scale: nextArea.pressed ? 0.85 : 1.0
                                Behavior on scale { NumberAnimation { duration: 80 } }
                            }

                            MouseArea {
                                id: nextArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (root.activePlayer && root.activePlayer.canGoNext) {
                                        root.activePlayer.next()
                                    }
                                }
                            }

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                }
            }

            // PAGE 4: App Launcher Container
            LauncherPage {
                id: page4
                parentSwipeView: swipeView
            }
        }

        PageIndicator {
            id: pageIndicator
            count: swipeView.count
            currentIndex: swipeView.currentIndex
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: island.isHovered || island.isControlCenter ? 1 : 0

            delegate: Rectangle {
                implicitWidth: index === pageIndicator.currentIndex ? 12 : 4
                implicitHeight: 4
                radius: 2
                color: index === pageIndicator.currentIndex ? "#ffffff" : "#333333"

                Behavior on implicitWidth { SpringAnimation { spring: 3; damping: 0.3 } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
    }
}
