import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

/**
 * The current user as a pill above the password island, unfolding into a
 * strip of every user's face. The island grows around the strip from a fixed
 * centre, so the faces stay put while the card uncovers them, and the current
 * face glides between its spot in the pill and its slot in the strip: up when
 * opening, and down from the picked slot when a user is chosen.
 *
 * `entries` is a list of { image, label }; `currentIndex` marks the current one.
 */
FocusScope {
    id: root

    property var entries: []
    property int currentIndex: 0
    property string fallbackIcon: "person"
    property int maxVisible: 5
    readonly property bool interactive: root.entries.length > 1
    readonly property bool open: root.isOpen
    signal picked(int index)
    // Closed by a pick, Escape or Return; not when focus simply moved elsewhere.
    signal dismissed

    property bool isOpen: false
    // 0 closed, 1 open. The size, the card and the gliding face are all laid
    // out from it, so they can never drift apart mid-animation.
    property real progress: root.isOpen ? 1 : 0
    Behavior on progress {
        NumberAnimation {
            duration: Theme.ms(450)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveDefaultSpatial
        }
    }
    // A slot's entrance, staggered by position; on the way out every slot
    // fades together and early, before the card closes over it.
    function reveal(index) {
        return root.isOpen ? root.ramp(0.15 + index * 0.06, 0.5) : root.ramp(0.55, 0.4);
    }
    // The spring may overshoot past open, never past closed: that would squeeze
    // the pill below its size and cut the name as it settles.
    function lerp(a, b) {
        return a + (b - a) * Math.max(0, root.progress);
    }
    function ramp(from, span) {
        return Math.max(0, Math.min(1, (root.progress - from) / span));
    }

    readonly property var current: root.entries[root.currentIndex] ?? null
    readonly property string label: root.current ? (root.current.label ?? "") : ""

    readonly property real inset: 3                 // the toolbar's padding
    readonly property real pad: 6
    readonly property real smallFace: Theme.toolbarHeight - 14
    readonly property real bigFace: 60
    readonly property real faceTop: 10              // inside a slot
    readonly property real slotWidth: 96
    readonly property real slotHeight: 100
    readonly property real slotSpacing: 4
    readonly property int visibleSlots: Math.max(1, Math.min(root.entries.length, root.maxVisible))
    readonly property real stripWidth: root.visibleSlots * root.slotWidth + (root.visibleSlots - 1) * root.slotSpacing

    readonly property real closedWidth: Math.ceil(Math.min(320, root.inset * 2 + pillRow.anchors.leftMargin + pillRow.implicitWidth + pillRow.anchors.rightMargin))
    readonly property real closedHeight: Theme.toolbarHeight
    readonly property real openWidth: Math.max(root.closedWidth, root.stripWidth + root.pad * 2)
    readonly property real openHeight: root.slotHeight + root.pad * 2

    width: root.lerp(root.closedWidth, root.openWidth)
    height: root.lerp(root.closedHeight, root.openHeight)

    // Where the current face sits in each state, in this item's own
    // coordinates. Both are taken at that state's size; since the size moves
    // with `progress` too, interpolating them glides the face in a straight line.
    readonly property real faceClosedX: root.inset + 4
    readonly property real faceClosedY: (root.closedHeight - root.smallFace) / 2
    function faceOpenX(index) {
        return (root.openWidth - root.stripWidth) / 2 + index * (root.slotWidth + root.slotSpacing) - strip.contentX + (root.slotWidth - root.bigFace) / 2;
    }
    readonly property real faceOpenY: root.pad + root.faceTop
    // A face in its slot at the current size (the strip is centred).
    function faceSlotX(index) {
        return (root.width - root.stripWidth) / 2 + index * (root.slotWidth + root.slotSpacing) - strip.contentX + (root.slotWidth - root.bigFace) / 2;
    }

    // The slot the keyboard (or the mouse) is on.
    property int highlighted: -1

    function show() {
        if (!root.interactive || root.isOpen)
            return;
        root.highlighted = root.currentIndex;
        strip.positionViewAtIndex(root.currentIndex, ListView.Contain);
        root.isOpen = true;
        root.forceActiveFocus();
    }
    function close() {
        root.isOpen = false;
    }
    function pick(index) {
        root.close();
        if (index !== root.currentIndex)
            root.picked(index);
        root.dismissed();
    }

    onActiveFocusChanged: if (!activeFocus) root.close()

    Keys.onPressed: event => {
        if (!root.isOpen)
            return;
        switch (event.key) {
        case Qt.Key_Left:
            root.highlighted = Math.max(0, root.highlighted - 1);
            strip.positionViewAtIndex(root.highlighted, ListView.Contain);
            break;
        case Qt.Key_Right:
            root.highlighted = Math.min(root.entries.length - 1, root.highlighted + 1);
            strip.positionViewAtIndex(root.highlighted, ListView.Contain);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.pick(root.highlighted >= 0 ? root.highlighted : root.currentIndex);
            break;
        case Qt.Key_Escape:
            root.close();
            root.dismissed();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: 0.9 * Theme.elevationMargin
        offset: Qt.vector2d(0.0, 1.0)
        spread: 1
        color: Theme.colShadow
        cached: true
        visible: !Theme.transparency
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.sharpMode ? Theme.roundingFull : root.lerp(root.closedHeight / 2, Theme.roundingLarge)
        color: Theme.m3surfaceContainer
        border.width: 1
        border.color: Theme.transparentize(Theme.colLayer0Border, Theme.transparency ? 1 : 1 - root.ramp(0, 0.6))
        clip: true

        // Keep clicks on the card from reaching the surface behind it.
        MouseArea {
            anchors.fill: parent
        }

        // ── open: every user's face ────────────────────────────────────────
        // Centred and pinned to the bottom, so it stays still on screen while
        // the card grows around it.
        ListView {
            id: strip
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: root.pad
            }
            width: root.stripWidth
            height: root.slotHeight
            orientation: ListView.Horizontal
            spacing: root.slotSpacing
            clip: true
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds
            visible: root.progress > 0
            enabled: root.isOpen
            model: root.entries

            delegate: IslandButton {
                id: slot
                required property var modelData
                required property int index
                readonly property bool isCurrent: slot.index === root.currentIndex
                // Staggered entrance, played back in reverse when closing.
                readonly property real reveal: root.reveal(slot.index)

                width: root.slotWidth
                height: root.slotHeight
                buttonRadius: Theme.roundingNormal
                // The current user is a tonal tile, like the current row of the
                // shell's lists; the colour fades over when another is picked.
                colBackground: slot.isCurrent ? Theme.m3secondaryContainer : (slot.index === root.highlighted ? Theme.m3surfaceContainerHigh : Theme.transparentize(Theme.m3surfaceContainerHigh, 1))
                colBackgroundHover: slot.isCurrent ? Theme.colSecondaryContainerHover : Theme.m3surfaceContainerHigh
                colBackgroundActive: slot.isCurrent ? Theme.colSecondaryContainerActive : Theme.m3surfaceContainerHighest
                colRipple: slot.isCurrent ? Theme.colSecondaryContainerActive : Theme.mix(Theme.m3surfaceContainerHighest, Theme.m3onSurface, 0.85)
                onHoveredChanged: if (hovered) root.highlighted = slot.index

                // The faces are drawn above the strip (see `faces`); a slot is
                // the tile and the name.
                opacity: slot.reveal
                transform: Translate {
                    y: 10 * (1 - slot.reveal)
                }

                contentItem: Item {
                    StyledText {
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            topMargin: root.faceTop + root.bigFace + 9
                            leftMargin: 6
                            rightMargin: 6
                        }
                        horizontalAlignment: Text.AlignHCenter
                        text: slot.modelData.label ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Theme.pxSmaller
                        font.weight: slot.isCurrent ? Font.Bold : Font.DemiBold
                        color: slot.isCurrent ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                    }
                }

                onClicked: {
                    const strip = root;
                    const picked = slot.index;
                    strip.pick(picked);
                }
            }
        }

        // ── closed: the pill ───────────────────────────────────────────────
        IslandButton {
            id: pill
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: root.inset
            }
            height: root.closedHeight - root.inset * 2
            enabled: root.interactive && !root.isOpen
            // Not dimmed when disabled: a single user is shown, just not switchable.
            opacity: 1 - root.ramp(0, 0.3)
            visible: opacity > 0
            pointingHandCursor: root.interactive
            onClicked: root.show()

            contentItem: Item {
                RowLayout {
                    id: pillRow
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: root.interactive ? 10 : 14
                    spacing: 8

                    // Room for the gliding face, drawn above everything.
                    Item {
                        Layout.preferredWidth: root.smallFace
                        Layout.preferredHeight: root.smallFace
                    }
                    StyledText {
                        id: pillLabel
                        Layout.fillWidth: true
                        text: root.label
                        elide: Text.ElideRight
                        font.pixelSize: Theme.pxSmall
                        color: Theme.m3onSurface
                    }
                    MaterialSymbol {
                        visible: root.interactive
                        text: "unfold_more"
                        iconSize: Theme.pxLarger
                        color: Theme.m3onSurfaceVariant
                    }
                }
            }
        }

        // ── every user's face, above the strip and the pill ────────────────
        // One face per user, kept for good: a pick never swaps a picture's
        // source (which would flash the fallback while it reloads). The
        // current face glides between the pill and its slot; the others
        // rise into their slots and fade, like the tiles. Drawn at the
        // strip's size and scaled down, so nothing is re-rasterised in motion.
        Repeater {
            id: faces
            model: root.entries

            delegate: Face {
                id: face
                required property var modelData
                required property int index
                readonly property bool isCurrent: face.index === root.currentIndex
                readonly property real reveal: root.reveal(face.index)
                readonly property real slotScale: 0.85 + 0.15 * face.reveal
                readonly property real slotInset: root.bigFace * (1 - face.slotScale) / 2

                source: face.modelData.image ?? ""
                transformOrigin: Item.TopLeft
                visible: face.isCurrent || face.reveal > 0
                opacity: face.isCurrent ? 1 : face.reveal
                scale: face.isCurrent ? root.lerp(root.smallFace, root.bigFace) / root.bigFace : face.slotScale
                x: face.isCurrent ? root.lerp(root.faceClosedX, root.faceOpenX(face.index)) : root.faceSlotX(face.index) + face.slotInset
                y: face.isCurrent ? root.lerp(root.faceClosedY, root.faceOpenY) : root.height - root.pad - root.slotHeight + root.faceTop + 10 * (1 - face.reveal) + face.slotInset
            }
        }
    }

    // A user's picture, or the person icon in the slanted shape without one.
    component Face: Item {
        id: faceItem
        property string source: ""
        width: root.bigFace
        height: root.bigFace

        // Only without a usable picture: not while one is still loading.
        readonly property bool fallback: faceItem.source === "" || picture.failed

        // Not secondary container: the current user's tile is that colour.
        MaterialShape {
            anchors.fill: parent
            visible: faceItem.fallback
            shape: "Slanted"
            color: Theme.m3surfaceContainerHighest
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: faceItem.fallback
            text: root.fallbackIcon
            fill: 1
            iconSize: 28
            color: Theme.m3onSurfaceVariant
        }
        RoundPicture {
            id: picture
            anchors.fill: parent
            source: faceItem.source
        }
    }
}
