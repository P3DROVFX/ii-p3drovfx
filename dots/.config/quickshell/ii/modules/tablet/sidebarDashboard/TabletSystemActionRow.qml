import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Bottom row of the shade's left column, following Android's layout: a wide pill that opens
 * the system tray, then the profile picture and the shade's own actions as separate circles.
 * Every hit target is a function of `rowHeight`, so the row stays thumb-sized on any display.
 */
Item {
    id: root

    property real rowHeight: 64
    property bool editMode: false

    signal editModeToggled(bool newEditMode)
    signal trayRequested
    signal dismissRequested

    implicitHeight: root.rowHeight

    readonly property real gap: Math.round(root.rowHeight * 0.18)
    // The circles read heavier than the pill at the same height, so they sit a notch under it.
    readonly property real circleSize: Math.round(root.rowHeight * 0.84)
    readonly property int trayItemCount: TrayService.allItems.length

    RowLayout {
        anchors.fill: parent
        spacing: root.gap

        // ── System tray pill ────────────────────────────────────────────────
        RippleButton {
            id: trayPill
            Layout.fillWidth: true
            Layout.fillHeight: true

            buttonRadius: Appearance.rounding.full
            buttonRadiusPressed: Appearance.rounding.large
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colBackgroundActive: Appearance.colors.colLayer1Active
            colRipple: Appearance.colors.colLayer1Active

            enabled: root.trayItemCount > 0
            opacity: enabled ? 1.0 : 0.6
            onClicked: root.trayRequested()

            contentItem: RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Math.round(root.rowHeight * 0.24)
                    rightMargin: Math.round(root.rowHeight * 0.28)
                }
                spacing: Math.round(root.rowHeight * 0.22)

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "info"
                    iconSize: Math.round(root.rowHeight * 0.38)
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Math.round(Appearance.font.pixelSize.normal * 1.15)
                    font.weight: 500
                    text: {
                        if (root.trayItemCount === 0)
                            return Translation.tr("No background apps");
                        if (root.trayItemCount === 1)
                            return Translation.tr("1 app is active");
                        return Translation.tr("%1 apps are active").arg(root.trayItemCount);
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.trayItemCount > 0
                    text: "chevron_right"
                    iconSize: Math.round(root.rowHeight * 0.38)
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── Profile picture (display only) ──────────────────────────────────
        Rectangle {
            id: profileCircle
            Layout.preferredWidth: root.circleSize
            Layout.preferredHeight: root.circleSize
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimaryContainer

            MultiEffect {
                anchors.fill: parent
                source: profileImage
                maskEnabled: true
                maskSource: profileMask
                visible: profileImage.status === Image.Ready
            }

            Item {
                id: profileMask
                anchors.fill: parent
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: "black"
                }
            }

            Image {
                id: profileImage
                anchors.fill: parent
                source: Directories.userAvatarPathAccountsService ?? ""
                fillMode: Image.PreserveAspectCrop
                visible: false
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: profileImage.status !== Image.Ready
                text: "person"
                iconSize: Math.round(root.circleSize * 0.46)
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        // ── Actions ─────────────────────────────────────────────────────────
        TabletTouchButton {
            diameter: root.circleSize
            Layout.alignment: Qt.AlignVCenter
            visible: Config.options.sidebar.quickToggles.style === "android"
            toggled: root.editMode
            buttonIcon: "edit"
            // The shade owns edit mode; this row only reports the intent.
            onClicked: root.editModeToggled(!root.editMode)
        }

        // The way back out of this family. Everything else on this row is reachable from a
        // desktop too; this one is the reason a tablet with no keyboard is not a one-way
        // door — the chooser was IPC-and-keybind only until it had a button somewhere.
        TabletTouchButton {
            diameter: root.circleSize
            Layout.alignment: Qt.AlignVCenter
            buttonIcon: "swap_horiz"
            onClicked: {
                root.dismissRequested();
                GlobalStates.shellSwitcherOpen = true;
            }
        }

        TabletTouchButton {
            diameter: root.circleSize
            Layout.alignment: Qt.AlignVCenter
            buttonIcon: "settings"
            onClicked: {
                root.dismissRequested();
                GlobalStates.toggleSettings();
            }
        }

        TabletTouchButton {
            diameter: root.circleSize
            Layout.alignment: Qt.AlignVCenter
            buttonIcon: "power_settings_new"
            accent: true
            onClicked: {
                root.dismissRequested();
                GlobalStates.sessionOpen = true;
            }
        }
    }
}
