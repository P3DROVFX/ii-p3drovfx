import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Sub-page for publishing updates to already published presets.
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack
    signal requestDiff(string name)
    property bool showBackButton: true

    property string presetName: ""
    property string bump: "patch"
    readonly property bool working: PresetStore.busyFor(root.presetName)
    readonly property var link: PresetStore.linkFor(root.presetName)

    function setPreset(name) {
        root.presetName = name;
        root.bump = "patch";
        notesField.text = "";
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        // Top Navigation Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: Translation.tr("Release update")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    text: root.link
                        ? Translation.tr("Published as %1 (v%2)").arg(root.link.repo).arg(root.link.version)
                        : Translation.tr("Update \"%1\"").arg(root.presetName)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        // Section: Version Bump Selection
        ContentSection {
            title: Translation.tr("Version bump")
            icon: "upgrade"
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Choose how significant this update is according to semantic versioning:")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: [
                            { id: "patch", label: Translation.tr("Patch"), desc: Translation.tr("Tweaks & fixes") },
                            { id: "minor", label: Translation.tr("Minor"), desc: Translation.tr("New settings") },
                            { id: "major", label: Translation.tr("Major"), desc: Translation.tr("Overhaul") }
                        ]

                        delegate: Rectangle {
                            id: bumpOption
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: 56
                            radius: Appearance.rounding.small
                            color: root.bump === modelData.id
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colSurfaceContainerLow
                            border.width: 1
                            border.color: root.bump === modelData.id
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOutlineVariant

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: bumpOption.modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: root.bump === bumpOption.modelData.id ? Font.Bold : Font.Normal
                                    color: root.bump === bumpOption.modelData.id
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnSurface
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: bumpOption.modelData.desc
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: root.bump === bumpOption.modelData.id
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.bump = bumpOption.modelData.id
                            }
                        }
                    }
                }
            }
        }

        // Section: Release Notes
        ContentSection {
            title: Translation.tr("Release notes")
            icon: "edit_note"
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    id: notesField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("What changed in this version? (optional)")
                }
            }
        }

        // Section: Diff Inspection
        ContentSection {
            title: Translation.tr("Review changes")
            icon: "compare_arrows"
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Compare your current local settings with the currently published release.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.Wrap
                }

                RippleButtonWithIcon {
                    materialIcon: "difference"
                    mainText: Translation.tr("View diff")
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSecondaryContainer
                    onClicked: root.requestDiff(root.presetName)
                }
            }
        }

        // Action Buttons Row
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 12

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: root.goBack()
            }

            DialogButton {
                buttonText: Translation.tr("Push update")
                enabled: !root.working
                colEnabled: Appearance.colors.colPrimary
                onClicked: {
                    PresetStore.pushUpdate(root.presetName, "", root.bump, notesField.text.trim(), null);
                    root.goBack();
                }
            }
        }
    }
}
