pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * An on/off pill: Caps Lock, Num Lock, the microphone, or anything a script sends with
 * `qs -c ii ipc call osd pill <icon> <label> <on|off|"">` (GlobalStates.osdPill).
 *
 * Same frame as OsdConnectValueIndicator - icon shape, middle panel, value shape, 380x72 -
 * so the island keeps its size when it moves between a slider and a pill. "on" fills the
 * shapes with the primary colour; a plain notice ("") has no value shape.
 */
Item {
    id: root

    readonly property var pill: GlobalStates.osdPill ?? ({})
    readonly property string pillState: (root.pill.state === "on" || root.pill.state === "off") ? root.pill.state : ""
    readonly property bool lit: root.pillState !== "off"

    // Read by the island (NotchContent.osdTargetWidth/Height), like the sliders'.
    property int osdWidth: 380
    property int osdHeight: 72

    readonly property int shapeIconSize: Appearance.font.pixelSize.huge
    readonly property int shapePadding: 8
    readonly property int shapeSize: shapeIconSize + shapePadding * 2 + 12
    readonly property color shapeColor: root.lit ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
    readonly property color symbolColor: root.lit ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant

    implicitWidth: root.osdWidth
    implicitHeight: root.osdHeight

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        spacing: 15

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.shapeSize
            Layout.preferredHeight: root.shapeSize
            iconSize: root.shapeIconSize
            padding: root.shapePadding
            shape: MaterialShape.Shape.Cookie9Sided
            text: root.pill.icon || "info"
            color: root.shapeColor
            colSymbol: root.symbolColor

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on colSymbol { ColorAnimation { duration: 150 } }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.shapeSize
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.small
            color: Appearance.colors.colSurfaceContainerHighest

            StyledText {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: root.pill.label ?? ""
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
            }
        }

        MaterialShape {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.shapeSize
            Layout.preferredHeight: root.shapeSize
            visible: root.pillState !== ""
            implicitSize: root.shapeSize
            shape: MaterialShape.Shape.Cookie9Sided
            color: root.shapeColor

            Behavior on color { ColorAnimation { duration: 150 } }

            StyledText {
                anchors.centerIn: parent
                text: root.pillState === "on" ? Translation.tr("On") : Translation.tr("Off")
                color: root.symbolColor
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.main
                font.bold: true
            }
        }
    }
}
