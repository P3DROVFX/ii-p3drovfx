import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

/**
 * "Related: X" cross-link chip for settings pages. Navigates the settings
 * window to another page by its SettingsPageRegistry id, optionally
 * highlighting a section after landing.
 *
 *   RelatedChip {
 *       pageId: "coreServices"
 *       label: Translation.tr("Weather service")
 *       sectionHighlight: Translation.tr("Weather")
 *   }
 */
RippleButton {
    id: root

    property string pageId: ""
    property string label: ""
    // Translated section title passed to pendingSectionHighlight on arrival
    property string sectionHighlight: ""
    property string chipIcon: "arrow_outward"

    implicitHeight: 28
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    onClicked: {
        const win = root.QsWindow.window;
        if (!win || win.pageIndexById === undefined)
            return ;

        const idx = win.pageIndexById(root.pageId);
        if (idx < 0)
            return ;

        if (root.sectionHighlight !== "")
            win.pendingSectionHighlight = root.sectionHighlight;

        win.currentPage = idx;
    }

    contentItem: RowLayout {
        spacing: 4

        MaterialSymbol {
            Layout.leftMargin: 8
            text: root.chipIcon
            iconSize: 14
            color: Appearance.colors.colOnSecondaryContainer
        }

        StyledText {
            Layout.rightMargin: 10
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSecondaryContainer
        }

    }

}
