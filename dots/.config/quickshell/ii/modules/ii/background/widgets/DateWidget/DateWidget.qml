import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

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
    }
}
