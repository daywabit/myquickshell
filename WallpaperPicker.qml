import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Qt.labs.folderlistmodel
import QtMultimedia
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Item {
    id: window
    width: Screen.width
    height: Screen.height
    focus: true

    // Visual Scaling Metric
    function s(val) { return val * (Screen.height / 1080); }

    property string currentFilter: "All"
    property string targetWallName: ""
    property string srcDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    readonly property real itemWidth: window.s(380)
    readonly property real itemHeight: window.s(410)
    readonly property real skewFactor: -0.35
    readonly property real selectedCenterOffset: (window.skewFactor * window.itemHeight) / 2

    // Adjusted expansion multipliers to prevent overlapping adjacent cards
    readonly property real selectedWidthMultiplier: 1.15
    readonly property real unselectedWidthMultiplier: 0.55

    // Filter Navigation Data
    readonly property var filterData: [
        { name: "All", label: "All" },
        { name: "History", label: "History" },
        { name: "Video", label: "Video" },
        { name: "Red", hex: "#FF4500" },
        { name: "Orange", hex: "#FFA500" },
        { name: "Yellow", hex: "#FFD700" },
        { name: "Green", hex: "#32CD32" },
        { name: "Blue", hex: "#1E90FF" },
        { name: "Purple", hex: "#8A2BE2" },
        { name: "Monochrome", hex: "#A9A9A9" }
    ]

    ListModel { id: displayModel }

    FolderListModel {
        id: srcModel
        folder: "file://" + window.srcDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.mp4", "*.mkv", "*.webm"]
        showDirs: false
        onStatusChanged: {
            if (status === FolderListModel.Ready) window.syncModel();
        }
    }

    function syncModel() {
        displayModel.clear();
        for (let i = 0; i < srcModel.count; i++) {
            let fn = srcModel.get(i, "fileName");
            let fu = srcModel.get(i, "fileUrl");
            if (!fn) continue;
            let isVid = fn.match(/\.(mp4|mkv|webm)$/i) !== null;
            displayModel.append({
                "fileName": fn,
                "fileUrl": String(fu),
                "isVideo": isVid
            });
        }
    }

    function applyWallpaper(fileName) {
        if (!fileName) return;
        let path = window.srcDir + "/" + fileName;
        Wallpaper.setWallpaper("all", path, "fade");
    }

    function stepIndex(dir) {
        let nextIdx = view.currentIndex + dir;
        if (nextIdx >= 0 && nextIdx < displayModel.count) {
            view.currentIndex = nextIdx;
        }
    }

    // Key Bindings
    Shortcut { sequence: "Left"; onActivated: window.stepIndex(-1) }
    Shortcut { sequence: "Right"; onActivated: window.stepIndex(1) }
    Shortcut {
        sequence: "Return"
        onActivated: {
            if (view.currentIndex >= 0 && view.currentIndex < displayModel.count) {
                window.applyWallpaper(displayModel.get(view.currentIndex).fileName);
            }
        }
    }

    // Central Parallelogram Skew Carousel
    ListView {
        id: view
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: 0
        clip: false
        focus: true

        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width / 2) - ((window.itemWidth * window.selectedWidthMultiplier) / 2) + window.selectedCenterOffset
        preferredHighlightEnd: (width / 2) + ((window.itemWidth * window.selectedWidthMultiplier) / 2) + window.selectedCenterOffset
        highlightMoveDuration: 350

        header: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * window.selectedWidthMultiplier) / 2) + window.selectedCenterOffset) }
        footer: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * window.selectedWidthMultiplier) / 2) - window.selectedCenterOffset) }
        model: displayModel

        delegate: Item {
            id: delegateRoot
            readonly property bool isCurrent: ListView.isCurrentItem
            readonly property int dist: Math.abs(index - view.currentIndex)
            readonly property real sideScale: Math.max(0.65, Math.pow(0.88, Math.max(0, dist - 1)))

            readonly property real cellWidth: isCurrent ? (window.itemWidth * window.selectedWidthMultiplier) : (window.itemWidth * window.unselectedWidthMultiplier * sideScale)
            readonly property real targetHeight: isCurrent ? (window.itemHeight + window.s(10)) : (window.itemHeight * Math.max(0.70, Math.pow(0.90, dist)))

            width: cellWidth
            height: targetHeight
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: window.s(20)
            z: isCurrent ? 100 : Math.max(1, 50 - dist)

            Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

            // Outer Skew Container
            Item {
                id: skewedWrapper
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                anchors.horizontalCenterOffset: -(window.skewFactor * height) / 2

                // Apply Parallelogram Shear Matrix
                transform: Matrix4x4 {
                    property real s: window.skewFactor
                    matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        view.currentIndex = index;
                        window.applyWallpaper(model.fileName);
                    }
                }

                // Inner Clipping Frame with Surface Border
                Rectangle {
                    anchors.fill: parent
                    radius: window.s(16)
                    color: "#181825"
                    border.color: isCurrent ? "#cba6f7" : "#313244"
                    border.width: isCurrent ? window.s(2) : 1
                    clip: true

                    // Counter-Skewed Artwork Layer
                    Image {
                        id: paperImage
                        anchors.centerIn: parent
                        width: (window.itemWidth * 1.6) + (window.itemHeight * Math.abs(window.skewFactor))
                        height: window.itemHeight + window.s(40)
                        fillMode: Image.PreserveAspectCrop
                        source: !model.isVideo ? model.fileUrl : ""
                        asynchronous: true
                        visible: !model.isVideo

                        // Invert Skew Matrix (+0.35) for Un-Distorted Artwork Rendering
                        transform: Matrix4x4 {
                            property real s: -window.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }

                    // Video Playback Indicator
                    Rectangle {
                        visible: model.isVideo
                        anchors.centerIn: parent
                        width: window.s(48); height: window.s(48)
                        radius: window.s(24)
                        color: Qt.rgba(0, 0, 0, 0.6)

                        Text {
                            anchors.centerIn: parent
                            text: "▶"
                            color: "#cdd6f4"
                            font.pixelSize: window.s(18)
                        }

                        transform: Matrix4x4 {
                            property real s: -window.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }
                }
            }
        }
    }

    // Top Floating Filter Bar
    Rectangle {
        id: filterBar
        anchors.top: parent.top
        anchors.topMargin: window.s(50)
        anchors.horizontalCenter: parent.horizontalCenter
        height: window.s(48)
        width: filterRow.width + window.s(24)
        radius: window.s(16)
        color: Qt.rgba(17/255, 17/255, 27/255, 0.88)
        border.color: "#313244"
        border.width: 1
        z: 200

        Row {
            id: filterRow
            anchors.centerIn: parent
            spacing: window.s(8)

            Repeater {
                model: window.filterData
                delegate: Rectangle {
                    width: modelData.hex ? window.s(32) : filterText.implicitWidth + window.s(20)
                    height: window.s(32)
                    radius: window.s(10)
                    color: modelData.hex ? modelData.hex : (window.currentFilter === modelData.name ? "#313244" : "#1e1e2e")
                    border.color: window.currentFilter === modelData.name ? "#cba6f7" : "transparent"
                    border.width: window.currentFilter === modelData.name ? 1.5 : 0

                    Text {
                        id: filterText
                        visible: !modelData.hex
                        anchors.centerIn: parent
                        text: modelData.label || ""
                        color: window.currentFilter === modelData.name ? "#cdd6f4" : "#a6adc8"
                        font.pixelSize: window.s(12)
                        font.bold: window.currentFilter === modelData.name
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.currentFilter = modelData.name
                    }
                }
            }
        }
    }
}
