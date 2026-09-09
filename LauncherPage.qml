import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: launcherRoot

    property var parentSwipeView
    property var island

    property string query: searchField.text.trim().toLowerCase()

    function focusSearch() {
        searchField.forceActiveFocus()
        searchField.selectAll()
    }

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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // --- Search Field ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: "#161618"
            radius: 10
            border.color: searchField.activeFocus ? "#ffffff" : "#1affffff"
            border.width: 1

            Behavior on border.color { ColorAnimation { duration: 180 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: "󰍉"
                    color: searchField.activeFocus ? "#ffffff" : "#66ffffff"
                    font.pixelSize: 13
                    font.family: "JetBrainsMono Nerd Font"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search applications..."
                    placeholderTextColor: "#55ffffff"
                    color: "white"
                    font.pixelSize: 12
                    font.family: "JetBrainsMono Nerd Font"
                    background: null
                    selectByMouse: true

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Down) {
                            if (appListView.count > 0) {
                                appListView.currentIndex = Math.min(appListView.currentIndex + 1, appListView.count - 1)
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Up) {
                            if (appListView.count > 0) {
                                appListView.currentIndex = Math.max(appListView.currentIndex - 1, 0)
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (launcherRoot.appList.length > 0 && appListView.currentIndex >= 0) {
                                var selectedApp = launcherRoot.appList[appListView.currentIndex]
                                if (selectedApp && selectedApp.execute) {
                                    selectedApp.execute()
                                    searchField.text = ""
                                    if (launcherRoot.island) {
                                        launcherRoot.island.isExpanded = false
                                    }
                                }
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            if (searchField.text.length > 0) {
                                searchField.text = ""
                            } else if (launcherRoot.island) {
                                launcherRoot.island.isExpanded = false
                            }
                            event.accepted = true
                        }
                    }

                    onTextChanged: appListView.currentIndex = 0
                }

                Text {
                    visible: searchField.text.length > 0
                    text: "✕"
                    color: "#88ffffff"
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            searchField.text = ""
                            launcherRoot.focusSearch()
                        }
                    }
                }
            }
        }

        // --- App List View ---
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

                readonly property bool isFocused: ListView.isCurrentItem

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: isFocused ? "#25ffffff" : (itemMouse.containsMouse ? "#12ffffff" : "transparent")
                    border.color: isFocused ? "#33ffffff" : "transparent"
                    border.width: isFocused ? 1 : 0

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22

                            Image {
                                anchors.fill: parent
                                sourceSize: Qt.size(22, 22)
                                source: Quickshell.iconPath(modelData.icon || "application-x-executable", true)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || ""
                                color: isFocused ? "#ffffff" : "#ddffffff"
                                font.pixelSize: 12
                                font.bold: isFocused
                                font.family: "JetBrainsMono Nerd Font"
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (modelData.comment || modelData.genericName || "").length > 0
                                text: modelData.comment || modelData.genericName || ""
                                color: "#88ffffff"
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
                        onEntered: appListView.currentIndex = index
                        onClicked: {
                            if (modelData && modelData.execute) {
                                modelData.execute()
                                searchField.text = ""
                                if (launcherRoot.island) {
                                    launcherRoot.island.isExpanded = false
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
                color: "#44ffffff"
                font.pixelSize: 12
                font.family: "JetBrainsMono Nerd Font"
            }
        }
    }
}
