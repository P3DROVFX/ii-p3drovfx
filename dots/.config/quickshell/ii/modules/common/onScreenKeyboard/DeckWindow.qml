import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * The deck's window: a strip that spans the whole bottom edge of the screen.
 *
 * The classic keyboard floats in the middle of its window with a button rail beside it; this one
 * gives every pixel of its width to the keys, so its height is all that decides how big they get.
 * That height is a share of the screen rather than a pixel count, which keeps the deck the same
 * size on any output. Pin and Hide moved into the key grid itself, so there is no rail left - the
 * window is a background and a deck, and the two corner keys report back through actions.
 */
PanelWindow {
    id: root

    property bool pinned: false

    signal pinToggled
    signal hideRequested

    readonly property real heightPercent: Config.options?.osk.heightPercent ?? 35
    readonly property real dockHeight: Math.round((root.screen?.height ?? 0) * root.heightPercent / 100)

    // Empty strip above the dock for the shadow to fall into. It stays outside the mask, so
    // clicks land on whatever window is up there.
    readonly property real shadowMargin: Appearance.sizes.elevationMargin

    // The rounded top corners cut into the two keys that sit in them; this holds the grid far
    // enough in that they do not poke back out. Nothing at the bottom, where the corners are square
    // and a key flush with the screen edge is easier to hit.
    readonly property real padding: Math.round(Appearance.rounding.windowRounding * 0.35)

    visible: !GlobalStates.screenLocked

    anchors {
        bottom: true
        left: true
        right: true
    }

    implicitHeight: root.dockHeight + root.shadowMargin

    // Edge to edge already, so there is no gap to leave for: the dock reserves exactly its height.
    exclusiveZone: root.pinned ? root.dockHeight : 0

    WlrLayershell.namespace: "quickshell:osk"
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    mask: Region {
        item: deckBackground
    }

    // Normalized so OskAutoShow can test touches against it without knowing which output the
    // touchscreen is mapped to. Full-bleed makes it simple: the dock owns the full width.
    Binding {
        target: OskAutoShow
        property: "keyboardBounds"
        when: root.visible && root.screen
        value: Qt.rect(0, (root.screen.height - root.dockHeight) / root.screen.height, 1, root.dockHeight / root.screen.height)
    }

    Binding {
        target: OskAutoShow
        property: "keyboardPinned"
        value: root.pinned
    }

    // Make it usable with other panels
    Component.onCompleted: {
        GlobalFocusGrab.addPersistent(root);
    }
    Component.onDestruction: {
        GlobalFocusGrab.removePersistent(root);
    }

    StyledRectangularShadow {
        target: deckBackground
    }

    Rectangle {
        id: deckBackground

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.dockHeight
        color: Appearance.colors.colLayer0

        // Only the top corners round: the other two sit off the bottom of the screen.
        radius: Appearance.rounding.windowRounding
        bottomLeftRadius: 0
        bottomRightRadius: 0

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.hideRequested();
        }

        DeckContent {
            anchors.fill: parent
            anchors.leftMargin: root.padding
            anchors.rightMargin: root.padding
            anchors.topMargin: root.padding
            pinned: root.pinned

            onActionTriggered: action => {
                if (action === "pin")
                    root.pinToggled();
                else if (action === "hide")
                    root.hideRequested();
            }
        }
    }
}
