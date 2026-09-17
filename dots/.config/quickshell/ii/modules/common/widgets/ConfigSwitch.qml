import qs.modules.common.widgets
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

RippleButton {
    id: root
    property string buttonIcon
    property string description: ""
    property real iconSize: 18
    property Component extraComponent: null
    property url configPage: ""
    property bool hasSubPageOverride: false
    // Navigation-only rows keep the switch visual without exposing a dead
    // toggle that is not backed by Config.
    property bool subPageOnly: false
    readonly property bool hasSubPage: configPage.toString() !== "" || hasSubPageOverride

    signal openSubPage

    Layout.fillWidth: true
    // A settings row is one tap target. Floor it at the Material minimum on a
    // touch-first family rather than fixing the height, so rows that are already
    // taller keep their size.
    implicitHeight: Math.max(contentLayout.implicitHeight + 20,
        PanelFamily.touchFirst ? Appearance.sizes.minimumTouchTarget + 12 : 0)
    font.pixelSize: Appearance.font.pixelSize.small
    property bool forceUniformRadius: false
    useDynamicRadius: true

    onClicked: {
        if (root.hasSubPage) {
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
        } else {
            checked = !checked;
        }
    }

    property color normalColor: Appearance.colors.colLayer2
    property color highlightColor: Appearance.colors.colSecondaryContainer

    colBackground: normalColor
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    isFirst: root.forceUniformRadius || (root.groupPosition?.isFirst ?? true)
    isLast: root.forceUniformRadius || (root.groupPosition?.isLast ?? true)

    topLeftRadius: forceUniformRadius ? rFull : ((isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall))
    topRightRadius: forceUniformRadius ? rFull : ((isPressed || prevIsPressed) ? rFull : (isHorizontalLayout ? (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)))
    bottomLeftRadius: forceUniformRadius ? rFull : ((isPressed || nextIsPressed) ? rFull : (isHorizontalLayout ? (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)))
    bottomRightRadius: forceUniformRadius ? rFull : ((isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall))

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
                active: root.buttonIcon && root.buttonIcon.length > 0
                visible: active
                Layout.alignment: Qt.AlignVCenter
                opacity: root.enabled ? 1 : 0.4

                sourceComponent: MaterialShapeWrappedMaterialSymbol {
                    id: iconWidget
                    text: root.buttonIcon
                    shape: root.checked ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Circle
                    iconSize: 18
                    padding: 6
                    fill: root.checked ? 1 : 0
                    color: root.checked ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
                    colSymbol: root.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 4
                opacity: root.enabled ? 1 : 0.4

                StyledText {
                    id: labelWidget
                    Layout.fillWidth: true
                    text: root.text
                    font.pixelSize: root.font.pixelSize
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
            }

            Loader {
                active: root.extraComponent !== null
                visible: active
                sourceComponent: root.extraComponent
                Layout.alignment: Qt.AlignVCenter
            }

            Rectangle {
                id: subPageDivider
                visible: root.hasSubPage
                Layout.preferredWidth: 2
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                color: Appearance.colors.colOutline
                opacity: 0.75
            }

            Item {
                implicitWidth: switchWidget.implicitWidth
                implicitHeight: switchWidget.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                StyledSwitch {
                    id: switchWidget
                    anchors.centerIn: parent
                    checked: root.checked
                    enabled: false
                    down: root.isPressed || (switchHitbox.pressed && switchHitbox.enabled)
                    isPressed: root.isPressed || (switchHitbox.pressed && switchHitbox.enabled)
                    opacity: root.enabled ? 1.0 : 0.4
                }

                // Keep the cursor above the disabled visual switch without
                // consuming any click; the row handles the interaction when hasSubPage is false.
                MouseArea {
                    anchors.fill: parent
                    z: 1
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }

        MouseArea {
            id: switchHitbox
            z: 2
            visible: root.hasSubPage
            enabled: root.hasSubPage && root.enabled
            hoverEnabled: enabled
            cursorShape: root.enabled && root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            x: contentLayout.x + subPageDivider.x + subPageDivider.width
            width: Math.max(0, parent.width - x)

            onClicked: {
                if (!root.subPageOnly)
                    root.checked = !root.checked;
            }
        }
    }
}
