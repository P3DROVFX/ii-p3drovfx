import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../../ii/dock/utilities"
import "../../../ii/dock/utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * One utility widget in Settings, as a feature tile. The stage shows its two
 * faces drawn by the real tile at the dock's size; the chosen face sits on a
 * filled plate and clicking a face picks it (adding the widget if it was off).
 * Then the title with the switch, the summary (two lines always reserved), and
 * a footer that always keeps its row, with "Configure" when there are options
 * — so every card in a row has the same height.
 */
Rectangle {
    id: root

    required property var info
    readonly property var entry: DockUtilityCatalog.entryFor(Config.options.dock.utilityWidgets ?? [], root.info.kind)
    readonly property bool added: root.entry !== null
    readonly property bool wide: root.entry?.wide ?? false
    readonly property color colContent: root.added ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

    signal configureRequested()

    function setAdded(value) {
        Config.options.dock.utilityWidgets = value
            ? DockUtilityCatalog.withKind(Config.options.dock.utilityWidgets ?? [], root.info.kind, root.wide)
            : DockUtilityCatalog.withoutKind(Config.options.dock.utilityWidgets ?? [], root.info.kind);
    }
    function choose(wide) {
        Config.options.dock.utilityWidgets = DockUtilityCatalog.withKind(Config.options.dock.utilityWidgets ?? [], root.info.kind, wide);
    }

    readonly property real stageHeight: 108
    implicitHeight: 18 + root.stageHeight + 14 + 44 + 34 + 46 + 16

    radius: Appearance.rounding.verylarge
    color: root.added
        ? (tileHover.hovered ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (tileHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: tileHover
    }

    // ── Stage: both faces at the dock's size, scaled down only if needed ──
    Rectangle {
        id: stage
        x: 18
        y: 18
        width: root.width - 36
        height: root.stageHeight
        radius: Appearance.rounding.large
        color: root.added ? ColorUtils.applyAlpha(root.colContent, 0.08) : Appearance.colors.colLayer2

        Row {
            id: faces
            anchors.centerIn: parent
            spacing: 8
            scale: Math.min(1, (stage.width - 24) / Math.max(1, faces.implicitWidth))

            Repeater {
                model: [false, true]
                delegate: Item {
                    id: face
                    required property bool modelData
                    readonly property bool chosen: root.added && root.wide === face.modelData
                    width: preview.width + 16
                    height: preview.height + 16

                    // The chosen face stands on a filled plate.
                    Rectangle {
                        anchors.fill: parent
                        radius: preview.bodyRadius + 8
                        color: face.chosen ? Appearance.colors.colSecondaryContainer
                            : faceArea.containsMouse ? ColorUtils.applyAlpha(root.colContent, 0.08) : "transparent"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                    UtilityPreview {
                        id: preview
                        anchors.centerIn: parent
                        kind: root.info.kind
                        wide: face.modelData
                        width: implicitWidth
                        height: implicitHeight
                    }
                    MouseArea {
                        id: faceArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choose(face.modelData)
                    }
                    StyledToolTip {
                        text: face.modelData ? Translation.tr("Wide") : Translation.tr("Square")
                        extraVisibleCondition: faceArea.containsMouse
                    }
                }
            }
        }
    }

    // ── Title, summary, footer ──────────────────────────────────────────
    ColumnLayout {
        anchors {
            left: parent.left
            right: parent.right
            top: stage.bottom
            bottom: parent.bottom
            leftMargin: 18
            rightMargin: 18
            topMargin: 14
            bottomMargin: 16
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: root.info.symbol
                iconSize: 20
                padding: 10
                fill: root.added ? 1 : 0
                shape: root.added ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: root.added ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.added ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr(root.info.title)
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
                color: root.colContent
                elide: Text.ElideRight
            }
            StyledSwitch {
                Layout.alignment: Qt.AlignVCenter
                sizeScale: 0.85
                checked: root.added
                activeColor: Appearance.colors.colPrimary
                activeThumbColor: Appearance.colors.colOnPrimary
                inactiveColor: Appearance.colors.colSurfaceContainerHighest
                onToggled: root.setAdded(checked)
            }
        }

        StyledText {
            id: summary
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.preferredHeight: summaryMetrics.height * 2
            text: Translation.tr(root.info.description)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colContent
            opacity: 0.8
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
            FontMetrics {
                id: summaryMetrics
                font: summary.font
            }
        }

        Item {
            Layout.fillHeight: true
        }

        // Footer: what is on the dock, and Configure — the row is always there.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                visible: root.added
                text: root.wide ? Translation.tr("Wide on the dock") : Translation.tr("Square on the dock")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.colContent
                elide: Text.ElideRight
            }
            Item {
                Layout.fillWidth: true
                visible: !root.added
            }

            RippleButton {
                visible: root.info.settings === true
                implicitHeight: 36
                implicitWidth: configureRow.implicitWidth + 28
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.small
                colBackground: ColorUtils.applyAlpha(root.colContent, 0.1)
                colBackgroundHover: ColorUtils.applyAlpha(root.colContent, 0.18)
                colBackgroundActive: ColorUtils.applyAlpha(root.colContent, 0.26)
                colRipple: ColorUtils.applyAlpha(root.colContent, 0.26)
                onClicked: root.configureRequested()

                contentItem: Item {
                    RowLayout {
                        id: configureRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "tune"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.colContent
                        }
                        StyledText {
                            text: Translation.tr("Configure")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: root.colContent
                        }
                    }
                }
            }
        }
    }
}
