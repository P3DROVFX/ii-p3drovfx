import qs.modules.ii.bar.styles
import qs
import qs.modules.common
import QtQuick

// Dispatches bar style based on cornerStyle.
// To add a new bar style: create XxxStyle.qml in bar/styles/ and add a case here.
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

    readonly property int cornerStyle: Config.options.bar.cornerStyle

    readonly property real verticalTopOffset: styleLoader.item ? (styleLoader.item.verticalTopOffset ?? 0) : 0
    readonly property real verticalBottomOffset: styleLoader.item ? (styleLoader.item.verticalBottomOffset ?? 0) : 0

    Loader {
        id: styleLoader
        anchors.fill: parent
        sourceComponent: resolveStyle()

        onLoaded: {
            console.log("[BarStyleLoader] onLoaded triggered for style: " + root.cornerStyle + " item: " + item + " Loader size: " + styleLoader.width + "x" + styleLoader.height);
            item.width = Qt.binding(() => styleLoader.width);
            item.height = Qt.binding(() => styleLoader.height);
            console.log("[BarStyleLoader] item size after bind: " + item.width + "x" + item.height);
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

    function resolveStyle() {
        switch (root.cornerStyle) {
        case 0:
            return hugStyle;
        case 1:
            return floatStyle;
        case 2:
            return rectStyle;
        case 3:
            return diStyle;
        case 4:
            return null; // Notch (futuro)
        default:
            return hugStyle;
        }
    }

    Component {
        id: hugStyle
        HugStyle {}
    }
    Component {
        id: floatStyle
        FloatStyle {}
    }
    Component {
        id: rectStyle
        RectStyle {}
    }

    Component {
        id: diStyle
        DynamicIslandStyle {
            screen: root.screen
            showBarBackground: root.showBarBackground
            isSearchActiveHere: root.isSearchActiveHere
            expectedSearchWidth: root.expectedSearchWidth
            frameThickness: root.frameThickness
            leftList: root.leftList
            centerList: root.centerList
            rightList: root.rightList
            activeTheme: root.activeTheme
        }
    }
}
