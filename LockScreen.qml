import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris

WlSessionLock {
    id: lockRoot
    locked: false

    function lock() {
        lockRoot.locked = true
    }

    function lockSession() {
        lock()
    }

    WlSessionLockSurface {
        id: lockScreenRoot

        property bool isAuthenticating: false

        // System Performance Metrics
        property real cpuValue: 0
        property real gpuValue: 0
        property real ramValue: 0
        property string ramText: "0 / 0 G"
        property real diskValue: 0
        property string diskText: "0 / 0 G"

        // Clock Widget Data
        property string timeString: "00:00"
        property string dateString: "Loading..."

        // Color Palette
        readonly property color color0: "#0a0a0d"
        readonly property color color8: "#1e1e24"

        // Geometric Shapes Pool for Password Prompt
        readonly property var geomShapes: ["●", "■", "▲", "◆", "★", "⬟", "✦", "⬢"]
        property var shapeList: []

        color: "transparent"

        // Function to dynamically randomize tile aspect ratios on each lock
        function randomizeTileSizes() {
            let r1H = 0.8 + Math.random() * 0.8
            let r2H = 0.8 + Math.random() * 0.8

            let cpuW = 0.7 + Math.random() * 0.8
            let gpuW = 0.7 + Math.random() * 0.8

            let ramW = 0.7 + Math.random() * 0.8
            let diskW = 0.7 + Math.random() * 0.8

            row1.Layout.preferredHeight = r1H * 100
            row2.Layout.preferredHeight = r2H * 100

            cpuTile.Layout.preferredWidth = cpuW * 100
            gpuTile.Layout.preferredWidth = gpuW * 100

            ramTile.Layout.preferredWidth = ramW * 100
            diskTile.Layout.preferredWidth = diskW * 100
        }

        Component.onCompleted: {
            passwordInput.forceActiveFocus()
            focusTimer.restart()
            updateClock()
            randomizeTileSizes()
            statsProc.running = true
        }

        Connections {
            target: lockRoot
            function onLockedChanged() {
                if (lockRoot.locked) {
                    lockScreenRoot.randomizeTileSizes()
                }
            }
        }

        Timer {
            id: focusTimer
            interval: 50
            repeat: false
            onTriggered: passwordInput.forceActiveFocus()
        }

        // Process to forcefully clear keybind traps on unlock
        Process {
            id: resetSubmapProc
            command: ["hyprctl", "dispatch", "submap", "reset"]
        }

        // Real-Time Clock Timer
        Timer {
            interval: 1000
            running: lockRoot.locked
            repeat: true
            triggeredOnStart: true
            onTriggered: lockScreenRoot.updateClock()
        }

        function updateClock() {
            let date = new Date()
            let h = String(date.getHours()).padStart(2, '0')
            let m = String(date.getMinutes()).padStart(2, '0')
            timeString = h + ":" + m

            let options = { weekday: 'long', month: 'short', day: 'numeric' }
            dateString = date.toLocaleDateString(undefined, options).toUpperCase()
        }

        // Periodic System Metrics Fetcher
        Timer {
            id: statsTimer
            interval: 2000
            running: lockRoot.locked
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                statsProc.running = false
                statsProc.running = true
            }
        }

        Process {
            id: statsProc
            command: [
                "sh", "-c",
                "cpu=$(LC_ALL=C top -bn1 | awk '/%?Cpu/ {print int($2+$4)}' | head -n1); [ -z \"$cpu\" ] && cpu=0; " +
                "ram_pct=$(free -m | awk '/Mem:/ {printf \"%.0f\", $3/$2*100}'); " +
                "ram_txt=$(free -m | awk '/Mem:/ {printf \"%.1f / %.0f G\", $3/1024, $2/1024}'); " +
                "disk_pct=$(df / | awk 'NR==2 {print $5}' | tr -d '%'); " +
                "disk_txt=$(df -m / | awk 'NR==2 {printf \"%.0f / %.0f G\", $3/1024, $2/1024}'); " +
                "gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo 0); " +
                "gpu=$(echo \"$gpu\" | tr -d ' '); [ -z \"$gpu\" ] && gpu=0; " +
                "echo \"$cpu|$ram_pct|$ram_txt|$disk_pct|$disk_txt|$gpu\""
            ]
            stdout: StdioCollector {
                onStreamFinished: {
                    let lines = this.text.trim().split("\n")
                    let last = lines.length > 0 ? lines[lines.length - 1].trim() : ""
                    if (last !== "") {
                        let parts = last.split("|")
                        if (parts.length >= 6) {
                            lockScreenRoot.cpuValue = Math.min(100, Math.max(0, parseFloat(parts[0]) || 0))
                            lockScreenRoot.ramValue = parseFloat(parts[1]) || 0
                            lockScreenRoot.ramText = parts[2] || ""
                            lockScreenRoot.diskValue = parseFloat(parts[3]) || 0
                            lockScreenRoot.diskText = parts[4] || ""
                            lockScreenRoot.gpuValue = parseFloat(parts[5]) || 0
                        }
                    }
                }
            }
            onExited: statsProc.running = false
        }

        function unlock() {
            lockRoot.locked = false
            resetSubmapProc.running = true
        }

        function attemptUnlock() {
            if (passwordInput.text.length > 0 && !isAuthenticating) {
                isAuthenticating = true
                authProc.pendingPassword = passwordInput.text
                authProc.running = true
            }
        }

        // MPRIS Media Player Integration
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

        onActivePlayerChanged: {
            if (activePlayer) {
                cachedTrackLength = activePlayer.length || 0
                mediaPosition = activePlayer.position || 0
            } else {
                cachedTrackLength = 0
                mediaPosition = 0
            }
        }

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

        Connections {
            target: lockScreenRoot.activePlayer

            function onTrackTitleChanged() {
                if (lockScreenRoot.activePlayer) {
                    lockScreenRoot.cachedTrackLength = lockScreenRoot.activePlayer.length || 0
                    lockScreenRoot.mediaPosition = lockScreenRoot.activePlayer.position || 0
                }
            }

            function onLengthChanged() {
                if (lockScreenRoot.activePlayer && (lockScreenRoot.activePlayer.length || 0) > lockScreenRoot.cachedTrackLength) {
                    lockScreenRoot.cachedTrackLength = lockScreenRoot.activePlayer.length
                }
            }

            function onPositionChanged() {
                if (!lockScreenRoot.isSeeking && lockScreenRoot.activePlayer) {
                    lockScreenRoot.mediaPosition = lockScreenRoot.activePlayer.position || 0
                }
            }
        }

        Timer {
            interval: 200
            running: lockScreenRoot.activePlayer && lockScreenRoot.activePlayer.isPlaying
            repeat: true
            onTriggered: {
                if (!lockScreenRoot.activePlayer || lockScreenRoot.isSeeking) return

                let playerLen = lockScreenRoot.activePlayer.length || 0
                if (playerLen > lockScreenRoot.cachedTrackLength) {
                    lockScreenRoot.cachedTrackLength = playerLen
                }

                let dbusPos = lockScreenRoot.activePlayer.position || 0

                if (Math.abs(lockScreenRoot.mediaPosition - dbusPos) > 0.8) {
                    lockScreenRoot.mediaPosition = dbusPos
                } else if (lockScreenRoot.effectiveLength > 0 && lockScreenRoot.mediaPosition < lockScreenRoot.effectiveLength) {
                    lockScreenRoot.mediaPosition = Math.min(lockScreenRoot.effectiveLength, lockScreenRoot.mediaPosition + 0.2)
                }
            }
        }

        Timer {
            id: seekDebounceTimer
            interval: 400
            repeat: false
            onTriggered: {
                lockScreenRoot.isSeeking = false
                if (lockScreenRoot.activePlayer) {
                    lockScreenRoot.mediaPosition = lockScreenRoot.activePlayer.position || 0
                }
            }
        }

        // PAM Password Validation
        Process {
            id: authProc
            property string pendingPassword: ""
            command: ["sh", "-c", "printf '%s\\n' \"$PASS\" | sudo -S -k true 2>/dev/null"]
            environment: { "PASS": pendingPassword }

            onExited: (code) => {
                if (!lockScreenRoot.isAuthenticating) return
                lockScreenRoot.isAuthenticating = false
                pendingPassword = ""

                if (code === 0) {
                    passwordInput.text = ""
                    lockScreenRoot.unlock()
                } else {
                    passwordInput.text = ""
                    shakeAnimation.start()
                    errorMessage.opacity = 1.0
                    hideErrorTimer.restart()
                }
            }
        }

        // Reduced Opacity Backdrop Overlay
        Rectangle {
            anchors.fill: parent
            color: "#40000000"

            MouseArea {
                anchors.fill: parent
                onClicked: passwordInput.forceActiveFocus()
            }
        }

        // Main Container Card
        Rectangle {
            id: lockCard
            anchors.centerIn: parent
            width: 730
            height: 400
            radius: 24
            color: Qt.rgba(0.08, 0.08, 0.1, 0.85)
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            clip: true

            SequentialAnimation {
                id: shakeAnimation
                NumberAnimation { target: lockCard; property: "anchors.horizontalCenterOffset"; to: -12; duration: 40 }
                NumberAnimation { target: lockCard; property: "anchors.horizontalCenterOffset"; to: 12; duration: 40 }
                NumberAnimation { target: lockCard; property: "anchors.horizontalCenterOffset"; to: -6; duration: 40 }
                NumberAnimation { target: lockCard; property: "anchors.horizontalCenterOffset"; to: 6; duration: 40 }
                NumberAnimation { target: lockCard; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 22

                // LEFT SIDE: System Monitors (Asymmetric Dynamic Bento Layout)
                ColumnLayout {
                    Layout.preferredWidth: 230
                    Layout.fillHeight: true
                    spacing: 10

                    ColumnLayout {
                        id: bentoGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        // Row 1 (CPU + GPU)
                        RowLayout {
                            id: row1
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10

                            LiquidStatTile {
                                id: cpuTile
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                icon: "󰍛"
                                title: "CPU"
                                value: lockScreenRoot.cpuValue
                                liquidColor: "#f38ba8"
                            }

                            LiquidStatTile {
                                id: gpuTile
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                icon: "󰢮"
                                title: "GPU"
                                value: lockScreenRoot.gpuValue
                                liquidColor: "#cba6f7"
                            }
                        }

                        // Row 2 (RAM + DISK)
                        RowLayout {
                            id: row2
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10

                            LiquidStatTile {
                                id: ramTile
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                icon: "󰘚"
                                title: "RAM"
                                value: lockScreenRoot.ramValue
                                badgeText: lockScreenRoot.ramText
                                liquidColor: "#89b4fa"
                            }

                            LiquidStatTile {
                                id: diskTile
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                icon: "󰋊"
                                title: "DISK"
                                value: lockScreenRoot.diskValue
                                badgeText: lockScreenRoot.diskText
                                liquidColor: "#89dceb"
                            }
                        }
                    }
                }

                // Vertical Separator
                Rectangle {
                    Layout.fillHeight: true
                    width: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // RIGHT SIDE: Unixporn Clock + Auth + MPRIS Controls
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14

                    // HEADER: Unixporn Minimal Clock Widget
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            spacing: 0

                            Text {
                                text: lockScreenRoot.timeString
                                color: "#ffffff"
                                font.pixelSize: 36
                                font.bold: true
                                font.family: "JetBrainsMono Nerd Font"
                            }

                            Text {
                                text: lockScreenRoot.dateString
                                color: "#89b4fa"
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 1
                                font.family: "JetBrainsMono Nerd Font"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 42
                            height: 42
                            radius: 21
                            color: lockScreenRoot.color0

                            Text {
                                anchors.centerIn: parent
                                text: lockScreenRoot.isAuthenticating ? "󰔟" : "󰌾"
                                color: "#ffffff"
                                font.pixelSize: 18
                                font.family: "JetBrainsMono Nerd Font"
                            }
                        }
                    }

                    // AUTHENTICATION SECTION (LARGER CLOSE-TOGETHER SHAPES & CLEAN CURSOR)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: 12
                            color: lockScreenRoot.color0

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    // Placeholder text when password is empty
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Enter password..."
                                        color: "#7c7c7c"
                                        font.pixelSize: 14
                                        font.family: "JetBrainsMono Nerd Font"
                                        visible: passwordInput.text.length === 0
                                    }

                                    // Container for geometric shapes & custom blinking cursor
                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2 // Reduced spacing to bring shapes closer together

                                        Repeater {
                                            model: passwordInput.text.length

                                            delegate: Item {
                                                width: 20
                                                height: 30

                                                Text {
                                                    id: shapeText
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: (index < lockScreenRoot.shapeList.length) ? lockScreenRoot.shapeList[index] : "●"
                                                    color: "#ffffff"
                                                    font.pixelSize: 22 // Larger geometric symbols
                                                    font.bold: true
                                                    font.family: "JetBrainsMono Nerd Font"

                                                    Component.onCompleted: dropAnim.start()

                                                    ParallelAnimation {
                                                        id: dropAnim
                                                        NumberAnimation {
                                                            target: shapeText
                                                            property: "y"
                                                            from: -35
                                                            to: Math.round((30 - shapeText.implicitHeight) / 2)
                                                            duration: 180
                                                            easing.type: Easing.OutCubic
                                                        }
                                                        NumberAnimation {
                                                            target: shapeText
                                                            property: "opacity"
                                                            from: 0.0
                                                            to: 1.0
                                                            duration: 80
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Sole Custom Blinking White Cursor
                                        Rectangle {
                                            width: 2
                                            height: 22
                                            color: "#ffffff"
                                            anchors.verticalCenter: parent.verticalCenter

                                            SequentialAnimation on opacity {
                                                loops: Animation.Infinite
                                                running: true
                                                NumberAnimation { to: 0.0; duration: 500 }
                                                NumberAnimation { to: 1.0; duration: 500 }
                                            }
                                        }
                                    }

                                    // Invisible Input Field with Native Cursor Suppressed
                                    TextField {
                                        id: passwordInput
                                        anchors.fill: parent
                                        color: "transparent"
                                        selectionColor: "transparent"
                                        selectedTextColor: "transparent"
                                        font.pixelSize: 14
                                        font.family: "JetBrainsMono Nerd Font"
                                        background: null
                                        cursorVisible: false
                                        cursorDelegate: Item {} // Completely removes Qt native cursor render

                                        onTextChanged: {
                                            let currentShapes = lockScreenRoot.shapeList.slice()
                                            while (currentShapes.length < passwordInput.text.length) {
                                                let randShape = lockScreenRoot.geomShapes[Math.floor(Math.random() * lockScreenRoot.geomShapes.length)]
                                                currentShapes.push(randShape)
                                            }
                                            while (currentShapes.length > passwordInput.text.length) {
                                                currentShapes.pop()
                                            }
                                            lockScreenRoot.shapeList = currentShapes
                                        }

                                        onAccepted: lockScreenRoot.attemptUnlock()
                                    }
                                }

                                Text {
                                    text: "󰌑"
                                    color: passwordInput.text.length > 0 ? "#ffffff" : "#7c7c7c"
                                    font.pixelSize: 15
                                    font.family: "JetBrainsMono Nerd Font"

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: lockScreenRoot.attemptUnlock()
                                    }
                                }
                            }
                        }

                        Text {
                            id: errorMessage
                            Layout.alignment: Qt.AlignHCenter
                            text: "Authentication Failed"
                            color: "#ff6b6b"
                            font.pixelSize: 11
                            font.family: "JetBrainsMono Nerd Font"
                            opacity: 0.0

                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // MEDIA PLAYER SECTION
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                width: 44
                                height: 44
                                radius: 10
                                color: lockScreenRoot.color0
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: lockScreenRoot.activePlayer ? (lockScreenRoot.activePlayer.trackArtUrl || "") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: lockScreenRoot.activePlayer && lockScreenRoot.activePlayer.trackArtUrl !== ""
                                    sourceSize.width: 100
                                    sourceSize.height: 100
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰎆"
                                    color: "#ffffff"
                                    font.pixelSize: 20
                                    font.family: "JetBrainsMono Nerd Font"
                                    opacity: 0.8
                                    visible: !lockScreenRoot.activePlayer || lockScreenRoot.activePlayer.trackArtUrl === ""
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: lockScreenRoot.activePlayer ? (lockScreenRoot.activePlayer.trackTitle || "No Track Playing") : "No Media Playing"
                                    color: "#ffffff"
                                    font.weight: Font.Bold
                                    font.pixelSize: 12
                                    font.family: "JetBrainsMono Nerd Font"
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: lockScreenRoot.activePlayer ? (lockScreenRoot.activePlayer.trackArtist || "Idle") : "Media Player"
                                    color: "#a0a0a0"
                                    font.pixelSize: 11
                                    font.family: "JetBrainsMono Nerd Font"
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                        }

                        // Progress Bar
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Rectangle {
                                Layout.fillWidth: true
                                height: 5
                                radius: 3
                                color: lockScreenRoot.color0
                                clip: true

                                Rectangle {
                                    property real progressRatio: lockScreenRoot.effectiveLength > 0 ? Math.min(1.0, Math.max(0.0, lockScreenRoot.mediaPosition / lockScreenRoot.effectiveLength)) : 0
                                    width: parent.width * progressRatio
                                    height: parent.height
                                    radius: parent.radius
                                    color: "#ffffff"

                                    Behavior on width { NumberAnimation { duration: 100 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    function seekTo(mouse) {
                                        if (!lockScreenRoot.activePlayer || lockScreenRoot.effectiveLength <= 0) return
                                        let pct = Math.max(0, Math.min(1, mouse.x / width))
                                        let sec = pct * lockScreenRoot.effectiveLength

                                        lockScreenRoot.isSeeking = true
                                        lockScreenRoot.mediaPosition = sec

                                        if (lockScreenRoot.activePlayer.canSeek) {
                                            lockScreenRoot.activePlayer.position = sec
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
                                    text: lockScreenRoot.formatTime(lockScreenRoot.mediaPosition)
                                    color: "#ffffff"
                                    font.pixelSize: 9
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: lockScreenRoot.formatTime(lockScreenRoot.effectiveLength)
                                    color: "#a0a0a0"
                                    font.pixelSize: 9
                                    font.family: "JetBrainsMono Nerd Font"
                                }
                            }
                        }

                        // Playback Controls
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                height: 32
                                radius: 8
                                color: prevArea.containsMouse ? "#3a3a3a" : lockScreenRoot.color0

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒮"
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                MouseArea {
                                    id: prevArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (lockScreenRoot.activePlayer && lockScreenRoot.activePlayer.canGoPrevious) {
                                            lockScreenRoot.activePlayer.previous()
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 32
                                radius: 8
                                color: playArea.containsMouse ? "#e0e0e0" : "#ffffff"

                                Text {
                                    anchors.centerIn: parent
                                    text: (lockScreenRoot.activePlayer && lockScreenRoot.activePlayer.isPlaying) ? "󰏤" : "󰐊"
                                    color: lockScreenRoot.color0
                                    font.pixelSize: 14
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                MouseArea {
                                    id: playArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (lockScreenRoot.activePlayer && lockScreenRoot.activePlayer.canTogglePlaying) {
                                            lockScreenRoot.activePlayer.togglePlaying()
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 32
                                radius: 8
                                color: nextArea.containsMouse ? "#3a3a3a" : lockScreenRoot.color0

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒭"
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                    font.family: "JetBrainsMono Nerd Font"
                                }

                                MouseArea {
                                    id: nextArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (lockScreenRoot.activePlayer && lockScreenRoot.activePlayer.canGoNext) {
                                            lockScreenRoot.activePlayer.next()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Timer {
            id: hideErrorTimer
            interval: 1800
            repeat: false
            onTriggered: errorMessage.opacity = 0.0
        }
    }
}
