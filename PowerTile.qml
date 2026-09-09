import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: tile

    property string icon: ""
    property string label: ""

    // Hold duration in milliseconds (2000 ms = 2 seconds)
    property int holdDuration: 2000

    // Liquid height animation driver
    property real liquidHeight: 0

    signal triggered()

    Layout.fillWidth: true
    Layout.fillHeight: true
    radius: 18
    color: "#121214"

    // Focus ring outline
    border.color: tileArea.containsMouse ? "#ffffff" : "#1a1a1e"
    border.width: tileArea.containsMouse ? 2 : 1

    Behavior on border.color { ColorAnimation { duration: 140 } }
    Behavior on border.width { NumberAnimation { duration: 140 } }

    // Wave animation offset driver
    property real waveOffset: 0
    NumberAnimation on waveOffset {
        id: waveLoop
        running: false
        from: 0
        to: Math.PI * 2
        duration: 600
        loops: Animation.Infinite
    }

    // Unified Liquid Canvas with Native Corner Clipping
    Canvas {
        id: liquidCanvas
        anchors.fill: parent
        anchors.margins: 2

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            if (tile.liquidHeight <= 0) return;

            ctx.save();

            // Define rounded corner clipping path matching inner tile geometry
            var r = Math.max(0, tile.radius - 2);
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
            ctx.clip(); // Constrains all liquid drawing strictly inside rounded corners

            // Water surface level calculation
            var liquidTop = height - tile.liquidHeight;
            var amplitude = 3;
            var frequency = 0.08;

            ctx.fillStyle = "#ffffff";
            ctx.beginPath();

            // Start from bottom-right corner
            ctx.moveTo(width, height);
            ctx.lineTo(0, height);
            ctx.lineTo(0, liquidTop);

            // Draw wavy liquid surface across the tile
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
            function onLiquidHeightChanged() { liquidCanvas.requestPaint(); }
            function onWaveOffsetChanged() {
                if (tile.liquidHeight > 0) liquidCanvas.requestPaint();
            }
        }
    }

    // Controlled Animations for Liquid Fill and Drain
    NumberAnimation {
        id: fillAnimation
        target: tile
        property: "liquidHeight"
        to: tile.height - 4
        duration: tile.holdDuration
        easing.type: Easing.Linear

        onStarted: waveLoop.start()
    }

    NumberAnimation {
        id: drainAnimation
        target: tile
        property: "liquidHeight"
        to: 0
        duration: 180
        easing.type: Easing.OutCubic

        onFinished: waveLoop.stop()
    }

    // Long-press timer
    Timer {
        id: holdTimer
        interval: tile.holdDuration
        repeat: false
        onTriggered: {
            tile.triggered()
        }
    }

    // Icon and Label Layout
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8
        z: 3 // Renders on top of liquid layer

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: tile.icon
            color: (tile.liquidHeight > tile.height * 0.55) ? "#000000" : "#ffffff"
            font.pixelSize: 26
            font.family: "JetBrainsMono Nerd Font"

            Behavior on color { ColorAnimation { duration: 100 } }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: tile.label
            color: (tile.liquidHeight > tile.height * 0.55) ? "#000000" : "#ffffff"
            font.bold: true
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"

            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    MouseArea {
        id: tileArea
        anchors.fill: parent
        hoverEnabled: true

        onPressed: {
            drainAnimation.stop()
            fillAnimation.start()
            holdTimer.start()
        }

        onReleased: {
            holdTimer.stop()
            fillAnimation.stop()
            drainAnimation.start()
        }

        onCanceled: {
            holdTimer.stop()
            fillAnimation.stop()
            drainAnimation.start()
        }
    }
}
