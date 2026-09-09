import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: wallpaperPage
    property var parentSwipeView
    property var island

    Component {
        id: execProcess
        Process { onExited: destroy() }
    }

    function applyWallpaper(imagePath) {
        var proc = execProcess.createObject(wallpaperPage, {
            command: [
                "bash",
                Quickshell.env("HOME") + "/.config/quickshell/scripts/set-wallpaper.sh",
                imagePath
            ]
        })
        proc.running = true
    }

    property var wallpaperList: []

    Process {
        id: scanProcess
        command: [
            "bash", "-c",
            "find ~/Pictures ~/Wallpapers ~/.config/backgrounds -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \\) 2>/dev/null | head -n 30"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let files = this.text.trim().split("\n").filter(f => f.length > 0)
                wallpaperPage.wallpaperList = files
            }
        }
    }

    Component.onCompleted: scanProcess.running = true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            Rectangle {
                width: 26
                height: 26
                radius: 8
                color: backArea.containsMouse ? "#22ffffff" : "#141414"

                Text {
                    anchors.centerIn: parent
                    text: "󰁍"
                    color: backArea.containsMouse ? "#ffffff" : "#aaaaaa"
                    font.pixelSize: 14
                    font.family: "JetBrainsMono Nerd Font"
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (wallpaperPage.parentSwipeView) {
                            wallpaperPage.parentSwipeView.currentIndex = 2
                        }
                    }
                }

                Behavior on color { ColorAnimation { duration: 120 } }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 26
                height: 26
                radius: 8
                color: refreshArea.containsMouse ? "#22ffffff" : "#141414"

                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    color: refreshArea.containsMouse ? "#ffffff" : "#aaaaaa"
                    font.pixelSize: 12
                    font.family: "JetBrainsMono Nerd Font"
                }

                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: scanProcess.running = true
                }

                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }

        ListView {
            id: wallView
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: 16
            clip: true

            snapMode: ListView.SnapToItem
            preferredHighlightBegin: (width - 160) / 2
            preferredHighlightEnd: (width + 160) / 2
            highlightRangeMode: ListView.StrictlyEnforceRange

            model: wallpaperPage.wallpaperList

            delegate: Item {
                id: delegateRoot
                width: 160
                height: wallView.height - 20
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                readonly property bool isFocused: ListView.isCurrentItem

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: "#141414"
                    border.color: delegateRoot.isFocused ? "#ffffff" : (itemArea.containsMouse ? "#66ffffff" : "#22ffffff")
                    border.width: delegateRoot.isFocused ? 2 : 1
                    clip: true

                    scale: delegateRoot.isFocused ? 1.12 : (itemArea.containsMouse ? 0.95 : 0.84)
                    opacity: delegateRoot.isFocused ? 1.0 : (itemArea.containsMouse ? 0.8 : 0.45)

                    Behavior on scale {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: 200 }
                    }

                    Image {
                        anchors.fill: parent
                        source: "file://" + modelData
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 320
                        sourceSize.height: 220
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 28
                        color: delegateRoot.isFocused ? "#e6000000" : "#aa000000"

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 10
                            text: modelData.split('/').pop()
                            color: delegateRoot.isFocused ? "#ffffff" : "#888888"
                            font.pixelSize: 10
                            font.bold: delegateRoot.isFocused
                            font.family: "JetBrainsMono Nerd Font"
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            wallView.currentIndex = index
                            wallpaperPage.applyWallpaper(modelData)
                            if (wallpaperPage.island) {
                                wallpaperPage.island.isExpanded = false
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: wallpaperPage.wallpaperList.length === 0
                text: "No wallpapers found in ~/Pictures or ~/Wallpapers"
                color: "#444444"
                font.pixelSize: 11
                font.family: "JetBrainsMono Nerd Font"
            }
        }
    }
}
