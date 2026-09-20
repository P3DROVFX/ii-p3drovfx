pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.modes

/**
 * Mode presentation on the Dynamic Island:
 * - Contracted: Flash banner when a mode starts or stops.
 * - Expanded: iOS Focus-style card with mode information and controls.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var payload: GlobalStates.modeFlashPayload
    readonly property var mode: Modes.activeMode
    readonly property string colorKey: (root.mode && root.mode.color) ? root.mode.color : (root.payload?.color ?? "")

    readonly property string displayName: {
        if (root.mode && root.mode.name)
            return root.mode.name;
        if (root.payload && root.payload.title)
            return root.payload.title;
        return Translation.tr("Modes & Routines");
    }

    readonly property string displayIcon: {
        if (root.mode && root.mode.icon)
            return root.mode.icon;
        if (root.payload && root.payload.icon)
            return root.payload.icon;
        return "tune";
    }

    readonly property string displayShape: {
        if (root.mode && root.mode.shape)
            return root.mode.shape;
        return "Cookie12Sided";
    }

    readonly property string statusText: {
        if (!Modes.active)
            return Translation.tr("Inactive");
        if (Modes.activeEndsAt > 0)
            return Translation.tr("Ends at %1").arg(ModeUi.clock(Modes.activeEndsAt));
        if (Modes.activeSince > 0)
            return Translation.tr("Active since %1").arg(ModeUi.clock(Modes.activeSince));
        return Translation.tr("Active");
    }

    readonly property string detailText: {
        if (!root.mode)
            return root.payload?.subtitle ?? "";
        return ModeUi.modeHeaderStatus(root.mode);
    }

    readonly property string detailIcon: {
        if (!root.mode)
            return "info";
        if (Modes.activeEndsAt > 0)
            return "schedule";
        if (Modes.activeSource === "manual")
            return "touch_app";
        return "auto_awesome";
    }

    // ==========================================
    // 1. CONTRACTED MODE (Banner)
    // ==========================================
    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 10
        visible: !root.isExpanded

        MaterialShape {
            id: iconShape
            shapeString: root.displayShape
            color: ModeUi.container(root.colorKey)
            implicitWidth: Math.max(16, Math.min(32, root.height - 4))
            implicitHeight: Math.max(16, Math.min(32, root.height - 4))
            Layout.alignment: Qt.AlignVCenter

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.displayIcon
                iconSize: Math.max(10, Math.min(16, iconShape.implicitHeight - 16))
                fill: 1
                color: ModeUi.onContainer(root.colorKey)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2

            StyledText {
                Layout.fillWidth: true
                text: root.payload ? (root.payload.title ?? "") : root.displayName
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.payload ? (root.payload.subtitle ?? "") : root.statusText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    onPayloadChanged: iconPulse.restart()

    SequentialAnimation {
        id: iconPulse
        NumberAnimation {
            target: iconShape
            property: "scale"
            to: 1.25
            duration: 120
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: iconShape
            property: "scale"
            to: 1.0
            duration: 220
            easing.type: Easing.OutBack
        }
    }

    // ==========================================
    // 2. EXPANDED MODE (iOS Focus Style Card)
    // ==========================================
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        visible: root.isExpanded

        // Header Row: MaterialShape Icon, Name + Status, and "ON" Badge
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShape {
                id: expandedIconShape
                shapeString: root.displayShape
                color: ModeUi.container(root.colorKey)
                implicitWidth: 38
                implicitHeight: 38
                Layout.alignment: Qt.AlignVCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.displayIcon
                    iconSize: 20
                    fill: 1
                    color: ModeUi.onContainer(root.colorKey)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.displayName
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.medium
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            // iOS-style "ON" Pill Badge
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 22
                implicitWidth: onRow.implicitWidth + 14
                radius: 11
                color: ColorUtils.transparentize(ModeUi.accent(root.colorKey), 0.82)

                Row {
                    id: onRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: ModeUi.accent(root.colorKey)

                        SequentialAnimation on opacity {
                            running: Modes.active && root.isExpanded
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.35; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.35; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ON"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Black
                        color: ModeUi.accent(root.colorKey)
                    }
                }
            }
        }

        // Info / Trigger details chip
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: 8
            color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.45)
            visible: root.detailText.length > 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.detailIcon
                    iconSize: 14
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.detailText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        // Action Buttons Row (iOS style pill buttons)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Turn off button
            RippleButton {
                id: turnOffBtn
                Layout.fillWidth: true
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colBackgroundActive: Appearance.colors.colErrorContainerActive
                colRipple: Appearance.colors.colErrorContainerActive
                onClicked: Modes.deactivate("manual")

                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "power_settings_new"
                            iconSize: 14
                            color: Appearance.colors.colOnErrorContainer
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Turn off")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.SemiBold
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }
                }
            }

            // Settings / Modes button
            RippleButton {
                id: settingsBtn
                Layout.fillWidth: true
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: {
                    if (root.mode && root.mode.id)
                        Modes.openAndReveal("mode", root.mode.id);
                    else
                        GlobalStates.modesOpen = true;
                }

                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "tune"
                            iconSize: 14
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Translation.tr("Settings")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.SemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }
}
