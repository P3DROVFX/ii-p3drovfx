pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.ii.bar.popups.keyboard
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Sculpt keyboard layout — three Material 3 Expressive ways to show "which
 * layout, out of which", chosen in the widget's page
 * (`bar.keyboardLayout.sculptVariant`):
 *
 *   selector   every layout as a pill, like a day selector: the current one
 *              wide and vivid, the others small soft pills you click straight
 *              into
 *   carousel   the current layout as the large item and the next one peeking,
 *              cropped; switching slides the carousel
 *   dial       a small dial with a dot per layout and a marker travelling
 *              round it, the layout's full name beside
 *
 * This file owns the data, the switching and the popup.
 */
MouseArea {
    id: root

    property bool vertical: false

    // Plain properties rather than readonly so a preview can hand in layouts.
    property var codes: HyprlandXkb.layoutCodes
    property string currentFullCode: HyprlandXkb.currentLayoutCode
    property string currentName: {
        HyprlandXkb.layoutDescriptions;
        return HyprlandXkb.descriptionFor(root.currentIndex);
    }

    readonly property string variant: Config.options.bar.keyboardLayout.sculptVariant ?? "selector"
    readonly property bool showName: Config.options.bar.keyboardLayout.sculptShowName ?? true
    readonly property bool uppercase: Config.options.bar.keyboardLayout.uppercaseLayout
    readonly property bool hasMultipleLayouts: root.codes.length > 1
    readonly property int currentIndex: Math.max(0, root.codes.indexOf(root.currentFullCode))
    readonly property var shortCodes: root.codes.map(code => root.abbreviate(code))

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

    visible: root.codes.length >= 1
    implicitWidth: !root.visible ? 0 : root.vertical
        ? Appearance.sizes.verticalBarWidth
        : (variantLoader.item?.implicitWidth ?? 0)
    implicitHeight: !root.visible ? 0 : root.vertical
        ? (variantLoader.item?.implicitHeight ?? 0)
        : Appearance.sizes.baseBarHeight

    hoverEnabled: !BarInteraction.clickToShow
    cursorShape: root.hasMultipleLayouts ? Qt.PointingHandCursor : Qt.ArrowCursor

    // Click-to-show gives the left click to the popup; cycling moves to the right button.
    readonly property bool rightClickCycles: BarInteraction.cycleOnRightClick
    acceptedButtons: root.rightClickCycles ? (Qt.LeftButton | Qt.RightButton) : Qt.LeftButton

    Component.onCompleted: HyprlandXkb.requestLayoutDescriptions()

    function abbreviate(fullCode: string): string {
        if (!fullCode)
            return "";
        const abbr = fullCode.split(':')[0].split('-')[0].slice(0, 2);
        return root.uppercase ? abbr.toUpperCase() : abbr.toLowerCase();
    }

    Process {
        id: switchProc
    }

    // -1 = the next layout.
    function switchTo(index: int): void {
        if (!root.hasMultipleLayouts || index === root.currentIndex)
            return;
        switchProc.running = false;
        switchProc.command = ["hyprctl", "switchxkblayout", "all", index < 0 ? "next" : String(index)];
        switchProc.running = true;
    }

    onClicked: mouse => {
        if (mouse.button !== (root.rightClickCycles ? Qt.RightButton : Qt.LeftButton))
            return;
        // The selector's pills are targets of their own: a click on one goes
        // straight to that layout. Anywhere else moves to the next one.
        const item = variantLoader.item;
        if (item && typeof item.indexAt === "function") {
            const point = root.mapToItem(item, mouse.x, mouse.y);
            const index = item.indexAt(point.x, point.y);
            if (index >= 0 && index !== root.currentIndex) {
                root.switchTo(index);
                return;
            }
        }
        root.switchTo(-1);
    }

    BarWidgetPalette {
        id: keyTones
        colorMode: Config.options.bar.keyboardLayout.colorMode
    }

    Loader {
        id: variantLoader
        anchors.centerIn: parent
        sourceComponent: root.variant === "carousel"
            ? carouselVariant
            : root.variant === "dial" ? dialVariant : selectorVariant
    }

    Component {
        id: selectorVariant
        SculptKeyboardSelector {
            vertical: root.vertical
            thickness: root.thickness
            tones: keyTones
            codes: root.shortCodes
            currentIndex: root.currentIndex
        }
    }

    Component {
        id: carouselVariant
        SculptKeyboardCarousel {
            vertical: root.vertical
            thickness: root.thickness
            tones: keyTones
            hovered: root.containsMouse
            codes: root.shortCodes
            currentIndex: root.currentIndex
        }
    }

    Component {
        id: dialVariant
        SculptKeyboardDial {
            vertical: root.vertical
            thickness: root.thickness
            tones: keyTones
            hovered: root.containsMouse
            codes: root.shortCodes
            currentIndex: root.currentIndex
            showName: root.showName
            currentName: root.currentName
        }
    }

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    PopupLoader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || held)
        sourceComponent: KeyboardLayoutPopup {
            hoverTarget: root
        }
    }
}
