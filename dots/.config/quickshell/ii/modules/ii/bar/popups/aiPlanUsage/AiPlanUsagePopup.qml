pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import qs.services

StyledPopup {
    id: root

    stickyHover: true
    popupRadius: Appearance.rounding.large

    readonly property int cardWidth: 420

    contentItem: ColumnLayout {
        id: contentLayout

        spacing: 0
        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        Item {
            id: providersHost

            Layout.fillWidth: true
            Layout.minimumWidth: root.cardWidth
            implicitHeight: Math.min(providersColumn.implicitHeight, 430)
            visible: AiPlanUsage.displayProviders.length > 0
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: providersHost.width
                    height: providersHost.height
                    radius: root.popupRadius
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
                            startAnim: contentLayout.startAnim
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
            Layout.minimumWidth: root.cardWidth
            Layout.fillWidth: true
            materialIcon: "cloud_off"
            text: AiPlanUsage.errorMessage.length > 0
                ? AiPlanUsage.errorMessage
                : Translation.tr("No enabled AI service has quota data yet.")
        }
    }
}
