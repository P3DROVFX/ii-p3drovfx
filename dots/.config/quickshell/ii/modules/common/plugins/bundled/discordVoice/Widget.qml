pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
Rectangle {
    id: root
    readonly property int avatarLimit: Config.options.overlay.discordVoice.maxAvatars
    readonly property real participantAvatarSize: Config.options.overlay.discordVoice.avatarSize
    readonly property string participantBackground: Config.options.overlay.discordVoice.participantBackground
    readonly property real participantBackgroundOpacity: Config.options.overlay.discordVoice.participantBackgroundOpacity
    readonly property bool blurEnabled: Config.options.overlay.discordVoice.blurEnabled
    readonly property real backgroundOpacity: 0.85
    readonly property string layoutMode: Config.options.overlay.discordVoice.layoutMode
    readonly property bool columnMode: layoutMode === "column"
    property bool namesOnLeft: false
    readonly property bool companionReady: DiscordVoice.backend === "vencord"
    readonly property bool isVencordClient: companionCheck.output.trim() !== ""

    Process {
        id: companionCheck
        command: ["bash", "-c", "ls ~/.config/equibop ~/.config/vesktop 2>/dev/null | head -1"]
        running: true
    }

    // Widest the overlay is allowed to grow before the avatar grid wraps onto
    // another row instead. Both avatar size and count are user-configurable, so
    // an unbounded single row would reach ~960px at the top of their ranges.
    readonly property real maxContentWidth: 720
    readonly property int visibleParticipants: Math.min(avatarLimit, DiscordVoice.participantCount)

    // Derived arithmetically rather than from the grid's implicitWidth: the
    // grid is anchored to this item's width, so reading its implicit size back
    // into implicitWidth would bind width to itself.
    readonly property real participantCellWidth: columnMode
        ? Math.max(176, participantAvatarSize + 116 + Appearance.spacing.space100)
        : Math.max(participantAvatarSize,
            76 + (participantBackground === "name" ? Appearance.spacing.space200 : 0))
    readonly property real participantStride: participantCellWidth
        + (columnMode ? Appearance.spacing.space75 : Appearance.spacing.space200)
    readonly property int participantColumns: columnMode ? 1
        : Math.max(1, Math.min(visibleParticipants,
            Math.floor((maxContentWidth + Appearance.spacing.space200) / participantStride)))
    readonly property real participantGridWidth: participantColumns > 0
        ? participantColumns * participantStride
            - (columnMode ? Appearance.spacing.space75 : Appearance.spacing.space200)
        : 0

    implicitWidth: Math.max(columnMode ? 256 : 344,
        participantGridWidth + Appearance.spacing.space150 * 2)
    implicitHeight: content.implicitHeight + Appearance.spacing.space300
    width: implicitWidth
    height: implicitHeight
    radius: Appearance.rounding.verylarge
    color: root.blurEnabled
        ? ColorUtils.transparentize(Appearance.colors.colLayer1, 1 - root.backgroundOpacity)
        : "transparent"
    border.width: 0

    function beginAuthorization() {
        DiscordVoice.authorizeAfterFocusRelease();
        GlobalStates.overlayOpen = false;
    }

    Process {
        id: installProcess
        command: ["bash", `${Directories.scriptPath}/discordVoice/vencord-companion/install.sh`]
        stdout: SplitParser { onRead: data => {} }
        stderr: SplitParser { onRead: data => {} }
    }

    ColumnLayout {
        id: content
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: Appearance.spacing.space150
        }
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space75
            DiscordGlyph {
                implicitSize: 36
                iconSize: 20
                color: Appearance.colors.colPrimaryContainer
                iconColor: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.preferredWidth: Math.min(channelName.implicitWidth, root.columnMode ? 92 : 160)
                Layout.maximumWidth: root.columnMode ? 92 : 160
                spacing: 0
                StyledText {
                    id: channelName
                    Layout.fillWidth: true
                    text: DiscordVoice.channel?.name || (DiscordVoice.status === "auth_required"
                        ? "Connect Discord" : "No voice channel")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    text: DiscordVoice.inVoice
                        ? `${DiscordVoice.participantCount} participant${DiscordVoice.participantCount === 1 ? "" : "s"}`
                        : (DiscordVoice.errorMessage || "Discord voice overlay")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                visible: DiscordVoice.status !== "auth_required" && DiscordVoice.status !== "authorizing"
                spacing: 0

                RippleButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: DiscordVoice.setMuted(!DiscordVoice.muted)
                    contentItem: MaterialShapeWrappedMaterialSymbol {
                        text: DiscordVoice.muted ? "mic_off" : "mic"
                        shape: DiscordVoice.muted ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie4Sided
                        implicitSize: 46
                        iconSize: 21
                        fill: DiscordVoice.muted ? 1 : 0
                        color: DiscordVoice.muted ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                        colSymbol: DiscordVoice.muted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                        scale: parent?.down ? 0.88 : (parent?.hovered ? 1.08 : 1)
                        Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack } }
                    }
                    StyledToolTip { text: DiscordVoice.muted ? "Unmute" : "Mute" }
                }

                RippleButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: DiscordVoice.setDeafened(!DiscordVoice.deafened)
                    contentItem: MaterialShapeWrappedMaterialSymbol {
                        text: DiscordVoice.deafened ? "headset_off" : "headphones"
                        shape: DiscordVoice.deafened ? MaterialShape.Shape.Boom : MaterialShape.Shape.Clover4Leaf
                        implicitSize: 46
                        iconSize: 21
                        fill: DiscordVoice.deafened ? 1 : 0
                        color: DiscordVoice.deafened ? Appearance.colors.colErrorContainer : Appearance.colors.colTertiaryContainer
                        colSymbol: DiscordVoice.deafened ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnTertiaryContainer
                        scale: parent?.down ? 0.88 : (parent?.hovered ? 1.08 : 1)
                        Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack } }
                    }
                    StyledToolTip { text: DiscordVoice.deafened ? "Undeafen" : "Deafen" }
                }
            }

            Item { Layout.fillWidth: true }
        }

        GridLayout {
            visible: DiscordVoice.participantCount > 0
            Layout.fillWidth: root.columnMode
            Layout.alignment: Qt.AlignHCenter
            columns: root.participantColumns
            rowSpacing: Appearance.spacing.space75
            columnSpacing: root.columnMode ? Appearance.spacing.space75 : Appearance.spacing.space200
            Repeater {
                model: DiscordVoice.participantModel
                ParticipantAvatar {
                    required property int index
                    visible: index < root.avatarLimit
                    avatarSize: root.participantAvatarSize
                    showName: true
                    maxNameWidth: root.columnMode ? 116 : 76
                    backgroundMode: root.participantBackground
                    backgroundOpacity: root.participantBackgroundOpacity
                    horizontalLayout: root.columnMode
                    nameOnLeft: root.namesOnLeft
                    Layout.fillWidth: root.columnMode
                }
            }
        }

        RippleButton {
            visible: DiscordVoice.status === "auth_required" || DiscordVoice.status === "authorizing"
            enabled: DiscordVoice.status !== "authorizing" && !installProcess.running
            Layout.fillWidth: true
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: {
                if (root.companionReady) return Appearance.colors.colPrimary;
                if (root.isVencordClient && !root.companionReady) return Appearance.colors.colError;
                return Appearance.colors.colPrimary;
            }
            onClicked: {
                if (root.companionReady || !root.isVencordClient)
                    root.beginAuthorization();
                else
                    installProcess.running = true;
            }
            StyledText {
                anchors.centerIn: parent
                text: {
                    if (installProcess.running) return "Installing…";
                    if (DiscordVoice.status === "authorizing") return "Waiting for Discord…";
                    if (root.isVencordClient && !root.companionReady) return "Install Companion";
                    return "Authorize Discord";
                }
                color: Appearance.colors.colOnPrimary
                font.weight: Font.DemiBold
            }
        }
    }
}
