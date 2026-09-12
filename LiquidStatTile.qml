import QtQuick
import QtQuick.Layouts

Rectangle {
    id: tile

    property string icon: ""
    property string title: ""
    property real value: 0           // Percentage (0 - 100)
    property string badgeText: ""    // Preferred bottom pill text property
    property string customText: ""   // Backward compatibility property for SideNotch.qml
    property color liquidColor: "#89b4fa"

    // Resolves either property if provided
    readonly property string displayText: badgeText !== "" ? badgeText : customText

    property real animatedValue: value
    property real waveOffset: 0

    implicitWidth: 130
    implicitHeight: 130
    Layout.fillWidth: true
    Layout.fillHeight: true

    radius: 18
    color: "#16161a"
    border.color: Qt.rgba(1, 1, 1, 0.08)
    border.width: 1

    Behavior on animatedValue {
        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }

    // Continuous wave animation loop
    NumberAnimation on waveOffset {
        running: true
        from: 0
        to: Math.PI * 2
        duration: 1600
        loops: Animation.Infinite
    }

    // Canvas Liquid Renderer with Dual-Layer Waves
    Canvas {
        id: liquidCanvas
        anchors.fill: parent
        anchors.margins: 1

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var liquidH = (tile.animatedValue / 100.0) * height;
            if (liquidH <= 0) return;

            ctx.save();

            // Rounded corner clipping path
            var r = Math.max(0, tile.radius - 1);
            ctx.beginPath();
            ctx.moveTo(r, 0);
            ctx.lineTo(width - r, 0);
            ctx.arcTo(width, 0, width, r, r);
            ctx.lineTo(width, height - r);
            ctx.arcTo(width, height, width - r, height, r);
            ctx.lineTo(r, height);
            ctx.arcTo(0, height, 0, height - r, r);
            ctx.lineTo(0, r);
            ctx.arcTo(0, 0, r, 0, r);
            ctx.closePath();
            ctx.clip();

            var liquidTop = height - liquidH;

            // --- BACK WAVE (Translucent) ---
            ctx.fillStyle = Qt.rgba(tile.liquidColor.r, tile.liquidColor.g, tile.liquidColor.b, 0.35);
            ctx.beginPath();
            ctx.moveTo(width, height);
            ctx.lineTo(0, height);
            ctx.lineTo(0, liquidTop);

            for (var x1 = 0; x1 <= width; x1 += 2) {
                var y1 = liquidTop + Math.sin(x1 * 0.05 - tile.waveOffset) * 4.0;
                ctx.lineTo(x1, y1);
            }
            ctx.lineTo(width, height);
            ctx.closePath();
            ctx.fill();

            // --- FRONT WAVE (Main Liquid) ---
            ctx.fillStyle = tile.liquidColor;
            ctx.beginPath();
            ctx.moveTo(width, height);
            ctx.lineTo(0, height);
            ctx.lineTo(0, liquidTop);

            for (var x2 = 0; x2 <= width; x2 += 2) {
                var y2 = liquidTop + Math.sin(x2 * 0.06 + tile.waveOffset) * 3.5;
                ctx.lineTo(x2, y2);
            }
            ctx.lineTo(width, height);
            ctx.closePath();
            ctx.fill();

            ctx.restore();
        }

        Connections {
            target: tile
            function onAnimatedValueChanged() { liquidCanvas.requestPaint(); }
            function onWaveOffsetChanged() { liquidCanvas.requestPaint(); }
        }
    }

    // Card Content Overlay
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 2
        z: 3

        // Top Row: Icon + Title
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: tile.icon
                color: (tile.animatedValue > 70) ? "#0a0a0c" : "#a6adc8"
                font.pixelSize: 14
                font.family: "JetBrainsMono Nerd Font"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: tile.title
                color: (tile.animatedValue > 70) ? "#0a0a0c" : "#8087a2"
                font.pixelSize: 10
                font.bold: true
                font.family: "JetBrainsMono Nerd Font"
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Item { Layout.fillHeight: true }

        // Main Percentage Display
        Text {
            Layout.alignment: Qt.AlignLeft
            text: Math.round(tile.animatedValue) + "%"
            color: (tile.animatedValue > 45 && tile.displayText === "") ? "#0a0a0c" : "#ffffff"
            font.pixelSize: 18
            font.bold: true
            font.family: "JetBrainsMono Nerd Font"
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        // Bottom Pill Badge (For RAM, DISK, or custom text)
        Rectangle {
            id: badge
            visible: tile.displayText !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            radius: 11
            color: Qt.rgba(1, 1, 1, 0.85)

            Text {
                anchors.centerIn: parent
                text: tile.displayText
                color: "#0a0a0c"
                font.pixelSize: 10
                font.bold: true
                font.family: "JetBrainsMono Nerd Font"
            }
        }
    }
}
