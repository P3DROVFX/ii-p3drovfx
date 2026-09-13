pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The one menu surface in this family: a header, then rows a finger can hit.
 *
 * There were three of these — the dock's long-press, the drawer's long-press, and the dock's
 * overflow page — each with its own radius, row height and font, so the same gesture on two
 * icons a centimetre apart produced two visibly different menus. Two of them were also
 * drawn at desktop sizes: 36px rows and small text on a surface meant for a fingertip.
 *
 * This is only the card. Where it is placed is the caller's problem, because the drawer can
 * draw one inside itself while the dock's layer is too short to hold anything above it.
 */
Rectangle {
    id: root

    /// One entry per row: `{ symbol, label, checked, destructive, trigger }`.
    property var actions: []
    property string headerText: ""
    property string headerIconPath: ""
    property string headerSymbol: ""

    signal actionTriggered

    // Rows are the whole target. The minimum touch target is a floor here, not the size:
    // a menu of rows exactly one fingertip tall is a menu you mis-tap. Callers may size
    // these from their own surface — the drawer has a screen to work with, the dock does
    // not — but every caller gets the same shape, spacing and type.
    property real rowHeight: Math.max(Appearance.sizes.minimumTouchTarget + 8, 56)
    property real menuPadding: Math.max(12, Appearance.sizes.elevationMargin)
    property real rowSpacing: Math.max(2, Math.round(Appearance.sizes.elevationMargin * 0.2))
    property real menuWidth: 320
    /// 0 leaves the card as tall as its rows. Anything else scrolls past it, because a menu
    /// taller than the screen is a menu with unreachable entries.
    property real maximumHeight: 0
    /// The row under the finger swells to a full pill and settles back, the same M3
    /// treatment NavigationRailButton uses. It is the only feedback a row gets: a finger
    /// leaves no hover behind it.
    property bool useDynamicRadius: true

    readonly property real contentHeight: menuColumn.implicitHeight + root.menuPadding * 2

    implicitWidth: root.menuWidth
    implicitHeight: root.maximumHeight > 0
        ? Math.min(root.contentHeight, root.maximumHeight) : root.contentHeight
    radius: Appearance.rounding.large
    color: Config.options.appearance.transparency.popups
        ? Appearance.colors.colLayer1
        : Appearance.m3colors.m3surfaceContainer

    Flickable {
        id: menuScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.contentHeight
        clip: true
        interactive: root.contentHeight > root.height
        boundsBehavior: Flickable.StopAtBounds

        // Positioned, not anchored: a child anchored to a Flickable's parent anchors to its
        // content item, whose size is the contentHeight this column is what determines —
        // and QML resolves that loop by leaving the card at zero, which is a menu that
        // opens and paints nothing. The width comes from the caller's number instead.
        ColumnLayout {
            id: menuColumn
            x: root.menuPadding
            y: root.menuPadding
            width: root.menuWidth - root.menuPadding * 2
            spacing: root.rowSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.bottomMargin: 6
                Layout.preferredHeight: root.headerText.length > 0 ? root.rowHeight * 0.72 : 0
                visible: root.headerText.length > 0
                spacing: 12

                IconImage {
                    visible: root.headerIconPath.length > 0
                    implicitSize: Appearance.font.pixelSize.huge
                    source: root.headerIconPath
                }

                MaterialSymbol {
                    visible: root.headerSymbol.length > 0
                    text: root.headerSymbol
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 4
                visible: root.headerText.length > 0
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            Repeater {
                model: root.actions

                delegate: RippleButton {
                    id: actionButton
                    required property var modelData

                    readonly property bool isChecked: actionButton.modelData.checked ?? false

                    Layout.fillWidth: true
                    implicitHeight: root.rowHeight
                    buttonRadius: root.useDynamicRadius
                        ? (actionButton.isChecked ? Appearance.rounding.full : Appearance.rounding.small)
                        : Appearance.rounding.normal
                    buttonRadiusPressed: root.useDynamicRadius
                        ? Appearance.rounding.full : Appearance.rounding.normal
                    colBackground: actionButton.isChecked
                        ? Appearance.colors.colSecondaryContainer : "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colBackgroundActive: Appearance.colors.colLayer1Active
                    colRipple: Appearance.colors.colLayer1Active

                    readonly property color contentColor: (actionButton.modelData.destructive ?? false)
                        ? Appearance.colors.colError
                        : (actionButton.isChecked
                            ? Appearance.m3colors.m3onSecondaryContainer
                            : Appearance.colors.colOnLayer1)

                    releaseAction: () => {
                        // Reported before the action runs: one of these opens another surface,
                        // and this menu must not still be sitting on top of it.
                        root.actionTriggered();
                        actionButton.modelData.trigger?.();
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 14

                        Loader {
                            Layout.preferredWidth: Appearance.font.pixelSize.huge
                            Layout.preferredHeight: Appearance.font.pixelSize.huge
                            active: String(actionButton.modelData.iconPath ?? "").length > 0
                            visible: active

                            sourceComponent: IconImage {
                                implicitSize: Appearance.font.pixelSize.huge
                                source: actionButton.modelData.iconPath
                            }
                        }

                        MaterialSymbol {
                            visible: String(actionButton.modelData.iconPath ?? "").length === 0
                            text: actionButton.modelData.symbol ?? "chevron_right"
                            iconSize: Appearance.font.pixelSize.huge
                            color: actionButton.contentColor
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: actionButton.modelData.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: actionButton.contentColor
                            elide: Text.ElideRight
                        }

                        MaterialSymbol {
                            visible: actionButton.isChecked
                            text: "check"
                            iconSize: Appearance.font.pixelSize.large
                            color: actionButton.contentColor
                        }
                    }
                }
            }
        }
    }
}
