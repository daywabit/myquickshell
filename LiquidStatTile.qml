import QtQuick
import QtQuick.Layouts

Rectangle {
    id: tile

    property string icon: ""
    property string title: ""
    property real value: 0           // Percentage (0 - 100) for liquid height
    property string customText: ""   // Custom formatted display text (e.g., GB usage)
    property color liquidColor: "#89b4fa"

    property real animatedValue: value
    property real waveOffset: 0

    Layout.fillWidth: true
    radius: 16
    color: "#121216"
    border.color: "#1f1f28"
    border.width: 1

    Behavior on animatedValue {
        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }

    // Continuous wave animation
    NumberAnimation on waveOffset {
        running: true
        from: 0
        to: Math.PI * 2
        duration: 1400
        loops: Animation.Infinite
    }

    // Canvas Liquid Renderer
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

            // Surface calculation
            var liquidTop = height - liquidH;
            var amplitude = 3.5;
            var frequency = 0.07;

            ctx.fillStyle = tile.liquidColor;
            ctx.beginPath();
            ctx.moveTo(width, height);
            ctx.lineTo(0, height);
            ctx.lineTo(0, liquidTop);

            for (var x = 0; x <= width; x += 2) {
                var y = liquidTop + Math.sin(x * frequency + tile.waveOffset) * amplitude;
                ctx.lineTo(x, y);
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
        anchors.margins: 10
        spacing: 2
        z: 3

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: tile.icon
                color: (tile.animatedValue > 65) ? "#0a0a0c" : "#a6adc8"
                font.pixelSize: 16
                font.family: "JetBrainsMono Nerd Font"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: tile.title
                color: (tile.animatedValue > 65) ? "#0a0a0c" : "#a6adc8"
                font.pixelSize: 10
                font.bold: true
                font.family: "JetBrainsMono Nerd Font"
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Item { Layout.fillHeight: true }

        Text {
            Layout.alignment: Qt.AlignLeft
            text: tile.customText !== "" ? tile.customText : (Math.round(tile.animatedValue) + "%")
            color: (tile.animatedValue > 45) ? "#0a0a0c" : "#cdd6f4"
            font.pixelSize: tile.customText !== "" ? 14 : 20
            font.bold: true
            font.family: "JetBrainsMono Nerd Font"
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
}
