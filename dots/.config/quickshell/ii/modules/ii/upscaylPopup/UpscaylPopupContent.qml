pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

/**
 * Corner card for services/Upscayl.qml: preview with the before → after size, the
 * scale group, the model chips, then a progress bar while the engine runs. Leaves
 * on its own once the upscaled wallpaper is applied.
 */
Item {
    id: root

    readonly property string phase: Upscayl.phase
    readonly property bool running: phase === "running"
    readonly property bool locked: running || phase === "done"

    readonly property real surfaceMargin: Appearance.sizes.elevationMargin
    property real popupWidth: 344
    property real padding: 18

    implicitWidth: popupWidth + 2 * surfaceMargin
    implicitHeight: contentLayout.implicitHeight + padding * 2 + 2 * surfaceMargin

    property alias staticMaskTarget: staticMaskTarget
    Item {
        id: staticMaskTarget
        anchors.fill: parent
        anchors.margins: root.surfaceMargin
    }

    // ── enter / leave ──
    property real reveal: 0
    Component.onCompleted: enterAnim.start()
    Connections {
        target: Upscayl
        function onPopupOpenChanged() {
            if (Upscayl.popupOpen) {
                leaveAnim.stop();
                enterAnim.start();
            } else {
                enterAnim.stop();
                leaveAnim.start();
            }
        }
    }
    NumberAnimation {
        id: enterAnim
        target: root; property: "reveal"; to: 1
        duration: Appearance.animation.elementMoveEnter.duration * 1.4
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
    }
    NumberAnimation {
        id: leaveAnim
        target: root; property: "reveal"; to: 0
        duration: Appearance.animation.elementMoveExit.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        onFinished: Upscayl.popupVisible = false
    }

    StyledRectangularShadow {
        target: card
        opacity: card.opacity
    }

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: root.surfaceMargin
        radius: Appearance.rounding.large
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        opacity: Math.min(1, root.reveal * 1.6)
        scale: 0.88 + 0.12 * root.reveal
        transformOrigin: Item.TopRight

        // Clicks inside never reach whatever is under the card.
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = true
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

            // ── header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    text: root.phase === "done" ? "check" : (root.phase === "error" ? "error" : "auto_awesome")
                    iconSize: 22
                    padding: 10
                    shape: root.phase === "done" ? MaterialShape.Shape.Circle
                        : root.running ? MaterialShape.Shape.SoftBurst
                        : root.phase === "error" ? MaterialShape.Shape.Square
                        : MaterialShape.Shape.Cookie7Sided
                    color: root.phase === "error" ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                    colSymbol: root.phase === "error" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.phase === "done" ? Translation.tr("Wallpaper upscaled")
                            : root.running ? Translation.tr("Upscaling…")
                            : Translation.tr("Upscale wallpaper")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Upscayl.fileName
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideMiddle
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: Upscayl.close()
                    StyledToolTip {
                        text: root.running ? Translation.tr("Keep upscaling in the background") : Translation.tr("Close")
                    }
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.running ? "keyboard_arrow_up" : "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            // ── preview: before → after ──
            ClippingRectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(width * 9 / 16)
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                StyledImage {
                    anchors.fill: parent
                    source: Upscayl.inputPath.length > 0 ? "file://" + Upscayl.inputPath : ""
                    sourceSize.width: 688
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                // The part still to go, dimmed; the processed side reads as "sharpened".
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: parent.width * (1 - Upscayl.progress)
                    visible: root.running
                    color: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.55)
                    Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    implicitWidth: sizeRow.implicitWidth + 16
                    implicitHeight: 28
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer

                    RowLayout {
                        id: sizeRow
                        anchors.centerIn: parent
                        spacing: 4
                        StyledText {
                            text: `${Upscayl.imageWidth}×${Upscayl.imageHeight}`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        MaterialSymbol {
                            text: "arrow_forward"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: `${Upscayl.imageWidth * Upscayl.scale}×${Upscayl.imageHeight * Upscayl.scale}`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }

            // ── scale ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: Upscayl.phase !== "error"

                SectionLabel { text: Translation.tr("Scale") }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Repeater {
                        model: [2, 3, 4]
                        delegate: RippleButton {
                            id: scaleButton
                            required property int modelData
                            required property int index
                            readonly property bool current: Upscayl.scale === modelData
                            readonly property real outer: Appearance.rounding.normal
                            readonly property real join: Appearance.rounding.verysmall

                            Layout.fillWidth: true
                            implicitHeight: 44
                            enabled: !root.locked
                            toggled: current
                            // One shape for the group; the chosen segment becomes a pill.
                            topLeftRadius: current ? height / 2 : (index === 0 ? outer : join)
                            bottomLeftRadius: topLeftRadius
                            topRightRadius: current ? height / 2 : (index === 2 ? outer : join)
                            bottomRightRadius: topRightRadius
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundActive: Appearance.colors.colLayer2Active
                            colBackgroundToggled: Appearance.colors.colPrimary
                            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                            colBackgroundToggledActive: Appearance.colors.colPrimaryActive
                            onClicked: Upscayl.scale = modelData

                            contentItem: Item {
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: -2
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: `${scaleButton.modelData}×`
                                        font.family: Appearance.font.family.title
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.DemiBold
                                        color: scaleButton.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        visible: scaleButton.modelData === Upscayl.autoScale
                                        text: Translation.tr("fits screen")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: scaleButton.current ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── model ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: Upscayl.phase !== "error" && Upscayl.models.length > 0

                SectionLabel { text: Translation.tr("Model") }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: Upscayl.models
                        delegate: RippleButton {
                            id: modelChip
                            required property string modelData
                            readonly property bool current: Upscayl.model === modelData

                            implicitHeight: 34
                            implicitWidth: chipRow.implicitWidth + 24
                            enabled: !root.locked
                            toggled: current
                            buttonRadius: current ? Appearance.rounding.small : Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundActive: Appearance.colors.colLayer2Active
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                            colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
                            onClicked: Upscayl.model = modelData

                            contentItem: Item {
                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        visible: modelChip.current
                                        text: "check"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    StyledText {
                                        text: Upscayl.modelLabel(modelChip.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: modelChip.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── probing / error ──
            StyledText {
                Layout.fillWidth: true
                visible: Upscayl.probing
                text: Translation.tr("Looking for Upscayl…")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            Rectangle {
                Layout.fillWidth: true
                visible: root.phase === "error"
                implicitHeight: errorText.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colErrorContainer
                StyledText {
                    id: errorText
                    anchors.fill: parent
                    anchors.margins: 10
                    text: Upscayl.errorText
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnErrorContainer
                }
            }

            // ── progress ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.locked

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: root.phase === "done" ? Translation.tr("Applied") : Upscayl.modelLabel(Upscayl.model)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: `${Math.round(Upscayl.progress * 100)}%`
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }
                StyledProgressBar {
                    Layout.fillWidth: true
                    valueBarHeight: 6
                    value: Upscayl.progress
                    wavy: root.running
                    animateWave: root.running
                }
            }

            // ── actions ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                visible: root.phase !== "done"

                RippleButton {
                    implicitHeight: 40
                    implicitWidth: cancelLabel.implicitWidth + 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: Upscayl.cancel()
                    contentItem: StyledText {
                        id: cancelLabel
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.running ? Translation.tr("Stop") : Translation.tr("Cancel")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }

                RippleButton {
                    id: primaryButton
                    readonly property bool openApp: root.phase === "error"
                    Layout.fillWidth: true
                    implicitHeight: 40
                    visible: !root.running
                    enabled: openApp || Upscayl.available
                    opacity: enabled ? 1 : 0.5
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    onClicked: {
                        if (openApp) {
                            Quickshell.execDetached(["bash", "-c", "command -v upscayl >/dev/null && exec upscayl || exec xdg-open https://upscayl.org"]);
                            Upscayl.close();
                        } else {
                            Upscayl.start();
                        }
                    }
                    contentItem: Item {
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: primaryButton.openApp ? "open_in_new" : "auto_awesome"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: primaryButton.openApp ? Translation.tr("Get Upscayl") : Translation.tr("Upscale %1×").arg(Upscayl.scale)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }
    }

    component SectionLabel: StyledText {
        Layout.leftMargin: 2
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }
}
