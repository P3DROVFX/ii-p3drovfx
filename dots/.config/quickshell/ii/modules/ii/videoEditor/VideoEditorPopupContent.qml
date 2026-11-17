pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string videoPath: ""
    property int transformOriginEdge: Item.TopLeft

    signal dismissed()
    signal editRequested()
    signal openFolderRequested()

    readonly property string fileName: {
        const clean = FileUtils.trimFileProtocol(root.videoPath || "");
        const idx = clean.lastIndexOf("/");
        return idx >= 0 ? clean.slice(idx + 1) : clean;
    }

    readonly property bool isHovered: popupHoverHandler.hovered

    Timer {
        id: dismissTimer
        interval: 8000
        repeat: false
        running: !root.isHovered
        onTriggered: root.dismissed()
    }

    onVideoPathChanged: dismissTimer.restart()

    onIsHoveredChanged: {
        if (isHovered) dismissTimer.stop();
        else dismissTimer.restart();
    }

    property alias contentBackground: contentBackground
    property alias staticMaskTarget: staticMaskTarget

    property real popupWidth: 320
    property real padding: 20
    readonly property real surfaceMargin: Appearance.sizes.elevationMargin

    implicitWidth: popupWidth + 2 * root.surfaceMargin
    implicitHeight: contentLayout.implicitHeight + root.padding * 2 + 2 * root.surfaceMargin

    // Static, unscaled item for the window input mask to avoid coordinate bugs during entrance scale.
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
    }

    StyledRectangularShadow {
        target: contentBackground
        opacity: contentBackground.opacity
    }

    Rectangle {
        id: contentBackground
        anchors {
            fill: parent
            margins: root.surfaceMargin
        }
        radius: Appearance.rounding.large
        color: Config.options.appearance.transparency.popups
            ? Appearance.colors.colLayer0
            : Appearance.m3colors.m3surfaceContainer

        opacity: Appearance.reducedMotion ? 1 : 0
        scale: Appearance.reducedMotion ? 1 : 0.85
        transformOrigin: root.transformOriginEdge

        Component.onCompleted: {
            if (!Appearance.reducedMotion)
                entranceAnim.start();
        }

        ParallelAnimation {
            id: entranceAnim
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
            NumberAnimation {
                target: contentBackground
                property: "scale"
                from: 0.85
                to: 1
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        // Prevent clicks inside the card from leaking to windows underneath.
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = true
            onClicked: mouse => mouse.accepted = true
            onPressed: mouse => mouse.accepted = true
            onReleased: mouse => mouse.accepted = true
        }

        HoverHandler {
            id: popupHoverHandler
        }

        ColumnLayout {
            id: contentLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.padding
            }
            spacing: 14

            // === HEADER ===
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Recording Finished")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.hugeass
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Do you want to edit it?")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colPrimary
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 34
                    implicitHeight: 34
                    padding: 0
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: root.dismissed()

                    contentItem: Item {
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // === MATERIAL SHAPE HERO ===
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 164
                implicitHeight: 164

                MaterialShape {
                    id: heroShape
                    anchors.centerIn: parent
                    implicitSize: 152
                    color: Appearance.colors.colPrimaryContainer
                    shape: editButton.hovered
                        ? MaterialShape.Shape.Sunny
                        : (folderButton.hovered ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Cookie12Sided)

                    scale: Appearance.reducedMotion ? 1 : 0
                    Component.onCompleted: {
                        if (!Appearance.reducedMotion)
                            shapeEnterAnim.start();
                    }
                    NumberAnimation {
                        id: shapeEnterAnim
                        target: heroShape
                        property: "scale"
                        from: 0
                        to: 1
                        duration: 550
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.8
                    }
                }

                MaterialSymbol {
                    id: heroIcon
                    anchors.centerIn: parent
                    text: "movie_edit"
                    iconSize: 64
                    color: Appearance.colors.colOnPrimaryContainer

                    scale: Appearance.reducedMotion ? 1 : 0
                    Component.onCompleted: {
                        if (!Appearance.reducedMotion)
                            iconEnterAnim.start();
                    }
                    NumberAnimation {
                        id: iconEnterAnim
                        target: heroIcon
                        property: "scale"
                        from: 0
                        to: 1
                        duration: 650
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.4
                    }
                }
            }

            // === RECORDED FILE CHIP ===
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                implicitHeight: 46
                visible: root.fileName !== ""
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHighest

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    MaterialSymbol {
                        text: "video_file"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.fileName
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideMiddle
                    }
                }
            }

            // === ACTION BUTTONS (50/50 symmetrical) ===
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Secondary: dashed outline, no fill
                RippleButton {
                    id: folderButton
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 44
                    implicitHeight: 44
                    padding: 0
                    buttonRadius: Appearance.rounding.full
                    buttonRadiusPressed: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12)
                    colBackgroundActive: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.20)
                    colRipple: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.22)
                    onClicked: root.openFolderRequested()

                    DashedBorder {
                        anchors.fill: parent
                        color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, folderButton.hovered ? 0.95 : 0.65)
                        borderWidth: 1
                        dashLength: 5
                        gapLength: 4
                        radius: folderButton.buttonEffectiveRadius
                    }

                    contentItem: Item {
                        RowLayout {
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - 16)
                            spacing: 6

                            MaterialSymbol {
                                text: "folder_open"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Open folder")
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // Primary: filled pill
                RippleButton {
                    id: editButton
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 44
                    implicitHeight: 44
                    padding: 0
                    buttonRadius: Appearance.rounding.full
                    buttonRadiusPressed: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: root.editRequested()

                    contentItem: Item {
                        RowLayout {
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - 16)
                            spacing: 6

                            MaterialSymbol {
                                text: "edit"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Edit Video")
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
