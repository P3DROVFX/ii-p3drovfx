import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Fork & branch sub-page of About & Updates.
 *
 * Both switches replace the whole ii folder, so each one is confirmed here
 * with what exactly gets replaced, then handed to a terminal window and the
 * Settings window closes: the setup script restarts the shell partway
 * through, and only a terminal keeps the log readable across that.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property bool onP3drovfx: ShellUpdates.activeFork === "p3drovfx" || ShellUpdates.activeFork === "mine"
    readonly property string forkLabel: ShellUpdates.forkLabel(ShellUpdates.activeFork)

    // What the confirmation dialog is about: "branch" or "fork", the
    // argument the script gets, and how the dialog names it.
    property string pendingKind: ""
    property string pendingTarget: ""
    property string pendingLabel: ""

    readonly property var forkPresets: [
        {
            "id": "p3drovfx",
            "label": "II-P3DROVFX",
            "detail": Translation.tr("This fork: the branch switcher and this page come from here"),
            "icon": "fork_right"
        },
        {
            "id": "end4",
            "label": "end-4 (dots-hyprland)",
            "detail": Translation.tr("The original illogical-impulse"),
            "icon": "deployed_code"
        },
        {
            "id": "vynx",
            "label": "ii-vynx",
            "detail": Translation.tr("The upstream this fork tracks"),
            "icon": "cloud_download"
        }
    ]

    function confirm(kind, target, label) {
        subPageRoot.pendingKind = kind;
        subPageRoot.pendingTarget = target;
        subPageRoot.pendingLabel = label;
        confirmDialog.show = true;
    }

    function runPending() {
        confirmDialog.show = false;
        if (subPageRoot.pendingKind === "branch")
            ShellUpdates.launchBranchSwitch(subPageRoot.pendingTarget);
        else if (subPageRoot.pendingKind === "fork")
            ShellUpdates.launchForkSwitch(subPageRoot.pendingTarget);
        else
            return;
        GlobalStates.settingsOpen = false;
    }

    component ForkRow: RippleButton {
        id: forkRow
        property string presetId: ""
        property string label: ""
        property string detail: ""
        property string presetIcon: ""
        readonly property bool isCurrent: ShellUpdates.activeFork === presetId || (presetId === "p3drovfx" && ShellUpdates.activeFork === "mine")

        Layout.fillWidth: true
        implicitHeight: forkRowLayout.implicitHeight + 20
        buttonRadius: Appearance.rounding.small
        colBackground: isCurrent ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: isCurrent ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        enabled: !isCurrent
        onClicked: subPageRoot.confirm("fork", presetId, label)

        contentItem: RowLayout {
            id: forkRowLayout
            spacing: 12

            MaterialSymbol {
                Layout.leftMargin: 4
                text: forkRow.isCurrent ? "check" : forkRow.presetIcon
                iconSize: 22
                color: forkRow.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: forkRow.label
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: forkRow.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: forkRow.isCurrent ? Translation.tr("Current") : forkRow.detail
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: forkRow.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                visible: !forkRow.isCurrent
                Layout.rightMargin: 4
                text: "swap_horiz"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Fork & branch")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Where the checkout stands ──
        ContentSection {
            icon: "hub"
            title: Translation.tr("Current source")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { "icon": "hub", "text": subPageRoot.forkLabel },
                        { "icon": "call_split", "text": ShellUpdates.activeBranch },
                        { "icon": "commit", "text": ShellUpdates.activeCommit.substring(0, 7) }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        visible: modelData.text !== ""
                        implicitWidth: chipLayout.implicitWidth + 24
                        implicitHeight: 32
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer

                        RowLayout {
                            id: chipLayout
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: 16
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                text: modelData.text
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            StyledText {
                visible: ShellUpdates.activeRemote !== ""
                Layout.fillWidth: true
                text: ShellUpdates.activeRemote
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideMiddle
            }
        }

        // ── Branch ──
        ContentSection {
            icon: "fork_right"
            title: Translation.tr("Branch")
            tooltip: Translation.tr("main is what has been tested; dev gets features as they land. Your settings are kept across the switch.")

            ConfigSelectionArray {
                currentValue: subPageRoot.onP3drovfx ? ShellUpdates.activeBranch : null
                onSelected: newValue => {
                    if (newValue === ShellUpdates.activeBranch)
                        return;
                    subPageRoot.confirm("branch", newValue, newValue);
                }
                options: [
                    {
                        "displayName": Translation.tr("main") + " · " + Translation.tr("stable"),
                        "icon": subPageRoot.onP3drovfx && ShellUpdates.activeBranch === "main" ? "check" : "verified",
                        "value": "main",
                        "enabled": subPageRoot.onP3drovfx
                    },
                    {
                        "displayName": Translation.tr("dev") + " · " + Translation.tr("new features"),
                        "icon": subPageRoot.onP3drovfx && ShellUpdates.activeBranch === "dev" ? "check" : "science",
                        "value": "dev",
                        "enabled": subPageRoot.onP3drovfx
                    }
                ]
            }

            StyledText {
                visible: !subPageRoot.onP3drovfx
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                text: Translation.tr("Branches are only offered for the II-P3DROVFX fork here. For another fork, run 'ii-p3drovfx branch <name>' in a terminal.")
            }
        }

        // ── Fork ──
        ContentSection {
            icon: "swap_horiz"
            title: Translation.tr("Fork")
            tooltip: Translation.tr("Replace the ii folder with another fork's latest. Settings are reset to that fork's defaults, since its options differ; a backup of the old folder and settings is kept.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: subPageRoot.forkPresets

                    delegate: ForkRow {
                        required property var modelData
                        presetId: modelData.id
                        label: modelData.label
                        detail: modelData.detail
                        presetIcon: modelData.icon
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8

                MaterialTextField {
                    id: customUrlField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("https://github.com/USER/REPO")
                    readonly property string url: text.trim()
                    readonly property bool valid: /^https?:\/\/github\.com\/[^\/\s]+\/[^\/\s]+\/?$/.test(url)
                }

                RippleButtonWithIcon {
                    Layout.preferredHeight: 44
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    colText: Appearance.colors.colOnSecondaryContainer
                    materialIcon: "download"
                    mainText: Translation.tr("Clone & switch")
                    enabled: customUrlField.valid
                    onClicked: subPageRoot.confirm("fork", customUrlField.url, customUrlField.url.replace(/^https?:\/\/github\.com\//, "").replace(/\/$/, ""))
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                Layout.topMargin: 8
                materialIcon: "info"
                text: Translation.tr("Other forks do not have this page. To come back, run 'ii-p3drovfx fork p3drovfx' in a terminal.")
            }
        }
    }

    WindowDialog {
        id: confirmDialog
        parent: subPageRoot
        anchors.fill: parent
        show: false
        backgroundWidth: 400
        z: 100000
        onDismiss: show = false

        WindowDialogTitle {
            text: Translation.tr("Switch to %1?").arg(subPageRoot.pendingLabel)
        }

        WindowDialogParagraph {
            text: subPageRoot.pendingKind === "branch"
                ? Translation.tr("The ii folder is replaced with the %1 branch of %2. Your settings are kept and the shell restarts. The run happens in a terminal window and this window closes.").arg(subPageRoot.pendingLabel).arg(subPageRoot.forkLabel)
                : Translation.tr("The ii folder is replaced with that fork's latest and your settings are reset to its defaults, since its options differ. A backup of both is kept. The run happens in a terminal window and this window closes.")
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: confirmDialog.show = false
            }

            DialogButton {
                buttonText: Translation.tr("Switch")
                onClicked: subPageRoot.runPending()
            }
        }
    }
}
