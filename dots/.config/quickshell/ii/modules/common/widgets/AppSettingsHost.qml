import QtQuick
import qs.modules.common

/**
 * Shows an app's settings page over its content (design doc §8.2, page over
 * page): a 0→1 `progress` drives opacity and a short rise. The page is built
 * on demand from `source` while `open`, and released once it has faded out.
 * Bind the covered content's opacity to `1 - progress` and its `enabled` to
 * `!open`. The page's `goBack()` signal closes it.
 */
Item {
    id: root

    property bool open: false
    property url source: ""
    readonly property alias item: loader.item

    property url _shownSource: ""
    property real progress: root.open ? 1 : 0

    signal closeRequested()

    Behavior on progress {
        enabled: !Appearance.reducedMotion
        NumberAnimation {
            duration: root.open ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
        }
    }

    onOpenChanged: if (root.open) root._shownSource = root.source
    onSourceChanged: if (root.open) root._shownSource = root.source
    onProgressChanged: if (root.progress === 0 && !root.open) root._shownSource = ""

    visible: root.progress > 0
    opacity: root.progress
    transform: Translate {
        y: (1 - root.progress) * 32
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: String(root._shownSource).length > 0
        source: root._shownSource
        onLoaded: item.forceActiveFocus()

        Connections {
            target: loader.item
            ignoreUnknownSignals: true
            function onGoBack() {
                root.closeRequested();
            }
        }
    }
}
