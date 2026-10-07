pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.phone
import qs.modules.settings.configs.widgets

/*
 * One page for the Phone widgets - Key (1x1), Deck (2x1), Tower (1x2) - and
 * Send (2x1). The hero is the four of them live, with what they depend on
 * (KDE Connect, scrcpy, LocalSend) and whether it is there.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets

    WidgetPageHeader {
        title: Translation.tr("Phone Widgets Options")
        onBack: root.goBack()
    }

    // [ Tower ][ Deck        ][ Key  ]
    // [       ][ Send        ][ deps ]
    WidgetPreviewStage {
        columns: 4
        rows: 2

        WidgetPreviewSlot {
            rowSpan: 2
            PhoneTowerWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.height / Math.max(1, implicitHeight)
            }
        }
        WidgetPreviewSlot {
            column: 1
            columnSpan: 2
            PhoneDeckWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            PhoneKeyWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            row: 1
            columnSpan: 2
            SendDropWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 3
            row: 1

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 8

                    StyledText {
                        text: Translation.tr("Needs")
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        color: Appearance.colors.colOnLayer2
                    }

                    Repeater {
                        model: [
                            { name: "KDE Connect", ok: KdeConnectService.available, detail: KdeConnectService.hasDevices ? Translation.tr("paired") : Translation.tr("no phone") },
                            { name: "scrcpy", ok: PhoneScrcpyService.available || KdeConnectService.scrcpyAvailable, detail: KdeConnectService.adbReachable ? "ADB" : Translation.tr("no ADB") },
                            { name: "LocalSend", ok: LocalSend.available, detail: LocalSend.cliVersion || "" }
                        ]

                        delegate: Rectangle {
                            id: dep
                            required property var modelData
                            width: parent.width
                            height: 46
                            radius: Appearance.rounding.normal
                            color: dep.modelData.ok ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3

                            MaterialSymbol {
                                id: depIcon
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: dep.modelData.ok ? "check_circle" : "cancel"
                                fill: 1
                                iconSize: 20
                                color: dep.modelData.ok ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                            Column {
                                anchors.left: depIcon.right
                                anchors.leftMargin: 8
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: dep.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: dep.modelData.ok ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    visible: text.length > 0
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: dep.modelData.ok ? dep.modelData.detail : Translation.tr("missing")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: dep.modelData.ok ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Phone Key (1x1)")
        icon: "cast"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "phone_key" }
            WidgetSizeSlider { options: root.widgets.phone_key }
        }
    }

    ContentSection {
        title: Translation.tr("Phone Deck (2x1)")
        icon: "phone_android"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "phone_deck" }
            WidgetSizeSlider { options: root.widgets.phone_deck }
        }
    }

    ContentSection {
        title: Translation.tr("Phone Tower (1x2)")
        icon: "smartphone"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "phone_tower" }
            WidgetSizeSlider { options: root.widgets.phone_tower }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("The phone's picture is the one set in Bluetooth Device Images, else a drawing of its model.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }
        }
    }

    ContentSection {
        title: Translation.tr("Send (2x1)")
        icon: "send_to_mobile"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "send_drop" }
            WidgetSizeSlider { options: root.widgets.send_drop }

            ConfigSelectionArray {
                currentValue: root.widgets.send_drop.backend ?? "kdeconnect"
                onSelected: newValue => root.widgets.send_drop.backend = newValue
                options: [
                    { displayName: "KDE Connect", icon: "smartphone", value: "kdeconnect" },
                    { displayName: "LocalSend", icon: "near_me", value: "localsend" }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("The device is picked on the widget itself and remembered.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
