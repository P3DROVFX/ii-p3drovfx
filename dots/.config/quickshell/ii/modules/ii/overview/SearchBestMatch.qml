pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets

/**
 * The top result, rendered as one row you read instead of a list you scan.
 *
 * A launcher's whole promise is that the first thing on screen is the thing you
 * meant. Presenting it at the same weight as the nine rows under it makes the
 * user verify that promise every time; giving it its own shape means the answer
 * is legible before the eye reaches the list.
 *
 * The row also surfaces what used to live behind Ctrl+K. A result's own actions
 * are the part of it that people never discover, and three of them fit here
 * without turning the row into a menu — the rest stay in the action panel.
 */
RippleButton {
    id: root

    property var entry
    property string query
    property int listIndex: 0
    property int listCurrentIndex: -1
    property int secondaryLimit: 4

    signal resultExecuted(string feedbackText)

    readonly property bool isSelected: root.listIndex === root.listCurrentIndex
    readonly property string itemName: entry?.name ?? ""
    readonly property string itemComment: entry?.comment ?? ""
    readonly property string itemType: entry?.type ?? ""
    readonly property string verb: entry?.verb ?? Translation.tr("Open")
    readonly property bool keepsOverviewOpen: entry?.keepOverviewOpen ?? false

    /**
     * The same action set the Ctrl+K panel offers — not just the result's own
     * `actions`, which most desktop entries do not define at all. That was the
     * difference between a prominent row that offers Pin to Dock, Copy ID and
     * Reset, and one that offers nothing but a taller silhouette.
     *
     * Index 0 is the primary action, which this row already presents as the
     * named verb next to Enter, so the chips start after it.
     */
    readonly property var actionItems: SearchResultActions.build(root.entry, {
        onDone: function () {},
        onExecuted: feedbackText => root.resultExecuted(feedbackText)
    })
    readonly property var secondaryActions: root.actionItems.slice(1, 1 + Math.max(0, root.secondaryLimit))
    readonly property int hiddenActionCount: Math.max(0, root.actionItems.length - 1 - root.secondaryActions.length)

    readonly property int contentPadding: 16

    function activate(): bool {
        root.clicked();
        return true;
    }

    // Both paths go through the shared action list, so a row activated from
    // here behaves exactly like the same row activated from the panel —
    // including the cases that must *not* close the launcher.
    function runPrimary() {
        const primary = root.actionItems[0];
        if (primary && typeof primary.execute === "function")
            primary.execute();
    }

    function runSecondary(index: int) {
        const action = root.secondaryActions[index];
        if (action && typeof action.execute === "function")
            action.execute();
    }

    implicitHeight: contentColumn.implicitHeight + root.contentPadding * 2
    buttonRadius: Appearance.rounding.large
    colBackground: root.isSelected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
    colRipple: Appearance.colors.colPrimaryContainerActive

    readonly property color colForeground: root.isSelected ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface

    PointingHandInteraction {}

    onClicked: root.runPrimary()

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.contentPadding
        anchors.rightMargin: root.contentPadding
        spacing: root.secondaryActions.length > 0 ? 12 : 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Item {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44

                MaterialShape {
                    anchors.fill: parent
                    visible: root.entry?.iconType === LauncherSearchResult.IconType.System
                    shape: MaterialShape.Shape.Cookie7Sided
                    color: root.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                }

                IconImage {
                    anchors.centerIn: parent
                    visible: root.entry?.iconType === LauncherSearchResult.IconType.System
                    source: Quickshell.iconPath(root.entry?.iconName ?? "", "image-missing")
                    implicitSize: 28
                    smooth: true
                }

                ClippingRectangle {
                    anchors.fill: parent
                    visible: root.entry?.iconType === LauncherSearchResult.IconType.Image && heroImage.status === Image.Ready
                    color: "transparent"
                    radius: Appearance.rounding.small

                    StyledImage {
                        id: heroImage
                        anchors.fill: parent
                        sourceSize.width: 88
                        sourceSize.height: 88
                        source: root.entry?.iconType === LauncherSearchResult.IconType.Image ? (root.entry?.iconName ?? "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.entry?.iconType === LauncherSearchResult.IconType.Material
                        || (root.entry?.iconType === LauncherSearchResult.IconType.Image && heroImage.status !== Image.Ready)
                    text: root.entry?.iconType === LauncherSearchResult.IconType.Material
                        ? (root.entry?.iconName ?? "")
                        : (root.entry?.fallbackIconName ?? "search")
                    iconSize: 32
                    fill: root.isSelected ? 1.0 : 0.0
                    color: root.colForeground
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.itemName
                    color: root.colForeground
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: {
                        const parts = [];
                        if (root.itemType.length > 0 && root.itemType !== Translation.tr("App"))
                            parts.push(root.itemType);
                        if (root.itemComment.length > 0)
                            parts.push(root.itemComment);
                        return parts.join(" • ");
                    }
                    color: root.colForeground
                    opacity: 0.7
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }

            // The primary action, named rather than implied. "Enter does the
            // obvious thing" is only obvious once you already know what it is.
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 8

                StyledText {
                    text: root.verb
                    color: root.colForeground
                    opacity: 0.8
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                }

                KeyHint {
                    keys: ["↵"]
                    surface: root.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                    onSurface: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                }
            }
        }

        // A Flow, not a Row: a RowLayout cannot shrink its children below their
        // implicit width, so any combination of long action names simply ran off
        // the panel. Wrapping degrades instead, at any width and any number of
        // chips the setting allows.
        Flow {
            id: actionFlow
            Layout.fillWidth: true
            // A Flow derives its height from the width it is given, so the
            // column has to be told to reserve the wrapped height.
            Layout.preferredHeight: actionFlow.implicitHeight
            visible: root.secondaryActions.length > 0
            spacing: 8

            Repeater {
                model: root.secondaryActions

                delegate: RippleButton {
                    id: actionChip
                    required property var modelData
                    required property int index

                    implicitHeight: 34
                    implicitWidth: chipContent.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive

                    PointingHandInteraction {}
                    onClicked: root.runSecondary(actionChip.index)

                    RowLayout {
                        id: chipContent
                        anchors.centerIn: parent
                        spacing: 7

                        Loader {
                            active: actionChip.modelData?.nativeIcon === true
                            visible: active
                            Layout.preferredWidth: active ? 18 : 0
                            Layout.preferredHeight: active ? 18 : 0
                            sourceComponent: IconImage {
                                source: Quickshell.iconPath(actionChip.modelData?.icon ?? "", "image-missing")
                                implicitSize: 18
                                smooth: true
                            }
                        }

                        MaterialSymbol {
                            visible: actionChip.modelData?.nativeIcon !== true && text.length > 0
                            text: actionChip.modelData?.icon ?? ""
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }

                        StyledText {
                            // Second net, for the single action whose name is
                            // longer than a whole line by itself.
                            Layout.maximumWidth: 150
                            elide: Text.ElideRight
                            text: actionChip.modelData?.name ?? ""
                            color: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }

                        KeyHint {
                            // Alt+n rather than a bare digit: the field keeps
                            // every plain key for the query itself.
                            keys: ["Alt", String(actionChip.index + 1)]
                            surface: root.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                            onSurface: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }
                    }
                }
            }

            // Wraps with the chips instead of being pinned to the right edge,
            // which is what pushed the last chip off the panel.
            Item {
                width: moreRow.implicitWidth
                height: 34
                visible: root.hiddenActionCount > 0

                RowLayout {
                    id: moreRow
                    anchors.centerIn: parent
                    spacing: 7

                    StyledText {
                        text: Translation.tr("%1 more").arg(String(root.hiddenActionCount))
                        color: root.colForeground
                        opacity: 0.7
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    KeyHint {
                        keys: ["Ctrl", "K"]
                        surface: root.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                        onSurface: root.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                    }
                }
            }
        }
    }
}
