import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    implicitWidth: container.width
    implicitHeight: container.height

    component HDText : Text {
        renderType: Text.QtRendering
    }
    component HDMaterialSymbol : MaterialSymbol {
        renderType: Text.QtRendering
    }

    property int batteryLevel: 100
    property bool isCharging: false
    property bool isPowerSaving: false

    property real boundedBatteryLevel: Math.max(0, Math.min(100, root.batteryLevel))

    property real batteryWidthScale: 1.55
    property real batteryHeightScale: 0.80
    property real batteryRadiusScale: 0.3
    property real capHeightScale: 0.35
    property real textSizeScale: 0.85

    property color colorFillNormal: Appearance.colors.colOnSurface
    property color colorFillCharging: "#18CC47"
    property color colorFillWarning: "#ea4335"
    property color colorFillPowerSaving: "#fbbc04"

    property color currentFillColor: {
        if (isCharging)
            return colorFillCharging;
        if (isPowerSaving)
            return colorFillPowerSaving;
        if (boundedBatteryLevel <= 20)
            return colorFillWarning;
        return colorFillNormal;
    }

    property color colorEmptyTrack: Qt.rgba(colorFillNormal.r, colorFillNormal.g, colorFillNormal.b, 0.3)

    property color colorTextEmpty: colorFillNormal
    property color colorTextFilled: Appearance.colors.colOnSurface

    property color colorBolt: colorFillNormal

    property real batteryWidth: root.height * batteryWidthScale
    property real batteryHeight: root.height * batteryHeightScale

    Item {
        id: container
        width: batteryWidth + (root.isCharging || root.isPowerSaving ? root.height * 0.65 : root.height * 0.15)
        height: root.height
        anchors.centerIn: parent

        Item {
            id: batteryCapContainer
            visible: !root.isCharging && !root.isPowerSaving
            height: batteryHeight * capHeightScale
            width: batteryHeight * 0.12
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: batteryMaskedRender.right
            anchors.leftMargin: 1
            clip: true

            Rectangle {
                width: parent.width * 2
                height: parent.height
                radius: height / 2
                color: root.colorEmptyTrack
                anchors.right: parent.right
            }
        }

        Item {
            id: batteryBase
            width: batteryWidth
            height: batteryHeight
            anchors.left: container.left
            anchors.verticalCenter: parent.verticalCenter
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: batteryHeight * batteryRadiusScale
                color: root.colorEmptyTrack

                HDText {
                    anchors.fill: parent
                    text: root.boundedBatteryLevel
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.round(parent.height * textSizeScale)
                    font.bold: true
                    color: root.colorTextEmpty
                    verticalAlignment: Text.AlignTop
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: Math.round(parent.height * 0.01)
                }
            }

            Item {
                id: fillWrapper
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * (root.boundedBatteryLevel / 100)
                clip: true

                Rectangle {
                    width: batteryBase.width
                    height: batteryBase.height
                    radius: batteryBase.height * batteryRadiusScale
                    color: root.currentFillColor
                }

                HDText {
                    width: batteryBase.width
                    height: batteryBase.height
                    text: root.boundedBatteryLevel

                    font.pixelSize: Math.round(batteryBase.height * textSizeScale)
                    font.family: Appearance.font.family.title
                    font.weight: Font.Black
                    color: root.colorTextFilled
                    verticalAlignment: Text.AlignTop
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: Math.round(batteryBase.height * 0.01)
                }
            }
        }

        Item {
            id: boltMask
            width: batteryBase.width
            height: batteryBase.height
            anchors.left: batteryBase.left
            anchors.verticalCenter: batteryBase.verticalCenter
            visible: false

            Item {
                visible: root.isCharging || root.isPowerSaving
                anchors.left: parent.right
                anchors.leftMargin: -batteryHeight * 0.35
                anchors.verticalCenter: parent.verticalCenter
                width: batteryHeight * 1.15
                height: batteryHeight * 1.15

                property string sym: root.isCharging ? "bolt" : "add"
                property real symSize: batteryHeight * 1.15
                property real outline: Math.max(1, Math.round(batteryHeight * 0.08))

                HDMaterialSymbol {
                    text: parent.sym
                    iconSize: parent.symSize
                    fill: 1
                    color: "black"
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -parent.outline
                }
                HDMaterialSymbol {
                    text: parent.sym
                    iconSize: parent.symSize
                    fill: 1
                    color: "black"
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: parent.outline
                }
                HDMaterialSymbol {
                    text: parent.sym
                    iconSize: parent.symSize
                    fill: 1
                    color: "black"
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -parent.outline
                }
                HDMaterialSymbol {
                    text: parent.sym
                    iconSize: parent.symSize
                    fill: 1
                    color: "black"
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: parent.outline
                }
                HDMaterialSymbol {
                    text: parent.sym
                    iconSize: parent.symSize
                    fill: 1
                    color: "black"
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -parent.outline
                    anchors.verticalCenterOffset: -parent.outline
                }
                HDMaterialSymbol {
                    text: parent.sym
                    iconSize: parent.symSize
                    fill: 1
                    color: "black"
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: parent.outline
                    anchors.verticalCenterOffset: parent.outline
                }
                HDMaterialSymbol {
                    text: parent.sym
                    iconSize: parent.symSize
                    fill: 1
                    color: "black"
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -parent.outline
                    anchors.verticalCenterOffset: parent.outline
                }
                HDMaterialSymbol {
                    text: parent.sym
                    iconSize: parent.symSize
                    fill: 1
                    color: "black"
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: parent.outline
                    anchors.verticalCenterOffset: -parent.outline
                }
            }
        }

        OpacityMask {
            id: batteryMaskedRender
            anchors.fill: batteryBase
            source: batteryBase
            maskSource: boltMask
            invert: true
        }

        Item {
            visible: root.isCharging || root.isPowerSaving
            anchors.left: batteryMaskedRender.right
            anchors.leftMargin: -batteryHeight * 0.35
            anchors.verticalCenter: parent.verticalCenter
            width: batteryHeight * 1.15
            height: batteryHeight * 1.15

            property string sym: root.isCharging ? "bolt" : "add"
            property real symSize: batteryHeight * 1.15

            HDMaterialSymbol {
                anchors.centerIn: parent
                text: parent.sym
                iconSize: parent.symSize
                fill: 1
                color: root.colorBolt
            }
        }
    }
}
