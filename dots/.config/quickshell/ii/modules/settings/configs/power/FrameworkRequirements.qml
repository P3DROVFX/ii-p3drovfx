import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A Framework laptop the service can't drive yet: what is there, what is missing. The fans
 * need framework_tool (framework-system package) for the duty and the cros_ec kernel
 * driver for the readings; the battery and LED settings need only framework_tool.
 */
Rectangle {
    id: root

    readonly property var requirements: [
        { "ok": FanControl.isFramework, "symbol": "laptop",
          "title": Translation.tr("Framework Laptop"),
          "detail": `${FanControl.caps?.vendor ?? ""} ${FanControl.caps?.product ?? ""}`.trim() },
        { "ok": FanControl.frameworkToolInstalled, "symbol": "terminal",
          "title": Translation.tr("framework_tool"),
          "detail": FanControl.frameworkToolInstalled
              ? Translation.tr("Found. Sets the fan duty, charge limit and fingerprint light.")
              : Translation.tr("Install the framework-system package, which provides it.") },
        { "ok": FanControl.frameworkEcDriver, "symbol": "memory",
          "title": Translation.tr("cros_ec kernel driver"),
          "detail": FanControl.frameworkEcDriver
              ? Translation.tr("Loaded. Temperatures and fan speeds come from it.")
              : Translation.tr("Load cros_ec_lpcs and cros_ec_hwmon (Linux 6.11 or newer).") }
    ]

    implicitHeight: column.implicitHeight + 40
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            MaterialShapeWrappedMaterialSymbol {
                text: "checklist"
                iconSize: 24
                padding: 12
                shape: MaterialShape.Shape.Cookie7Sided
                color: Appearance.colors.colTertiaryContainer
                colSymbol: Appearance.colors.colOnTertiaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: Translation.tr("Framework support")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("The fans follow the firmware until both are in place.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
        }

        Repeater {
            model: root.requirements
            delegate: Rectangle {
                id: requirement
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: reqRow.implicitHeight + 24
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: reqRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 16
                    }
                    spacing: 12

                    MaterialShapeWrappedMaterialSymbol {
                        text: requirement.modelData.symbol
                        iconSize: 18
                        padding: 8
                        shape: requirement.modelData.ok ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Circle
                        color: requirement.modelData.ok ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer
                        colSymbol: requirement.modelData.ok ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: requirement.modelData.title
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: requirement.modelData.detail
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }
                    MaterialSymbol {
                        text: requirement.modelData.ok ? "check_circle" : "cancel"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.huge
                        color: requirement.modelData.ok ? Appearance.colors.colPrimary : Appearance.colors.colError
                    }
                }
            }
        }
    }
}
