import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import Qt5Compat.GraphicalEffects

AbstractBackgroundWidget {
    id: root

    configEntryName: "date"

    implicitWidth: 240
    implicitHeight: 240

    Rectangle {
        id: bgRect
        anchors.fill: parent
        anchors.margins: 10
        color: {
            let base = Appearance.colors.colSurfaceContainerHighest;
            return Qt.rgba(base.r, base.g, base.b, 1.0);
        }
        radius: Appearance.rounding.large

        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bgRect.width
                height: bgRect.height
                radius: bgRect.radius
                antialiasing: true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 0

            Rectangle {
                id: monthRect
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: {
                    let base = Appearance.colors.colSurfaceContainerLow;
                    return Qt.rgba(base.r, base.g, base.b, 1.0);
                }
                radius: Appearance.rounding.normal

                StyledText {
                    anchors.centerIn: parent
                    text: {
                        let monthStr = Qt.locale().toString(DateTime.clock.date, "MMM");
                        monthStr = monthStr.replace(".", "");
                        return monthStr.substring(0, 3).toUpperCase();
                    }
                    font {
                        pixelSize: 42
                        bold: true
                        family: Appearance.font.family.main
                    }
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledText {
                    anchors.centerIn: parent
                    text: DateTime.clock.date.getDate().toString()
                    font {
                        pixelSize: 98
                        weight: Font.Black
                        bold: true
                        family: "Google Sans Flex"
                        variableAxes: ({ "ROND": 100, "wght": 800 })
                    }
                    color: Appearance.colors.colPrimary
                }
            }
        }

        // Inner shadow mask canvas to create a solid frame with a rounded rectangle cutout matching the card
        Canvas {
            id: shadowMaskCanvas
            x: -80
            y: -80
            // Expand the canvas bounds significantly to prevent the drop shadow blur from being clipped
            width: bgRect.width + 160
            height: bgRect.height + 160
            visible: false

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = "black";
                ctx.beginPath();
                
                // Outer rectangle covering the expanded canvas size
                ctx.rect(0, 0, width, height);
                
                // Inner rounded rectangle matching the card's position and rounding
                var rx = 80;
                var ry = 80;
                var rw = bgRect.width;
                var rh = bgRect.height;
                var r = bgRect.radius;
                
                ctx.moveTo(rx + r, ry);
                ctx.arcTo(rx, ry, rx, ry + r, r);
                ctx.lineTo(rx, ry + rh - r);
                ctx.arcTo(rx, ry + rh, rx + r, ry + rh, r);
                ctx.lineTo(rx + rw - r, ry + rh);
                ctx.arcTo(rx + rw, ry + rh, rx + rw, ry + rh - r, r);
                ctx.lineTo(rx + rw, ry + r);
                ctx.arcTo(rx + rw, ry, rx + rw - r, ry, r);
                ctx.lineTo(rx + r, ry);
                
                ctx.closePath();
                ctx.fill("evenodd");
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        // DropShadow casting inward from the mask frame, creating the inner shadow effect
        DropShadow {
            id: innerShadow
            x: -80
            y: -80
            width: shadowMaskCanvas.width
            height: shadowMaskCanvas.height
            source: shadowMaskCanvas
            radius: 32 // reduced to 24 for clean tight look
            samples: 49 // reduced to 49 for optimized smooth blur
            color: Qt.rgba(0, 0, 0, 0.25) // high opacity, deep shadow
            horizontalOffset: 0
            verticalOffset: 0
        }
    }
}
