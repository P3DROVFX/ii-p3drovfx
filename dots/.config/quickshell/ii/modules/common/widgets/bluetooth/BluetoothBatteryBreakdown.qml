pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    property var batteryInfo: null
    property bool compact: false
    property bool showLabels: true
    property bool showCase: true
    property bool horizontal: true

    readonly property var components: {
        if (!root.batteryInfo || !root.batteryInfo.components)
            return [];
        return root.batteryInfo.components.filter(c => {
            if (!c || !c.available)
                return false;
            if (c.id === "case" && !root.showCase)
                return false;
            return true;
        });
    }

    readonly property bool hasComponents: root.components.length > 0

    implicitWidth: mainLayout.implicitWidth
    implicitHeight: mainLayout.implicitHeight

    function getComponentIcon(id: string): string {
        switch (id) {
            case "left": return "earbuds";
            case "right": return "earbuds";
            case "case": return "battery_charging_full";
            case "device": return "headphones";
            default: return "battery_std";
        }
    }

    function getComponentBadge(id: string): string {
        switch (id) {
            case "left": return "L";
            case "right": return "R";
            case "case": return "C";
            default: return "";
        }
    }

    GridLayout {
        id: mainLayout
        anchors.fill: parent
        columns: root.horizontal ? root.components.length : 1
        rows: root.horizontal ? 1 : root.components.length
        rowSpacing: root.compact ? 6 : 10
        columnSpacing: root.compact ? 12 : 16

        Repeater {
            model: root.components
            delegate: Item {
                id: compItem
                required property var modelData
                required property int index

                readonly property var comp: modelData
                readonly property int level: comp.level !== null ? comp.level : 0
                readonly property bool isCharging: Boolean(comp.charging)
                readonly property bool isLow: level <= 15

                Layout.fillWidth: !root.horizontal
                Layout.preferredWidth: root.horizontal ? (root.compact ? 72 : 96) : -1
                implicitWidth: root.horizontal ? (root.compact ? 72 : 96) : compRow.implicitWidth
                implicitHeight: root.compact ? 24 : 52

                // Compact horizontal item
                RowLayout {
                    id: compRow
                    anchors.fill: parent
                    visible: root.compact
                    spacing: 4

                    Rectangle {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        radius: Appearance.rounding.full
                        color: compItem.isCharging ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                        StyledText {
                            anchors.centerIn: parent
                            text: root.getComponentBadge(compItem.comp.id) || "•"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: compItem.isCharging ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    StyledText {
                        text: compItem.level + "%"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: compItem.isLow ? Appearance.m3colors.m3error : Appearance.colors.colOnSurface
                    }

                    MaterialSymbol {
                        visible: compItem.isCharging
                        text: "bolt"
                        iconSize: 12
                        color: Appearance.colors.colPrimary
                    }
                }

                // Expanded card item
                ColumnLayout {
                    anchors.fill: parent
                    visible: !root.compact
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        // Badge / Icon
                        Rectangle {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            radius: Appearance.rounding.full
                            color: compItem.isCharging ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                            StyledText {
                                anchors.centerIn: parent
                                text: root.getComponentBadge(compItem.comp.id) || "•"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: compItem.isCharging ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        StyledText {
                            visible: root.showLabels
                            text: compItem.comp.label || ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Item { Layout.fillWidth: true }

                        MaterialSymbol {
                            visible: compItem.isCharging
                            text: "bolt"
                            iconSize: 14
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: compItem.level + "%"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: compItem.isLow ? Appearance.m3colors.m3error : Appearance.colors.colOnSurface
                        }
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        valueBarHeight: 6
                        from: 0
                        to: 1
                        value: compItem.level / 100.0
                        highlightColor: compItem.isLow ? Appearance.m3colors.m3error : (compItem.isCharging ? Appearance.colors.colPrimary : Appearance.colors.colPrimary)
                        trackColor: Appearance.colors.colSurfaceContainerHighest
                    }
                }
            }
        }
    }
}
