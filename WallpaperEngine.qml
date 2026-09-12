import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtMultimedia

ShellRoot {
    id: globalRoot

    Variants {
        id: root
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: barWindow

                required property var modelData
                screen: modelData

                // Wayland Background Layer Shell Configuration
                WlrLayershell.namespace: "wallpaper-bg"
                WlrLayershell.layer: WlrLayer.Background
                focusable: false
                exclusionMode: ExclusionMode.Ignore
                mask: Region {}
                color: "#0a0a0f"

                // Replace "anchors.fill: parent" with this:
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                // Caching & Path Identifiers
                readonly property string wpCacheDir: Caching.getCacheDir("wallpaper")
                readonly property string wpStatePath: wpCacheDir + "/current_" + barWindow.screen.name
                readonly property string wpCopyDir: wpCacheDir + "/copy_" + barWindow.screen.name
                readonly property string wpSnapshotPath: wpCacheDir + "/current_wallpaper.png"
                readonly property string wpMonitorSnapshotPath: wpCacheDir + "/current_wallpaper_" + barWindow.screen.name + ".png"

                property string currentWallpaperPath: ""
                property string originalFileName: ""
                property int activeLayer: 0
                property string pathA: ""
                property bool isVideoA: false
                property string pathB: ""
                property bool isVideoB: false
                property bool playbackPaused: false

                readonly property int transitionDuration: 900
                property real transitionProgress: 1.0
                property bool isPreloading: false

                Component.onCompleted: restorePoller.running = true

                Connections {
                    target: Wallpaper

                    function onWallpaperChanged(screenName, path, transition) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            barWindow.changeWallpaper(path, transition);
                        }
                    }

                    function onPlaybackChanged(screenName, state) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            if (state === "pause") {
                                barWindow.playbackPaused = true;
                                barWindow.stopA();
                                barWindow.stopB();
                            } else if (state === "play") {
                                barWindow.playbackPaused = false;
                                if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                                if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                            }
                        }
                    }

                    function onWallpaperCleared(screenName) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            barWindow.currentWallpaperPath = "";
                            barWindow.pathA = "";
                            barWindow.pathB = "";
                            barWindow.isVideoA = false;
                            barWindow.isVideoB = false;
                            barWindow.stopA();
                            barWindow.stopB();
                        }
                    }
                }

                // State Restoration Poller
                Process {
                    id: restorePoller
                    running: false
                    command: [
                        "bash", "-c",
                        "F1='" + barWindow.wpStatePath + "'; F2='" + barWindow.wpStatePath + "_name'; [ -f \"$F1\" ] && cat \"$F1\" || true; echo '---SPLIT---'; [ -f \"$F2\" ] && cat \"$F2\" || true"
                    ]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let parts = this.text.split("---SPLIT---");
                            let savedPath = parts[0] ? parts[0].trim() : "";
                            let savedName = parts[1] ? parts[1].trim() : "";
                            if (savedPath !== "") {
                                barWindow.originalFileName = savedName;
                                barWindow._loadNew(savedPath, false);
                                if (barWindow.isVideo(savedPath)) {
                                    videoSnapshotProcess.targetPath = savedPath;
                                    videoSnapshotProcess.running = true;
                                }
                            }
                        }
                    }
                }

                Timer {
                    id: videoWarmUpTimer
                    interval: 200
                    repeat: false
                    onTriggered: barWindow.triggerTransition()
                }

                Process {
                    id: videoSnapshotProcess
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || true",
                        "_", targetPath, barWindow.wpSnapshotPath
                    ]
                }

                function isVideo(p) {
                    let lp = p.toLowerCase();
                    return lp.endsWith(".mp4") || lp.endsWith(".mkv") || lp.endsWith(".mov") || lp.endsWith(".webm");
                }

                function playA() { if (videoLoaderA.item && typeof videoLoaderA.item.play === "function") videoLoaderA.item.play(); }
                function stopA() { if (videoLoaderA.item && typeof videoLoaderA.item.stop === "function") videoLoaderA.item.stop(); }
                function playB() { if (videoLoaderB.item && typeof videoLoaderB.item.play === "function") videoLoaderB.item.play(); }
                function stopB() { if (videoLoaderB.item && typeof videoLoaderB.item.stop === "function") videoLoaderB.item.stop(); }

                function triggerTransition() {
                    videoWarmUpTimer.stop();
                    barWindow.isPreloading = false;
                    transitionAnim.restart();
                }

                function _loadNew(path, force) {
                    if (!path || (!force && path === barWindow.currentWallpaperPath)) return;

                    let cleanPath = String(path).trim();
                    let vid = barWindow.isVideo(cleanPath);

                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    barWindow.transitionProgress = 0.0;
                    barWindow.isPreloading = true;

                    if (barWindow.activeLayer === 1) {
                        barWindow.pathA = cleanPath;
                        barWindow.isVideoA = vid;
                        barWindow.activeLayer = 0;
                        if (vid) { barWindow.playA(); videoWarmUpTimer.restart(); }
                        else { barWindow.triggerTransition(); }
                    } else {
                        barWindow.pathB = cleanPath;
                        barWindow.isVideoB = vid;
                        barWindow.activeLayer = 1;
                        if (vid) { barWindow.playB(); videoWarmUpTimer.restart(); }
                        else { barWindow.triggerTransition(); }
                    }

                    barWindow.currentWallpaperPath = cleanPath;
                }

                function changeWallpaper(path, ttype) {
                    if (!path) return;
                    let cleanPath = String(path).trim();
                    let origName = cleanPath.substring(cleanPath.lastIndexOf("/") + 1);

                    Quickshell.execDetached(["bash", "-c",
                        "mkdir -p '" + wpCopyDir + "' && printf '%s' '" + cleanPath + "' > '" + wpStatePath + "' && printf '%s' '" + origName + "' > '" + wpStatePath + "_name'"
                    ]);

                    if (barWindow.isVideo(cleanPath)) {
                        videoSnapshotProcess.targetPath = cleanPath;
                        videoSnapshotProcess.running = true;
                    }

                    barWindow._loadNew(cleanPath, true);
                }

                PropertyAnimation {
                    id: transitionAnim
                    target: barWindow
                    property: "transitionProgress"
                    from: 0.0
                    to: 1.0
                    duration: barWindow.transitionDuration
                    easing.type: Easing.InOutCubic

                    onFinished: {
                        if (barWindow.activeLayer === 0) {
                            barWindow.stopB();
                            barWindow.pathB = "";
                            barWindow.isVideoB = false;
                        } else {
                            barWindow.stopA();
                            barWindow.pathA = "";
                            barWindow.isVideoA = false;
                        }
                    }
                }

                // Dual-Layer Scene
                Item {
                    id: scene
                    anchors.fill: parent
                    clip: true

                    // Layer A
                    Item {
                        id: layerA
                        anchors.fill: parent
                        readonly property bool isIncoming: barWindow.activeLayer === 0
                        readonly property real p: barWindow.transitionProgress
                        z: isIncoming ? 2 : 1
                        visible: isIncoming || p < 1.0
                        opacity: (barWindow.isPreloading && isIncoming) ? 0.0 : (isIncoming ? p : 1.0 - p)

                        Image {
                            anchors.fill: parent
                            source: !barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoA && barWindow.pathA !== ""
                        }

                        Loader {
                            id: videoLoaderA
                            anchors.fill: parent
                            active: barWindow.isVideoA && barWindow.pathA !== ""
                            sourceComponent: Component {
                                Item {
                                    anchors.fill: parent
                                    function play() { playerA.play(); }
                                    function stop() { playerA.stop(); }
                                    MediaPlayer {
                                        id: playerA
                                        source: barWindow.isVideoA && barWindow.pathA ? "file://" + barWindow.pathA : ""
                                        videoOutput: videoOutA
                                        loops: MediaPlayer.Infinite
                                    }
                                    VideoOutput { id: videoOutA; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
                                }
                            }
                        }
                    }

                    // Layer B
                    Item {
                        id: layerB
                        anchors.fill: parent
                        readonly property bool isIncoming: barWindow.activeLayer === 1
                        readonly property real p: barWindow.transitionProgress
                        z: isIncoming ? 2 : 1
                        visible: isIncoming || p < 1.0
                        opacity: (barWindow.isPreloading && isIncoming) ? 0.0 : (isIncoming ? p : 1.0 - p)

                        Image {
                            anchors.fill: parent
                            source: !barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoB && barWindow.pathB !== ""
                        }

                        Loader {
                            id: videoLoaderB
                            anchors.fill: parent
                            active: barWindow.isVideoB && barWindow.pathB !== ""
                            sourceComponent: Component {
                                Item {
                                    anchors.fill: parent
                                    function play() { playerB.play(); }
                                    function stop() { playerB.stop(); }
                                    MediaPlayer {
                                        id: playerB
                                        source: barWindow.isVideoB && barWindow.pathB ? "file://" + barWindow.pathB : ""
                                        videoOutput: videoOutB
                                        loops: MediaPlayer.Infinite
                                    }
                                    VideoOutput { id: videoOutB; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
