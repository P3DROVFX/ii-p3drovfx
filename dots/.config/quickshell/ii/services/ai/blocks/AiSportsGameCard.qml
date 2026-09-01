pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/** Native transcript projection for the bounded ESPN DTO. */
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
                    text: "sports_score"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.card?.data?.league ?? root.card?.summary ?? "Sports")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }

            Repeater {
                model: ScriptModel {
                    values: Array.from(root.card?.data?.games ?? []).slice(0, 20)
                }

                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: gameColumn.implicitHeight + Appearance.rounding.small * 2
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer3

                    ColumnLayout {
                        id: gameColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Appearance.rounding.small
                        spacing: Appearance.rounding.unsharpenmore / 2

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const home = modelData?.home ?? ({ name: "TBD", score: "" });
                                const away = modelData?.away ?? ({ name: "TBD", score: "" });
                                return `${home.name} ${home.score} · ${away.name} ${away.score}`;
                            }
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer3
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: [String(modelData?.status ?? ""), String(modelData?.venue ?? "")].filter(value => value.length > 0).join(" · ")
                            visible: text.length > 0
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
