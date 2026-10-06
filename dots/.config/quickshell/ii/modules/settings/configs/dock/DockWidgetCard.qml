pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One of the dock's own widgets or buttons as a feature tile, the sibling of
 * DockUtilityCard: the stage shows it drawn by the dock's own component, then
 * the title with the switch, the summary (two lines always reserved) and a
 * footer row that is always there, with "Configure" when the item has a page
 * of its own. Clicking the tile toggles it.
 */
Rectangle {
    id: root

    /** The dock item to draw: { type, actionId? } as DockContent's model holds it. */
    property var itemData: ({})
    property var context: null
    /** Slots the item takes on the dock (its width on the stage). */
    property real slots: 1
    property string symbol: ""
    property string title: ""
    property string summary: ""
    /** Shown in the footer while on; "" for nothing. */
    property string stateText: ""
    property bool checked: false
    property bool configurable: false
    /** False while the item has nothing to draw (no player, no games): the strip says why. */
    property bool hasContent: true
    property string emptyHint: ""

    signal toggled(bool value)
    signal configureRequested()

    readonly property color colContent: root.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
    readonly property real stageHeight: 108

    implicitHeight: 18 + root.stageHeight + 14 + 44 + 34 + 46 + 16
    radius: Appearance.rounding.verylarge
    color: root.checked
        ? (tileHover.hovered ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (tileHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: tileHover
    }
    // Under the content, so the switch and Configure keep their clicks.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }

    // ── Stage: the item at the dock's size, scaled down only if needed ────
    Rectangle {
        id: stage
        x: 18
        y: 18
        width: root.width - 36
        height: root.stageHeight
        radius: Appearance.rounding.large
        color: root.checked ? ColorUtils.applyAlpha(root.colContent, 0.08) : Appearance.colors.colLayer2

        // The item at its dock size, straight on the stage.
        Item {
            id: strip
            anchors.centerIn: parent
            readonly property real slot: root.context?.buttonSlotSize ?? 60
            readonly property real cross: root.context?.buttonSlotHeight ?? 60
            width: strip.slot * root.slots
            height: strip.cross
            scale: Math.min(1, (stage.width - 24) / Math.max(1, strip.width), (stage.height - 16) / Math.max(1, strip.height))
            opacity: root.checked ? 1 : 0.72
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            DockItemView {
                anchors.fill: parent
                active: root.hasContent
                itemData: root.itemData
                context: root.context
            }
            Row {
                visible: !root.hasContent
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.symbol
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, strip.width - 56)
                    text: root.emptyHint
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }
        // The stage is a picture: nothing on it takes the pointer, and the wheel
        // still scrolls the page.
        DockInputShield {
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled(!root.checked)
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
                text: root.symbol
                iconSize: 20
                padding: 10
                fill: root.checked ? 1 : 0
                shape: root.checked ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
                color: root.colContent
                elide: Text.ElideRight
            }
            StyledSwitch {
                Layout.alignment: Qt.AlignVCenter
                sizeScale: 0.85
                checked: root.checked
                activeColor: Appearance.colors.colPrimary
                activeThumbColor: Appearance.colors.colOnPrimary
                inactiveColor: Appearance.colors.colSurfaceContainerHighest
                onToggled: root.toggled(checked)
            }
        }

        StyledText {
            id: summary
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.preferredHeight: summaryMetrics.height * 2
            text: root.summary
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

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: root.checked ? root.stateText : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.colContent
                elide: Text.ElideRight
            }

            RippleButton {
                visible: root.configurable
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
