pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * `badge` variant of the Sculpt Bluetooth widget — the weather-cookie layout.
 *
 * The charge sits inside a scalloped cookie, and the cookie's outline is the
 * charge's mood: a sunny burst when there is plenty, a softer cookie in the
 * middle, a sharp boom when it runs low (the shape morphs, nothing spins). The
 * device's glyph rides on a small disc overlapping the cookie's corner, and the
 * name with a one-word status sits beside it in two type voices.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property bool hovered: false
    property BarWidgetPalette tones
    property bool low: false
    property string deviceName: ""
    property string glyph: "bluetooth"
    property bool hasBattery: false
    property real battery: 0
    property bool showName: true
    property int deviceCount: 1

    readonly property bool named: root.showName && !root.vertical
    readonly property int cookieShape: !root.hasBattery
        ? MaterialShape.Shape.Cookie6Sided
        : root.battery > 0.5
            ? MaterialShape.Shape.Sunny
            : root.battery > 0.15
                ? MaterialShape.Shape.Cookie9Sided
                : MaterialShape.Shape.SoftBoom
    readonly property real discSize: Math.round(root.thickness * 0.46)

    implicitWidth: root.vertical ? root.thickness : root.thickness + (root.named ? labels.implicitWidth + 8 : 0)
    implicitHeight: root.thickness

    Item {
        id: cookieSlot
        width: root.thickness
        height: root.thickness

        MaterialShape {
            id: cookie
            anchors.centerIn: parent
            implicitSize: root.thickness
            shape: root.cookieShape
            color: root.hovered ? root.tones.colBackgroundHover : root.tones.colBackground

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(cookie)
            }

            StyledText {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                anchors.verticalCenterOffset: -1
                visible: root.hasBattery
                text: Math.round(root.battery * 100)
                color: root.tones.colOnBackground
                font.family: Appearance.font.family.title
                font.pixelSize: Math.round(root.thickness * 0.4)
                font.variableAxes: ({
                    "wght": 800,
                    "ROND": 100
                })
                font.features: ({
                    "tnum": 1
                })
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.hasBattery
                text: root.glyph
                fill: 1
                iconSize: Math.round(root.thickness * 0.5)
                color: root.tones.colOnBackground
            }
        }

        // The device, overlapping the cookie's corner.
        Rectangle {
            visible: root.hasBattery
            x: root.thickness - root.discSize + 2
            y: root.thickness - root.discSize + 1
            width: root.discSize
            height: root.discSize
            radius: root.discSize / 2
            color: root.tones.colBackgroundVariant

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.glyph
                fill: 1
                iconSize: Math.round(root.discSize * 0.66)
                color: root.tones.colOnBackgroundVariant
            }
        }
    }

    Column {
        id: labels
        visible: root.named
        x: root.thickness + 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: -1

        StyledText {
            width: Math.min(implicitWidth, 104)
            text: root.deviceName
            elide: Text.ElideRight
            color: root.tones.colBare
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledText {
            text: root.low
                ? Translation.tr("Charge soon")
                : root.deviceCount > 1
                    ? Translation.tr("%1 devices").arg(root.deviceCount)
                    : Translation.tr("Connected")
            color: root.low ? Appearance.colors.colError : root.tones.colBare
            opacity: root.low ? 1 : 0.7
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.variableAxes: ({
                "wght": 420,
                "wdth": 100,
                "slnt": -10,
                "ROND": 100
            })
        }
    }
}
