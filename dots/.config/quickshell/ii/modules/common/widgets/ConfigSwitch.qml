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
    implicitHeight: contentLayout.implicitHeight + 20
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

    readonly property int itemIndex: {
        var p = parent;
        if (!p)
            return 0;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === root) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1)
            return 0;

        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }

        var idx = 0;
        for (var i = startIdx; i < selfIdx; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius !== "undefined") {
                idx++;
            }
        }
        return idx;
    }

    readonly property int totalItems: {
        var p = parent;
        if (!p)
            return 1;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === root) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1)
            return 1;

        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }

        var endIdx = children.length - 1;
        for (var i = selfIdx + 1; i < children.length; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                endIdx = i - 1;
                break;
            }
        }

        var count = 0;
        for (var i = startIdx; i <= endIdx; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius !== "undefined") {
                count++;
            }
        }
        return count;
    }

    property bool isFirst: forceUniformRadius ? true : (itemIndex === 0)
    property bool isLast: forceUniformRadius ? true : (itemIndex === totalItems - 1)

    readonly property bool prevIsPressed: {
        var p = parent;
        if (!p)
            return false;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === root) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx <= 0)
            return false;

        var startIdx = 0;
        for (var i = selfIdx - 1; i >= 0; --i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                startIdx = i + 1;
                break;
            }
        }

        for (var i = selfIdx - 1; i >= startIdx; --i) {
            var child = children[i];
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
    }

    readonly property bool nextIsPressed: {
        var p = parent;
        if (!p)
            return false;
        var children = p.children;
        var selfIdx = -1;
        for (var i = 0; i < children.length; ++i) {
            if (children[i] === root) {
                selfIdx = i;
                break;
            }
        }
        if (selfIdx === -1 || selfIdx >= children.length - 1)
            return false;

        var endIdx = children.length - 1;
        for (var i = selfIdx + 1; i < children.length; ++i) {
            if (children[i].visible && typeof children[i].topLeftRadius === "undefined") {
                endIdx = i - 1;
                break;
            }
        }

        for (var i = selfIdx + 1; i <= endIdx; ++i) {
            var child = children[i];
            if (child.visible && typeof child.topLeftRadius !== "undefined") {
                return child.isPressed === true || (child.down !== undefined && child.down === true);
            }
        }
        return false;
    }

    readonly property bool isHorizontalLayout: {
        var p = parent;
        if (!p)
            return false;
        var pStr = p.toString();
        return (pStr.indexOf("RowLayout") !== -1 || pStr.indexOf("Row") !== -1) && pStr.indexOf("Column") === -1;
    }

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: forceUniformRadius ? rFull : ((isPressed || prevIsPressed) ? rFull : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall))
    topRightRadius: forceUniformRadius ? rFull : ((isPressed || prevIsPressed) ? rFull : (isHorizontalLayout ? (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall)))
    bottomLeftRadius: forceUniformRadius ? rFull : ((isPressed || nextIsPressed) ? rFull : (isHorizontalLayout ? (isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall) : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall)))
    bottomRightRadius: forceUniformRadius ? rFull : ((isPressed || nextIsPressed) ? rFull : (isLast ? Appearance.rounding.large : Appearance.rounding.verysmall))

    Behavior on topLeftRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on topRightRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on bottomLeftRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on bottomRightRadius {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(root)
    }

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
                    isPressed: root.isPressed
                    opacity: root.enabled ? 1.0 : 0.4
                }

                // Keep the cursor above the disabled visual switch without
                // consuming any click; the row handles the interaction.
                MouseArea {
                    anchors.fill: parent
                    z: 1
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                MouseArea {
                    anchors.fill: parent
                    z: 2
                    enabled: root.hasSubPage && root.enabled
                    hoverEnabled: enabled
                    cursorShape: root.enabled && root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!root.subPageOnly)
                            root.checked = !root.checked;
                    }
                }
            }
        }
    }
}
