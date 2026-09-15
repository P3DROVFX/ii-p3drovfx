pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import "../../../ii/bar/shared/cards"

// Shelf-hosted popup for the dictation chip. Mirrors the bar's dictation popup
// (hero + target window + action buttons) driven by DictationService directly,
// positioned by the shelf's own chip popup container instead of a bar-anchored
// PanelWindow.
Item {
    id: root

    property var shelf

    readonly property bool transcribing: DictationService.transcribing
    readonly property bool busy: DictationService.busy
    readonly property bool idleButton: !root.busy && (Config.options?.dictation?.alwaysShowIndicator ?? false)
    readonly property bool recording: DictationService.recording
    readonly property int elapsedSeconds: Math.floor(DictationService.elapsedMs / 1000)

    readonly property Toplevel targetWindow: ToplevelManager.activeToplevel
    readonly property string targetTitle: {
        const title = root.targetWindow?.title ?? "";
        return title.length > 0 ? title : Translation.tr("No focused window");
    }

    implicitWidth: 384
    implicitHeight: 125 + 10 + 54 + 10 + 38

    function formatTime(seconds) {
        const m = Math.floor(seconds / 60);
        const s = seconds % 60;
        return Translation.tr("%1:%2").arg(m).arg(String(s).padStart(2, "0"));
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        radius: Appearance.rounding.full
        color: Appearance.colors.colSurfaceContainerHigh
    }

    ColumnLayout {
        id: panelLayout
        anchors.fill: parent
        spacing: 10

        HeroCard {
            Layout.fillWidth: true
            compactMode: true
            implicitWidth: 360
            implicitHeight: 125
            titleSize: Appearance.font.pixelSize.larger
            subtitleSize: Appearance.font.pixelSize.smaller

            icon: root.transcribing ? "graphic_eq" : "mic"
            title: {
                if (root.transcribing)
                    return Translation.tr("Transcribing…");
                if (root.idleButton)
                    return Translation.tr("Dictate");
                return Translation.tr("Dictating…");
            }
            subtitle: {
                if (root.transcribing)
                    return Translation.tr("Turning speech into text");
                if (root.idleButton)
                    return DictationService.available
                        ? Translation.tr("Click to start dictating")
                        : Translation.tr("Not ready — see Settings");
                return Config.options.dictation.outputMode === "clipboard"
                    ? Translation.tr("Click to stop and copy text")
                    : Translation.tr("Click to stop and insert text");
            }

            pillText: root.busy ? root.formatTime(root.elapsedSeconds) : ""
            pillIcon: root.busy ? "timer" : ""
            pillColor: root.transcribing ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
            pillTextColor: Appearance.colors.colOnPrimary
            pillIconColor: Appearance.colors.colOnPrimary
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: targetRow.implicitHeight + 18
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            RowLayout {
                id: targetRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialSymbol {
                    text: "web_asset"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.targetTitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: DictationService.languageBadge
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                visible: root.idleButton
                buttonRadius: Appearance.rounding.full
                materialIcon: "mic"
                mainText: Translation.tr("Start dictating")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: {
                    DictationService.toggle();
                    root.shelf?.closeChipPopup();
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                visible: root.busy
                buttonRadius: Appearance.rounding.full
                materialIcon: "keyboard_tab"
                mainText: Config.options.dictation.outputMode === "clipboard"
                    ? Translation.tr("Stop & copy")
                    : Translation.tr("Stop & insert")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: {
                    DictationService.stop();
                    root.shelf?.closeChipPopup();
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                visible: root.busy
                buttonRadius: Appearance.rounding.full
                materialIcon: "delete"
                mainText: Translation.tr("Discard")
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive
                colText: Appearance.colors.colOnErrorContainer
                onClicked: {
                    DictationService.discard();
                    root.shelf?.closeChipPopup();
                }
            }
        }
    }
}