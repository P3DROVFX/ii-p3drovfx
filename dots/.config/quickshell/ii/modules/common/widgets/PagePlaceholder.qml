import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property bool shown: true
    property alias icon: shapeWidget.text
    property alias iconSize: shapeWidget.iconSize
    property alias iconPadding: shapeWidget.padding
    property alias title: widgetNameText.text
    property alias description: widgetDescriptionText.text
    property alias shape: shapeWidget.shape
    property alias descriptionHorizontalAlignment: widgetDescriptionText.horizontalAlignment
    property bool animateIconOnShow: false
    // Touch hosts render the same placeholder larger without forking it.
    property real sizeScale: 1.0
    property real titlePixelSize: Appearance.font.pixelSize.larger
    property real descriptionPixelSize: Appearance.font.pixelSize.small

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

    property int entranceTrigger: -1

    onEntranceTriggerChanged: {
        if (entranceTrigger >= 0 && shown) {
            triggerEntrance();
        }
    }

    onOpacityChanged: {
        if (opacity > 0.9 && animateIconOnShow && !_iconAnimated) {
            _iconAnimated = true;
            triggerEntrance();
        } else if (opacity < 0.1) {
            _iconAnimated = false;
        }
    }

    property bool _iconAnimated: false

    onShownChanged: {
        if (shown && animateIconOnShow) {
            triggerEntrance();
        }
    }

    property real rippleProgress: 0.0

    function triggerEntrance() {
        iconEntranceAnim.stop();
        
        // Reset sub-element animation states before starting
        shapeWidget.scale = 0.2;
        iconRotation.angle = -45;
        iconBlur.radius = 30;
        
        root.rippleProgress = 0.0;
        
        widgetNameTextTranslate.y = 30;
        widgetNameTextContainer.opacity = 0.0;
        
        descTranslate.x = -15;
        descBlur.radius = 12;
        widgetDescriptionText.opacity = 0.0;

        iconEntranceAnim.start();
    }

    SequentialAnimation {
        id: iconEntranceAnim
        ScriptAction {
            script: {
                iconBlur.enabled = true;
                descBlur.enabled = true;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: shapeWidget
                property: "scale"
                from: 0.2
                to: 1.15
                duration: 450
                easing.type: Easing.OutBack
            }
            NumberAnimation {
                target: iconRotation
                property: "angle"
                from: -45
                to: 0
                duration: 600
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: iconBlur
                property: "radius"
                from: 30
                to: 0
                duration: 500
                easing.type: Easing.OutCubic
            }
        }
        NumberAnimation {
            target: shapeWidget
            property: "scale"
            to: 1.0
            duration: 150
            easing.type: Easing.InOutCubic
        }
        ParallelAnimation {
            // Radial wave ripple animation (Lockscreen style)
            NumberAnimation {
                target: root
                property: "rippleProgress"
                from: 0.0
                to: 1.0
                duration: 650
                easing.type: Easing.OutQuart
            }
            // Title reveal (text translate up inside clip)
            NumberAnimation {
                target: widgetNameTextTranslate
                property: "y"
                from: 30
                to: 0
                duration: 500
                easing.type: Easing.OutExpo
            }
            NumberAnimation {
                target: widgetNameTextContainer
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: 400
                easing.type: Easing.OutCubic
            }
            // Description reveal (drift horizontal + blur)
            NumberAnimation {
                target: descTranslate
                property: "x"
                from: -15
                to: 0
                duration: 500
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: descBlur
                property: "radius"
                from: 12
                to: 0
                duration: 450
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: widgetDescriptionText
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: 400
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction {
            script: {
                iconBlur.enabled = false;
                descBlur.enabled = false;
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

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: shapeWidget.implicitWidth
            implicitHeight: shapeWidget.implicitHeight

            Item {
                id: rippleContainer
                anchors.centerIn: parent
                width: shapeWidget.width * 2.5
                height: shapeWidget.height * 2.5

                Rectangle {
                    id: rippleWave1
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: width / 2
                    color: Appearance.colors.colPrimary
                    opacity: (1.0 - root.rippleProgress) * 0.4
                    scale: root.rippleProgress
                }

                Rectangle {
                    id: rippleWave2
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: width / 2
                    color: "transparent"
                    border.color: Appearance.colors.colPrimary
                    border.width: 3
                    opacity: (1.0 - root.rippleProgress) * 0.8
                    scale: Math.pow(root.rippleProgress, 0.7)
                }
            }

            MaterialShapeWrappedMaterialSymbol {
                id: shapeWidget
                anchors.centerIn: parent
                padding: 12
                iconSize: Math.round(56 * root.sizeScale)
                rotation: -30 * (1 - root.opacity)
                
                // Value holder for the entrance animation. This used to be a
                // real FastBlur just to carry `radius`, which cost every
                // placeholder a shader pass and an offscreen surface it never
                // drew into. The blur that is actually applied is layer.effect.
                QtObject {
                    id: iconBlur
                    property real radius: 0
                    property bool enabled: false
                }

                layer.enabled: iconBlur.radius > 0
                layer.effect: Component {
                    FastBlur {
                        radius: iconBlur.radius
                    }
                }

                transform: Rotation {
                    id: iconRotation
                    origin.x: shapeWidget.width / 2
                    origin.y: shapeWidget.height / 2
                    angle: 0
                }
            }
        }

        Item {
            id: widgetNameTextContainer
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: widgetNameText.implicitWidth
            implicitHeight: widgetNameText.implicitHeight
            clip: true
            visible: title !== ""

            StyledText {
                id: widgetNameText
                anchors.fill: parent
                font {
                    family: Appearance.font.family.title
                    pixelSize: Math.round(root.titlePixelSize * root.sizeScale)
                    variableAxes: Appearance.font.variableAxes.title
                }
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter

                transform: Translate {
                    id: widgetNameTextTranslate
                    y: 0
                }
            }
        }

        StyledText {
            id: widgetDescriptionText
            visible: description !== ""
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            font.pixelSize: Math.round(root.descriptionPixelSize * root.sizeScale)
            color: Appearance.m3colors.m3outline
            horizontalAlignment: root.descriptionHorizontalAlignment ?? Text.AlignHCenter
            wrapMode: Text.Wrap

            QtObject {
                id: descBlur
                property real radius: 0
                property bool enabled: false
            }

            layer.enabled: descBlur.radius > 0
            layer.effect: Component {
                FastBlur {
                    radius: descBlur.radius
                }
            }

            transform: Translate {
                id: descTranslate
                x: 0
            }
        }
    }
}
