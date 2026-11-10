import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The frame of a utility widget's options page: back button, title, and the
 * page's sections as content. Options use the original config components
 * (ConfigSwitch, ConfigSelectionArray, ConfigSpinBox…) with their tooltips.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()
    property string title: ""
    default property alias content: page.contentData
    // For a host that draws this page in a card (the dock's Edit Mode menu):
    // the height it needs, and the padding under the last control.
    readonly property alias flickable: page.flickable
    property alias bottomContentPadding: page.bottomContentPadding

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: 12

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
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }
    }
}
