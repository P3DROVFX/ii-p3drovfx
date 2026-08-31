pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

/**
 * Bar indicator for shell/fork updates. Invisible while the local checkout
 * matches the remote branch; otherwise a single symbol, which grows on hover to
 * reveal how many commits behind it is — the ExpressiveUtilButtons idiom.
 *
 * Clicking opens the update script in a terminal *without* --no-confirm, so the
 * script prompts before touching anything, unlike the Settings button.
 */
MouseArea {
    id: indicator
    property bool vertical: false

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    readonly property bool available: ShellUpdates.hasUpdate
    // 0 means the count is unknown (non-GitHub remote, offline, rate-limited),
    // not "level" — hasUpdate already settled that. Never expand into an empty
    // pill when there is no number to show.
    readonly property int behind: ShellUpdates.commitsBehind
    readonly property bool expanded: containsMouse && behind > 0

    readonly property real baseSize: (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) - 14
    readonly property int animDuration: Math.round(120 * Appearance.animMultiplier)

    implicitWidth: available ? (vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth) : 0
    implicitHeight: available ? (vertical ? pill.implicitHeight : Appearance.sizes.baseBarHeight) : 0

    visible: available

    Component.onCompleted: rootItem.toggleVisible(indicator.available)
    onAvailableChanged: rootItem.toggleVisible(indicator.available)

    onClicked: {
        const terminal = Config.options?.apps?.terminal || "kitty -1";
        const hyprFlag = (Config.options?.update?.replaceHyprConfig ?? true) ? "--hypr" : "--no-hypr";
        // Array form, so a home directory with a space in it cannot break the
        // command apart the way a single shell string would.
        const cmd = terminal.split(" ").filter(part => part.length > 0);
        cmd.push("-e", "bash", "-c", 'if [ ! -f "$1" ]; then ' + 'printf "Update script not found:\\n  %s\\n\\n[Press Enter to close] " "$1"; read -r; exit 1; fi; ' + 'bash "$1" update --keep-config "$2"; ' + 'printf "\\n[Press Enter to close] "; read -r', "ii-update", ShellUpdates.setupScript, hyprFlag);
        Quickshell.execDetached(cmd);
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        radius: Appearance.rounding.full
        color: indicator.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer

        implicitWidth: indicator.vertical ? indicator.baseSize : indicator.baseSize + countRevealer.implicitWidth
        implicitHeight: indicator.vertical ? indicator.baseSize + countRevealer.implicitHeight : indicator.baseSize

        Behavior on color {
            ColorAnimation { duration: indicator.animDuration }
        }

        MaterialSymbol {
            id: symbol
            text: "deployed_code_update"
            fill: 1
            iconSize: Appearance.font.pixelSize.large
            color: indicator.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer

            width: indicator.baseSize
            height: indicator.baseSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            anchors {
                left: indicator.vertical ? undefined : parent.left
                top: indicator.vertical ? parent.top : undefined
                horizontalCenter: indicator.vertical ? parent.horizontalCenter : undefined
                verticalCenter: indicator.vertical ? undefined : parent.verticalCenter
            }

            Behavior on color {
                ColorAnimation { duration: indicator.animDuration }
            }
        }

        // Revealer animates its own implicit size, so the pill grows with it
        // rather than needing a second animation of its own.
        Revealer {
            id: countRevealer
            vertical: indicator.vertical
            reveal: indicator.expanded
            anchors {
                left: indicator.vertical ? undefined : symbol.right
                top: indicator.vertical ? symbol.bottom : undefined
                horizontalCenter: indicator.vertical ? parent.horizontalCenter : undefined
                verticalCenter: indicator.vertical ? undefined : parent.verticalCenter
            }

            StyledText {
                text: indicator.behind
                color: indicator.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                font.letterSpacing: -0.3
                rightPadding: indicator.vertical ? 0 : 10
                bottomPadding: indicator.vertical ? 8 : 0
                Component.onCompleted: width = implicitWidth

                Behavior on color {
                    ColorAnimation { duration: indicator.animDuration }
                }
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: indicator.containsMouse
        requireOverlay: false
        text: {
            const where = `${ShellUpdates.activeFork} @ ${ShellUpdates.activeBranch}`;
            const count = indicator.behind > 0 ? Translation.tr("%1 new commit(s)").arg(indicator.behind) : Translation.tr("New commits available");
            const shas = `${ShellUpdates.activeCommit.substring(0, 7)} → ${ShellUpdates.remoteCommit.substring(0, 7)}`;
            return `${count}\n${where}  ·  ${shas}\n\n` + Translation.tr("Click to update in a terminal (asks before applying)");
        }
    }
}
