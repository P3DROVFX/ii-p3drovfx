import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The presets you publish: what is out there, at which version, and the two
 * things worth doing to them — seeing what a release would change, and making
 * that release.
 */
ColumnLayout {
    id: root
    spacing: 12
    Layout.fillWidth: true

    signal pushRequested(string name)
    signal diffRequested(string name)

    Component.onCompleted: {
        PresetStore.ensureLoaded();
        PresetStore.refreshAuth();
    }

    GithubSignInPanel {
        Layout.fillWidth: true
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 20
        spacing: 6
        visible: PresetStore.published.length === 0

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "cloud_upload"
            iconSize: 44
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("You have not published anything yet. Open My presets and use the share button on one of them.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    Repeater {
        model: PresetStore.published

        delegate: Rectangle {
            id: publishedRow
            required property var modelData

            readonly property bool working: PresetStore.busyFor(publishedRow.modelData.name)
            // A published preset whose file was deleted locally can still be
            // updated later, but not from what is no longer on disk.
            readonly property bool missing: publishedRow.modelData.present === false

            Layout.fillWidth: true
            implicitHeight: rowColumn.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerLow

            ColumnLayout {
                id: rowColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: publishedRow.modelData.name
                            elide: Text.ElideRight
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("%1 · version %2")
                                .arg(publishedRow.modelData.repo)
                                .arg(publishedRow.modelData.version)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    StyledText {
                        visible: publishedRow.working
                        text: Translation.tr("Working…")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: publishedRow.missing
                    text: Translation.tr("This preset is no longer in your list, so there is nothing to release from.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        materialIcon: "publish"
                        mainText: Translation.tr("Push update")
                        enabled: !publishedRow.working && !publishedRow.missing
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        colText: Appearance.colors.colOnPrimaryContainer
                        onClicked: root.pushRequested(String(publishedRow.modelData.name))
                    }

                    RippleButtonWithIcon {
                        materialIcon: "difference"
                        mainText: Translation.tr("Show diff")
                        enabled: !publishedRow.working && !publishedRow.missing
                        onClicked: root.diffRequested(String(publishedRow.modelData.name))
                    }

                    RippleButtonWithIcon {
                        materialIcon: "link"
                        mainText: Translation.tr("Copy link")
                        onClicked: Quickshell.clipboardText = String(publishedRow.modelData.repoUrl ?? "")
                    }

                    Item { Layout.fillWidth: true }

                    RippleButtonWithIcon {
                        materialIcon: "link_off"
                        mainText: Translation.tr("Stop managing")
                        enabled: !publishedRow.working
                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainerHover
                        colRipple: Appearance.colors.colErrorContainerActive
                        colText: Appearance.colors.colOnErrorContainer
                        onClicked: PresetStore.unlink(String(publishedRow.modelData.name))

                        StyledToolTip {
                            text: Translation.tr("Forgets the repository. The preset and what is already published both stay.")
                        }
                    }
                }
            }
        }
    }
}
