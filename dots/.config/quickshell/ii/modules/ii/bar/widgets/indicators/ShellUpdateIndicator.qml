pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import QtQuick
import QtQuick.Layouts
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
    // Edit Mode has to be able to reach a widget that is currently showing
    // nothing: with the checkout up to date this indicator takes no space at
    // all, so there would be nothing to grab, drag or place. While the mode is
    // on it is drawn as though an update were waiting. Rendering only - the
    // stored visibility flag stays on the real condition, and the bar ORs the
    // mode in on its side.
    readonly property bool shown: indicator.available || GlobalStates.editMode
    // 0 means the count is unknown (non-GitHub remote, offline, rate-limited),
    // not "level" — hasUpdate already settled that. Never expand into an empty
    // pill when there is no number to show.
    readonly property int behind: ShellUpdates.commitsBehind
    // Hovered, or holding its popup open: the pill stays lit and expanded for
    // as long as the popup is up, so it reads as the popup's anchor.
    readonly property bool engaged: containsMouse || popup.opened
    readonly property bool expanded: engaged && behind > 0

    readonly property real baseSize: (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) - 14
    readonly property int animDuration: Math.round(120 * Appearance.animMultiplier)

    implicitWidth: shown ? (vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth) : 0
    implicitHeight: shown ? (vertical ? pill.implicitHeight : Appearance.sizes.baseBarHeight) : 0

    visible: shown

    Component.onCompleted: rootItem.toggleVisible(indicator.available)
    onAvailableChanged: rootItem.toggleVisible(indicator.available)

    // In click-to-show mode the press belongs to the popup (which carries an
    // Update button of its own); with hover popups the click keeps launching
    // the update directly, as it always has.
    onClicked: {
        if (BarInteraction.clickToShow) return;
        indicator.launchUpdate();
    }

    function launchUpdate() {
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
        color: indicator.engaged ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer

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
            color: indicator.engaged ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer

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
                color: indicator.engaged ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                font.letterSpacing: -0.3
                rightPadding: indicator.vertical ? 0 : 10
                bottomPadding: indicator.vertical ? 8 : 0

                Behavior on color {
                    ColorAnimation { duration: indicator.animDuration }
                }
            }
        }
    }

    // What the update contains: the AI summary when there is one, then the
    // commits grouped by kind, capped so a big update does not fill the screen.
    // Sticky so the Summarize button and the rows can be reached.
    StyledPopup {
        id: popup
        hoverTarget: indicator
        stickyHover: true
        popupRadius: Appearance.rounding.large

        readonly property int cardWidth: 380

        contentItem: ColumnLayout {
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: popup.cardWidth
                implicitWidth: popup.cardWidth
                implicitHeight: cardColumn.implicitHeight + 28
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh

                ColumnLayout {
                    id: cardColumn
                    anchors {
                        fill: parent
                        margins: 14
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "deployed_code_update"
                            fill: 1
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: indicator.behind > 0 ? Translation.tr("%1 new commit(s)").arg(indicator.behind) : Translation.tr("New commits available")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `${ShellUpdates.activeFork} @ ${ShellUpdates.activeBranch}  ·  ${ShellUpdates.activeCommit.substring(0, 7)} → ${ShellUpdates.remoteCommit.substring(0, 7)}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        RippleButtonWithIcon {
                            visible: ShellUpdates.compareUrl !== ""
                            materialIcon: "open_in_new"
                            mainText: Translation.tr("GitHub")
                            onClicked: Qt.openUrlExternally(ShellUpdates.compareUrl)
                        }
                    }

                    ShellUpdateSummaryCard {
                        Layout.fillWidth: true
                        compact: true
                    }

                    // The summary already condenses the list; showing both made
                    // the popup taller than the screen. The full list lives on
                    // the About page.
                    ShellUpdateChangelog {
                        visible: ShellUpdates.commits.length > 0 && !ShellUpdateSummary.current
                        Layout.fillWidth: true
                        compact: true
                        maxRows: 10
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            visible: !BarInteraction.clickToShow
                            text: Translation.tr("Click the icon to update in a terminal (asks before applying)")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                        }

                        Item {
                            visible: BarInteraction.clickToShow
                            Layout.fillWidth: true
                        }

                        RippleButtonWithIcon {
                            materialIcon: "terminal"
                            mainText: Translation.tr("Update")
                            onClicked: {
                                popup.close();
                                indicator.launchUpdate();
                            }

                            StyledToolTip {
                                requireOverlay: false
                                text: Translation.tr("Runs the update script in a terminal; it asks before applying")
                            }
                        }
                    }
                }
            }
        }
    }
}
