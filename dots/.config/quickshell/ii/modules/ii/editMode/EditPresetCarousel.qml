import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The saved looks, as a two-row carousel that scrolls sideways.
 *
 * One row of 160px cards was a corridor: with twenty presets most of them were
 * a long drag away and nothing said how far. Two rows of larger cards fill the
 * panel's width with less than two columns, so the next column always peeks
 * in from the edge - the strip says it scrolls before anyone tries. Columns
 * fill top to bottom, so the order reads down and then across.
 *
 * The wheel scrolls it (sideways) until an end, then hands the wheel back to
 * the page. The arrows at the edges page a column at a time and the pill
 * underneath is both where you are and a scrubber.
 *
 * Shape is state: the applied card fills with the primary container, its
 * corners open wider and its picture rounds with it; the check rides on a
 * cookie, not inside a ring.
 */
Item {
    id: root

    property var presets: []
    property string activePreset: ""
    property int sortEpoch: 0
    signal applyRequested(string name)

    readonly property int rows: 2
    readonly property real spacing: 8
    // A column and three quarters of the next: the peek is the affordance.
    readonly property real visibleColumns: 1.75
    readonly property real cardWidth: Math.floor((root.width - root.spacing) / root.visibleColumns)
    readonly property real cardHeight: Math.round(root.cardWidth * 0.8)
    // Every cell carries a gap under it, the last row's too: the GridView
    // needs it to fit both rows, and it doubles as the space above the pill.
    readonly property real stripHeight: (root.cardHeight + root.spacing) * root.rows
    readonly property int columnCount: Math.ceil(root.presets.length / root.rows)
    readonly property real columnStep: root.cardWidth + root.spacing
    readonly property bool scrollable: grid.contentWidth > grid.width + 1

    implicitHeight: root.stripHeight + (root.scrollable ? indicator.height + 4 : -root.spacing)

    // ── Scrolling ────────────────────────────────────────────────────────────
    readonly property real maxContentX: Math.max(0, grid.contentWidth - grid.width)

    function scrollTo(x) {
        scrollAnimation.stop();
        scrollAnimation.from = grid.contentX;
        scrollAnimation.to = Math.max(0, Math.min(root.maxContentX, x));
        if (Appearance.reducedMotion) {
            grid.contentX = scrollAnimation.to;
            return;
        }
        scrollAnimation.start();
    }
    function page(direction) {
        // Whole columns: a page always lands with a column's edge at the start.
        const target = scrollAnimation.running ? scrollAnimation.to : grid.contentX;
        const column = Math.round(target / root.columnStep) + direction;
        root.scrollTo(column * root.columnStep);
    }
    function revealActive() {
        const index = root.presets.findIndex(p => String(p.name ?? "") === root.activePreset);
        if (index < 0)
            return;
        const column = Math.floor(index / root.rows);
        const start = column * root.columnStep;
        if (start < grid.contentX || start + root.cardWidth > grid.contentX + grid.width)
            grid.contentX = Math.max(0, Math.min(root.maxContentX, start - root.columnStep * 0.5));
    }

    NumberAnimation {
        id: scrollAnimation
        target: grid
        property: "contentX"
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    // A new order starts from the front and re-deals; a first fill shows the
    // applied look. Cards created by scrolling later arrive settled.
    property bool _dealing: false
    Timer {
        id: dealWindow
        interval: 120
        onTriggered: root._dealing = false
    }
    function _deal() {
        root._dealing = true;
        dealWindow.restart();
    }
    onSortEpochChanged: {
        scrollAnimation.stop();
        root._deal();
        grid.contentX = 0;
    }
    property bool _revealed: false
    onPresetsChanged: {
        if (root._revealed || root.presets.length === 0)
            return;
        root._revealed = true;
        root._deal();
        Qt.callLater(root.revealActive);
    }

    GridView {
        id: grid
        width: root.width
        height: root.stripHeight
        flow: GridView.FlowTopToBottom
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: root.scrollable
        cellWidth: root.columnStep
        cellHeight: root.cardHeight + root.spacing
        model: root.presets
        cacheBuffer: root.columnStep * 2

        onMovementStarted: scrollAnimation.stop()

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: root.cardWidth
            height: root.cardHeight

            PresetCard {
                id: card
                anchors.fill: parent
                preset: cell.modelData
                active: root.activePreset === String(cell.modelData.name ?? "")
            }

            // Re-deal: a column at a time, front to back.
            StaggeredEntrance {
                target: card
                index: Math.floor(cell.index / root.rows)
                step: 34
                maximumDelay: 240
                active: !Appearance.reducedMotion && root._dealing
            }
        }
    }

    // The wheel turns the strip until it reaches an end, then lets the page
    // have it back.
    // A MouseArea rather than a WheelHandler: it can decline a wheel event
    // (`accepted = false`) and, taking no buttons, lets every click through.
    MouseArea {
        anchors.fill: grid
        z: 5
        acceptedButtons: Qt.NoButton
        enabled: root.scrollable
        onWheel: event => {
            const dx = event.angleDelta.x;
            const dy = event.angleDelta.y;
            const delta = Math.abs(dx) > Math.abs(dy) ? dx : dy;
            const pixel = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.pixelDelta.y;
            const base = scrollAnimation.running ? scrollAnimation.to : grid.contentX;
            const step = pixel !== 0 ? -pixel : -delta / 120 * root.columnStep * 0.6;
            const next = Math.max(0, Math.min(root.maxContentX, base + step));
            if (Math.abs(next - base) < 0.5) {
                event.accepted = false;
                return;
            }
            if (pixel !== 0) {
                scrollAnimation.stop();
                grid.contentX = next;
            } else {
                root.scrollTo(next);
            }
        }
    }

    // ── Edge arrows ──────────────────────────────────────────────────────────
    HoverHandler {
        id: stripHover
    }

    EdgeArrow {
        anchors.left: grid.left
        anchors.leftMargin: 6
        anchors.verticalCenter: grid.verticalCenter
        anchors.verticalCenterOffset: -root.spacing / 2
        symbol: "chevron_left"
        shown: root.scrollable && stripHover.hovered && grid.contentX > 1
        onClicked: root.page(-1)
    }
    EdgeArrow {
        anchors.right: grid.right
        anchors.rightMargin: 6
        anchors.verticalCenter: grid.verticalCenter
        anchors.verticalCenterOffset: -root.spacing / 2
        symbol: "chevron_right"
        shown: root.scrollable && stripHover.hovered && grid.contentX < root.maxContentX - 1
        onClicked: root.page(1)
    }

    // ── Where you are: a pill that is also a scrubber ────────────────────────
    Item {
        id: indicator
        visible: root.scrollable
        anchors.top: grid.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width * 0.5, 160)
        height: 12

        readonly property real fraction: grid.contentWidth > 0 ? Math.min(1, grid.width / grid.contentWidth) : 1
        readonly property real progress: root.maxContentX > 0 ? grid.contentX / root.maxContentX : 0
        readonly property bool engaged: scrubHover.hovered || scrub.pressed

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: indicator.engaged ? 8 : 4
            radius: height / 2
            color: Appearance.colors.colSurfaceContainerHighest

            Behavior on height {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(track)
            }

            Rectangle {
                readonly property real thumbWidth: Math.max(track.height * 2, track.width * indicator.fraction)
                width: thumbWidth
                height: parent.height
                x: (track.width - thumbWidth) * indicator.progress
                radius: height / 2
                color: Appearance.colors.colPrimary
            }
        }

        HoverHandler {
            id: scrubHover
            cursorShape: Qt.PointingHandCursor
        }
        MouseArea {
            id: scrub
            anchors.fill: parent
            anchors.margins: -6
            preventStealing: true
            function seek(x) {
                const t = Math.max(0, Math.min(1, (x - 6) / indicator.width));
                scrollAnimation.stop();
                grid.contentX = t * root.maxContentX;
            }
            onPressed: event => seek(event.x)
            onPositionChanged: event => {
                if (pressed)
                    seek(event.x);
            }
        }
    }

    // ── Pieces ───────────────────────────────────────────────────────────────
    component EdgeArrow: Rectangle {
        id: arrow
        property string symbol: ""
        property bool shown: false
        signal clicked()

        width: 36
        height: 36
        radius: arrowTap.pressed ? Appearance.rounding.small : width / 2
        color: arrowHover.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
        opacity: arrow.shown ? 1 : 0
        visible: opacity > 0
        scale: arrow.shown ? 1 : 0.8

        Behavior on opacity {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(arrow)
        }
        Behavior on scale {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(arrow)
        }
        Behavior on radius {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(arrow)
        }

        StyledRectangularShadow {
            target: arrow
            z: -1
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: arrow.symbol
            iconSize: 22
            color: Appearance.colors.colOnSecondaryContainer
        }

        HoverHandler {
            id: arrowHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: arrowTap
            onTapped: arrow.clicked()
        }
    }

    component PresetCard: Rectangle {
        id: card

        property var preset: ({})
        property bool active: false
        readonly property string presetName: String(card.preset.name ?? "")
        readonly property string wallpaper: String(card.preset.wallpaper ?? "")
        readonly property bool busy: PresetStore.busyFor(card.presetName)
        readonly property bool tooNew: Number(card.preset.configVersion ?? 0) > 0
            && Number(card.preset.configVersion) > Config.currentConfigVersion
        readonly property bool fromStore: PresetStore.isFromStore(card.presetName)
        readonly property int screens: Number(card.preset.screenWallpapers ?? 0)
        readonly property bool hovered: cardHover.hovered
        readonly property bool pressed: cardTap.pressed
        readonly property bool clickable: !card.active && !card.busy && !PresetStore.busy
        readonly property real pad: 6
        readonly property real labelHeight: 34

        radius: card.active ? Appearance.rounding.verylarge
            : (card.pressed ? Appearance.rounding.normal : Appearance.rounding.large)
        // A little of the primary in the container, so the applied card is
        // told apart even under a scheme whose containers are all one grey.
        color: card.active
            ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.84)
            : (card.hovered && card.clickable ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colSurfaceContainerHigh)
        scale: card.pressed && card.clickable ? 0.95 : 1

        Behavior on radius {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
        }
        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
        }
        Behavior on scale {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
        }

        // The picture, its corners following the card's.
        ClippingRectangle {
            id: picture
            x: card.pad
            y: card.pad
            width: card.width - card.pad * 2
            height: card.height - card.pad - card.labelHeight
            radius: Math.max(Appearance.rounding.unsharpenmore, card.radius - card.pad)
            color: Appearance.colors.colSurfaceContainerHighest

            StyledImage {
                anchors.fill: parent
                sourceSize: Qt.size(420, 340)
                source: card.wallpaper !== "" ? card.wallpaper : `${Directories.assetsPath}/images/default_wallpaper.png`
                fillMode: Image.PreserveAspectCrop
                opacity: card.busy ? 0.45 : 1

                Behavior on opacity {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(card)
                }
            }

            MaterialLoadingIndicator {
                anchors.centerIn: parent
                implicitSize: 40
                visible: card.busy
                loading: card.busy
            }
        }

        // What the preset carries beyond a look: a video, its own pictures
        // per screen, a store origin, a newer shell than this one.
        Row {
            anchors.left: picture.left
            anchors.top: picture.top
            anchors.margins: 6
            spacing: 4

            Badge {
                shown: card.tooNew
                symbol: "system_update_alt"
                tint: Appearance.colors.colErrorContainer
                ink: Appearance.colors.colOnErrorContainer
                tip: Translation.tr("Made with a newer version of the shell")
            }
            Badge {
                shown: card.fromStore
                symbol: "storefront"
                tip: Translation.tr("From the store")
            }
            Badge {
                shown: card.preset.video === true
                symbol: "movie"
                tip: Translation.tr("Video wallpaper")
            }
            Badge {
                shown: card.screens > 1
                symbol: "desktop_windows"
                tip: Translation.tr("A wallpaper per screen")
            }
        }

        // Applied: a check on a cookie, in the card's own accent.
        MaterialShapeWrappedMaterialSymbol {
            anchors.right: picture.right
            anchors.top: picture.top
            anchors.margins: 6
            implicitSize: 30
            iconSize: 17
            padding: 0
            visible: card.active
            text: "check"
            shape: MaterialShape.Shape.Cookie7Sided
            color: Appearance.colors.colPrimary
            colSymbol: Appearance.colors.colOnPrimary
        }

        StyledText {
            id: nameText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: card.pad + 6
            anchors.rightMargin: card.pad + 6
            height: card.labelHeight
            verticalAlignment: Text.AlignVCenter
            text: card.presetName
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.variableAxes: card.active
                ? ({ "wght": 650, "wdth": 100, "ROND": 100 })
                : ({ "wght": 450, "wdth": 100, "ROND": 100 })
            color: card.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
        }

        HoverHandler {
            id: cardHover
            cursorShape: card.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        TapHandler {
            id: cardTap
            enabled: card.clickable
            onTapped: root.applyRequested(card.presetName)
        }

        StyledToolTip {
            text: card.active ? Translation.tr("%1 · applied").arg(card.presetName)
                : nameText.truncated ? Translation.tr("Apply %1").arg(card.presetName)
                : Translation.tr("Apply preset")
            extraVisibleCondition: card.hovered
        }
    }

    component Badge: Rectangle {
        id: badge
        property bool shown: false
        property string symbol: ""
        property string tip: ""
        property color tint: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainerLowest, 0.15)
        property color ink: Appearance.colors.colOnSurface

        visible: badge.shown
        width: 24
        height: 24
        radius: 12
        color: badge.tint

        MaterialSymbol {
            anchors.centerIn: parent
            text: badge.symbol
            iconSize: 14
            color: badge.ink
        }

        HoverHandler {
            id: badgeHover
        }
        StyledToolTip {
            text: badge.tip
            extraVisibleCondition: badgeHover.hovered
        }
    }
}
