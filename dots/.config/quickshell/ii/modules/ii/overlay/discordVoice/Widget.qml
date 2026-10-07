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
    readonly property bool autoResize: Config.options.overlay.discordVoice.autoResize
    readonly property real backgroundOpacity: 0.85
    readonly property string layoutMode: Config.options.overlay.discordVoice.layoutMode
    readonly property bool columnMode: layoutMode === "column"
    readonly property bool gridMode: layoutMode === "grid"
    property bool namesOnLeft: false
    readonly property bool companionReady: DiscordVoice.backend === "vencord"
    // Detected by the service, which also decides whether the bridge runs at all.
    readonly property bool isVencordClient: DiscordVoice.isVencordClient

    readonly property real maxContentWidth: 720
    readonly property int visibleParticipants: Math.min(avatarLimit, DiscordVoice.participantCount)

    readonly property real effectiveAvatarSize: gridMode
        ? (visibleParticipants <= 1 ? Math.max(72, root.participantAvatarSize * 1.5)
            : (visibleParticipants <= 4 ? Math.max(56, root.participantAvatarSize * 1.2)
            : root.participantAvatarSize))
        : root.participantAvatarSize

    readonly property real participantCellWidth: columnMode
        ? Math.max(176, effectiveAvatarSize + 116 + 8)
        : Math.max(effectiveAvatarSize,
            (gridMode ? 96 : 76) + (participantBackground === "name" ? 16 : 0))
    readonly property real participantStride: participantCellWidth
        + (columnMode ? 6 : (gridMode ? 12 : 16))
    readonly property int participantColumns: {
        if (columnMode) return 1;
        if (gridMode) {
            if (visibleParticipants <= 1) return 1;
            if (visibleParticipants <= 2) return 2;
            if (visibleParticipants <= 4) return 2;
            if (visibleParticipants <= 6) return 3;
            if (visibleParticipants <= 9) return 3;
            return 4;
        }
        return Math.max(1, Math.min(visibleParticipants,
            Math.floor((maxContentWidth + 16) / participantStride)))
    }
    readonly property real participantGridWidth: participantColumns > 0
        ? participantColumns * participantStride
            - (columnMode ? 6 : (gridMode ? 12 : 16))
        : 0

    implicitWidth: Math.max(
        root.autoResize ? content.implicitWidth + 12 * 2 : (columnMode ? 256 : 344),
        participantGridWidth + 12 * 2)
    implicitHeight: content.implicitHeight + 24
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

    property string installMessage: ""

    Process {
        id: installProcess
        command: ["bash", `${Directories.scriptPath}/discordVoice/vencord-companion/install.sh`]
        stdout: SplitParser { onRead: data => console.log("[DiscordVoice Companion Install]", data) }
        stderr: SplitParser { onRead: data => {
            console.warn("[DiscordVoice Companion Install Error]", data);
            root.installMessage = data.trim();
        }}
        onStarted: {
            root.installMessage = "";
        }
        onExited: (code, status) => {
            if (code === 0) {
                root.installMessage = "Installed! Restart your Discord client.";
                DiscordVoice.recheck();
            } else if (!root.installMessage) {
                root.installMessage = "Failed (exit code " + code + ")";
            }
        }
    }

    ColumnLayout {
        id: content
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 12
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            DiscordGlyph {
                implicitSize: 36
                iconSize: 20
                color: Appearance.colors.colPrimaryContainer
                iconColor: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
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
                    Layout.fillWidth: true
                    text: DiscordVoice.inVoice
                        ? `${DiscordVoice.participantCount} participant${DiscordVoice.participantCount === 1 ? "" : "s"}`
                        : (DiscordVoice.errorMessage || "Discord voice overlay")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
            }

            RowLayout {
                visible: DiscordVoice.inVoice
                spacing: 0

                RippleButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: DiscordVoice.setMuted(!DiscordVoice.muted)
                    contentItem: MaterialShapeWrappedMaterialSymbol {
                        anchors.centerIn: parent
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
                        anchors.centerIn: parent
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
        }

        GridLayout {
            visible: DiscordVoice.participantCount > 0
            Layout.fillWidth: root.columnMode || root.gridMode
            Layout.alignment: Qt.AlignHCenter
            columns: root.participantColumns
            rowSpacing: 6
            columnSpacing: root.columnMode ? 6 : (root.gridMode ? 12 : 16)
            Repeater {
                model: DiscordVoice.participantModel
                ParticipantAvatar {
                    required property int index
                    visible: index < root.avatarLimit
                    avatarSize: root.effectiveAvatarSize
                    showName: true
                    maxNameWidth: root.columnMode ? 116 : (root.gridMode ? 96 : 76)
                    backgroundMode: root.participantBackground
                    backgroundOpacity: root.participantBackgroundOpacity
                    horizontalLayout: root.columnMode
                    nameOnLeft: root.namesOnLeft
                    Layout.fillWidth: root.columnMode || root.gridMode
                    Layout.fillHeight: root.gridMode
                }
            }
        }

        RippleButton {
            visible: DiscordVoice.status === "auth_required" || DiscordVoice.status === "authorizing" || (!root.companionReady && root.isVencordClient)
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
                else {
                    root.installMessage = "Installing...";
                    installProcess.running = true;
                }
            }
            StyledText {
                anchors.centerIn: parent
                text: {
                    if (installProcess.running) return "Installing Companion…";
                    if (root.installMessage !== "") return root.installMessage;
                    if (DiscordVoice.status === "authorizing") return "Waiting for Discord…";
                    if (root.isVencordClient && !root.companionReady) return "Install Companion";
                    return "Authorize Discord";
                }
                color: Appearance.colors.colOnPrimary
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledToolTip {
                visible: root.installMessage !== ""
                text: root.installMessage
            }
        }

        StyledText {
            visible: root.isVencordClient && !root.companionReady
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Make sure Discord/Vesktop is closed during installation")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }
}
