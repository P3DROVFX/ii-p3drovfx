pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// A folder's contents, not its menu: left-clicking a group opens this card
// beside the icon — the context dialog's surface language (same card colour,
// border, corner, scrim and reveal), but a grid of the apps inside, each
// launching on click. The context menu stays where it belongs: right-click.
FocusScope {
    id: root
    required property var entry
    // The tile's rect in this layer's coordinates, handed in by the layer so
    // the card can sit under it (or above it when the screen edge is closer).
    required property rect tileRect
    signal closeRequested()
    // The header's two group operations, carried to the layer that owns the
    // store: rename opens the context dialog on its rename page, ungroup
    // dissolves the members back onto the desktop.
    signal renameRequested()
    signal ungroupRequested()

    readonly property var apps: entry.apps ?? []
    readonly property int columns: Math.max(1, Math.min(4, apps.length))
    readonly property real cellWidth: 74
    property real reveal: 0
    property bool closing: false
    // The mode's shrink, undone: this card is laid out and drawn in SCREEN
    // pixels (DesktopShortcutsLayer's counterScale; 1 outside the mode).
    // tileRect arrives in surface coordinates, so the anchor maths converts
    // it by 1/counterScale and converts the settled screen-space corner
    // back — with counterScale=1 every line below is the old one.
    property real counterScale: 1

    function dismiss() {
        if (closing)
            return;
        closing = true;
        revealMotion.stop();
        revealMotion.to = 0;
        revealMotion.start();
    }
    // The cascade of the item context dialog's own language, applied to the
    // grid: header first, then one slice per grid ROW (a per-cell cascade
    // would make a row's far cells lag their own line). One scalar, LINEAR,
    // pure arithmetic, exits in reverse for free — every slice eases itself
    // (smoothstep), and the two clocks are separate: the card lands in the
    // first slice and stands still while the grid waves in inside it.
    readonly property real bodySpan: 0.22
    readonly property real plateSpan: 0.22
    readonly property real rowLead: 0.2
    readonly property real rowSpan: 0.55
    readonly property int gridRows: Math.ceil(apps.length / columns)
    function ease(t: real): real {
        return t * t * (3 - 2 * t);
    }
    readonly property real bodyReveal: root.ease(Math.min(1, reveal / bodySpan))
    readonly property real plateReveal: root.ease(Math.min(1, reveal / plateSpan))

    function rowReveal(index: int, count: int): real {
        const step = count > 1
            ? Math.min(0.041, (1 - root.rowLead - root.rowSpan) / (count - 1)) : 0;
        const t = (root.reveal - root.rowLead - index * step) / root.rowSpan;
        return root.ease(Math.max(0, Math.min(1, t)));
    }
    function launch(app) {
        DesktopShortcuts.launch(app);
        root.dismiss();
    }

    focus: true
    Component.onCompleted: {
        root.forceActiveFocus();
        revealMotion.start();
    }
    Keys.onEscapePressed: event => {
        event.accepted = true;
        root.dismiss();
    }

    NumberAnimation {
        id: revealMotion
        target: root
        property: "reveal"
        to: 1
        duration: Appearance.reducedMotion ? 0
            : root.closing ? Appearance.animation.popupExit.duration
                : Appearance.animation.popupEnter.duration
        easing.type: Easing.Linear
        onFinished: { if (root.closing) root.closeRequested(); }
    }

    // Click anywhere outside closes. The scrim covers the whole layer, so a
    // press on another icon closes the folder rather than launching through.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
        onWheel: wheel => wheel.accepted = true
    }

    // The card leaves its icon the way a folder opens: one below the tile
    // slides down out of it, one above slides up out of it, so the movement
    // reads as travel from the thing it belongs to, not as a generic fade.
    readonly property bool opensDownward: card.y > tileRect.y + tileRect.height / 2
    Rectangle {
        id: card
        readonly property real gap: 8
        x: {
            const k = root.counterScale;
            const ts = root.tileRect;
            Math.max(card.gap, Math.min(root.width - width - card.gap,
                (ts.x + ts.width / 2) / k - width / 2)) * k
        }
        y: {
            const k = root.counterScale;
            const tsy = root.tileRect.y / k;
            const tsh = root.tileRect.height / k;
            (tsy + tsh + implicitHeight + 2 * card.gap > root.height
                ? Math.max(card.gap, tsy - implicitHeight - card.gap)
                : tsy + tsh + card.gap) * k
        }
        width: Math.min(root.width - 2 * card.gap, root.columns * root.cellWidth + (root.columns - 1) * 4 + 24)
        height: implicitHeight
        implicitHeight: cardLayout.implicitHeight + 24
        radius: Appearance.rounding.windowRounding
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        opacity: Math.min(1, root.reveal * 8)
        scale: root.counterScale * (0.94 + 0.06 * root.bodyReveal)
        transformOrigin: Item.TopLeft
        transform: Translate { y: (1 - root.bodyReveal) * (root.opensDownward ? -10 : 10) }
        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: 12
            anchors.topMargin: 8
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 8
                opacity: root.plateReveal
                // The group's own face: the same 2×2 member mosaic the tile
                // draws, shrunk to header size, so the card is unmistakably
                // the icon you clicked.
                Grid {
                    Layout.alignment: Qt.AlignVCenter
                    columns: 2
                    spacing: 2
                    Repeater {
                        model: root.apps.slice(0, 4)
                        delegate: IconImage {
                            required property var modelData
                            implicitSize: 11
                            source: Quickshell.iconPath(modelData.icon, "image-missing")
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.entry.name || root.entry.id || ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    visible: root.apps.length > 0
                    text: `${root.apps.length}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                // Rename and ungroup, as small icon buttons at the header's
                // end — the grid stays about launching, the header about
                // managing. No borders, no plate; the hover circle is the
                // affordance.
                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1
                    colRipple: Appearance.colors.colLayer1Active
                    scaleBehaviorEnabled: false
                    pointingHandCursor: true
                    activeFocusOnTab: true
                    onClicked: root.renameRequested()
                    Keys.onReturnPressed: clicked()
                    contentItem: MaterialSymbol {
                        text: "edit"
                        iconSize: 18
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1
                    colRipple: Appearance.colors.colLayer1Active
                    scaleBehaviorEnabled: false
                    pointingHandCursor: true
                    activeFocusOnTab: true
                    onClicked: root.ungroupRequested()
                    Keys.onReturnPressed: clicked()
                    contentItem: MaterialSymbol {
                        text: "folder_off"
                        iconSize: 18
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, appGrid.implicitHeight)
                visible: root.apps.length > 0
                contentHeight: appGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                GridLayout {
                    id: appGrid
                    width: parent.width
                    columns: root.columns
                    columnSpacing: 4
                    rowSpacing: 4
                    Repeater {
                        model: root.apps
                        delegate: RippleButton {
                            required property var modelData
                            required property int index
                            readonly property real arrived: root.rowReveal(
                                Math.floor(index / root.columns), root.gridRows)
                            implicitWidth: root.cellWidth
                            implicitHeight: 76
                            buttonRadius: Appearance.rounding.normal
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1
                            colBackgroundActive: Appearance.colors.colLayer1Active
                            colRipple: Appearance.colors.colLayer1Active
                            pointingHandCursor: true
                            activeFocusOnTab: true
                            opacity: arrived
                            visualScale: 0.965 + 0.035 * arrived
                            transformOrigin: Item.TopLeft
                            opacityBehaviorEnabled: root.reveal >= 1
                            Keys.onReturnPressed: clicked()
                            onClicked: root.launch(modelData)
                            contentItem: ColumnLayout {
                                spacing: 2
                                IconImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 8
                                    implicitSize: 36
                                    source: Quickshell.iconPath(modelData.icon, "image-missing")
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.margins: 6
                                    Layout.topMargin: 0
                                    text: modelData.name || modelData.id
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.margins: 4
                visible: root.apps.length === 0
                text: Translation.tr("No applications in this group")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }
}
