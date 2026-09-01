pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/** Native transcript projection for Gmail metadata and explicit body DTOs. */
Item {
    id: root

    required property var card
    property bool compact: false

    implicitHeight: surface.implicitHeight

    Rectangle {
        id: surface
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: content.implicitHeight + Appearance.rounding.normal * 2
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Appearance.rounding.normal
            spacing: Appearance.rounding.unsharpenmore

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.rounding.unsharpenmore

                MaterialSymbol {
                    text: "mail"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.card?.summary ?? "Gmail")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }

            Repeater {
                model: ScriptModel {
                    values: Array.from(root.card?.data?.messages ?? [])
                }

                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Appearance.rounding.unsharpenmore / 2

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const message = modelData?.message ?? modelData ?? ({ });
                            return [String(message.subject ?? "(sem assunto)"), String(message.from ?? "")].filter(value => value.length > 0).join(" · ");
                        }
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: String(modelData?.body ?? "").length > 0
                        text: String(modelData?.body ?? "")
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }
}
