pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Sculpt search — three Material 3 Expressive search entries, chosen in the
 * widget's page (`bar.searchWidget.sculptVariant`):
 *
 *   field     an assistant's prompt bar: a soft field with the placeholder in
 *             it and a vivid action circle at the end
 *   display   the word itself as the button — black, wide, slanted display
 *             type on a vivid card, standing up straight under the pointer
 *   split     an M3 Expressive split button: search on the leading half, the
 *             app overview on the trailing one
 *
 * All three follow the size mode (compact / balanced / extended) and the
 * colour mode of the search widget's page.
 */
Item {
    id: root

    property bool vertical: false

    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    readonly property string variant: Config.options.bar.searchWidget.sculptVariant ?? "field"
    readonly property string sizeMode: Config.options.bar.searchWidget.sizeMode ?? "compact"
    readonly property bool hasShortcut: root.sizeMode === "extended"
        && (Config.options.bar.searchWidget.showShortcutHint ?? true)
    readonly property bool activated: GlobalStates.overviewOpen
        && GlobalStates.searchOnlyMode
        && (root.screenName === "" || GlobalStates.activeSearchMonitor === root.screenName)

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property int contentRotation: root.vertical
        ? (Config.options.bar.bottom ? 90 : -90)
        : 0

    BarWidgetPalette {
        id: searchTones
        colorMode: Config.options.bar.searchWidget.colorMode ?? "tonal"
    }

    readonly property real targetLength: root.vertical
        ? (variantLoader.item?.implicitHeight ?? root.thickness)
        : (variantLoader.item?.implicitWidth ?? root.thickness)
    property real animatedLength: root.targetLength
    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength
    implicitHeight: root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight
    clip: true

    function toggleSearch(): void {
        GlobalStates.toggleSearchOnly(root.screenName);
    }

    Loader {
        id: variantLoader
        anchors.centerIn: parent
        sourceComponent: root.variant === "display"
            ? displayVariant
            : root.variant === "split" ? splitVariant : fieldVariant
    }

    Component {
        id: fieldVariant
        SculptSearchField {
            vertical: root.vertical
            thickness: root.thickness
            contentRotation: root.contentRotation
            sizeMode: root.sizeMode
            hasShortcut: root.hasShortcut
            activated: root.activated
            tones: searchTones
            onActivate: root.toggleSearch()
        }
    }

    Component {
        id: displayVariant
        SculptSearchDisplay {
            vertical: root.vertical
            thickness: root.thickness
            contentRotation: root.contentRotation
            sizeMode: root.sizeMode
            hasShortcut: root.hasShortcut
            activated: root.activated
            tones: searchTones
            onActivate: root.toggleSearch()
        }
    }

    Component {
        id: splitVariant
        SculptSearchSplit {
            vertical: root.vertical
            thickness: root.thickness
            contentRotation: root.contentRotation
            sizeMode: root.sizeMode
            hasShortcut: root.hasShortcut
            activated: root.activated
            overviewOpen: GlobalStates.overviewOpen && !GlobalStates.searchOnlyMode
            tones: searchTones
            onActivate: root.toggleSearch()
            onOpenOverview: GlobalStates.toggleOverview(root.screenName)
        }
    }
}
