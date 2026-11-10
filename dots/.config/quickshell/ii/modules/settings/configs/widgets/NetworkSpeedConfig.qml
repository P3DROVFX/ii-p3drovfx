pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/bar/widgets/networkSpeed"

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    readonly property string style: Config.options.bar.styles.networkSpeed ?? "default"

    NetworkSpeedReadout {
        id: live
    }

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Network speed")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "preview"
        title: Translation.tr("Live preview")

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: root.style === "expressive" ? expressiveHorizontalPreview : defaultHorizontalPreview
                }
            }

            Rectangle {
                Layout.preferredWidth: Appearance.sizes.verticalBarWidth + 28
                Layout.fillHeight: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: root.style === "expressive" ? expressiveVerticalPreview : defaultVerticalPreview
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "swap_horiz"
            text: Translation.tr("Left is the horizontal bar, right is the vertical one. Hover the widget in the bar for the interface name.")
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Design")

        ContentSubsection {
            title: Translation.tr("Visual style")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.networkSpeed
                onSelected: newValue => Config.options.bar.styles.networkSpeed = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "expressive"
            title: Translation.tr("Expressive variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.networkSpeed.expressiveVariant
                onSelected: newValue => Config.options.bar.networkSpeed.expressiveVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Capsule"), icon: "stadium", value: "capsule" },
                    { displayName: Translation.tr("Split"), icon: "splitscreen", value: "split" },
                    { displayName: Translation.tr("Rows"), icon: "table_rows", value: "rows" },
                    { displayName: Translation.tr("Graph"), icon: "bar_chart", value: "graph" }
                ]
            }
        }

        ExpressiveColorModeSubsection {
            visible: root.style === "expressive"
            currentValue: Config.options.bar.networkSpeed.colorMode
            onSelected: newValue => Config.options.bar.networkSpeed.colorMode = String(newValue)
        }
    }

    ContentSection {
        icon: "swap_vert"
        title: Translation.tr("What to show")

        ContentSubsection {
            title: Translation.tr("Direction")

            ConfigSelectionArray {
                currentValue: Config.options.bar.networkSpeed.mode
                onSelected: newValue => Config.options.bar.networkSpeed.mode = String(newValue)
                options: [
                    { displayName: Translation.tr("Both"), icon: "swap_vert", value: "both" },
                    { displayName: Translation.tr("Download"), icon: "download", value: "download" },
                    { displayName: Translation.tr("Upload"), icon: "upload", value: "upload" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Unit")

            ConfigSelectionArray {
                currentValue: Config.options.bar.networkSpeed.unit
                onSelected: newValue => Config.options.bar.networkSpeed.unit = String(newValue)
                options: [
                    { displayName: Translation.tr("Bytes (MB/s)"), icon: "storage", value: "bytes" },
                    { displayName: Translation.tr("Bits (Mbps)"), icon: "wifi", value: "bits" }
                ]
            }
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Behaviour")

        ConfigSwitch {
            buttonIcon: "text_fields"
            text: Translation.tr("Show the unit next to the number")
            checked: Config.options.bar.networkSpeed.showUnit
            onCheckedChanged: Config.options.bar.networkSpeed.showUnit = checked
        }

        ConfigSwitch {
            buttonIcon: "density_small"
            text: Translation.tr("Compact: tighter margins and spacing")
            checked: Config.options.bar.networkSpeed.compact
            onCheckedChanged: Config.options.bar.networkSpeed.compact = checked
        }

        ConfigSwitch {
            buttonIcon: "visibility_off"
            text: Translation.tr("Hide the widget while there is no connection")
            checked: Config.options.bar.networkSpeed.hideWhenOffline
            onCheckedChanged: Config.options.bar.networkSpeed.hideWhenOffline = checked
        }
    }

    ContentSection {
        icon: "monitoring"
        title: Translation.tr("Right now")

        ConfigRow {
            uniform: true

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                StyledText {
                    anchors.centerIn: parent
                    text: live.online ? live.interfaceName : Translation.tr("No active connection")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                StyledText {
                    anchors.centerIn: parent
                    text: "↓ %1 %2   ↑ %3 %4".arg(live.down.number).arg(live.down.unit).arg(live.up.number).arg(live.up.unit)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    Component {
        id: defaultHorizontalPreview
        NetworkSpeedWidget {
            vertical: false
        }
    }

    Component {
        id: defaultVerticalPreview
        NetworkSpeedWidget {
            vertical: true
        }
    }

    Component {
        id: expressiveHorizontalPreview
        ExpressiveNetworkSpeed {
            vertical: false
        }
    }

    Component {
        id: expressiveVerticalPreview
        ExpressiveNetworkSpeed {
            vertical: true
        }
    }
}
