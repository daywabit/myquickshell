pragma Singleton
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string wallpaperDir: StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/Wallpapers"
    property string currentWallpaper: ""
    property bool isMuted: false

    signal wallpaperChanged(string screenName, string path, string transition)
    signal playbackChanged(string screenName, string state)
    signal wallpaperCleared(string screenName)

    function setWallpaper(screenName, path, transition) {
        currentWallpaper = path
        wallpaperChanged(screenName, path, transition)
    }

    function clearWallpaper(screenName) {
        currentWallpaper = ""
        wallpaperCleared(screenName)
    }
}
