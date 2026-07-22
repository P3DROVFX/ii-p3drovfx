import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property bool shown: true
    property alias icon: shapeWidget.text
    property alias title: widgetNameText.text
    property alias description: widgetDescriptionText.text
    property alias shape: shapeWidget.shape
    property alias descriptionHorizontalAlignment: widgetDescriptionText.horizontalAlignment
    property bool animateIconOnShow: false

    opacity: shown ? 1 : 0
    visible: opacity > 0
    anchors {
        fill: parent
        topMargin: -30 * (1 - opacity)
        bottomMargin: 30 * (1 - opacity)
    }

    Behavior on opacity {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    onOpacityChanged: {
        if (opacity > 0.9 && animateIconOnShow && !_iconAnimated) {
            _iconAnimated = true;
            iconEntranceAnim.start();
        } else if (opacity < 0.1) {
            _iconAnimated = false;
        }
    }

    property bool _iconAnimated: false

    onShownChanged: {
        if (shown && animateIconOnShow) {
            iconEntranceAnim.start();
        }
    }

    SequentialAnimation {
        id: iconEntranceAnim
        ParallelAnimation {
            NumberAnimation {
                target: shapeWidget
                property: "scale"
                from: 0.3
                to: 1.0
                duration: 500
                easing.type: Easing.OutBack
            }
            NumberAnimation {
                target: iconRotation
                property: "angle"
                from: -360
                to: 0
                duration: 600
                easing.type: Easing.OutCubic
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 5

        MaterialShapeWrappedMaterialSymbol {
            id: shapeWidget
            Layout.alignment: Qt.AlignHCenter
            padding: 12
            iconSize: 56
            rotation: -30 * (1 - root.opacity)
            
            transform: Rotation {
                id: iconRotation
                origin.x: shapeWidget.width / 2
                origin.y: shapeWidget.height / 2
                angle: 0
            }
        }
        StyledText {
            id: widgetNameText
            visible: title !== ""
            Layout.alignment: Qt.AlignHCenter
            font {
                family: Appearance.font.family.title
                pixelSize: Appearance.font.pixelSize.larger
                variableAxes: Appearance.font.variableAxes.title
            }
            color: Appearance.m3colors.m3outline
            horizontalAlignment: Text.AlignHCenter
        }
        StyledText {
            id: widgetDescriptionText
            visible: description !== ""
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.m3colors.m3outline
            horizontalAlignment: root.descriptionHorizontalAlignment ?? Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
