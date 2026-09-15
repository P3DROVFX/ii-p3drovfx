pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Reusable content for the AI plan-usage popup. Rendered either inside the
// bar's StyledPopup window (bar) or inside the shelf's in-window chipPopup
// slot (akebono shelf). Drive the entrance animation by binding `opened` and
// `popupOpenProgress`.
ColumnLayout {
    id: ctn

    property bool opened: false
    property real popupOpenProgress: 0.0
    readonly property int cardWidth: 420
    property int popupRadius: Appearance.rounding.large

    spacing: 0
    readonly property bool startAnim: ctn.opened && ctn.popupOpenProgress > 0.6

    Item {
        id: providersHost

        Layout.fillWidth: true
        Layout.minimumWidth: ctn.cardWidth
        implicitHeight: Math.min(providersColumn.implicitHeight, 430)
        visible: AiPlanUsage.displayProviders.length > 0
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: providersHost.width
                height: providersHost.height
                radius: ctn.popupRadius
            }
        }

        StyledFlickable {
            id: providersFlick

            anchors.fill: parent
            contentHeight: providersColumn.implicitHeight
            clip: true
            interactive: contentHeight > height

            ColumnLayout {
                id: providersColumn

                width: providersFlick.width
                spacing: 8

                Repeater {
                    id: providerRepeater
                    model: AiPlanUsage.displayProviders

                    delegate: AiProviderQuotaCard {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        providerData: modelData
                        startAnim: ctn.startAnim
                        animDelay: Math.min(index, 3)
                            * Math.round(Appearance.animation.elementMoveFast.duration / 3)
                        accentColor: index % 3 === 0
                            ? Appearance.colors.colSecondary
                            : index % 3 === 1
                                ? Appearance.colors.colTertiary
                                : Appearance.colors.colPrimary
                        accentContainer: index % 3 === 0
                            ? Appearance.colors.colSecondaryContainer
                            : index % 3 === 1
                                ? Appearance.colors.colTertiaryContainer
                                : Appearance.colors.colPrimaryContainer
                        onAccentContainer: index % 3 === 0
                            ? Appearance.colors.colOnSecondaryContainer
                            : index % 3 === 1
                                ? Appearance.colors.colOnTertiaryContainer
                                : Appearance.colors.colOnPrimaryContainer
                    }
                }

                // Bottom spacer: prevent the last card from sitting flush
                // against the popup's rounded bottom corner.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Appearance.rounding.normal
                }
            }
        }
    }

    NoticeBox {
        visible: AiPlanUsage.displayProviders.length === 0
        Layout.minimumWidth: ctn.cardWidth
        Layout.fillWidth: true
        materialIcon: "cloud_off"
        text: AiPlanUsage.errorMessage.length > 0
            ? AiPlanUsage.errorMessage
            : Translation.tr("No enabled AI service has quota data yet.")
    }
}