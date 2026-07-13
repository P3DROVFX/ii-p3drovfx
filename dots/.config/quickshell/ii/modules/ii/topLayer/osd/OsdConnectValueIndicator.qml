pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    // Core properties
    required property real value
    required property string icon
    required property string name
    property var shape
    property bool rotateIcon: false
    property bool scaleIcon: false
    property real maxLimit: 1.0
    property real from: 0.0
    property real to: 1.0
    property bool useProgressBar: false
    property int stepCount: 0

    signal valueUpdateRequested(real newValue)

    // Customization Variables
    property int osdWidth: 380
    property int osdHeight: 72
    property int osdSpacing: 15
    property int outerMarginLeft: 32
    property int outerMarginRight: 32

    // Left & Right shapes configurations
    property int shapeIconSize: Appearance.font.pixelSize.huge
    property int shapePadding: 8
    property int shapeSize: shapeIconSize + shapePadding * 2 + 12
    property color shapeBgColorNormal: Appearance.colors.colSurfaceContainerHighest
    property color shapeBgColorError: Appearance.colors.colErrorContainer
    property color shapeSymbolColorNormal: Appearance.colors.colOnSurfaceVariant
    property color shapeSymbolColorError: Appearance.m3colors.m3onErrorContainer
    property int rotationDuration: 350

    // Slider container configurations
    property color sliderBgColor: Appearance.colors.colSurfaceContainerHighest
    property int sliderPadding: 2
    property int sliderCornerRadius: Appearance.rounding.small
    property color sliderBorderColor: "transparent"
    property int sliderBorderWidth: 0

    // Slider vertical lines configurations
    property int lineWidth: 3
    property int lineGap: 5
    property int lineVerticalPadding: 6
    property int lineCornerRadius: 2
    property color lineColor: Appearance.colors.colOnSurfaceVariant
    property int slideMultiplier: 50 // Map 100% to 100 line steps for 1% alignment snapping
    property bool snapToLines: true

    // Mask Fade (Gradients) configurations
    property real maskEdgePosition: 0.0
    property real maskCenterPosition: 0.5
    property color maskEdgeColor: "transparent"
    property color maskCenterColor: "black"

    // Slide Animations configurations
    property int slideAnimationDuration: Appearance.animation.elementMove.duration
    property int slideAnimationEasingType: Appearance.animation.elementMove.type
    property var slideAnimationBezierCurve: Appearance.animation.elementMove.bezierCurve

    // Math Calculations
    readonly property real normalizedValue: (to > from) ? Math.max((value - from) / (to - from), 0.0) : Math.max(value, 0.0)
    readonly property real maxAllowedValue: Math.max(1.5, root.maxLimit)
    readonly property real targetValue: snapToLines ? Math.round(normalizedValue * slideMultiplier) / slideMultiplier : normalizedValue

    property real animatedValue: targetValue
    Behavior on animatedValue {
        NumberAnimation {
            duration: root.slideAnimationDuration
            easing.type: root.slideAnimationEasingType
            easing.bezierCurve: root.slideAnimationBezierCurve
        }
    }

    // Dynamic line count to populate the viewport based on maxAllowedValue (e.g. 1.5 or 150%)
    readonly property int visibleHalfLines: Math.ceil((linesContainer.width / 2) / (lineWidth + lineGap))
    readonly property int baseLineIndex: visibleHalfLines
    readonly property int lineCount: 2 * visibleHalfLines + Math.ceil(maxAllowedValue * slideMultiplier) + 1

    implicitWidth: root.osdWidth
    implicitHeight: root.osdHeight

    RowLayout {
        id: valueRow
        anchors.fill: parent
        anchors.leftMargin: root.outerMarginLeft
        anchors.rightMargin: root.outerMarginRight
        spacing: root.osdSpacing

        // Left Part: MaterialShape with icon and rotation animation
        MaterialShapeWrappedMaterialSymbol {
            id: leftShape
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.shapeSize
            Layout.preferredHeight: root.shapeSize
            iconSize: root.shapeIconSize
            padding: root.shapePadding
            shape: root.shape
            text: root.icon
            rotation: root.rotateIcon ? root.value * 360 : 0
            color: root.value > root.maxLimit ? root.shapeBgColorError : root.shapeBgColorNormal
            colSymbol: root.value > root.maxLimit ? root.shapeSymbolColorError : root.shapeSymbolColorNormal

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on colSymbol { ColorAnimation { duration: 150 } }
            Behavior on rotation {
                NumberAnimation {
                    duration: root.rotationDuration
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.5
                }
            }
        }

        // Middle Part: Custom slider with dynamic sliding lines & opacity mask
        Rectangle {
            id: sliderContainer
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: root.shapeSize
            Layout.alignment: Qt.AlignVCenter
            Layout.topMargin: root.sliderPadding
            Layout.bottomMargin: root.sliderPadding
            
            color: root.sliderBgColor
            radius: root.sliderCornerRadius
            border.color: root.sliderBorderColor
            border.width: root.sliderBorderWidth

            Item {
                id: linesContainer
                anchors.fill: parent
                anchors.margins: root.sliderPadding
                clip: true
                visible: !root.useProgressBar

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: maskSourceItem
                }

                Item {
                    id: slidingTrack
                    width: linesRow.width
                    height: parent.height
                    
                    x: {
                        if (linesContainer.width <= 0) return 0;
                        const viewportCenter = linesContainer.width / 2;
                        const middleLineX = root.baseLineIndex * (root.lineWidth + root.lineGap) + (root.lineWidth / 2);
                        const basePos = viewportCenter - middleLineX;
                        const slideAmount = root.animatedValue * root.slideMultiplier * (root.lineWidth + root.lineGap);
                        return basePos - slideAmount;
                    }

                    Row {
                        id: linesRow
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height - (2 * root.lineVerticalPadding)
                        spacing: root.lineGap

                        Repeater {
                            model: root.lineCount
                            delegate: Rectangle {
                                width: root.lineWidth
                                height: parent.height
                                radius: root.lineCornerRadius
                                color: root.lineColor
                            }
                        }
                    }
                }
            }

            Item {
                id: maskSourceItem
                anchors.fill: linesContainer
                visible: false

                LinearGradient {
                    anchors.fill: parent
                    start: Qt.point(0, 0)
                    end: Qt.point(parent.width, 0)
                    gradient: Gradient {
                        GradientStop { position: root.maskEdgePosition; color: root.maskEdgeColor }
                        GradientStop { position: root.maskCenterPosition; color: root.maskCenterColor }
                        GradientStop { position: 1.0 - root.maskEdgePosition; color: root.maskEdgeColor }
                    }
                }
            }

            // Progress Bar Fill
            Rectangle {
                id: progressFill
                visible: root.useProgressBar
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: root.sliderPadding
                width: Math.max(0, (parent.width - 2 * root.sliderPadding) * root.animatedValue)
                radius: root.sliderCornerRadius
                color: root.value > root.maxLimit ? root.shapeBgColorError : Appearance.colors.colPrimary

                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        // Right Part: MaterialShape with numeric value representation (no rotation)
        MaterialShape {
            id: rightShape
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.shapeSize
            Layout.preferredHeight: root.shapeSize
            implicitSize: root.shapeSize
            shape: root.shape
            color: leftShape.color
            
            StyledText {
                anchors.centerIn: parent
                text: Math.round(root.normalizedValue * 100)
                color: leftShape.colSymbol
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.main
                font.bold: true
            }
        }
    }

    MouseArea {
        id: mouseHandler
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        property real dragStartX: 0
        property real dragStartValue: 0

        onPressed: (mouse) => {
            dragStartX = mouse.x;
            dragStartValue = root.value;
            GlobalStates.osdInteraction();
        }

        onPositionChanged: (mouse) => {
            if (pressed) {
                let deltaX = mouse.x - dragStartX;
                let range = root.to - root.from;
                let newValue = dragStartValue + (deltaX / sliderContainer.width) * range;
                newValue = Math.max(root.from, Math.min(root.maxLimit, newValue));
                root.valueUpdateRequested(newValue);
                GlobalStates.osdInteraction();
            }
        }

        onWheel: (event) => {
            let delta = event.angleDelta.y || event.angleDelta.x;
            if (delta === 0) return;
            let step = 0.02 * (root.to - root.from);
            let newValue = root.value + (delta > 0 ? step : -step);
            newValue = Math.max(root.from, Math.min(root.maxLimit, newValue));
            root.valueUpdateRequested(newValue);
            GlobalStates.osdInteraction();
            event.accepted = true;
        }
    }
}
