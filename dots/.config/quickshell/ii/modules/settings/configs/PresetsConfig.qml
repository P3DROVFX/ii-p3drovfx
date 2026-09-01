import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    forceWidth: false

    ContentSection {
        icon: "style"
        title: Translation.tr("Presets")
        Layout.fillWidth: true

        ConfigPresetsView {
            id: presetsView
            text: Translation.tr("Preset Manager")
            onApplyRequested: (name, scanResult) => {
                page.pendingPreset = name;
                page.pendingScan = scanResult;
                page.scanDetailsShown = false;
                applyDialog.show = true;
            }
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: -20
        text: Translation.tr('Not all options are available in this app. You should also check the config file by hitting the "Config file" button on the topleft corner or opening ~/.config/illogical-impulse/config.json manually.')

        RippleButtonWithIcon {
            id: copyPathButton
            property bool justCopied: false
            buttonRadius: Appearance.rounding.small
            materialIcon: justCopied ? "check" : "content_copy"
            mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
            onClicked: {
                copyPathButton.justCopied = true;
                Quickshell.clipboardText = FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                revertTextTimer.restart();
            }
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            Timer {
                id: revertTextTimer
                interval: 1500
                onTriggered: {
                    copyPathButton.justCopied = false;
                }
            }
        }
    }

    Connections {
        target: Config.options.appearance.palette
        function onTypeChanged() {
            page.showRestartFab = true;
        }
    }

    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            page.showRestartFab = true;
        }
    }

    // ── Apply confirmation ────────────────────────────────────────
    // A preset is a whole config file, and a few config keys are commands the
    // shell runs. Nothing is written until what those commands are has been
    // put in front of whoever is applying it.
    property string pendingPreset: ""
    property var pendingScan: null
    property bool scanDetailsShown: false

    readonly property bool scanUsable: page.pendingScan && page.pendingScan.ok === true
    readonly property var scanGroups: page.scanUsable ? page.pendingScan.groups : []
    readonly property int scanTotal: page.scanUsable ? page.pendingScan.total : 0

    // How many findings of one group are spelled out before the rest are
    // summed up, so one crowded preset cannot push the buttons off screen.
    readonly property int scanDetailLimit: 6

    function riskIcon(groupId) {
        if (groupId === "shell") return "terminal";
        if (groupId === "ai") return "smart_toy";
        if (groupId === "network") return "public";
        return "help";
    }

    function riskLabel(group) {
        if (group.id === "shell")
            return Translation.tr("Commands it can run on your system: %1").arg(group.count);
        if (group.id === "ai")
            return Translation.tr("Assistant permissions it widens: %1").arg(group.count);
        if (group.id === "network")
            return Translation.tr("Servers and search engines it redirects: %1").arg(group.count);
        return Translation.tr("Other settings that read like commands: %1").arg(group.count);
    }

    WindowDialog {
        id: applyDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        preferredDialogWidth: 520
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr('Apply "%1"?').arg(page.pendingPreset)
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Your current settings are saved first. Anything tied to this machine — API keys, save folders, monitor names and your profile — is kept as it is.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: !page.scanUsable
            materialIcon: "help"
            text: Translation.tr("This preset could not be inspected, so there is no telling what it changes. Apply it only if you trust where it came from.")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            visible: page.scanUsable && page.scanTotal === 0
            text: Translation.tr("Nothing in this preset runs commands or sends your data anywhere new.")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: page.scanTotal > 0

            Repeater {
                model: page.scanGroups

                delegate: Rectangle {
                    id: riskCard
                    required property var modelData
                    readonly property bool severe: riskCard.modelData.severity === "high"

                    Layout.fillWidth: true
                    implicitHeight: riskColumn.implicitHeight + 20
                    radius: Appearance.rounding.small
                    color: riskCard.severe ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer

                    ColumnLayout {
                        id: riskColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialSymbol {
                                text: page.riskIcon(riskCard.modelData.id)
                                iconSize: 18
                                color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: page.riskLabel(riskCard.modelData)
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 26
                            spacing: 6
                            visible: page.scanDetailsShown

                            Repeater {
                                model: riskCard.modelData.items.slice(0, page.scanDetailLimit)

                                delegate: ColumnLayout {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        wrapMode: Text.Wrap
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                                        opacity: 0.8
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: riskCard.modelData.count > page.scanDetailLimit
                                text: Translation.tr("and %1 more").arg(riskCard.modelData.count - page.scanDetailLimit)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                                opacity: 0.8
                            }
                        }
                    }
                }
            }
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Presets shared by other people are used at your own discretion. They are not reviewed by this project, and no responsibility is taken for what one does to your system.")
            color: Appearance.colors.colOnSurfaceVariant
            font.italic: true
        }

        WindowDialogButtonRow {
            Layout.fillWidth: true

            DialogButton {
                visible: page.scanTotal > 0
                buttonText: page.scanDetailsShown ? Translation.tr("Hide details") : Translation.tr("Show details")
                onClicked: page.scanDetailsShown = !page.scanDetailsShown
            }

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: applyDialog.show = false
            }

            DialogButton {
                buttonText: Translation.tr("Apply")
                colEnabled: page.scanTotal > 0 ? Appearance.colors.colError : Appearance.colors.colPrimary
                onClicked: {
                    presetsView.applyPreset(page.pendingPreset);
                    applyDialog.show = false;
                }
            }
        }
    }

    property bool showRestartFab: false

    FloatingActionButton {
        id: restartFab
        parent: page.parent
        anchors {
            right: parent ? parent.right : undefined
            bottom: parent ? parent.bottom : undefined
            margins: 30
        }
        z: 100
        iconText: "restart_alt"
        buttonText: Translation.tr("Restart Shell")
        expanded: false
        visible: opacity > 0
        opacity: page.showRestartFab ? 1 : 0
        scale: opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        colBackground: Appearance.colors.colTertiaryContainer
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colRipple: Appearance.colors.colTertiaryContainerActive
        colOnBackground: Appearance.colors.colOnTertiaryContainer

        onClicked: {
            Quickshell.execDetached(["bash", "-c", "qs kill -c ii && qs -c ii &"]);
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: restartFab.expanded = true
            onExited: restartFab.expanded = false
        }
    }
}
