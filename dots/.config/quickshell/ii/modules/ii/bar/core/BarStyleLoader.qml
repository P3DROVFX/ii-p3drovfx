import qs
import qs.modules.common
import QtQuick

// Dispatches bar style based on cornerStyle via lazy URL loading so only the
// active style is compiled and instantiated (avoids eagerly compiling all 4
// bar styles, including DynamicIslandStyle, when unused).
Item {
    id: root

    required property bool isDynamicIsland
    required property bool showBarBackground
    required property var activeTheme
    required property var screen
    required property bool isSearchActiveHere
    required property real expectedSearchWidth
    required property real frameThickness
    required property var leftList
    required property var centerList
    required property var rightList

    readonly property int cornerStyle: BarInteraction.cornerStyle

    readonly property real verticalTopOffset: styleLoader.item ? (styleLoader.item.verticalTopOffset ?? 0) : 0
    readonly property real verticalBottomOffset: styleLoader.item ? (styleLoader.item.verticalBottomOffset ?? 0) : 0
    readonly property real islandExtent: styleLoader.item ? (styleLoader.item.islandExtent ?? 0) : 0

    Loader {
        id: styleLoader
        anchors.fill: parent
        source: root.resolveStyleUrl()

        property bool styleSettled: false
        opacity: styleSettled ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onLoaded: {
            styleLoader.styleSettled = false;
            Qt.callLater(() => styleLoader.styleSettled = true);
            item.width = Qt.binding(() => styleLoader.width);
            item.height = Qt.binding(() => styleLoader.height);
            item.showBarBackground = Qt.binding(() => root.showBarBackground);
            item.activeTheme = Qt.binding(() => root.activeTheme);
            item.leftList = Qt.binding(() => root.leftList);
            item.centerList = Qt.binding(() => root.centerList);
            item.rightList = Qt.binding(() => root.rightList);
            if (root.cornerStyle === 3) {
                item.screen = Qt.binding(() => root.screen);
                item.isSearchActiveHere = Qt.binding(() => root.isSearchActiveHere);
                item.expectedSearchWidth = Qt.binding(() => root.expectedSearchWidth);
                item.frameThickness = Qt.binding(() => root.frameThickness);
            }
        }
    }

    function resolveStyleUrl() {
        switch (root.cornerStyle) {
        case 0:
            return Qt.resolvedUrl("../styles/HugStyle.qml");
        case 1:
            return Qt.resolvedUrl("../styles/FloatStyle.qml");
        case 2:
            return Qt.resolvedUrl("../styles/RectStyle.qml");
        case 3:
            return Qt.resolvedUrl("../styles/DynamicIslandStyle.qml");
        case 4:
            return ""; // Notch (futuro)
        default:
            return Qt.resolvedUrl("../styles/HugStyle.qml");
        }
    }
}
