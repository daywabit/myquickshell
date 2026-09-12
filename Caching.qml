pragma Singleton
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string cacheDir: StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/quickshell"

    function getCacheDir(subDir) {
        return subDir ? cacheDir + "/" + subDir : cacheDir
    }

    function getThumbnail(path) {
        return path
    }
}
