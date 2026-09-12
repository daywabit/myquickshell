import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: drawerWindow

    // Keep visible so Wayland receives hover input at the bottom screen edge
    visible: true
    // Prevent Hyprland from reserving space or tiling around this window
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "quickshell-nixpkg-drawer"
    WlrLayershell.layer: WlrLayershell.Overlay

    property bool isOpen: false

    function openDrawer() {
        isOpen = true;
        searchInput.forceActiveFocus();
    }

    function closeDrawer() {
        isOpen = false;
        resultsModel.clear();
        searchInput.text = "";
    }

    anchors {
        bottom: true
    }

    width: 650
    // Dynamic height: 8px hover trigger zone when closed, 420px when active
    height: isOpen ? 420 : 8
    color: "transparent"

    WlrLayershell.keyboardFocus: drawerWindow.isOpen
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    Shortcut {
        sequence: "Escape"
        enabled: drawerWindow.isOpen
        onActivated: drawerWindow.closeDrawer()
    }

    // Process executor to launch the selected package
    Process {
        id: launcherProcess
    }

    function launchPkg(pkgAttr) {
        var parts = pkgAttr.split('.');
        var attrName = parts[parts.length - 1];

        launcherProcess.command = ["sh", "-c", "nix-shell -p " + pkgAttr + " --run " + attrName + " &"];
        launcherProcess.running = true;
        drawerWindow.closeDrawer();
    }

    // Nixpkgs Search Engine
    ListModel {
        id: resultsModel
    }

    Process {
        id: searchProcess
        stdout: SplitParser {
            onRead: data => {
                var line = data.trim();
                if (line.length > 0) {
                    var parts = line.split(/\s+/);
                    var attr = parts[0];
                    resultsModel.append({ "attr": attr });
                }
            }
        }
    }

    function executeSearch() {
        resultsModel.clear();
        if (searchInput.text.trim() === "") return;

        var term = searchInput.text.trim().replace(/'/g, "");
        searchProcess.command = ["sh", "-c", "nix-env -qaP '.*" + term + ".*' 2>/dev/null | head -n 30"];
        searchProcess.running = true;
    }

    // Hover Trigger Zone (Active at bottom edge when drawer is closed)
    MouseArea {
        anchors.fill: parent
        enabled: !drawerWindow.isOpen
        hoverEnabled: true
        onEntered: drawerWindow.openDrawer()
    }

    // Solid Black Container (Visible when open)
    Rectangle {
        anchors.fill: parent
        visible: drawerWindow.isOpen
        color: "#000000"
        radius: 12

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Enlarged Search Input (No borders / highlights)
            TextField {
                id: searchInput
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                font.pixelSize: 18
                color: "#ffffff"
                placeholderText: "Type package name (e.g. hyprland)..."
                placeholderTextColor: "#666666"
                selectByMouse: true

                background: Rectangle {
                    color: "#181818"
                    radius: 8
                    border.width: 0
                }

                onTextChanged: executeSearch()

                onAccepted: {
                    if (resultsModel.count > 0) {
                        var targetIndex = resultsView.currentIndex >= 0 ? resultsView.currentIndex : 0;
                        launchPkg(resultsModel.get(targetIndex).attr);
                    }
                }

                Keys.onDownPressed: {
                    if (resultsView.count > 0) {
                        resultsView.currentIndex = Math.min(resultsView.currentIndex + 1, resultsView.count - 1);
                    }
                }
                Keys.onUpPressed: {
                    if (resultsView.count > 0) {
                        resultsView.currentIndex = Math.max(resultsView.currentIndex - 1, 0);
                    }
                }
            }

            // Search Results List
            ListView {
                id: resultsView
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: resultsModel
                clip: true
                spacing: 4

                delegate: Rectangle {
                    width: resultsView.width
                    height: 42
                    color: ListView.isCurrentItem ? "#222222" : "transparent"
                    radius: 6

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        Text {
                            text: model.attr
                            color: "#ffffff"
                            font.pixelSize: 15
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: resultsView.currentIndex = index
                        onClicked: launchPkg(model.attr)
                    }
                }
            }
        }
    }
}
