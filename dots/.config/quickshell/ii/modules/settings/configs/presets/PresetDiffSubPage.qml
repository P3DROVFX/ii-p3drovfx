import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Sub-page for inspecting differences between local and remote preset settings.
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack
    property bool showBackButton: true

    property string presetName: ""
    property bool incoming: false
    property var result: null
    property bool loading: false

    readonly property var changes: root.result && root.result.ok === true
        ? (root.result.changes ?? []) : []
    readonly property int total: root.result && root.result.ok === true
        ? (root.result.total ?? 0) : 0

    function setDiff(name, wantIncoming) {
        root.presetName = name;
        root.incoming = wantIncoming === true;
        root.result = null;
        root.loading = true;
        PresetStore.diff(name, root.incoming);
    }

    Connections {
        target: PresetStore

        function onDiffReady(name, res) {
            if (name !== root.presetName)
                return;
            root.loading = false;
            root.result = res;
        }
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
                    text: root.incoming
                        ? Translation.tr("Incoming update changes")
                        : Translation.tr("Exported release changes")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    text: Translation.tr("Preset: \"%1\"").arg(root.presetName)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: root.loading
        }

        // Section: Summary & Changes List
        ContentSection {
            title: Translation.tr("Changes (%1)").arg(root.total)
            icon: "difference"
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                NoticeBox {
                    Layout.fillWidth: true
                    visible: !root.loading && root.total === 0
                    materialIcon: "check"
                    text: Translation.tr("No differences found. Settings are identical.")
                }

                Repeater {
                    model: root.changes

                    delegate: Rectangle {
                        id: changeCard
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: changeCol.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainerLow
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant

                        ColumnLayout {
                            id: changeCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Key path
                                StyledText {
                                    Layout.fillWidth: true
                                    text: changeCard.modelData.path ?? ""
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideMiddle
                                }

                                // Kind badge (added / removed / changed)
                                Rectangle {
                                    implicitHeight: 22
                                    implicitWidth: kindText.implicitWidth + 12
                                    radius: Appearance.rounding.full
                                    color: changeCard.modelData.kind === "added"
                                        ? Appearance.colors.colTertiaryContainer
                                        : (changeCard.modelData.kind === "removed"
                                            ? Appearance.colors.colErrorContainer
                                            : Appearance.colors.colSecondaryContainer)

                                    StyledText {
                                        id: kindText
                                        anchors.centerIn: parent
                                        text: changeCard.modelData.kind ?? "changed"
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: changeCard.modelData.kind === "added"
                                            ? Appearance.colors.colOnTertiaryContainer
                                            : (changeCard.modelData.kind === "removed"
                                                ? Appearance.colors.colOnErrorContainer
                                                : Appearance.colors.colOnSecondaryContainer)
                                    }
                                }
                            }

                            // Old vs New value
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: changeCard.modelData.before !== undefined || changeCard.modelData.after !== undefined

                                StyledText {
                                    visible: changeCard.modelData.before !== undefined
                                    text: `- ${JSON.stringify(changeCard.modelData.before)}`
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colError
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    visible: changeCard.modelData.after !== undefined
                                    text: `+ ${JSON.stringify(changeCard.modelData.after)}`
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colTertiary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }
        }

        // Action Button
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 12

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Close")
                onClicked: root.goBack()
            }
        }
    }
}
