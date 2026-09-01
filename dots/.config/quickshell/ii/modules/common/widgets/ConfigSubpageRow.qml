import qs.modules.common.widgets
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

/**
 * Compact navigation row for Settings sub-pages.
 * Replaces oversized ServiceCard / SubPageEntryButton when the destination
 * is simply a detailed settings sub-page.
 */
RippleButton {
    id: root

    property string buttonIcon: ""
    property alias iconName: root.buttonIcon
    property string title: ""
    text: title
    property string description: ""
    property string summary: ""
    property string badgeText: ""
    property var warning: "" // string message or boolean
    property url configPage: ""
    property real iconSize: 18
    property Component extraComponent: null

    signal openSubPage()

    Layout.fillWidth: true
    implicitHeight: contentLayout.implicitHeight + 20
    font.pixelSize: Appearance.font.pixelSize.normal
    useDynamicRadius: true

    onClicked: {
        root.openSubPage();
        if (root.configPage.toString() !== "") {
            var p = root.parent;
            var searchSection = null;
            while (p) {
                if (typeof p.activeSubPage !== "undefined") {
                    p.activeSubPage = root.configPage;
                    return;
                }
                if (p.searchResult === true && p.navigateToPage !== undefined)
                    searchSection = p;
                p = p.parent;
            }
            if (searchSection)
                searchSection.navigateToPage(root.configPage.toString());
        }
    }

    property color normalColor: Appearance.colors.colLayer2
    property color highlightColor: Appearance.colors.colSecondaryContainer

    colBackground: normalColor
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    readonly property string effectiveIcon: (root.buttonIcon && root.buttonIcon.length > 0) ? root.buttonIcon : (root.icon?.name ?? "")

    HighlightOverlay {
        id: highlightOverlay
        anchors.fill: parent
        radius: root.buttonEffectiveRadius
        color: root.highlightColor
    }

    ScrollAnimate {}

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12

            Loader {
                active: root.effectiveIcon.length > 0
                visible: active
                Layout.alignment: Qt.AlignVCenter
                opacity: root.enabled ? 1 : 0.4

                sourceComponent: MaterialShapeWrappedMaterialSymbol {
                    id: iconWidget
                    text: root.effectiveIcon
                    shape: MaterialShape.Shape.Circle
                    iconSize: root.iconSize
                    padding: 6
                    fill: 0
                    color: Appearance.colors.colLayer3
                    colSymbol: Appearance.colors.colOnLayer3
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 4
                opacity: root.enabled ? 1 : 0.4

                StyledText {
                    id: labelWidget
                    Layout.fillWidth: true
                    text: root.title.length > 0 ? root.title : root.text
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.description.length > 0
                    text: root.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.summary.length > 0
                    text: root.summary
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                    wrapMode: Text.WordWrap
                    opacity: 0.9
                }
            }

            Loader {
                active: root.extraComponent !== null
                visible: active
                sourceComponent: root.extraComponent
                Layout.alignment: Qt.AlignVCenter
            }

            // Optional warning badge
            Rectangle {
                visible: (typeof root.warning === "boolean" && root.warning) || (typeof root.warning === "string" && root.warning.length > 0)
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 22
                implicitWidth: warningRow.implicitWidth + 12
                radius: Appearance.rounding.full
                color: Appearance.colors.colErrorContainer

                RowLayout {
                    id: warningRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: "warning"
                        iconSize: 14
                        color: Appearance.colors.colOnErrorContainer
                    }

                    StyledText {
                        visible: typeof root.warning === "string" && root.warning.length > 0
                        text: typeof root.warning === "string" ? root.warning : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
            }

            // Optional badge
            Rectangle {
                visible: root.badgeText.length > 0
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 22
                implicitWidth: badgeLabel.implicitWidth + 14
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer

                StyledText {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: root.badgeText
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            // Trailing navigation chevron
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "arrow_forward"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
                opacity: root.enabled ? 0.65 : 0.3
            }
        }
    }
}
