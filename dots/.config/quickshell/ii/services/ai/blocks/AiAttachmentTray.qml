pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

/**
 * What is going out with the next message.
 *
 * One row of chips above the composer, one per file, each with a thumbnail if
 * there is one to show and a way to take it back off. A file that was turned
 * away says why, in the same place, rather than not appearing and leaving the
 * drop looking like it never registered.
 */
Item {
    id: root

    readonly property var files: Ai.attachments
    readonly property string notice: Ai.attachmentNotice
    /** Set while a drag is over the composer, to say what dropping would do. */
    property string dragHint: ""

    readonly property real chipHeight: Math.round(Appearance.font.pixelSize.huge * 2)
    /**
     * One inset for every side of the chip, so the round button at its end
     * sits as far from the edge as it does from the top and the bottom. Half
     * the height was the old value and it left the button stranded in the
     * middle of its own chip, with the dashes a thumb's width away from it.
     */
    readonly property real chipPadding: Math.round(root.chipHeight * 0.14)
    /**
     * The leading edge is the curved one, so what starts there is pushed in
     * far enough to clear the arc rather than sitting inside it.
     */
    readonly property real chipLeadingInset: Math.round(root.chipHeight * 0.32)
    readonly property real chipGap: Appearance.rounding.unsharpenmore
    readonly property real chipButtonSize: root.chipHeight - root.chipPadding * 2
    /** Keeps one long name from pushing the row past the composer's width. */
    readonly property real chipMaximumTextWidth: Math.max(80, root.width * 0.45)

    readonly property bool hasContent: root.files.length > 0 || root.notice.length > 0 || root.dragHint.length > 0

    implicitHeight: root.hasContent ? contentColumnLayout.implicitHeight : 0
    visible: implicitHeight > 0
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    function symbolFor(kind: string): string {
        if (kind === "context")
            return "attachment";
        if (kind === "image")
            return "image";
        if (kind === "pdf")
            return "picture_as_pdf";
        if (kind === "audio")
            return "music_note";
        if (kind === "video")
            return "movie";
        if (kind === "text")
            return "description";
        return "file_present";
    }

    function detailFor(file: var): string {
        if (file?.kind !== "context")
            return Ai.humanSize(Number(file?.bytes ?? 0));
        const source = String(file?.source ?? file?.contextKind ?? Translation.tr("context"));
        const destination = String(Ai.currentModelEntry?.title ?? Translation.tr("selected model"));
        return source + " · " + Ai.humanSize(Number(file?.bytes ?? 0)) + " · " + destination;
    }

    ColumnLayout {
        id: contentColumnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 4

        StyledFlickable {
            Layout.fillWidth: true
            implicitHeight: root.files.length > 0 ? chipsRowLayout.implicitHeight : 0
            visible: root.files.length > 0
            contentWidth: chipsRowLayout.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            RowLayout {
                id: chipsRowLayout
                height: parent.height
                spacing: 4

                Repeater {
                    model: ScriptModel {
                        values: root.files
                    }

                    delegate: Rectangle {
                        id: fileChip
                        required property var modelData
                        required property int index

                        implicitWidth: chipRowLayout.implicitWidth + root.chipLeadingInset + root.chipPadding
                        implicitHeight: root.chipHeight
                        radius: height / 2
                        // Outlined, not filled: an attachment is a thing on its
                        // way out, not a control, and the dashes say "pending"
                        // without spending a surface colour on it.
                        color: "transparent"

                        DashedBorder {
                            // Inset by its own stroke rather than by a flat
                            // pixel, so the dashes land inside the chip at any
                            // rounding scale instead of straddling its edge.
                            anchors.fill: parent
                            anchors.margins: borderWidth / 2
                            // Passed whole: the border clamps a radius its own
                            // path cannot take, and subtracting the inset here
                            // as well left the arc a hair too tight for a pill.
                            radius: fileChip.radius
                            // Fine and close together: a long dash on a short
                            // pill spends most of its length in the corners,
                            // where it reads as a broken outline rather than
                            // as a dashed one.
                            borderWidth: Math.max(1, Math.round(Appearance.font.pixelSize.smaller / 8))
                            dashLength: Math.max(2, Math.round(root.chipHeight * 0.09))
                            gapLength: Math.max(2, Math.round(root.chipHeight * 0.07))
                            color: Appearance.colors.colPrimary
                        }

                        // Arrives with the file rather than appearing finished.
                        opacity: 0
                        scale: 0.85
                        Component.onCompleted: chipEnter.start()

                        ParallelAnimation {
                            id: chipEnter

                            NumberAnimation {
                                target: fileChip
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }

                            NumberAnimation {
                                target: fileChip
                                property: "scale"
                                from: 0.85
                                to: 1
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Easing.OutBack
                            }
                        }

                        RowLayout {
                            id: chipRowLayout
                            anchors.left: parent.left
                            anchors.leftMargin: root.chipLeadingInset
                            anchors.right: parent.right
                            anchors.rightMargin: root.chipPadding
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.chipGap

                            Loader {
                                // A picture says what it is faster than its
                                // name does; everything else gets an icon.
                                active: fileChip.modelData.kind === "image"
                                visible: active
                                sourceComponent: Rectangle {
                                    id: thumbnail
                                    // Smaller than the round button at the
                                    // other end: this end of the chip is the
                                    // curved one and a square that fills it
                                    // touches the dashes.
                                    implicitWidth: Math.round(root.chipHeight * 0.6)
                                    implicitHeight: Math.round(root.chipHeight * 0.6)
                                    radius: Appearance.rounding.verysmall
                                    color: Appearance.colors.colLayer1

                                    StyledImage {
                                        anchors.fill: parent
                                        source: Qt.resolvedUrl(fileChip.modelData.path)
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize.width: Math.round(root.chipHeight * 1.2)
                                        sourceSize.height: Math.round(root.chipHeight * 1.2)
                                        asynchronous: true

                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: thumbnail.width
                                                height: thumbnail.height
                                                radius: thumbnail.radius
                                            }
                                        }
                                    }
                                }
                            }

                            MaterialSymbol {
                                visible: fileChip.modelData.kind !== "image"
                                text: root.symbolFor(fileChip.modelData.kind)
                                fill: 1
                                iconSize: 24
                                color: Appearance.colors.colPrimary
                            }

                            ColumnLayout {
                                spacing: 0

                                StyledText {
                                    // A name long enough to push the chip past
                                    // the composer is elided in the middle, so
                                    // both the subject and the extension survive.
                                    Layout.maximumWidth: root.chipMaximumTextWidth
                                    text: fileChip.modelData.name
                                    elide: Text.ElideMiddle
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: true
                                    color: Appearance.colors.colPrimary
                                }

                                StyledText {
                                    text: root.detailFor(fileChip.modelData)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colPrimary
                                    opacity: 0.8
                                }
                            }

                            RippleButton {
                                implicitWidth: root.chipButtonSize
                                implicitHeight: root.chipButtonSize
                                buttonRadius: Appearance.rounding.full
                                topPadding: 0
                                bottomPadding: 0
                                leftPadding: 0
                                rightPadding: 0
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                colRipple: Appearance.colors.colPrimaryActive
                                onClicked: Ai.removeAttachment(fileChip.index)

                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "close"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnPrimary
                                }

                                StyledToolTip {
                                    text: Translation.tr("Remove")
                                }
                            }
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.dragHint.length > 0
            visible: active
            sourceComponent: Rectangle {
                implicitHeight: 32
                radius: Appearance.rounding.small
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "attach_file"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }

                    StyledText {
                        text: root.dragHint
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.notice.length > 0
            visible: active
            sourceComponent: RowLayout {
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "error"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3error
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.notice
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3error
                }

                RippleButton {
                    implicitWidth: 24
                    implicitHeight: 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: Ai.attachmentNotice = ""

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3error
                    }
                }
            }
        }
    }
}
