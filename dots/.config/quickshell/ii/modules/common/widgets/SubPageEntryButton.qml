import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Shared entry point for a Settings sub-page.
 *
 * Navigation stays visually neutral: its icon conveys the destination while
 * colour remains available for states that carry semantic risk elsewhere.
 */
RippleButton {
    id: root

    property string entryIcon: ""
    property string entryTitle: ""
    property string entryDescription: ""
    property color entryAccent: Appearance.colors.colPrimary
    property color entryOnAccent: Appearance.colors.colOnPrimary

    Layout.fillWidth: true
    implicitHeight: entryRow.implicitHeight + 32
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colSurfaceContainerHigh
    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
    colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
    colRipple: Appearance.colors.colSurfaceContainerHighestActive

    contentItem: RowLayout {
        id: entryRow
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.entryIcon
            shape: MaterialShape.Shape.Circle
            iconSize: Appearance.font.pixelSize.large
            padding: 8
            color: root.entryAccent
            colSymbol: root.entryOnAccent
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.entryTitle
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                text: root.entryDescription
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                opacity: 0.82
            }
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "arrow_forward"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
    }
}
