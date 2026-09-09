import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets

PanelWindow {
    id: sidebarRoot

    property bool isOpen: false

    // Navigation: 0 = Main Deck View, 1 = Wi-Fi Subpage, 2 = Bluetooth Subpage
    property int currentViewIndex: 0

    // Control Center Main States
    property bool wifiEnabled: true
    property bool btEnabled: false
    property bool caffeineEnabled: false
    property bool dndEnabled: false

    // Recording States
    property bool isRecording: false
    property bool isPaused: false
    property bool recModeRegion: false    // false = Fullscreen (default), true = Region
    property bool recAudioEnabled: false  // false = Muted, true = Sound On
    property int recDurationSec: 0
    property var recentRecordings: []

    // Fullscreen Detector State
    property bool isFullscreenActive: false

    // Sliders
    property int volumeLevel: 50
    property int brightnessLevel: 70

    // Wi-Fi Interactive States
    property var wifiList: []
    property string selectedWifiSsid: ""
    property string wifiPasswordText: ""
    property string wifiStatusMsg: ""
    property bool isWifiConnecting: false

    // Bluetooth Interactive States
    property var btList: []

    // Signal to open existing Power Menu
    signal openPowerMenu()

    WlrLayershell.namespace: "quickshell-drawer"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    // --- Helper Functions ---
    function formatTime(sec) {
        let m = Math.floor(sec / 60)
        let s = sec % 60
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
    }

    function startRecording() {
        sidebarRoot.close()
        let audioFlag = sidebarRoot.recAudioEnabled ? "-a" : ""
        let geomFlag = sidebarRoot.recModeRegion ? "-g \"$(slurp)\"" : ""

        let cmd = "sleep 0.4 && DIR=\"$HOME/Videos/Recordings\" && mkdir -p \"$DIR\" && FILE=\"$DIR/Recording_$(date +%Y%m%d_%H%M%S).mp4\" && wf-recorder " + audioFlag + " " + geomFlag + " -f \"$FILE\" && notify-send -a \"QuickShell\" \"Recording Saved\" \"Saved to ~/Videos/Recordings\""

        sidebarRoot.runCmd(["sh", "-c", cmd])
        sidebarRoot.isRecording = true
        sidebarRoot.isPaused = false
        sidebarRoot.recDurationSec = 0
    }

    function pauseResumeRecording() {
        sidebarRoot.runCmd(["pkill", "-USR1", "wf-recorder"])
        sidebarRoot.isPaused = !sidebarRoot.isPaused
    }

    function stopRecording() {
        sidebarRoot.runCmd(["pkill", "-INT", "wf-recorder"])
        sidebarRoot.isRecording = false
        sidebarRoot.isPaused = false
        scanRecordings()
    }

    function scanRecordings() {
        sidebarRoot.exec(["sh", "-c", "mkdir -p $HOME/Videos/Recordings && ls -1t $HOME/Videos/Recordings | head -n 4"], (raw) => {
            let files = raw.split("\n").map(f => f.trim()).filter(f => f.length > 0)
            sidebarRoot.recentRecordings = files
        })
    }

    Timer {
        id: clearRecordingsTimer
        interval: 300
        repeat: false
        onTriggered: sidebarRoot.scanRecordings()
    }

    function clearRecordingsHistory() {
        sidebarRoot.runCmd(["sh", "-c", "rm -rf $HOME/Videos/Recordings/*"])
        clearRecordingsTimer.restart()
    }

    // --- Process Execution Helpers ---
    Component {
        id: cmdRunner
        Process { onExited: destroy() }
    }

    function runCmd(args) {
        var p = cmdRunner.createObject(sidebarRoot, { command: args })
        if (p) p.running = true
    }

    Component {
        id: cmdExec
        Process {
            id: proc
            property var callback
            stdout: StdioCollector {
                onStreamFinished: {
                    let last = this.text.trim() || ""
                    if (proc.callback) proc.callback(last)
                }
            }
            onExited: destroy()
        }
    }

    function exec(args, callback) {
        var p = cmdExec.createObject(sidebarRoot, { command: args, callback: callback })
        if (p) p.running = true
    }

    // --- System Control Functions ---
    function scanWifi() {
        sidebarRoot.exec(["nmcli", "-t", "-f", "SSID,SECURITY,SIGNAL,ACTIVE", "dev", "wifi", "list"], (raw) => {
            let lines = raw.split("\n")
            let list = []
            let seen = {}
            for (let i = 0; i < lines.length; i++) {
                let parts = lines[i].split(":")
                if (parts.length >= 4) {
                    let ssid = parts[0].replace(/\\:/g, ":").trim()
                    let sec = parts[1].trim()
                    let sig = parseInt(parts[2]) || 0
                    let active = parts[3].trim() === "yes"
                    if (ssid !== "" && !seen[ssid]) {
                        seen[ssid] = true
                        list.push({ ssid: ssid, security: sec, signal: sig, active: active })
                    }
                }
            }
            sidebarRoot.wifiList = list
        })
    }

    function scanBluetooth() {
        sidebarRoot.exec(["bluetoothctl", "devices"], (raw) => {
            let lines = raw.split("\n")
            let list = []
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim()
                let parts = line.split(" ")
                if (parts.length >= 3 && parts[0] === "Device") {
                    list.push({ mac: parts[1], name: parts.slice(2).join(" ") })
                }
            }
            sidebarRoot.btList = list
        })
    }

    function connectWifi(ssid, password) {
        sidebarRoot.isWifiConnecting = true
        sidebarRoot.wifiStatusMsg = "Connecting..."
        let args = password !== ""
            ? ["nmcli", "dev", "wifi", "connect", ssid, "password", password]
            : ["nmcli", "dev", "wifi", "connect", ssid]

        sidebarRoot.exec(args, (res) => {
            sidebarRoot.isWifiConnecting = false
            if (res.includes("successfully activated")) {
                sidebarRoot.wifiStatusMsg = "Connected!"
                sidebarRoot.selectedWifiSsid = ""
                sidebarRoot.wifiPasswordText = ""
                scanWifi()
            } else {
                sidebarRoot.wifiStatusMsg = "Connection failed."
            }
        })
    }

    Timer {
        id: wifiDisconnectTimer
        interval: 600
        repeat: false
        onTriggered: sidebarRoot.scanWifi()
    }

    function disconnectWifi(ssid) {
        sidebarRoot.runCmd(["nmcli", "connection", "down", "id", ssid])
        wifiDisconnectTimer.restart()
    }

    // Recording Duration Timer
    Timer {
        interval: 1000
        running: sidebarRoot.isRecording && !sidebarRoot.isPaused
        repeat: true
        onTriggered: sidebarRoot.recDurationSec++
    }

    // Dynamic Timer Sync
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            sidebarRoot.exec(["hyprctl", "activewindow", "-j"], (raw) => {
                try {
                    let win = JSON.parse(raw)
                    sidebarRoot.isFullscreenActive = Boolean(win && (win.fullscreen === true || win.fullscreen === 1 || win.fullscreen === 2 || win.fullscreenMode > 0))
                } catch(e) {
                    sidebarRoot.isFullscreenActive = false
                }
            })

            sidebarRoot.exec(["nmcli", "radio", "wifi"], (last) => { sidebarRoot.wifiEnabled = last.includes("enabled") })
            sidebarRoot.exec(["bluetoothctl", "show"], (last) => { sidebarRoot.btEnabled = last.includes("Powered: yes") })

            sidebarRoot.exec(["pgrep", "-x", "wf-recorder"], (last) => {
                let running = (last.trim().length > 0)
                sidebarRoot.isRecording = running
                if (!running) {
                    sidebarRoot.isPaused = false
                    sidebarRoot.recDurationSec = 0
                }
            })

            sidebarRoot.exec(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], (raw) => {
                let match = raw.match(/Volume:\s+([0-9.]+)/)
                if (match && match[1] && !volDrag.pressed) {
                    sidebarRoot.volumeLevel = Math.round(parseFloat(match[1]) * 100)
                }
            })

            sidebarRoot.exec(["brightnessctl", "i", "-m"], (raw) => {
                let parts = raw.split(",")
                if (parts.length >= 4 && !brightDrag.pressed) {
                    sidebarRoot.brightnessLevel = parseInt(parts[3].replace("%", "")) || 50
                }
            })

            if (sidebarRoot.isOpen) scanRecordings()
            if (sidebarRoot.currentViewIndex === 1 && !sidebarRoot.isWifiConnecting) scanWifi()
            else if (sidebarRoot.currentViewIndex === 2) scanBluetooth()
        }
    }

    // Masking Target Items
    Item { id: fullScreenSurface; anchors.fill: parent }
    Item { id: triggerEdge; width: 8; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right }

    Region { id: fullRegion; item: fullScreenSurface }
    Region { id: triggerRegion; item: triggerEdge }

    mask: isOpen ? fullRegion : triggerRegion

    function open() {
        sidebarRoot.currentViewIndex = 0
        sidebarRoot.scanRecordings()
        isOpen = true
    }

    function close() {
        trayContextMenu.closeMenu()
        isOpen = false
    }

    Shortcut {
        sequence: "Escape"
        enabled: sidebarRoot.isOpen
        onActivated: {
            if (trayContextMenu.activeHandle !== null) {
                trayContextMenu.closeMenu()
            } else if (sidebarRoot.currentViewIndex !== 0) {
                sidebarRoot.currentViewIndex = 0
            } else {
                sidebarRoot.close()
            }
        }
    }

    MouseArea {
        id: hoverTriggerArea
        anchors.fill: triggerEdge
        enabled: !sidebarRoot.isOpen && !sidebarRoot.isFullscreenActive
        hoverEnabled: true
        onEntered: sidebarRoot.open()
    }

    // Solid Dimmer
    Rectangle {
        anchors.fill: parent
        color: "#80000000"
        opacity: sidebarRoot.isOpen ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                trayContextMenu.closeMenu()
                sidebarRoot.close()
            }
        }
    }

    // Dismiss context menu when clicking outside
    MouseArea {
        anchors.fill: parent
        enabled: trayContextMenu.activeHandle !== null
        z: 998
        onClicked: trayContextMenu.closeMenu()
    }

    // Dynamic System Tray Context Menu Overlay
    Rectangle {
        id: trayContextMenu
        z: 999
        visible: activeHandle !== null
        width: 210
        height: menuLayout.implicitHeight + 16
        color: "#181825"
        border.color: "#313244"
        border.width: 1
        radius: 12

        property var activeHandle: null
        property var menuStack: []

        function openMenu(handle, posX, posY) {
            menuStack = []
            activeHandle = handle
            x = Math.max(10, Math.min(sidebarRoot.width - width - 10, posX - width))
            y = Math.min(sidebarRoot.height - height - 10, posY)
        }

        function closeMenu() {
            activeHandle = null
            menuStack = []
        }

        QsMenuOpener {
            id: trayMenuOpener
            menu: trayContextMenu.activeHandle
        }

        ColumnLayout {
            id: menuLayout
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            // Back button for submenus
            Rectangle {
                Layout.fillWidth: true
                height: 26
                radius: 6
                color: backArea.containsMouse ? "#313244" : "transparent"
                visible: trayContextMenu.menuStack.length > 0

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    spacing: 6
                    Text { text: "‹"; color: "#89b4fa"; font.pixelSize: 14; font.weight: Font.Bold }
                    Text { text: "Back"; color: "#cdd6f4"; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font" }
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        var prevHandle = trayContextMenu.menuStack.pop()
                        trayContextMenu.activeHandle = prevHandle
                    }
                }
            }

            Repeater {
                model: trayMenuOpener ? trayMenuOpener.children : []

                delegate: Rectangle {
                    required property var modelData // QsMenuEntry
                    Layout.fillWidth: true
                    height: Boolean(modelData && modelData.isSeparator) ? 1 : 28
                    radius: 6
                    color: Boolean(modelData && modelData.isSeparator) ? "#313244" : (entryArea.containsMouse ? "#313244" : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        visible: Boolean(modelData && !modelData.isSeparator)
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: modelData ? (modelData.text || "") : ""
                            color: Boolean(modelData && modelData.enabled) ? "#cdd6f4" : "#6c7086"
                            font.pixelSize: 11
                            font.family: "JetBrainsMono Nerd Font"
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "›"
                            color: "#89b4fa"
                            font.pixelSize: 12
                            visible: Boolean(modelData && modelData.hasChildren)
                        }
                    }

                    MouseArea {
                        id: entryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: Boolean(modelData && !modelData.isSeparator && modelData.enabled)

                        onClicked: {
                            if (modelData.hasChildren) {
                                trayContextMenu.menuStack.push(trayContextMenu.activeHandle)
                                trayContextMenu.activeHandle = modelData
                            } else {
                                modelData.triggered()
                                trayContextMenu.closeMenu()
                            }
                        }
                    }
                }
            }
        }
    }

    // Outer Drawer Surface
    Rectangle {
        id: drawer
        property real visibleWidth: 440
        property real cornerRadius: 28

        width: visibleWidth + cornerRadius
        anchors.top: parent.top
        anchors.topMargin: -cornerRadius
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -cornerRadius

        x: sidebarRoot.isOpen ? (parent.width - visibleWidth - 16) : parent.width

        radius: cornerRadius
        color: "#000000"

        layer.enabled: drawerAnim.running
        layer.smooth: true

        Behavior on x {
            id: drawerAnim
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: drawer.cornerRadius + 20
            anchors.bottomMargin: drawer.cornerRadius + 20
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 16

            // =================================================
            // TOP HEADER: TITLE + SYSTEM TRAY CONTAINER
            // =================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "CONTROL CENTER"
                    color: "#ffffff"
                    font.weight: Font.ExtraBold
                    font.pixelSize: 12
                    font.letterSpacing: 3
                    font.family: "JetBrainsMono Nerd Font"
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: systemTrayCard
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredWidth: Boolean(systemTrayCard && systemTrayCard.expanded) ? Math.max(34, trayList.implicitWidth + 34) : 34
                    height: 32
                    radius: 12
                    color: "#0f0f0f"
                    border.color: "#1e1e1e"
                    border.width: 1

                    property bool expanded: false

                    Behavior on Layout.preferredWidth {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        RowLayout {
                            id: trayList
                            visible: Boolean(systemTrayCard && systemTrayCard.expanded)
                            spacing: 8

                            Repeater {
                                model: SystemTray.items

                                delegate: Item {
                                    id: trayItemDelegate
                                    required property var modelData
                                    width: 18
                                    height: 18

                                    IconImage {
                                        anchors.fill: parent
                                        source: modelData ? modelData.icon : ""
                                        asynchronous: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                                        onClicked: (mouse) => {
                                            if (mouse.button === Qt.LeftButton) {
                                                modelData.activate()
                                            } else if (mouse.button === Qt.RightButton) {
                                                if (modelData && modelData.menu) {
                                                    var pos = mapToItem(fullScreenSurface, mouse.x, mouse.y)
                                                    trayContextMenu.openMenu(modelData.menu, pos.x, pos.y)
                                                } else if (modelData) {
                                                    modelData.secondaryActivate()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 6
                            color: arrowArea.pressed ? "#33ffffff" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Boolean(systemTrayCard && systemTrayCard.expanded) ? "󰅂" : "󰅁"
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.family: "JetBrainsMono Nerd Font"
                            }

                            MouseArea {
                                id: arrowArea
                                anchors.fill: parent
                                onClicked: systemTrayCard.expanded = !systemTrayCard.expanded
                            }
                        }
                    }
                }
            }

            // =================================================
            // CONTROLS & RECORDER CONTAINER
            // =================================================
            Rectangle {
                id: boundedWidgetCard
                Layout.fillWidth: true
                height: 380
                radius: 24
                color: "#0f0f0f"
                clip: true

                StackLayout {
                    id: viewStack
                    anchors.fill: parent
                    anchors.margins: 14
                    currentIndex: sidebarRoot.currentViewIndex

                    // VIEW 0: MAIN DECK VIEW
                    Item {
                        opacity: StackLayout.isCurrentItem ? 1.0 : 0.0
                        scale: StackLayout.isCurrentItem ? 1.0 : 0.98
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 14

                            SwipeView {
                                id: mainSwipeView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                // SLIDE 1: MAIN CONTROLS
                                Item {
                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: 14

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 2
                                            rowSpacing: 10
                                            columnSpacing: 10

                                            // Wi-Fi Card
                                            Rectangle {
                                                id: wifiCard
                                                Layout.fillWidth: true; height: 56; radius: 16
                                                color: sidebarRoot.wifiEnabled ? "#89b4fa" : "#1e1e1e"
                                                scale: wifiMainArea.pressed ? 0.96 : 1.0

                                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8
                                                    MouseArea {
                                                        id: wifiMainArea
                                                        Layout.fillWidth: true; Layout.fillHeight: true
                                                        onClicked: {
                                                            let target = sidebarRoot.wifiEnabled ? "off" : "on"
                                                            sidebarRoot.wifiEnabled = !sidebarRoot.wifiEnabled
                                                            sidebarRoot.runCmd(["nmcli", "radio", "wifi", target])
                                                        }
                                                        RowLayout {
                                                            anchors.centerIn: parent; spacing: 8
                                                            Text { text: sidebarRoot.wifiEnabled ? "󰤨" : "󰤭"; color: sidebarRoot.wifiEnabled ? "#11111b" : "#ffffff"; font.pixelSize: 16; font.family: "JetBrainsMono Nerd Font" }
                                                            Text { text: "Wi-Fi"; color: sidebarRoot.wifiEnabled ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                                        }
                                                    }
                                                    Rectangle {
                                                        id: wifiSubBtn
                                                        width: 30; height: 30; radius: 10
                                                        color: sidebarRoot.wifiEnabled ? "#1a000000" : "#33ffffff"
                                                        scale: wifiSubArea.pressed ? 0.88 : 1.0

                                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                        Text { anchors.centerIn: parent; text: "󰅂"; color: sidebarRoot.wifiEnabled ? "#11111b" : "#ffffff"; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                                        MouseArea { id: wifiSubArea; anchors.fill: parent; onClicked: { sidebarRoot.currentViewIndex = 1; sidebarRoot.scanWifi() } }
                                                    }
                                                }
                                            }

                                            // Bluetooth Card
                                            Rectangle {
                                                id: btCard
                                                Layout.fillWidth: true; height: 56; radius: 16
                                                color: sidebarRoot.btEnabled ? "#b4befe" : "#1e1e1e"
                                                scale: btMainArea.pressed ? 0.96 : 1.0

                                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 8
                                                    MouseArea {
                                                        id: btMainArea
                                                        Layout.fillWidth: true; Layout.fillHeight: true
                                                        onClicked: {
                                                            let target = sidebarRoot.btEnabled ? "off" : "on"
                                                            sidebarRoot.btEnabled = !sidebarRoot.btEnabled
                                                            sidebarRoot.runCmd(["bluetoothctl", "power", target])
                                                        }
                                                        RowLayout {
                                                            anchors.centerIn: parent; spacing: 8
                                                            Text { text: sidebarRoot.btEnabled ? "󰂯" : "󰂲"; color: sidebarRoot.btEnabled ? "#11111b" : "#ffffff"; font.pixelSize: 16; font.family: "JetBrainsMono Nerd Font" }
                                                            Text { text: "Bluetooth"; color: sidebarRoot.btEnabled ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                                        }
                                                    }
                                                    Rectangle {
                                                        id: btSubBtn
                                                        width: 30; height: 30; radius: 10
                                                        color: sidebarRoot.btEnabled ? "#1a000000" : "#33ffffff"
                                                        scale: btSubArea.pressed ? 0.88 : 1.0

                                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                        Text { anchors.centerIn: parent; text: "󰅂"; color: sidebarRoot.btEnabled ? "#11111b" : "#ffffff"; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                                        MouseArea { id: btSubArea; anchors.fill: parent; onClicked: { sidebarRoot.currentViewIndex = 2; sidebarRoot.scanBluetooth() } }
                                                    }
                                                }
                                            }

                                            // Caffeine Card
                                            Rectangle {
                                                id: caffCard
                                                Layout.fillWidth: true; height: 56; radius: 16
                                                color: sidebarRoot.caffeineEnabled ? "#fab387" : "#1e1e1e"
                                                scale: caffArea.pressed ? 0.96 : 1.0

                                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 8
                                                    Text { text: sidebarRoot.caffeineEnabled ? "󰅶" : "󰒲"; color: sidebarRoot.caffeineEnabled ? "#11111b" : "#ffffff"; font.pixelSize: 16; font.family: "JetBrainsMono Nerd Font" }
                                                    Text { text: "Caffeine"; color: sidebarRoot.caffeineEnabled ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                                }
                                                MouseArea {
                                                    id: caffArea
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        sidebarRoot.caffeineEnabled = !sidebarRoot.caffeineEnabled
                                                        if (sidebarRoot.caffeineEnabled) sidebarRoot.runCmd(["systemd-inhibit", "--what=idle", "--who=QuickShell", "--why=Caffeine", "sleep", "infinity"])
                                                        else sidebarRoot.runCmd(["pkill", "-f", "systemd-inhibit --what=idle --who=QuickShell"])
                                                    }
                                                }
                                            }

                                            // DND Card
                                            Rectangle {
                                                id: dndCard
                                                Layout.fillWidth: true; height: 56; radius: 16
                                                color: sidebarRoot.dndEnabled ? "#f38ba8" : "#1e1e1e"
                                                scale: dndArea.pressed ? 0.96 : 1.0

                                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 8
                                                    Text { text: sidebarRoot.dndEnabled ? "󰂛" : "󰂚"; color: sidebarRoot.dndEnabled ? "#11111b" : "#ffffff"; font.pixelSize: 16; font.family: "JetBrainsMono Nerd Font" }
                                                    Text { text: "DND"; color: sidebarRoot.dndEnabled ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                                }
                                                MouseArea {
                                                    id: dndArea
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        sidebarRoot.dndEnabled = !sidebarRoot.dndEnabled
                                                        sidebarRoot.runCmd(["swaync-client", "-d", "-t"])
                                                    }
                                                }
                                            }
                                        }

                                        // Sliders
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 10

                                            // Volume Slider
                                            Rectangle {
                                                Layout.fillWidth: true; height: 48; radius: 16
                                                color: "#1e1e1e"; clip: true

                                                Rectangle {
                                                    width: parent.width * (sidebarRoot.volumeLevel / 100)
                                                    height: parent.height; radius: parent.radius; color: "#a6e3a1"
                                                    Behavior on width { enabled: !volDrag.pressed; NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                                }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
                                                    Text { text: sidebarRoot.volumeLevel === 0 ? "󰝟" : (sidebarRoot.volumeLevel < 50 ? "󰖀" : "󰕾"); color: sidebarRoot.volumeLevel > 15 ? "#11111b" : "#ffffff"; font.pixelSize: 15; font.family: "JetBrainsMono Nerd Font" }
                                                    Text { text: "Volume"; color: sidebarRoot.volumeLevel > 35 ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font" }
                                                    Item { Layout.fillWidth: true }
                                                    Text { text: sidebarRoot.volumeLevel + "%"; color: sidebarRoot.volumeLevel > 85 ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font" }
                                                }

                                                MouseArea {
                                                    id: volDrag; anchors.fill: parent; preventStealing: true
                                                    onPressed: (mouse) => updateVol(mouse.x)
                                                    onPositionChanged: (mouse) => { if (pressed) updateVol(mouse.x) }
                                                    function updateVol(mouseX) {
                                                        let pct = Math.max(0, Math.min(100, Math.round((mouseX / width) * 100)))
                                                        sidebarRoot.volumeLevel = pct
                                                        sidebarRoot.runCmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", pct + "%"])
                                                    }
                                                }
                                            }

                                            // Brightness Slider
                                            Rectangle {
                                                Layout.fillWidth: true; height: 48; radius: 16
                                                color: "#1e1e1e"; clip: true

                                                Rectangle {
                                                    width: parent.width * (sidebarRoot.brightnessLevel / 100)
                                                    height: parent.height; radius: parent.radius; color: "#f9e2af"
                                                    Behavior on width { enabled: !brightDrag.pressed; NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                                }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
                                                    Text { text: "󰃠"; color: sidebarRoot.brightnessLevel > 15 ? "#11111b" : "#ffffff"; font.pixelSize: 15; font.family: "JetBrainsMono Nerd Font" }
                                                    Text { text: "Brightness"; color: sidebarRoot.brightnessLevel > 35 ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font" }
                                                    Item { Layout.fillWidth: true }
                                                    Text { text: sidebarRoot.brightnessLevel + "%"; color: sidebarRoot.brightnessLevel > 85 ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font" }
                                                }

                                                MouseArea {
                                                    id: brightDrag; anchors.fill: parent; preventStealing: true
                                                    onPressed: (mouse) => updateBright(mouse.x)
                                                    onPositionChanged: (mouse) => { if (pressed) updateBright(mouse.x) }
                                                    function updateBright(mouseX) {
                                                        let pct = Math.max(10, Math.min(100, Math.round((mouseX / width) * 100)))
                                                        sidebarRoot.brightnessLevel = pct
                                                        sidebarRoot.runCmd(["brightnessctl", "set", pct + "%"])
                                                    }
                                                }
                                            }
                                        }

                                        // Quick Actions
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 10

                                            // Capture Action
                                            Rectangle {
                                                Layout.fillWidth: true; height: 48; radius: 16; color: "#89dceb"
                                                scale: capArea.pressed ? 0.95 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                RowLayout { anchors.centerIn: parent; spacing: 8
                                                    Text { text: "󰹑"; color: "#11111b"; font.pixelSize: 15; font.family: "JetBrainsMono Nerd Font" }
                                                    Text { text: "Capture"; color: "#11111b"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                                }
                                                MouseArea {
                                                    id: capArea
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        sidebarRoot.close()
                                                        sidebarRoot.runCmd([
                                                            "sh", "-c",
                                                            "sleep 0.4 && (DIR=\"$HOME/Pictures/Screenshots\" && mkdir -p \"$DIR\" && hyprshot -m region -o \"$DIR\" || (FILE=\"$DIR/Screenshot_$(date +%Y%m%d_%H%M%S).png\" && grim -g \"$(slurp)\" \"$FILE\" && wl-copy < \"$FILE\" && notify-send -a \"QuickShell\" -i \"$FILE\" \"Screenshot Captured\" \"Saved to ~/Pictures/Screenshots\"))"
                                                        ])
                                                    }
                                                }
                                            }

                                            // Power Action
                                            Rectangle {
                                                Layout.fillWidth: true; height: 48; radius: 16; color: "#cba6f7"
                                                scale: pwrArea.pressed ? 0.95 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                RowLayout { anchors.centerIn: parent; spacing: 8
                                                    Text { text: "󰐥"; color: "#11111b"; font.pixelSize: 15; font.family: "JetBrainsMono Nerd Font" }
                                                    Text { text: "Power"; color: "#11111b"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                                }
                                                MouseArea { id: pwrArea; anchors.fill: parent; onClicked: { sidebarRoot.close(); sidebarRoot.openPowerMenu() } }
                                            }
                                        }
                                    }
                                }

                                // SLIDE 2: ANIMATED SCREEN RECORDER
                                Item {
                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: 14

                                        Rectangle {
                                            Layout.fillWidth: true; height: 56; radius: 16
                                            color: sidebarRoot.isRecording ? "#f38ba8" : "#1e1e1e"

                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 14
                                                Text {
                                                    text: "RECORDING"
                                                    color: sidebarRoot.isRecording ? "#11111b" : "#ffffff"
                                                    font.weight: Font.ExtraBold; font.pixelSize: 15; font.letterSpacing: 2; font.family: "JetBrainsMono Nerd Font"
                                                }
                                                Item { Layout.fillWidth: true }
                                                RowLayout {
                                                    spacing: 10
                                                    Rectangle {
                                                        width: 42; height: 42; radius: 21; visible: sidebarRoot.isRecording
                                                        opacity: visible ? 1.0 : 0.0; color: sidebarRoot.isPaused ? "#f9e2af" : "#11111b"
                                                        scale: recPauseArea.pressed ? 0.88 : 1.0
                                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                        Text { anchors.centerIn: parent; text: sidebarRoot.isPaused ? "󰐊" : "󰏤"; color: sidebarRoot.isPaused ? "#11111b" : "#ffffff"; font.pixelSize: 18; font.family: "JetBrainsMono Nerd Font" }
                                                        MouseArea { id: recPauseArea; anchors.fill: parent; onClicked: sidebarRoot.pauseResumeRecording() }
                                                    }
                                                    Rectangle {
                                                        width: 42; height: 42; radius: 21
                                                        color: sidebarRoot.isRecording ? "#11111b" : "#f38ba8"
                                                        scale: recToggleArea.pressed ? 0.88 : 1.0
                                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                        Text { anchors.centerIn: parent; text: sidebarRoot.isRecording ? "󰓛" : "󰑊"; color: sidebarRoot.isRecording ? "#f38ba8" : "#11111b"; font.pixelSize: 18; font.family: "JetBrainsMono Nerd Font" }
                                                        MouseArea { id: recToggleArea; anchors.fill: parent; onClicked: { if (sidebarRoot.isRecording) sidebarRoot.stopRecording(); else sidebarRoot.startRecording() } }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; height: 56; radius: 16; color: "#1e1e1e"
                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 5; spacing: 5
                                                Rectangle {
                                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 12
                                                    color: !sidebarRoot.recModeRegion ? "#89b4fa" : "transparent"
                                                    scale: modeFullArea.pressed ? 0.96 : 1.0
                                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                    RowLayout {
                                                        anchors.centerIn: parent; spacing: 10
                                                        Text { text: "󰍹"; color: !sidebarRoot.recModeRegion ? "#11111b" : "#ffffff"; font.pixelSize: 18; font.family: "JetBrainsMono Nerd Font" }
                                                        Text { text: "FULLSCREEN"; color: !sidebarRoot.recModeRegion ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.letterSpacing: 1.5; font.family: "JetBrainsMono Nerd Font" }
                                                    }
                                                    MouseArea { id: modeFullArea; anchors.fill: parent; onClicked: sidebarRoot.recModeRegion = false }
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 12
                                                    color: sidebarRoot.recModeRegion ? "#89b4fa" : "transparent"
                                                    scale: modeRegArea.pressed ? 0.96 : 1.0
                                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                    RowLayout {
                                                        anchors.centerIn: parent; spacing: 10
                                                        Text { text: "󰒅"; color: sidebarRoot.recModeRegion ? "#11111b" : "#ffffff"; font.pixelSize: 18; font.family: "JetBrainsMono Nerd Font" }
                                                        Text { text: "REGION"; color: sidebarRoot.recModeRegion ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.letterSpacing: 1.5; font.family: "JetBrainsMono Nerd Font" }
                                                    }
                                                    MouseArea { id: modeRegArea; anchors.fill: parent; onClicked: sidebarRoot.recModeRegion = true }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; height: 56; radius: 16; color: "#1e1e1e"
                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 5; spacing: 5
                                                Rectangle {
                                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 12
                                                    color: !sidebarRoot.recAudioEnabled ? "#a6e3a1" : "transparent"
                                                    scale: audioMuteArea.pressed ? 0.96 : 1.0
                                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                    RowLayout {
                                                        anchors.centerIn: parent; spacing: 10
                                                        Text { text: "󰝟"; color: !sidebarRoot.recAudioEnabled ? "#11111b" : "#ffffff"; font.pixelSize: 18; font.family: "JetBrainsMono Nerd Font" }
                                                        Text { text: "MUTED"; color: !sidebarRoot.recAudioEnabled ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.letterSpacing: 1.5; font.family: "JetBrainsMono Nerd Font" }
                                                    }
                                                    MouseArea { id: audioMuteArea; anchors.fill: parent; onClicked: sidebarRoot.recAudioEnabled = false }
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 12
                                                    color: sidebarRoot.recAudioEnabled ? "#a6e3a1" : "transparent"
                                                    scale: audioOnArea.pressed ? 0.96 : 1.0
                                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                    RowLayout {
                                                        anchors.centerIn: parent; spacing: 10
                                                        Text { text: "󰓃"; color: sidebarRoot.recAudioEnabled ? "#11111b" : "#ffffff"; font.pixelSize: 18; font.family: "JetBrainsMono Nerd Font" }
                                                        Text { text: "AUDIO ON"; color: sidebarRoot.recAudioEnabled ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.letterSpacing: 1.5; font.family: "JetBrainsMono Nerd Font" }
                                                    }
                                                    MouseArea { id: audioOnArea; anchors.fill: parent; onClicked: sidebarRoot.recAudioEnabled = true }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 6
                                                Text { text: "RECORDINGS HISTORY"; color: "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 11; font.letterSpacing: 1.5; font.family: "JetBrainsMono Nerd Font" }
                                                Item { Layout.fillWidth: true }
                                                Rectangle {
                                                    width: 90; height: 26; radius: 8; color: "#f38ba8"
                                                    scale: clearBtnArea.pressed ? 0.92 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                    RowLayout {
                                                        anchors.centerIn: parent; spacing: 4
                                                        Text { text: "󰆴"; color: "#11111b"; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font" }
                                                        Text { text: "CLEAR"; color: "#11111b"; font.weight: Font.ExtraBold; font.pixelSize: 10; font.letterSpacing: 1; font.family: "JetBrainsMono Nerd Font" }
                                                    }
                                                    MouseArea { id: clearBtnArea; anchors.fill: parent; onClicked: sidebarRoot.clearRecordingsHistory() }
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true; height: 120; radius: 16; color: "#1e1e1e"; clip: true
                                                ColumnLayout {
                                                    anchors.centerIn: parent; visible: sidebarRoot.recentRecordings.length === 0; spacing: 6
                                                    Text { text: "󰈔"; color: "#ffffff"; font.pixelSize: 26; font.family: "JetBrainsMono Nerd Font"; Layout.alignment: Qt.AlignHCenter }
                                                    Text { text: "No recordings found"; color: "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font"; Layout.alignment: Qt.AlignHCenter }
                                                }

                                                ScrollView {
                                                    anchors.fill: parent; anchors.margins: 8; visible: sidebarRoot.recentRecordings.length > 0; clip: true
                                                    ColumnLayout {
                                                        width: parent.width; spacing: 6
                                                        Repeater {
                                                            model: sidebarRoot.recentRecordings
                                                            delegate: Rectangle {
                                                                required property string modelData
                                                                Layout.fillWidth: true; height: 40; radius: 10; color: recRowArea.pressed ? "#222222" : "#111111"
                                                                scale: recRowArea.pressed ? 0.98 : 1.0
                                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                                                RowLayout {
                                                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                                                                    Text { text: "󰿎"; color: "#ffffff"; font.pixelSize: 14; font.family: "JetBrainsMono Nerd Font" }
                                                                    Text { Layout.fillWidth: true; text: modelData; color: "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font"; elide: Text.ElideRight }
                                                                }
                                                                MouseArea { id: recRowArea; anchors.fill: parent; onClicked: sidebarRoot.runCmd(["xdg-open", "$HOME/Videos/Recordings/" + modelData]) }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Slide Indicators
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter; spacing: 6
                                Repeater {
                                    model: mainSwipeView.count
                                    delegate: Rectangle {
                                        width: mainSwipeView.currentIndex === index ? 18 : 6
                                        height: 6; radius: 3; color: mainSwipeView.currentIndex === index ? "#89b4fa" : "#ffffff"
                                        opacity: mainSwipeView.currentIndex === index ? 1.0 : 0.3
                                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }

                    // VIEW 1: WI-FI SUBPAGE
                    Item {
                        opacity: StackLayout.isCurrentItem ? 1.0 : 0.0
                        scale: StackLayout.isCurrentItem ? 1.0 : 0.98
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent; spacing: 12
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Rectangle {
                                    width: 30; height: 30; radius: 10; color: "#1e1e1e"
                                    scale: wifiBackArea.pressed ? 0.88 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                    Text { anchors.centerIn: parent; text: "󰁍"; color: "#ffffff"; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                    MouseArea { id: wifiBackArea; anchors.fill: parent; onClicked: sidebarRoot.currentViewIndex = 0 }
                                }
                                Text { text: "WI-FI"; color: "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 60; height: 26; radius: 13; color: sidebarRoot.wifiEnabled ? "#89b4fa" : "#1e1e1e"
                                    scale: wifiToggleBtnArea.pressed ? 0.92 : 1.0
                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                    Text { anchors.centerIn: parent; text: sidebarRoot.wifiEnabled ? "ON" : "OFF"; color: sidebarRoot.wifiEnabled ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 10; font.family: "JetBrainsMono Nerd Font" }
                                    MouseArea { id: wifiToggleBtnArea; anchors.fill: parent; onClicked: { let target = sidebarRoot.wifiEnabled ? "off" : "on"; sidebarRoot.wifiEnabled = !sidebarRoot.wifiEnabled; sidebarRoot.runCmd(["nmcli", "radio", "wifi", target]) } }
                                }
                            }

                            ScrollView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                ColumnLayout {
                                    width: parent.width; spacing: 8
                                    Repeater {
                                        model: sidebarRoot.wifiList
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true; height: 44; radius: 12; color: modelData.active ? "#89b4fa" : "#1e1e1e"
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 10
                                                Text { text: "󰤨"; color: modelData.active ? "#11111b" : "#ffffff"; font.pixelSize: 14; font.family: "JetBrainsMono Nerd Font" }
                                                Text { Layout.fillWidth: true; text: modelData.ssid; color: modelData.active ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font"; elide: Text.ElideRight }
                                                Rectangle {
                                                    width: modelData.active ? 80 : 64; height: 26; radius: 8; color: modelData.active ? "#11111b" : "#89b4fa"
                                                    scale: wifiConnArea.pressed ? 0.90 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                                    Text { anchors.centerIn: parent; text: modelData.active ? "Disconnect" : "Connect"; color: modelData.active ? "#ffffff" : "#11111b"; font.weight: Font.ExtraBold; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font" }
                                                    MouseArea { id: wifiConnArea; anchors.fill: parent; onClicked: { if (modelData.active) sidebarRoot.disconnectWifi(modelData.ssid); else { sidebarRoot.selectedWifiSsid = modelData.ssid; sidebarRoot.wifiPasswordText = "" } } }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; visible: sidebarRoot.selectedWifiSsid !== ""; height: 86; radius: 12; color: "#1e1e1e"
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 8; spacing: 6
                                    Text { text: "Password for " + sidebarRoot.selectedWifiSsid; color: "#ffffff"; font.pixelSize: 10; font.family: "JetBrainsMono Nerd Font" }
                                    Rectangle {
                                        Layout.fillWidth: true; height: 28; radius: 6; color: "#111111"
                                        TextInput {
                                            id: passInput; anchors.fill: parent; anchors.leftMargin: 8; verticalAlignment: TextInput.AlignVCenter
                                            color: "#ffffff"; echoMode: TextInput.Password; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font"
                                            onTextChanged: sidebarRoot.wifiPasswordText = text
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            width: 52; height: 22; radius: 5; color: "#2e2e2e"
                                            scale: wifiCancelArea.pressed ? 0.90 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                            Text { anchors.centerIn: parent; text: "Cancel"; color: "#ffffff"; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font" }
                                            MouseArea { id: wifiCancelArea; anchors.fill: parent; onClicked: sidebarRoot.selectedWifiSsid = "" }
                                        }
                                        Rectangle {
                                            width: 62; height: 22; radius: 5; color: "#89b4fa"
                                            scale: wifiSubmitArea.pressed ? 0.90 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                            Text { anchors.centerIn: parent; text: "Connect"; color: "#11111b"; font.weight: Font.ExtraBold; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font" }
                                            MouseArea { id: wifiSubmitArea; anchors.fill: parent; onClicked: sidebarRoot.connectWifi(sidebarRoot.selectedWifiSsid, sidebarRoot.wifiPasswordText) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // VIEW 2: BLUETOOTH SUBPAGE
                    Item {
                        opacity: StackLayout.isCurrentItem ? 1.0 : 0.0
                        scale: StackLayout.isCurrentItem ? 1.0 : 0.98
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent; spacing: 12
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Rectangle {
                                    width: 30; height: 30; radius: 10; color: "#1e1e1e"
                                    scale: btBackArea.pressed ? 0.88 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                    Text { anchors.centerIn: parent; text: "󰁍"; color: "#ffffff"; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                    MouseArea { id: btBackArea; anchors.fill: parent; onClicked: sidebarRoot.currentViewIndex = 0 }
                                }
                                Text { text: "BLUETOOTH"; color: "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 60; height: 26; radius: 13; color: sidebarRoot.btEnabled ? "#b4befe" : "#1e1e1e"
                                    scale: btToggleBtnArea.pressed ? 0.92 : 1.0
                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                    Text { anchors.centerIn: parent; text: sidebarRoot.btEnabled ? "ON" : "OFF"; color: sidebarRoot.btEnabled ? "#11111b" : "#ffffff"; font.weight: Font.ExtraBold; font.pixelSize: 10; font.family: "JetBrainsMono Nerd Font" }
                                    MouseArea { id: btToggleBtnArea; anchors.fill: parent; onClicked: { let target = sidebarRoot.btEnabled ? "off" : "on"; sidebarRoot.btEnabled = !sidebarRoot.btEnabled; sidebarRoot.runCmd(["bluetoothctl", "power", target]) } }
                                }
                            }

                            ScrollView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                ColumnLayout {
                                    width: parent.width; spacing: 8
                                    Repeater {
                                        model: sidebarRoot.btList
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true; height: 42; radius: 10; color: "#1e1e1e"
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10
                                                Text { text: "󰂯"; color: "#ffffff"; font.pixelSize: 13; font.family: "JetBrainsMono Nerd Font" }
                                                Text { Layout.fillWidth: true; text: modelData.name; color: "#ffffff"; font.pixelSize: 11; font.family: "JetBrainsMono Nerd Font"; elide: Text.ElideRight }
                                                Rectangle {
                                                    width: 62; height: 24; radius: 6; color: "#b4befe"
                                                    scale: btPairArea.pressed ? 0.90 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                                    Text { anchors.centerIn: parent; text: "Pair"; color: "#11111b"; font.weight: Font.ExtraBold; font.pixelSize: 9; font.family: "JetBrainsMono Nerd Font" }
                                                    MouseArea { id: btPairArea; anchors.fill: parent; onClicked: sidebarRoot.runCmd(["bluetoothctl", "connect", modelData.mac]) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // =================================================
            // BOTTOM CONTAINER: BATTERY & POWER PROFILES
            // =================================================
            WidgetsDeck {
                Layout.fillWidth: true
                batteryLevel: 72
                isCharging: false
                onRunCommand: function(cmd) { sidebarRoot.runCmd(cmd) }
            }
        }
    }
}
