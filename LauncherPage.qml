import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: launcherRoot
    property var parentSwipeView
    property bool isCurrentPage: parentSwipeView && parentSwipeView.currentIndex === 3

    property string query: searchField.text.trim().toLowerCase()

    property var appList: {
        if (!DesktopEntries.applications || !DesktopEntries.applications.values) return []

        const allEntries = [...DesktopEntries.applications.values]
            .filter(d => d && d.name && !d.noDisplay)
            .sort((a, b) => a.name.localeCompare(b.name))

        if (query === "") return allEntries

        return allEntries.filter(d => {
            const name = (d.name || "").toLowerCase()
            const comment = (d.comment || "").toLowerCase()
            const generic = (d.genericName || "").toLowerCase()
            return name.includes(query) || comment.includes(query) || generic.includes(query)
        })
    }

    onIsCurrentPageChanged: {
        if (isCurrentPage) {
            searchField.forceActiveFocus()
        }
    }

    // Capture ESC key pressed inside the Launcher to collapse back to island mode
    Keys.onEscapePressed: {
        if (parentSwipeView) {
            parentSwipeView.currentIndex = 0
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Search Bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            color: "#141414"
            radius: 10
            border.width: 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search applications..."
                    placeholderTextColor: "#555555"
                    color: "white"
                    font.pixelSize: 12
                    font.family: "JetBrainsMono Nerd Font"
                    background: null
                    selectByMouse: true

                    Keys.onEscapePressed: {
                        if (searchField.text.length > 0) {
                            searchField.text = ""
                        } else if (launcherRoot.parentSwipeView) {
                            launcherRoot.parentSwipeView.currentIndex = 0
                        }
                    }

                    Keys.onReturnPressed: {
                        if (appList.count > 0) {
                            var firstApp = launcherRoot.appList[0]
                            if (firstApp && firstApp.execute) {
                                firstApp.execute()
                                if (launcherRoot.parentSwipeView) {
                                    launcherRoot.parentSwipeView.currentIndex = 0
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: searchField.text.length > 0
                    text: "✕"
                    color: "#888888"
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        onClicked: searchField.text = ""
                    }
                }
            }
        }

        // Caelestia-style Vertical Application List
        ListView {
            id: appListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4

            model: launcherRoot.appList

            delegate: Item {
                width: appListView.width
                height: 38

                Rectangle {
                    anchors.fill: parent
                    color: itemMouse.containsMouse ? "#1e1e1e" : "transparent"
                    radius: 8

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10

                        // Fixed explicit dimensions to solve 'qt.svg.draw: buffer size too big'
                        Item {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22

                            IconImage {
                                anchors.fill: parent
                                source: Quickshell.iconPath(modelData.icon || "application-x-executable", true)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || ""
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "JetBrainsMono Nerd Font"
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (modelData.comment || modelData.genericName || "").length > 0
                                text: modelData.comment || modelData.genericName || ""
                                color: "#777777"
                                font.pixelSize: 9
                                font.family: "JetBrainsMono Nerd Font"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (modelData && modelData.execute) {
                                modelData.execute()
                                if (launcherRoot.parentSwipeView) {
                                    launcherRoot.parentSwipeView.currentIndex = 0
                                }
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: appListView.count === 0
                text: "No applications found"
                color: "#444444"
                font.pixelSize: 12
                font.family: "JetBrainsMono Nerd Font"
            }
        }
    }
}
