import qs.modules.common.widgets
import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string text: ""
    property string icon
    property alias value: spinBoxWidget.value
    property alias stepSize: spinBoxWidget.stepSize
    property alias from: spinBoxWidget.from
    property alias to: spinBoxWidget.to

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + 32

    color: Appearance.colors.colLayer2Base

    HoverHandler {
        id: hoverHandler
    }
    property bool hovered: hoverHandler.hovered

    readonly property int itemIndex: {
        var p = parent;
        if (!p)
            return 0;
        var idx = 0;
        for (var i = 0; i < p.children.length; ++i) {
            if (p.children[i] === root)
                return idx;
            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                idx++;
        }
        return 0;
    }

    readonly property int totalItems: {
        var p = parent;
        if (!p)
            return 1;
        var count = 0;
        for (var i = 0; i < p.children.length; ++i) {
            if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined")
                count++;
        }
        return count;
    }

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1

    topLeftRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
    topRightRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
    bottomLeftRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
    bottomRightRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall

    HighlightOverlay {
        id: highlightOverlay
        anchors.fill: parent
        radius: Math.max(root.topLeftRadius, root.bottomLeftRadius)
    }

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Loader {
            active: root.icon && root.icon.length > 0
            visible: active
            Layout.alignment: Qt.AlignVCenter
            opacity: root.enabled ? 1 : 0.4

            sourceComponent: MaterialShapeWrappedMaterialSymbol {
                text: root.icon
                readonly property bool isActive: spinBoxWidget.activeFocus || spinBoxWidget.up.pressed || spinBoxWidget.down.pressed
                shape: isActive ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Circle
                iconSize: 18
                padding: 6
                color: isActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                colSymbol: isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3

                Behavior on color {
                    ColorAnimation {
                        duration: 250
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on colSymbol {
                    ColorAnimation {
                        duration: 250
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }

        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnLayer2
            opacity: root.enabled ? 1 : 0.4
        }

        StyledSpinBox {
            id: spinBoxWidget
            Layout.fillWidth: false
        }
    }
}
