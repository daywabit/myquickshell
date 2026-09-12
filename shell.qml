import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris

Scope {
    id: scopeRoot

    // --- 1. Wallpaper Engine (Runs continuously in background) ---
    WallpaperEngine {}

    // --- 2. Nixpkgs Search Drawer (Bottom Center) ---
    NixPkgDrawer {
        id: nixPkgDrawer
    }

    // --- 3. Standalone Fullscreen Wallpaper Picker Window ---
    PanelWindow {
        id: wallpaperPickerWindow

        WlrLayershell.namespace: "quickshell-wallpaper-picker"
        WlrLayershell.layer: WlrLayershell.Overlay

        // Cover the entire screen
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        color: "transparent"
        visible: false

        // Take keyboard focus (arrow keys, enter) only when launched
        WlrLayershell.keyboardFocus: visible
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None

        // Embed the picker full-screen
        WallpaperPicker {
            anchors.fill: parent
            focus: wallpaperPickerWindow.visible
        }

        // Close on Escape key
        Shortcut {
            sequence: "Escape"
            enabled: wallpaperPickerWindow.visible
            onActivated: wallpaperPickerWindow.visible = false
        }
    }

    // --- Left Edge Side Notch ---
    SideNotch {}

    // --- Lock Screen Window ---
    LockScreen {
        id: lockScreen
    }

    // --- Power Menu Window ---
    PowerMenu {
        id: powerMenu
        onLockRequested: lockScreen.lock()
    }

    // --- OSD Volume / Brightness Pill ---
    Osd {
        id: osd
    }

    // --- Right Sidebar Drawer ---
    Sidebar {
        id: sidebar
        onOpenPowerMenu: powerMenu.toggle()
    }

    // --- IPC Handler for external keybinds & OSD ---
    Process {
        id: ipcPipe
        command: ["sh", "-c", "rm -f /tmp/quickshell_island.fifo && mkfifo /tmp/quickshell_island.fifo && exec cat /tmp/quickshell_island.fifo"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n")
                let msg = lines.length > 0 ? lines[lines.length - 1].trim() : ""

                if (msg === "lock") {
                    lockScreen.lock()
                } else if (msg === "wallpaper") {
                    wallpaperPickerWindow.visible = !wallpaperPickerWindow.visible
                } else if (msg === "nixpkgs" || msg === "nixsearch") {
                    nixPkgDrawer.toggle()
                } else if (msg === "launcher") {
                    root.openLauncher()
                } else if (msg === "toggle") {
                    island.isExpanded = !island.isExpanded
                } else if (msg === "powermenu") {
                    powerMenu.toggle()
                } else if (msg === "vol_up") {
                    root.runCmd(["pamixer", "-i", "5"])
                    root.triggerVolumeOsd()
                } else if (msg === "vol_down") {
                    root.runCmd(["pamixer", "-d", "5"])
                    root.triggerVolumeOsd()
                } else if (msg === "vol_mute") {
                    root.runCmd(["pamixer", "-t"])
                    root.triggerVolumeOsd()
                } else if (msg === "bright_up") {
                    root.runCmd(["brightnessctl", "set", "+5%"])
                    root.triggerBrightnessOsd()
                } else if (msg === "bright_down") {
                    root.runCmd(["brightnessctl", "set", "5%-"])
                    root.triggerBrightnessOsd()
                } else if (msg === "vol" || msg === "volume") {
                    root.triggerVolumeOsd()
                } else if (msg === "brightness" || msg === "bright") {
                    root.triggerBrightnessOsd()
                }

                ipcRestartTimer.restart()
            }
        }
    }

    Timer {
        id: ipcRestartTimer
        interval: 100
        repeat: false
        onTriggered: {
            ipcPipe.running = false
            ipcPipe.running = true
        }
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell-top-spacer"
        WlrLayershell.layer: WlrLayershell.Top

        anchors {
            top: true
            left: true
            right: true
        }

        implicitHeight: 32
        exclusionMode: ExclusionMode.Auto
        color: "transparent"
        focusable: false

        Item { id: emptySpacerSurface; width: 0; height: 0 }
        Region { id: emptySpacerRegion; item: emptySpacerSurface }
        mask: emptySpacerRegion
    }

    PanelWindow {
        id: root

        WlrLayershell.namespace: "quickshell-island"
        WlrLayershell.layer: WlrLayershell.Top

        WlrLayershell.keyboardFocus: island.isExpanded
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        Item {
            id: fullScreenSurface
            anchors.fill: parent
        }

        Region {
            id: fullRegion
            item: fullScreenSurface
        }

        Region {
            id: islandRegion
            item: island
        }

        mask: island.isExpanded ? fullRegion : islandRegion

        Shortcut {
            sequence: "Escape"
            enabled: island.isExpanded
            onActivated: island.isExpanded = false
        }

        Timer {
            id: focusSyncTimer
            interval: 40
            repeat: false
            onTriggered: {
                if (island.isExpanded && swipeView.currentIndex === 2 && page2) {
                    if (typeof page2.focusSearch === "function") {
                        page2.focusSearch()
                    }
                }
            }
        }

        function openLauncher() {
            swipeView.currentIndex = 2
            island.isExpanded = true
            focusSyncTimer.restart()
        }

        function triggerVolumeOsd() {
            exec(["pamixer", "--get-volume"], (volStr) => {
                let val = parseInt(volStr)
                if (!isNaN(val)) root.volumeLevel = val
                exec(["pamixer", "--get-mute"], (muteStr) => {
                    let muted = muteStr.trim() === "true"
                    osd.showVolume(root.volumeLevel, muted)
                })
            })
        }

        function triggerBrightnessOsd() {
            exec(["brightnessctl", "-m"], (last) => {
                let parts = last.split(",")
                if (parts.length >= 4) {
                    let val = parseInt(parts[3].replace("%", ""))
                    if (!isNaN(val)) root.brightnessLevel = val
                }
                osd.showBrightness(root.brightnessLevel)
            })
        }

        MouseArea {
            anchors.fill: parent
            enabled: island.isExpanded
            onClicked: island.isExpanded = false
        }

        SystemClock {
            id: clock
            precision: SystemClock.Minutes
        }

        property bool wifiEnabled: true
        property bool btEnabled: false
        property bool caffeineEnabled: false
        property bool isRecording: false
        property int volumeLevel: 50
        property int brightnessLevel: 70

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
            let len = activePlayer.length || 0
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
            if (p) p.running = true
        }

        Component {
            id: cmdExec
            Process {
                id: proc
                property var callback
                stdout: StdioCollector {
                    onStreamFinished: {
                        let lines = this.text.trim().split("\n")
                        let last = lines.length > 0 ? lines[lines.length - 1].trim() : ""
                        if (proc.callback) proc.callback(last)
                    }
                }
                onExited: destroy()
            }
        }

        function exec(args, callback) {
            var p = cmdExec.createObject(root, { command: args, callback: callback })
            if (p) p.running = true
        }

        Timer {
            id: seekDebounceTimer
            interval: 400
            repeat: false
            onTriggered: {
                root.isSeeking = false
                if (root.activePlayer) {
                    root.mediaPosition = root.activePlayer.position || 0
                }
            }
        }

        Connections {
            target: root.activePlayer

            function onTrackTitleChanged() {
                if (root.activePlayer) {
                    root.cachedTrackLength = root.activePlayer.length || 0
                    root.mediaPosition = root.activePlayer.position || 0
                }
            }

            function onLengthChanged() {
                if (root.activePlayer && (root.activePlayer.length || 0) > root.cachedTrackLength) {
                    root.cachedTrackLength = root.activePlayer.length
                }
            }

            function onPositionChanged() {
                if (!root.isSeeking && root.activePlayer) {
                    root.mediaPosition = root.activePlayer.position || 0
                }
            }
        }

        Timer {
            interval: 200
            running: root.activePlayer && root.activePlayer.isPlaying
            repeat: true
            onTriggered: {
                if (!root.activePlayer || root.isSeeking) return

                let playerLen = root.activePlayer.length || 0
                if (playerLen > root.cachedTrackLength) {
                    root.cachedTrackLength = playerLen
                }

                let dbusPos = root.activePlayer.position || 0

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
            triggeredOnStart: true
            onTriggered: {
                root.exec(["pgrep", "-x", "wf-recorder"], (last) => { root.isRecording = (last.trim().length > 0) })
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

        Rectangle {
            id: island

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: isExpanded ? 2 : 8

            property bool isHovered: hoverHandler.hovered
            property bool isExpanded: false

            onIsExpandedChanged: {
                if (isExpanded) {
                    focusSyncTimer.restart()
                }
            }

            color: "#000000"
            border.width: 0
            clip: true

            states: [
                State {
                    name: "CLOSED"
                    when: !island.isExpanded && !island.isHovered
                    PropertyChanges { target: island; width: root.isRecording ? 142 : 105; height: 28; radius: 14 }
                },
                State {
                    name: "HOVER"
                    when: !island.isExpanded && island.isHovered
                    PropertyChanges { target: island; width: root.isRecording ? 275 : 240; height: 44; radius: 22 }
                },
                State {
                    name: "EXPANDED"
                    when: island.isExpanded
                    PropertyChanges { target: island; width: 520; height: 250; radius: 22 }
                }
            ]

            transitions: [
                Transition {
                    NumberAnimation {
                        properties: "width,height,radius"
                        duration: 300
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.25
                    }
                }
            ]

            HoverHandler { id: hoverHandler }

            Item {
                id: pillHeader
                anchors.fill: parent
                opacity: island.isExpanded ? 0 : 1
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: 100 } }

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

                        Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
                    }

                    Rectangle {
                        width: 1
                        height: 12
                        color: "#333333"
                        visible: island.isHovered && !island.isExpanded
                    }

                    Text {
                        text: Qt.formatDateTime(clock.date, "ddd MMM d")
                        color: "#a6adc8"
                        font.pixelSize: 11
                        font.family: "JetBrainsMono Nerd Font"
                        antialiasing: true
                        visible: island.isHovered && !island.isExpanded
                    }

                    RowLayout {
                        id: recIndicator
                        spacing: 6
                        visible: opacity > 0
                        opacity: root.isRecording ? 1.0 : 0.0
                        scale: root.isRecording ? 1.0 : 0.2

                        Behavior on opacity {
                            NumberAnimation { duration: 220; easing.type: Easing.OutQuad }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 320
                                easing.type: root.isRecording ? Easing.OutBack : Easing.InBack
                                easing.overshoot: 1.5
                            }
                        }

                        Rectangle {
                            width: 1
                            height: island.isHovered ? 14 : 10
                            color: "#33ffffff"
                        }

                        Item {
                            width: 12
                            height: 12

                            Rectangle {
                                anchors.centerIn: parent
                                width: 10
                                height: 10
                                radius: 5
                                color: "#f38ba8"

                                SequentialAnimation on scale {
                                    running: root.isRecording
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1.0; to: 1.65; duration: 750; easing.type: Easing.OutQuad }
                                    NumberAnimation { from: 1.65; to: 1.0; duration: 750; easing.type: Easing.InQuad }
                                }

                                SequentialAnimation on opacity {
                                    running: root.isRecording
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.55; to: 0.0; duration: 750; easing.type: Easing.OutQuad }
                                    NumberAnimation { from: 0.0; to: 0.55; duration: 750; easing.type: Easing.InQuad }
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: "#f38ba8"
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !island.isExpanded
                    onClicked: island.isExpanded = true
                }
            }

            Item {
                id: expandedContent
                anchors.centerIn: parent
                width: 520
                height: 250
                opacity: island.isExpanded ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: 120 } }

                WheelHandler {
                    id: wheelHandler
                    enabled: island.isExpanded
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
                    interactive: island.isExpanded

                    onCurrentIndexChanged: {
                        if (currentIndex === 2 && island.isExpanded) {
                            focusSyncTimer.restart()
                        }
                    }

                    Item {
                        id: page0

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "CONTROL CENTER"
                                    color: "#ffffff"
                                    font.weight: Font.ExtraBold
                                    font.pixelSize: 11
                                    font.letterSpacing: 2
                                    font.family: "JetBrainsMono Nerd Font"
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
                                    color: root.wifiEnabled ? "#89b4fa" : "#1e1e1e"

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: root.wifiEnabled ? "󰤨" : "󰤭"
                                            color: root.wifiEnabled ? "#11111b" : "#ffffff"
                                            font.pixelSize: 14
                                            font.family: "JetBrainsMono Nerd Font"
                                        }

                                        Text {
                                            text: "Wi-Fi"
                                            color: root.wifiEnabled ? "#11111b" : "#ffffff"
                                            font.weight: Font.ExtraBold
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
                                    color: root.btEnabled ? "#b4befe" : "#1e1e1e"

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: root.btEnabled ? "󰂯" : "󰂲"
                                            color: root.btEnabled ? "#11111b" : "#ffffff"
                                            font.pixelSize: 14
                                            font.family: "JetBrainsMono Nerd Font"
                                        }

                                        Text {
                                            text: "Bluetooth"
                                            color: root.btEnabled ? "#11111b" : "#ffffff"
                                            font.weight: Font.ExtraBold
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
                                    color: root.caffeineEnabled ? "#fab387" : "#1e1e1e"

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: root.caffeineEnabled ? "󰅶" : "󰒲"
                                            color: root.caffeineEnabled ? "#11111b" : "#ffffff"
                                            font.pixelSize: 14
                                            font.family: "JetBrainsMono Nerd Font"
                                        }

                                        Text {
                                            text: "Caffeine"
                                            color: root.caffeineEnabled ? "#11111b" : "#ffffff"
                                            font.weight: Font.ExtraBold
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
                                    color: "#1e1e1e"
                                    clip: true

                                    Rectangle {
                                        width: parent.width * (root.volumeLevel / 100.0)
                                        height: parent.height
                                        radius: parent.radius
                                        color: "#a6e3a1"

                                        Behavior on width { NumberAnimation { duration: 60 } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12

                                        Text {
                                            text: root.volumeLevel === 0 ? "󰝟" : (root.volumeLevel > 50 ? "󰕾" : "󰖀")
                                            color: root.volumeLevel > 15 ? "#11111b" : "#ffffff"
                                            font.pixelSize: 14
                                            font.family: "JetBrainsMono Nerd Font"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: root.volumeLevel + "%"
                                            color: root.volumeLevel > 85 ? "#11111b" : "#ffffff"
                                            font.weight: Font.ExtraBold
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
                                    color: "#1e1e1e"
                                    clip: true

                                    Rectangle {
                                        width: parent.width * (root.brightnessLevel / 100.0)
                                        height: parent.height
                                        radius: parent.radius
                                        color: "#f9e2af"

                                        Behavior on width { NumberAnimation { duration: 60 } }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12

                                        Text {
                                            text: "󰃠"
                                            color: root.brightnessLevel > 15 ? "#11111b" : "#ffffff"
                                            font.pixelSize: 14
                                            font.family: "JetBrainsMono Nerd Font"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: root.brightnessLevel + "%"
                                            color: root.brightnessLevel > 85 ? "#11111b" : "#ffffff"
                                            font.weight: Font.ExtraBold
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

                    Item {
                        id: page1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "MEDIA PLAYER"
                                    color: "#f38ba8"
                                    font.weight: Font.ExtraBold
                                    font.pixelSize: 11
                                    font.letterSpacing: 2
                                    font.family: "JetBrainsMono Nerd Font"
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
                                    color: "#1e1e1e"
                                    border.color: "#f38ba8"
                                    border.width: 1
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: root.activePlayer ? (root.activePlayer.trackArtUrl || "") : ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: root.activePlayer && root.activePlayer.trackArtUrl !== ""
                                        sourceSize.width: 108
                                        sourceSize.height: 108
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰎆"
                                        color: "#f38ba8"
                                        font.pixelSize: 22
                                        font.family: "JetBrainsMono Nerd Font"
                                        opacity: 0.8
                                        visible: !root.activePlayer || root.activePlayer.trackArtUrl === ""
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.activePlayer ? (root.activePlayer.trackTitle || "No Track Playing") : "No Media Playing"
                                        color: "#ffffff"
                                        font.weight: Font.ExtraBold
                                        font.pixelSize: 13
                                        font.family: "JetBrainsMono Nerd Font"
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.activePlayer ? (root.activePlayer.trackArtist || "Idle") : "Idle"
                                        color: "#a6adc8"
                                        font.pixelSize: 11
                                        font.family: "JetBrainsMono Nerd Font"
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Rectangle {
                                    id: progressTrack
                                    Layout.fillWidth: true
                                    height: 6
                                    radius: 3
                                    color: "#1e1e1e"
                                    clip: true

                                    Rectangle {
                                        property real progressRatio: root.effectiveLength > 0 ? Math.min(1.0, Math.max(0.0, root.mediaPosition / root.effectiveLength)) : 0
                                        width: parent.width * progressRatio
                                        height: parent.height
                                        radius: parent.radius
                                        color: "#f38ba8"

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
                                        color: "#f38ba8"
                                        font.pixelSize: 9
                                        font.family: "JetBrainsMono Nerd Font"
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: root.formatTime(root.effectiveLength)
                                        color: "#a6adc8"
                                        font.pixelSize: 9
                                        font.family: "JetBrainsMono Nerd Font"
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 36
                                    radius: 10
                                    color: prevArea.containsMouse ? "#2a2a2a" : "#1e1e1e"

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
                                    color: playArea.containsMouse ? "#f5c2e7" : "#f38ba8"

                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.activePlayer && root.activePlayer.isPlaying) ? "󰏤" : "󰐊"
                                        color: "#11111b"
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
                                    color: nextArea.containsMouse ? "#2a2a2a" : "#1e1e1e"

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

                    LauncherPage {
                        id: page2
                        parentSwipeView: swipeView
                        island: island
                    }
                }

                PageIndicator {
                    id: pageIndicator
                    count: swipeView.count
                    currentIndex: swipeView.currentIndex
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: island.isExpanded ? 1 : 0

                    delegate: Rectangle {
                        implicitWidth: index === pageIndicator.currentIndex ? 18 : 6
                        implicitHeight: 6
                        radius: 3
                        color: index === pageIndicator.currentIndex ? "#89b4fa" : "#ffffff"
                        opacity: index === pageIndicator.currentIndex ? 1.0 : 0.3

                        Behavior on implicitWidth { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }
        }
    }
}
