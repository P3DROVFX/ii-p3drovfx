pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The page's subject: the desktop wallpaper itself, playing the effect the page is about to
 * change. Pills over the picture follow the hero rules, all at one height and one inset: a
 * name tag and a caption top left, replay top right, the effect picker bottom left and,
 * while parallax plays, the workspace dots bottom right. As the page scrolls the hero
 * folds (`collapse` 0 → 1) down to the picker alone. `mode` is owned by the page, which
 * also steers the hero while the pointer tries an option on.
 */
ClippingRectangle {
    id: root

    readonly property real inset: 16
    readonly property real pillHeight: 40
    readonly property real pillSidePadding: 16
    readonly property real bandGap: 8
    readonly property real tagSpacing: 8
    readonly property real fullLabelsBreak: 640
    readonly property real compactBreak: 520
    readonly property real chipSpacing: 6
    readonly property real dotSize: 8
    readonly property real dotActiveWidth: 22
    readonly property real dotSpacing: 6
    readonly property real topFadeStart: 0.35
    readonly property var effects: [
        { "id": "parallax", "symbol": "sync_alt", "label": Translation.tr("Parallax") },
        { "id": "blur", "symbol": "blur_on", "label": Translation.tr("Blur") },
        { "id": "transition", "symbol": "animation", "label": Translation.tr("Transition") }
    ]

    property string mode: "parallax"
    property string kind: ""
    property string detail: ""
    property string caption: ""
    property string source: ""
    property string alternate: ""
    property real zoom: 1.07
    property real blurAmount: 0.8
    property string transitionShader: ""
    property bool transitionAnimated: true
    property bool locked: false
    // 0 fully open, 1 folded to the picker.
    property real collapse: 0

    signal modeRequested(string mode)

    readonly property bool compact: root.width < root.compactBreak
    readonly property bool fullLabels: root.width >= root.fullLabelsBreak
    readonly property real topOpacity: Math.max(0, 1 - Math.max(0, root.collapse - root.topFadeStart) / (1 - root.topFadeStart) * 2)
    readonly property real bandHeight: root.inset + root.pillHeight + root.bandGap

    function play() {
        if (!root.locked)
            stage.play();
    }

    function settle() {
        stage.settle();
    }

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    BackgroundStage {
        id: stage
        anchors.fill: parent
        mode: root.mode
        source: root.source
        alternate: root.alternate
        zoom: root.zoom
        blurAmount: root.blurAmount
        transitionShader: root.transitionShader
        transitionAnimated: root.transitionAnimated
        topBand: root.bandHeight * (1 - root.collapse)
        bottomBand: root.bandHeight
    }

    Row {
        anchors {
            left: parent.left
            top: parent.top
            margins: root.inset
        }
        height: root.pillHeight
        spacing: root.tagSpacing
        opacity: root.topOpacity
        visible: opacity > 0.01

        Rectangle {
            height: root.pillHeight
            width: Math.max(root.pillHeight, Math.min(tagRow.implicitWidth + root.pillSidePadding * 2,
                root.width - root.inset * 2 - root.pillHeight - root.tagSpacing * 2 - captionPill.width))
            radius: height / 2
            color: Appearance.m3colors.m3surfaceContainerHigh

            RowLayout {
                id: tagRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: root.pillSidePadding
                    rightMargin: root.pillSidePadding
                }
                spacing: 8

                StyledText {
                    text: root.kind
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !root.compact
                    text: root.detail
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideMiddle
                }
            }
        }

        Rectangle {
            id: captionPill
            height: root.pillHeight
            width: captionText.implicitWidth + root.pillSidePadding * 2
            radius: height / 2
            color: root.locked ? Appearance.colors.colErrorContainer : Appearance.colors.colTertiaryContainer

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            StyledText {
                id: captionText
                anchors.centerIn: parent
                text: root.locked ? Translation.tr("Effects locked by video") : root.caption
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                color: root.locked ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnTertiaryContainer
            }
        }
    }

    RippleButton {
        anchors {
            right: parent.right
            top: parent.top
            margins: root.inset
        }
        visible: !root.locked && root.topOpacity > 0.01
        opacity: root.topOpacity
        implicitWidth: root.pillHeight
        implicitHeight: root.pillHeight
        buttonRadius: height / 2
        colBackground: Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colRipple: Appearance.colors.colSurfaceContainerHighestHover
        onClicked: root.play()

        MaterialSymbol {
            anchors.centerIn: parent
            text: "replay"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledToolTip {
            text: Translation.tr("Play the effect again")
        }
    }

    Row {
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: root.inset
        }
        height: root.pillHeight
        spacing: root.chipSpacing
        opacity: root.locked ? 0.45 : 1
        enabled: !root.locked

        Repeater {
            model: root.effects

            delegate: BackgroundEffectChip {
                required property var modelData

                symbol: modelData.symbol
                label: modelData.label
                chosen: root.mode === modelData.id
                showLabel: root.fullLabels || chosen
                onClicked: {
                    root.modeRequested(modelData.id);
                    root.play();
                }
            }
        }
    }

    Rectangle {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: root.inset
        }
        height: root.pillHeight
        width: dotsRow.implicitWidth + root.pillSidePadding * 2
        radius: height / 2
        color: Appearance.m3colors.m3surfaceContainerHigh
        opacity: root.mode === "parallax" && !root.locked ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Row {
            id: dotsRow
            anchors.centerIn: parent
            spacing: root.dotSpacing

            Repeater {
                model: 3

                delegate: Rectangle {
                    required property int index

                    readonly property bool active: index === stage.workspace
                    anchors.verticalCenter: parent.verticalCenter
                    width: active ? root.dotActiveWidth : root.dotSize
                    height: root.dotSize
                    radius: height / 2
                    color: active ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                    Behavior on width {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
