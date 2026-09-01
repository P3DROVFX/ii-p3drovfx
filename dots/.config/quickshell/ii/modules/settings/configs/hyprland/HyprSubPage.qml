import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The frame every hub sub-page shares: a back button, a title, a one-line subtitle, and the
 * scrolling column the sections go in.
 *
 * The overlay that slides a sub-page in expects the page's root to carry `showBackButton` and a
 * `goBack` signal, and sets the first and listens to the second. Nine pages each carried forty
 * lines of the same header for that; this is the header, once.
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    /// A page of this shape can push one of its own; the host is here rather than in each page
    /// that needs one, so going back from the deeper page returns here instead of two levels up.
    property alias activeSubPage: subPageOverlay.activeSubPage

    property string title: ""
    property string subtitle: ""

    default property alias content: page.contentData

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        RowLayout {
            visible: root.showBackButton
            Layout.fillWidth: true
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

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
