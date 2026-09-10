import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * About this shell: the projects this configuration builds on, newest first,
 * each with its links. Moved off the About page so the update status could
 * come first there.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    component LineageEntry: ContentSubsection {
        id: entry
        property string name: ""
        property string url: ""
        property string urlLabel: ""
        property Component logo: null
        // [{icon, label, url, fill}]
        property var links: []

        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            spacing: 14

            Loader {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                sourceComponent: entry.logo
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    text: entry.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    visible: entry.url !== ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: `<a href='${entry.url}'>${entry.urlLabel !== "" ? entry.urlLabel : entry.url.replace(/^https?:\/\/(www\.)?/, "")}</a>`
                    textFormat: Text.RichText
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    PointingHandLinkHover {}
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                Repeater {
                    model: entry.links

                    delegate: RippleButtonWithIcon {
                        required property var modelData
                        materialIcon: modelData.icon
                        materialIconFill: modelData.fill ?? true
                        mainText: modelData.label
                        onClicked: Qt.openUrlExternally(modelData.url)
                    }
                }
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
                text: Translation.tr("About this shell")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "account_tree"
            title: Translation.tr("Lineage")
            tooltip: Translation.tr("Each project below builds on the one after it.")

            LineageEntry {
                title: Translation.tr("This fork")
                icon: "call_split"
                name: "ii-p3drovfx"
                url: "https://github.com/P3DROVFX/ii-p3drovfx"
                links: [
                    { "icon": "code", "label": Translation.tr("GitHub"), "url": "https://github.com/P3DROVFX/ii-p3drovfx" },
                    { "icon": "adjust", "label": Translation.tr("Issues"), "url": "https://github.com/P3DROVFX/ii-p3drovfx/issues", "fill": false }
                ]
                logo: Image {
                    source: "file://" + Quickshell.shellPath("assets/icons/ii-p3drovfx.png")
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectFit
                }
            }

            LineageEntry {
                title: Translation.tr("Upstream")
                icon: "code"
                name: "ii-vynx"
                url: "https://github.com/vaguesyntax/ii-vynx"
                links: [
                    { "icon": "auto_stories", "label": Translation.tr("Wiki"), "url": "https://github.com/vaguesyntax/ii-vynx/wiki" },
                    { "icon": "adjust", "label": Translation.tr("Issues"), "url": "https://github.com/vaguesyntax/ii-vynx/issues", "fill": false }
                ]
                logo: CustomIcon {
                    source: "ii-vynx"
                }
            }

            LineageEntry {
                title: Translation.tr("Parent dots")
                icon: "deployed_code"
                name: "illogical-impulse"
                url: "https://github.com/end-4/dots-hyprland"
                links: [
                    { "icon": "auto_stories", "label": Translation.tr("Wiki"), "url": "https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/" },
                    { "icon": "favorite", "label": Translation.tr("Sponsor"), "url": "https://github.com/sponsors/end-4" }
                ]
                logo: IconImage {
                    implicitSize: 48
                    source: Quickshell.iconPath("illogical-impulse")
                }
            }

            LineageEntry {
                title: Translation.tr("Distribution")
                icon: "developer_board"
                name: SystemInfo.distroName
                url: SystemInfo.homeUrl
                links: [
                    { "icon": "auto_stories", "label": Translation.tr("Docs"), "url": SystemInfo.documentationUrl },
                    { "icon": "bug_report", "label": Translation.tr("Bugs"), "url": SystemInfo.bugReportUrl }
                ]
                logo: IconImage {
                    implicitSize: 48
                    source: Quickshell.iconPath(SystemInfo.logo)
                }
            }
        }
    }
}
