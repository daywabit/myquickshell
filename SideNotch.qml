import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: window

    WlrLayershell.namespace: "quickshell-sidenotch"
    WlrLayershell.layer: WlrLayershell.Overlay
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.keyboardFocus: window.panelState === "expanded"
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    property string panelState: "hidden"

    // Dynamic System Stats
    property real cpuUsage: 0
    property real ramUsage: 0
    property string ramText: "0 GB"
    property real gpuUsage: 0
    property real diskUsage: 0
    property string diskText: "0 GB"

    // System Monitor Polling Script
    Process {
        id: statFetcher
        command: ["sh", "-c", "
            # CPU
            read -r cpu u n s i w irq sirq st g gn < /proc/stat
            t=$((u+n+s+i+w+irq+sirq+st))
            idle=$((i+w))

            # RAM (Used GB, Total GB, Pct)
            eval $(free -m | awk '/Mem:/ {printf \"ram_used=%.1f; ram_total=%.1f; ram_pct=%.0f;\", $3/1024, $2/1024, $3/$2*100}')

            # DISK (Used GB, Total GB, Pct)
            eval $(df -m / | awk 'NR==2 {printf \"disk_used=%.0f; disk_total=%.0f; disk_pct=%.0f;\", $3/1024, $2/1024, $3/$2*100}')

            # GPU
            if command -v nvidia-smi >/dev/null 2>&1; then
                gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0)
            elif [ -f /sys/class/drm/card0/device/gpu_busy_percent ]; then
                gpu=$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || echo 0)
            else
                gpu=0
            fi

            echo \"$t $idle $ram_pct $disk_pct $gpu $ram_used $ram_total $disk_used $disk_total\"
        "]

        property real lastTotal: 0
        property real lastIdle: 0

        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split(/\s+/);
                if (parts.length >= 9) {
                    var total = parseFloat(parts[0]);
                    var idle = parseFloat(parts[1]);

                    if (statFetcher.lastTotal > 0) {
                        var diffTotal = total - statFetcher.lastTotal;
                        var diffIdle = idle - statFetcher.lastIdle;
                        if (diffTotal > 0) {
                            window.cpuUsage = Math.max(0, Math.min(100, ((diffTotal - diffIdle) / diffTotal) * 100));
                        }
                    }
                    statFetcher.lastTotal = total;
                    statFetcher.lastIdle = idle;

                    window.ramUsage = parseFloat(parts[2]) || 0;
                    window.diskUsage = parseFloat(parts[3]) || 0;
                    window.gpuUsage = parseFloat(parts[4]) || 0;

                    var rUsed = parseFloat(parts[5]) || 0;
                    var rTot = parseFloat(parts[6]) || 0;
                    window.ramText = rUsed.toFixed(1) + " / " + rTot.toFixed(0) + " G";

                    var dUsed = parseFloat(parts[7]) || 0;
                    var dTot = parseFloat(parts[8]) || 0;
                    window.diskText = dUsed.toFixed(0) + " / " + dTot.toFixed(0) + " G";
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statFetcher.running = true
    }

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    color: "transparent"

    Item { id: fullScreenSurface; anchors.fill: parent }

    mask: Region {
        item: window.panelState === "expanded" ? fullScreenSurface : panelPill
    }

    Timer {
        id: edgeHoverTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (window.panelState === "hidden") window.panelState = "peek"
        }
    }

    MouseArea {
        id: backdrop
        anchors.fill: parent
        enabled: window.panelState === "expanded"
        onClicked: window.panelState = "hidden"
    }

    Shortcut {
        sequence: "Escape"
        enabled: window.panelState === "expanded"
        onActivated: window.panelState = "hidden"
    }

    // Main Sliding Drawer Container
    Item {
        id: panelPill

        width: 270
        height: 310
        anchors.verticalCenter: parent.verticalCenter

        x: {
            if (window.panelState === "hidden") return -width + 4
            if (window.panelState === "peek") return -width + 36
            return 0
        }

        Behavior on x {
            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
        }

        // Screen Bezel Shell Frame
        Rectangle {
            anchors.fill: parent
            color: "#0a0a0c"
            radius: 22
            border.color: "#1f1f28"
            border.width: 1

            // Flatten inner left edge
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.radius
                color: parent.color
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: parent.color
            }
        }

        // Asymmetric Bento Masonry Layout
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // Column 1 (Left): Tall CPU + Compact RAM
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                LiquidStatTile {
                    title: "CPU"
                    icon: "󰍛"
                    value: window.cpuUsage
                    liquidColor: "#f38ba8"
                    implicitHeight: 150
                }

                LiquidStatTile {
                    title: "RAM"
                    icon: "󰘚"
                    value: window.ramUsage
                    customText: window.ramText
                    liquidColor: "#cba6f7"
                    implicitHeight: 130
                }
            }

            // Column 2 (Right): Compact GPU + Tall DISK
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                LiquidStatTile {
                    title: "GPU"
                    icon: "󰢮"
                    value: window.gpuUsage
                    liquidColor: "#a6e3a1"
                    implicitHeight: 110
                }

                LiquidStatTile {
                    title: "DISK"
                    icon: "󰋊"
                    value: window.diskUsage
                    customText: window.diskText
                    liquidColor: "#89dceb"
                    implicitHeight: 170
                }
            }
        }

        MouseArea {
            id: pillHoverArea
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
                if (window.panelState === "hidden") edgeHoverTimer.start()
            }
            onExited: {
                if (edgeHoverTimer.running) edgeHoverTimer.stop()
                if (window.panelState === "peek") window.panelState = "hidden"
            }
            onClicked: {
                if (window.panelState === "peek") window.panelState = "expanded"
            }
        }
    }
}
