import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Image {
    asynchronous: !source.toString().startsWith("image://icon/")
    retainWhileLoading: true
    mipmap: true
    smooth: true
    visible: opacity > 0
    opacity: (status === Image.Ready) ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    property list<string> fallbacks: []
    property int currentFallbackIndex: 0

    onStatusChanged: {
        if (status === Image.Error && currentFallbackIndex < fallbacks.length) {
            source = fallbacks[currentFallbackIndex];
            currentFallbackIndex += 1;
        }
    }

    sourceSize: {
        if (width === 0 || height === 0) return Qt.size(1, 1);
        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        return Qt.size(width * dpr, height * dpr);
    }
}
