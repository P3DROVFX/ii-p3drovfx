pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Google Material 3 Expressive Split Button.
 *
 * Consists of two adjacent interactive zones:
 * - Leading button: Primary action with text and optional icon.
 * - Trailing button: Disclosure button (arrow) that opens a contextual M3 menu.
 * - Shapes: Outer corners are fully rounded (pill), inner corners have an expressive small radius.
 * - Separator: Expressive 2dp gap between buttons.
 */
Item {
    id: root

    // Properties for leading (primary) action
    property string text: ""
    property string icon: ""
    property real iconSize: 24
    property real leadingWidth: 0
    property string tooltip: ""

    // Properties for trailing (menu) action
    property string arrowIcon: "keyboard_arrow_down"
    property real arrowIconSize: 24
    property real trailingWidth: 0
    property string arrowTooltip: Translation.tr("More options")

    // Geometry and Expressive Radii
    property real buttonHeight: 56
    property real outerRadius: buttonHeight / 2
    property real innerRadius: 6
    property real gap: 2

    // Colors & Theme (Defaults to Filled; can be styled for Tonal/Surface)
    property color colBackground: Appearance.colors.colPrimary
    property color colForeground: Appearance.colors.colOnPrimary
    property color colBackgroundHover: Appearance.colors.colPrimaryHover ?? Qt.lighter(colBackground, 1.1)
    property color colBackgroundActive: Appearance.colors.colPrimaryActive ?? Qt.darker(colBackground, 1.1)
    property color colRipple: Appearance.colors.colPrimaryActive ?? Qt.darker(colBackground, 1.15)

    // Popup Menu configuration
    property var model: []
    property real popupWidth: 0
    property string popupDirection: "auto" // "auto", "up", "down"
    readonly property bool popupOpen: menuPopup.visible

    // Signals
    signal clicked()
    signal actionSelected(string id, var item)

    implicitHeight: buttonHeight
    implicitWidth: buttonRow.implicitWidth

    function openMenu() {
        menuPopup.open();
    }

    function closeMenu() {
        menuPopup.close();
    }

    function toggleMenu() {
        if (menuPopup.visible) {
            menuPopup.close();
        } else {
            menuPopup.open();
        }
    }

    RowLayout {
        id: buttonRow
        anchors.fill: parent
        spacing: root.gap

        // 1. Leading Button (Primary Action)
        RippleButton {
            id: leadingBtn
            Layout.preferredHeight: root.buttonHeight
            Layout.preferredWidth: root.leadingWidth > 0 ? root.leadingWidth : leadingContent.implicitWidth + 36
            Layout.fillHeight: true

            buttonRadius: 0
            topLeftRadius: root.outerRadius
            bottomLeftRadius: root.outerRadius
            topRightRadius: root.innerRadius
            bottomRightRadius: root.innerRadius

            colBackground: root.colBackground
            colBackgroundHover: root.colBackgroundHover
            colBackgroundActive: root.colBackgroundActive
            colRipple: root.colRipple

            contentItem: Item {
                RowLayout {
                    id: leadingContent
                    anchors.centerIn: parent
                    spacing: 10

                    MaterialSymbol {
                        visible: root.icon.length > 0
                        text: root.icon
                        iconSize: root.iconSize
                        color: root.colForeground
                    }

                    StyledText {
                        visible: root.text.length > 0
                        text: root.text
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: root.colForeground
                    }
                }
            }

            StyledToolTip {
                text: root.tooltip
                extraVisibleCondition: root.tooltip.length > 0 && leadingBtn.hovered && !menuPopup.visible
            }

            onClicked: root.clicked()
        }

        // 2. Trailing Button (Menu Trigger)
        RippleButton {
            id: trailingBtn
            Layout.preferredHeight: root.buttonHeight
            Layout.preferredWidth: root.trailingWidth > 0 ? root.trailingWidth : Math.max(48, root.buttonHeight * 0.85)
            Layout.fillHeight: true

            buttonRadius: 0
            topLeftRadius: root.innerRadius
            bottomLeftRadius: root.innerRadius
            topRightRadius: root.outerRadius
            bottomRightRadius: root.outerRadius

            toggled: menuPopup.visible
            colBackground: menuPopup.visible ? root.colBackgroundActive : root.colBackground
            colBackgroundHover: root.colBackgroundHover
            colBackgroundActive: root.colBackgroundActive
            colRipple: root.colRipple

            contentItem: MaterialSymbol {
                id: arrowSym
                anchors.centerIn: parent
                text: root.arrowIcon
                iconSize: root.arrowIconSize
                color: root.colForeground

                rotation: menuPopup.visible ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            StyledToolTip {
                text: root.arrowTooltip
                extraVisibleCondition: root.arrowTooltip.length > 0 && trailingBtn.hovered && !menuPopup.visible
            }

            onClicked: root.toggleMenu()
        }
    }

    // 3. Material 3 Menu Popup
    Popup {
        id: menuPopup
        padding: 6
        width: root.popupWidth > 0 ? root.popupWidth : Math.max(root.implicitWidth, 210)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        readonly property bool shouldOpenUpwards: {
            if (root.popupDirection === "up") return true;
            if (root.popupDirection === "down") return false;
            // In "auto" mode, check window/screen positioning
            const mapPt = root.mapToItem(null, 0, 0);
            const parentH = root.Window.window ? root.Window.window.height : 600;
            return mapPt.y > (parentH / 2);
        }

        x: root.width - width
        y: shouldOpenUpwards ? -(height + 6) : (root.height + 6)

        enter: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardDecel
                }
                NumberAnimation {
                    property: "scale"
                    from: 0.92
                    to: 1.0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardDecel
                }
            }
        }

        exit: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardAccel
                }
                NumberAnimation {
                    property: "scale"
                    from: 1.0
                    to: 0.92
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardAccel
                }
            }
        }

        background: Item {
            StyledRectangularShadow {
                target: popupCard
            }

            Rectangle {
                id: popupCard
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Config.options.appearance.transparency.popups
                    ? Appearance.colors.colLayer0
                    : Appearance.m3colors.m3surfaceContainerHigh
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
            }
        }

        contentItem: ColumnLayout {
            spacing: 4

            Repeater {
                model: root.model

                delegate: RippleButton {
                    id: menuItemBtn
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.medium

                    colBackground: menuItemBtn.hovered
                        ? Appearance.colors.colLayer3Hover
                        : "transparent"
                    colBackgroundActive: Appearance.colors.colLayer3Active
                    colRipple: Appearance.colors.colLayer3Active

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        MaterialSymbol {
                            text: (menuItemBtn.modelData && menuItemBtn.modelData.icon) ? menuItemBtn.modelData.icon : "circle"
                            iconSize: 22
                            color: Appearance.colors.colOnSurface
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: (menuItemBtn.modelData && menuItemBtn.modelData.label) ? menuItemBtn.modelData.label : ""
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                visible: menuItemBtn.modelData && menuItemBtn.modelData.description !== undefined && String(menuItemBtn.modelData.description).length > 0
                                Layout.fillWidth: true
                                text: (menuItemBtn.modelData && menuItemBtn.modelData.description) ? menuItemBtn.modelData.description : ""
                                font.pixelSize: 11
                                color: Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }

                    onClicked: {
                        menuPopup.close();
                        root.actionSelected(menuItemBtn.modelData.id || "", menuItemBtn.modelData);
                    }
                }
            }
        }
    }
}
