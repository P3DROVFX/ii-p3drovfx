import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Every favorite as a row; a click opens it. Editing lives in Settings. */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var sites: panel.tile?.sites ?? []

    spacing: 3

    Repeater {
        model: panel.sites
        delegate: RippleButton {
            id: row
            required property var modelData
            required property int index
            Layout.fillWidth: true
            implicitHeight: 56
            buttonRadius: row.index === 0 ? ClockStyle.radiusNormal : ClockStyle.radiusSmall
            colBackground: ClockStyle.colField
            colBackgroundHover: ClockStyle.colFieldHover
            colRipple: ClockStyle.colSurfaceActive
            onClicked: {
                panel.tile?.open(row.modelData);
                panel.host?.closePanel();
            }
            contentItem: Item {
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 14
                    spacing: 12
                    SiteIcon {
                        implicitWidth: 36
                        implicitHeight: 36
                        url: row.modelData.url
                        title: row.modelData.title ?? ""
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.title || row.modelData.url
                            color: ClockStyle.colOnSurface
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(row.modelData.url).replace(/^https?:\/\/(www\.)?/, "")
                            color: ClockStyle.colOnSurfaceVariant
                            font.pixelSize: ClockStyle.textSmall
                            elide: Text.ElideRight
                        }
                    }
                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: 16
                        color: ClockStyle.colOnSurfaceVariant
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.sites.length === 0
        implicitHeight: 72
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        StyledText {
            anchors.centerIn: parent
            text: Translation.tr("No favorites yet")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
        }
    }

    ClockButton {
        Layout.fillWidth: true
        Layout.topMargin: 6
        symbol: "edit"
        label: Translation.tr("Edit favorites")
        onClicked: {
            panel.host?.closePanel();
            GlobalStates.openSettingsPage("dock", "widgets/DockUtilitiesConfig.qml");
        }
    }
}
