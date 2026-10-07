pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.core
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.island
import qs.services
import "island/IslandCatalog.js" as Catalog

/**
 * Settings → Dynamic Island.
 *
 * Leads with the island itself, live over the wallpaper, then where it lives (two
 * mode cards that say what the bar needs when they cannot be had), the way into the
 * activities, what opens inside it as tiles, and the plain options in their
 * original sections. Search indexes sections/DynamicIslandModeSection.qml for the
 * cards and tiles, which keep the same switches and side effects.
 */
Item {
    id: dynamicIslandConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var fn: Config.options.bar.floatingNotch
    readonly property bool barNotTop: Config.options.bar.bottom || Config.options.bar.vertical
    readonly property bool centerInBarActive: Config.options.bar.floatingNotch.centerInBar
    /** One answer for "is any island on?"; every island control gates on it. */
    readonly property bool islandOn: Config.options.bar.floatingNotch.enable
        || Config.options.bar.floatingNotch.centerInBar

    Connections {
        target: dynamicIslandConfigRoot
        function onBarNotTopChanged() {
            if (!dynamicIslandConfigRoot.barNotTop && Config.options.bar.floatingNotch.enable) {
                Config.options.bar.floatingNotch.enable = false;
            }
        }
    }

    // ── Try-on: what a tile under the pointer shows on the hero ─────────────
    /**
     * Found from where the pointer is on the page, not from each tile's own hover: the
     * hero opens over the page, and over the top tiles too, so the tile it came from
     * (or the next one) is often under it. By position the try-on follows the pointer
     * from tile to tile whatever is drawn above them.
     */
    property string tryHost: ""
    property var tryProps: ({})
    property string tryKey: ""
    HoverHandler {
        id: pagePointer
        onPointChanged: dynamicIslandConfigRoot.resolveTry()
        onHoveredChanged: dynamicIslandConfigRoot.resolveTry()
    }
    Timer {
        id: tryRelease
        interval: 240
        onTriggered: {
            dynamicIslandConfigRoot.tryHost = "";
            dynamicIslandConfigRoot.tryKey = "";
        }
    }
    Timer {
        id: tryDwell
        property var pending: null
        interval: 90
        onTriggered: {
            const target = tryDwell.pending;
            if (!target)
                return;
            dynamicIslandConfigRoot.tryProps = target.props;
            dynamicIslandConfigRoot.tryHost = target.host;
        }
    }
    /** Most specific first: a chip before the tile it sits on. */
    function tryTargets() {
        const fn = dynamicIslandConfigRoot.fn;
        return [
            { item: rowChip, host: "wallpaper", props: { "style": "row" } },
            { item: carouselChip, host: "wallpaper", props: { "style": "carousel" } },
            { item: overviewTile, host: "overview", props: {} },
            { item: sessionTile, host: "session", props: {} },
            { item: switcherTile, host: "switcher", props: {} },
            { item: wallpaperTile, host: "wallpaper", props: {} },
            { item: askSudo, host: "askpass", props: { "kind": "sudo", "style": fn.askpassStyle } },
            { item: askTerminal, host: "askpass", props: { "kind": "sudo", "style": fn.askpassTerminalStyle } },
            { item: askPolkit, host: "askpass", props: { "kind": "polkit", "style": fn.askpassStyle } },
            { item: askSsh, host: "askpass", props: { "kind": "ssh", "style": fn.askpassStyle } },
            { item: askStyleArray, host: "askpass", props: { "kind": "sudo", "style": fn.askpassStyle } },
            { item: askTerminalStyleArray, host: "askpass", props: { "kind": "sudo", "style": fn.askpassTerminalStyle } }
        ];
    }
    function resolveTry() {
        let target = null;
        if (pagePointer.hovered && !subPageOverlay.isOpen) {
            const p = pagePointer.point.position;
            // Below the hero's resting height only: the resting hero has no tile under it.
            const pageTop = page.y;
            const list = dynamicIslandConfigRoot.tryTargets();
            for (let i = 0; i < list.length && p.y >= pageTop; i++) {
                const item = list[i].item;
                if (!item || !item.visible || item.width <= 0)
                    continue;
                const q = item.mapFromItem(dynamicIslandConfigRoot, p.x, p.y);
                if (q.x >= 0 && q.y >= 0 && q.x < item.width && q.y < item.height) {
                    target = list[i];
                    break;
                }
            }
        }
        const key = target ? target.host + ":" + JSON.stringify(target.props) : "";
        if (key === dynamicIslandConfigRoot.tryKey)
            return;
        dynamicIslandConfigRoot.tryKey = key;
        if (target) {
            tryRelease.stop();
            tryDwell.pending = target;
            tryDwell.restart();
        } else {
            tryDwell.stop();
            tryRelease.restart();
        }
    }

    function openActivities() {
        subPageOverlay.open(Qt.resolvedUrl("widgets/DynamicIslandActivitiesConfig.qml"));
    }

    function goToBar() {
        const win = dynamicIslandConfigRoot.QsWindow.window;
        if (!win || win.currentPage === undefined || win.pageIndexById === undefined)
            return;
        const idx = win.pageIndexById("bar");
        if (idx >= 0) {
            win.pendingSectionHighlight = Translation.tr("Bar position");
            win.currentPage = idx;
        }
    }

    function setCenterInBar(checked) {
        if (checked === Config.options.bar.floatingNotch.centerInBar)
            return;

        if (checked) {
            // Refused rather than coerced: silently rewriting the user's
            // bar style to enable a different feature is worse than not
            // enabling it. The selector blocks the reverse direction too.
            if (!ShellModePolicy.centerInBarStyleSupported)
                return;
            Config.options.bar.floatingNotch.enable = false;
            Config.options.sidebar.sidebarStyle = "default";
            Config.options.bar.bottom = false;
            Config.options.bar.vertical = false;
            if (Config.options.bar.barBackgroundStyle !== 3)
                Config.options.bar.barBackgroundStyle = 0;
            if (Config.options.appearance.fakeScreenRounding === 3 || Config.options.appearance.fakeScreenRounding === 4)
                Config.options.appearance.fakeScreenRounding = 1;
            Config.options.bar.autoHide.enable = false;

            // The centre belongs to the island: stash the user's
            // layout and empty the group. The old code only hid the
            // entries, which left zombie widgets occupying the centre
            // in the layout editor and in the saved config.
            var cl = Config.options.bar.layouts.center;
            if (cl && cl.length) {
                var stashed = [];
                for (var i = 0; i < cl.length; i++) {
                    stashed.push({
                        id: cl[i].id,
                        centered: cl[i].centered === true,
                        visible: cl[i].visible !== false,
                    });
                }
                Persistent.states.bar.centerStash = stashed;
                Config.options.bar.layouts.center = [];
            }

            Config.options.bar.floatingNotch.centerInBar = true;
        } else {
            Config.options.bar.floatingNotch.centerInBar = false;
            // Give back what was taken, but only while the centre is
            // still empty: if the user rebuilt it by hand meanwhile,
            // their new layout wins and the stash is dropped.
            var stash = Persistent.states.bar.centerStash;
            var current = Config.options.bar.layouts.center;
            if (stash && stash.length > 0 && (!current || current.length === 0))
                Config.options.bar.layouts.center = stash;
            Persistent.states.bar.centerStash = [];
        }
    }

    function setFloating(checked) {
        if (checked === Config.options.bar.floatingNotch.enable)
            return;
        if (checked && !dynamicIslandConfigRoot.barNotTop)
            return;
        if (checked && Config.options.bar.floatingNotch.centerInBar)
            Config.options.bar.floatingNotch.centerInBar = false;
        // The island takes the top edge: the bar's auto-hide would hide the bar out from
        // under it. Same rule "island in bar center" enforces; Bar → Behavior locks the
        // toggle while this holds.
        if (checked && !Config.options.bar.vertical)
            Config.options.bar.autoHide.enable = false;
        Config.options.bar.floatingNotch.enable = checked;
    }

    readonly property int activitiesOn: {
        let n = 0;
        let total = 0;
        for (let i = 0; i < Catalog.activities.length; i++) {
            const entry = Catalog.activities[i];
            if (entry.needs === "easyEffects" && !EasyEffects.available)
                continue;
            if (dynamicIslandConfigRoot.fn[entry.key] !== true)
                n++;
        }
        return n;
    }
    readonly property int activitiesTotal: Catalog.activities.filter(e => e.needs !== "easyEffects" || EasyEffects.available).length

    // ── The island, live ──────────────────────────────────────────────
    IslandPreviewStage {
        id: hero
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        // Sticky and as short as what it shows: a resting pill, or the surface a tile
        // below is pointing at.
        height: Math.min(hero.preferredHeight, Math.max(hero.minHeight, dynamicIslandConfigRoot.height * 0.6))
        Behavior on height {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        opacity: subPageOverlay.slideProgress
        z: 5
        hostId: dynamicIslandConfigRoot.tryHost
        hostProps: dynamicIslandConfigRoot.tryProps
        shapeOverride: shapePicker.tried
        restSideIds: {
            const ids = [];
            if (MprisController.activePlayer && dynamicIslandConfigRoot.fn.disableMedia !== true)
                ids.push("media");
            if (dynamicIslandConfigRoot.fn.disableWeather !== true)
                ids.push("weather");
            if (dynamicIslandConfigRoot.fn.disableBatteryGlance !== true)
                ids.push("batteryGlance");
            return ids;
        }
        islandOn: dynamicIslandConfigRoot.islandOn

        // Name tag, bottom-left: the name in the title face over where it lives.
        Rectangle {
            id: heroTag
            readonly property real room: (hero.width - hero.islandTargetWidth * hero.liveScale) / 2
            opacity: heroTag.room > heroTag.width + 28 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 11
            height: tagColumn.implicitHeight + 12
            width: Math.min(hero.width - 90, tagColumn.implicitWidth + 36)
            radius: Math.min(height / 2, Appearance.rounding.large)
            color: Appearance.colors.colSurfaceContainerHigh

            ColumnLayout {
                id: tagColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Dynamic Island")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
                RowLayout {
                    spacing: 6
                    Rectangle {
                        width: 7
                        height: 7
                        radius: 3.5
                        color: dynamicIslandConfigRoot.islandOn ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                    }
                    StyledText {
                        text: {
                            if (!dynamicIslandConfigRoot.islandOn)
                                return Translation.tr("Off");
                            const where = dynamicIslandConfigRoot.centerInBarActive ? Translation.tr("In the bar") : Translation.tr("Floating");
                            const shape = IslandPolicy.shape === "island" ? Translation.tr("Island") : Translation.tr("Notch");
                            return where + " · " + shape;
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // The page's main action, bottom-right: same height as the tag.
        RippleButton {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 11
            readonly property real room: (hero.width - hero.islandTargetWidth * hero.liveScale) / 2
            opacity: dynamicIslandConfigRoot.islandOn && room > implicitWidth + 28 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            // Pills along the same edge share one height.
            implicitHeight: heroTag.height
            implicitWidth: hero.width < 420 ? heroTag.height : heroActionRow.implicitWidth + 36
            buttonRadius: height / 2
            buttonRadiusPressed: Appearance.rounding.small
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: dynamicIslandConfigRoot.openActivities()
            StyledToolTip {
                visible: hero.width < 420 && parent.hovered
                text: Translation.tr("Activities")
            }
            contentItem: Item {
                RowLayout {
                    id: heroActionRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "widgets"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        visible: hero.width >= 420
                        text: Translation.tr("Activities")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }


    // Lifts the hero off the page only while it is open over it. Analytic, beside the
    // hero rather than a layer on it: a layer re-rendered the whole stage (screen copies
    // included) into a texture and blurred it on every frame of the opening.
    RectangularShadow {
        anchors.fill: hero
        z: 4
        radius: Appearance.rounding.verylarge
        blur: 22
        offset.y: 6
        color: Appearance.colors.colShadow
        opacity: hero.height > hero.minHeight + 1 ? hero.opacity : 0
        visible: opacity > 0.01
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    ContentPage {
        id: page
        anchors.fill: undefined
        // Under the hero's resting height, never its open one: the hero opens over the
        // page, so the tile under the pointer never moves out from under it.
        anchors.top: parent.top
        anchors.topMargin: hero.minHeight + 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Where it lives ────────────────────────────────────────────────
        Item {
            id: modes
            Layout.fillWidth: true
            readonly property bool stacked: width < 620
            readonly property int gap: 12
            readonly property real cardWidth: modes.stacked ? width : Math.floor((width - gap) / 2)
            implicitHeight: modes.stacked ? barCard.implicitHeight + gap + floatCard.implicitHeight : barCard.implicitHeight

            IslandModeCard {
                id: barCard
                x: 0
                y: 0
                width: modes.cardWidth
                symbol: "align_justify_center"
                shapeOn: MaterialShape.Shape.Cookie12Sided
                title: Translation.tr("In the bar")
                summary: barCard.checked
                    ? (Config.options.bar.cornerStyle === 3
                        ? Translation.tr("Holds the bar's centre; its widget groups flank it and step aside as it grows.")
                        : Translation.tr("Holds the bar's centre. Its centre widgets are stashed until you give it back."))
                    : Translation.tr("Takes the bar's centre. Forces Default mode, bar Top and a Transparent background.")
                checked: dynamicIslandConfigRoot.centerInBarActive
                available: !dynamicIslandConfigRoot.barNotTop && ShellModePolicy.centerInBarStyleSupported
                blockedText: dynamicIslandConfigRoot.barNotTop
                    ? Translation.tr("Needs the bar at the top of the screen.")
                    : Translation.tr("Needs the Hug or Dynamic Island bar style (any style with the Island shape) and a Transparent or Islands background.")
                fixLabel: Translation.tr("Bar settings")
                onToggledByUser: value => dynamicIslandConfigRoot.setCenterInBar(value)
                onFixRequested: dynamicIslandConfigRoot.goToBar()
            }

            IslandModeCard {
                id: floatCard
                x: modes.stacked ? 0 : modes.cardWidth + modes.gap
                y: modes.stacked ? barCard.implicitHeight + modes.gap : 0
                width: modes.cardWidth
                symbol: "water_drop"
                shapeOn: MaterialShape.Shape.Flower
                title: Translation.tr("Floating")
                summary: Translation.tr("Hangs from the top edge on its own, free of the bar.")
                checked: Config.options.bar.floatingNotch.enable
                available: dynamicIslandConfigRoot.barNotTop
                blockedText: Translation.tr("Needs the bar at the bottom or on a side, so the top edge is free.")
                fixLabel: Translation.tr("Bar settings")
                onToggledByUser: value => dynamicIslandConfigRoot.setFloating(value)
                onFixRequested: dynamicIslandConfigRoot.goToBar()
            }
        }

        // ── Its shape ─────────────────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 12
            visible: dynamicIslandConfigRoot.islandOn
            title: Translation.tr("Shape")
            symbol: "interests"

            IslandShapePicker {
                id: shapePicker
                Layout.fillWidth: true
                currentValue: Config.options.bar.floatingNotch.shape
                // Refused rather than coerced, as everywhere else here: the notch cannot
                // sit in a Float or Rect bar centre, and dropping back to it would
                // silently switch the island off instead of changing a shape.
                notchBlocked: ShellModePolicy.notchShapeBlockedByCenterInBar
                notchBlockedText: Translation.tr(ShellModePolicy.notchShapeBlockedReasonKey)
                islandColor: hero.islandColor
                onSelected: value => Config.options.bar.floatingNotch.shape = value
            }
        }

        // ── Activities: the way in ────────────────────────────────────────
        RippleButton {
            id: activitiesPane
            Layout.fillWidth: true
            visible: dynamicIslandConfigRoot.islandOn
            implicitHeight: activitiesColumn.implicitHeight + 40
            buttonRadius: Appearance.rounding.verylarge
            buttonRadiusPressed: Appearance.rounding.large
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            onClicked: dynamicIslandConfigRoot.openActivities()

            contentItem: Item {
                ColumnLayout {
                    id: activitiesColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        MaterialShapeWrappedMaterialSymbol {
                            text: "widgets"
                            iconSize: 24
                            padding: 12
                            fill: 1
                            shape: activitiesPane.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                            color: Appearance.colors.colPrimaryContainer
                            colSymbol: Appearance.colors.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Activities & glances")
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Announcements, live activities, side glances and system notches, each previewed on the island")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        // The count, in condensed digits.
                        StyledText {
                            text: dynamicIslandConfigRoot.activitiesOn
                            font.family: Appearance.font.family.main
                            font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                            font.pixelSize: Math.round(Appearance.font.pixelSize.huge * 1.7)
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("of %1\non").arg(dynamicIslandConfigRoot.activitiesTotal)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            lineHeight: 0.9
                            color: Appearance.colors.colSubtext
                        }
                        MaterialSymbol {
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    // What is on, glyph by glyph: the island's vocabulary at a glance.
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: Catalog.activities.filter(e => e.needs !== "easyEffects" || EasyEffects.available)
                            delegate: MaterialShapeWrappedMaterialSymbol {
                                id: chipGlyph
                                required property var modelData
                                readonly property bool on: dynamicIslandConfigRoot.fn[chipGlyph.modelData.key] !== true
                                text: chipGlyph.modelData.icon
                                iconSize: 15
                                padding: 6
                                fill: chipGlyph.on ? 1 : 0
                                shape: chipGlyph.on ? chipGlyph.getShape(chipGlyph.modelData.shape) : MaterialShape.Shape.Circle
                                color: chipGlyph.on ? Appearance.colors.colSecondaryContainer : "transparent"
                                colSymbol: chipGlyph.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOutline
                            }
                        }
                    }
                }
            }
        }

        // ── Inside the island ─────────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 12
            visible: dynamicIslandConfigRoot.islandOn
            title: Translation.tr("Opens inside the island")
            symbol: "open_in_full"

            Item {
                id: tiles
                Layout.fillWidth: true
                implicitHeight: tileFlow.implicitHeight

                readonly property int gap: 12
                readonly property int fits: Math.max(1, Math.floor((width + gap) / (260 + gap)))
                // Four tiles: one row of four, two of two or a column, never 3 + 1.
                readonly property int columns: fits >= 4 ? 4 : fits >= 2 ? 2 : 1
                readonly property int tileWidth: Math.floor((width - gap * (columns - 1)) / columns)
                readonly property int tileHeight: 200

                Flow {
                    id: tileFlow
                    width: parent.width
                    spacing: tiles.gap

                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: tiles.tileHeight
                        id: overviewTile
                        symbol: "grid_view"
                        shapeOn: MaterialShape.Shape.Cookie4Sided
                        title: Translation.tr("Overview")
                        summary: checked ? Translation.tr("A small fixed grid under the search field")
                            : Translation.tr("The desktop overview keeps its own grid and animations")
                        checked: dynamicIslandConfigRoot.fn.integratedOverview
                        onToggled: value => dynamicIslandConfigRoot.fn.integratedOverview = value
                    }
                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: tiles.tileHeight
                        id: sessionTile
                        symbol: "power_settings_new"
                        shapeOn: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("Session menu")
                        summary: checked ? Translation.tr("The eight actions in a four-by-two grid, in the island")
                            : Translation.tr("The power button opens the full-screen session screen")
                        checked: dynamicIslandConfigRoot.fn.integratedSessionMenu
                        onToggled: value => dynamicIslandConfigRoot.fn.integratedSessionMenu = value
                    }
                    ColorsFeatureTile {
                        width: tiles.tileWidth
                        height: tiles.tileHeight
                        id: switcherTile
                        symbol: "tab"
                        shapeOn: MaterialShape.Shape.Clover4Leaf
                        title: Translation.tr("Alt+Tab")
                        summary: checked ? Translation.tr("A cover flow of live window previews")
                            : Translation.tr("Alt+Tab opens the floating switcher panel")
                        checked: !dynamicIslandConfigRoot.fn.disableWindowSwitcher
                        onToggled: value => dynamicIslandConfigRoot.fn.disableWindowSwitcher = !value
                    }
                    ColorsFeatureTile {
                        id: wallpaperTile
                        width: tiles.tileWidth
                        height: tiles.tileHeight
                        symbol: "wallpaper"
                        shapeOn: MaterialShape.Shape.Flower
                        title: Translation.tr("Wallpaper picker")
                        summary: checked ? Translation.tr("Browse in the island, the folder above and the toolbars below")
                            : Translation.tr("Opens the full-screen wallpaper selector")
                        checked: dynamicIslandConfigRoot.fn.integratedWallpaperBrowser
                        onToggled: value => dynamicIslandConfigRoot.fn.integratedWallpaperBrowser = value

                        ColorsChip {
                            visible: wallpaperTile.checked
                            implicitHeight: 32
                            id: rowChip
                            symbol: "view_column"
                            label: Translation.tr("Row")
                            chosen: dynamicIslandConfigRoot.fn.wallpaperBrowserStyle === "row"
                            colContent: wallpaperTile.colContent
                            colChosen: Appearance.colors.colPrimary
                            colOnChosen: Appearance.colors.colOnPrimary
                            onClicked: dynamicIslandConfigRoot.fn.wallpaperBrowserStyle = "row"
                        }
                        ColorsChip {
                            visible: wallpaperTile.checked
                            implicitHeight: 32
                            id: carouselChip
                            symbol: "view_carousel"
                            label: Translation.tr("Carousel")
                            chosen: dynamicIslandConfigRoot.fn.wallpaperBrowserStyle === "carousel"
                            colContent: wallpaperTile.colContent
                            colChosen: Appearance.colors.colPrimary
                            colOnChosen: Appearance.colors.colOnPrimary
                            onClicked: dynamicIslandConfigRoot.fn.wallpaperBrowserStyle = "carousel"
                        }
                    }
                }
            }
        }

        // ── Beside the island ─────────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 12
            visible: dynamicIslandConfigRoot.islandOn
            title: Translation.tr("Beside and on the island")
            symbol: "bubble_chart"

            Item {
                id: extraTiles
                Layout.fillWidth: true
                implicitHeight: extraFlow.implicitHeight
                readonly property int gap: 12
                readonly property int columns: width >= 2 * 260 + gap ? 2 : 1
                readonly property int tileWidth: Math.floor((width - gap * (columns - 1)) / columns)

                Flow {
                    id: extraFlow
                    width: parent.width
                    spacing: extraTiles.gap

                    ColorsFeatureTile {
                        width: extraTiles.tileWidth
                        height: 176
                        symbol: "bubble_chart"
                        shapeOn: MaterialShape.Shape.Sunny
                        title: Translation.tr("Auxiliary bubbles")
                        summary: checked ? Translation.tr("Media, workspaces and live activities move into bubbles beside the island; rest on one to open it")
                            : Translation.tr("Live activities sit beside the clock, in the island itself")
                        checked: dynamicIslandConfigRoot.fn.auxiliaryBubble
                        onToggled: value => dynamicIslandConfigRoot.fn.auxiliaryBubble = value
                    }
                    ColorsFeatureTile {
                        width: extraTiles.tileWidth
                        height: 176
                        symbol: "subtitles"
                        shapeOn: MaterialShape.Shape.Cookie7Sided
                        title: Translation.tr("Teleprompter")
                        summary: checked ? (Teleprompter.running ? Translation.tr("Reading a script now") : Translation.tr("A script scrolling on the island, for recordings and interviews"))
                            : Translation.tr("Read a script scrolling on the island, for recordings and interviews")
                        checked: Config.options.dynamicIsland.widgets.teleprompter.enable === true
                        configurable: true
                        onConfigureRequested: subPageOverlay.open(Qt.resolvedUrl("features/TeleprompterConfig.qml"))
                        onToggled: value => {
                            Config.options.dynamicIsland.widgets.teleprompter.enable = value;
                            if (!value)
                                Teleprompter.stop();
                        }
                    }
                }
            }
        }

        // ── Appearance ────────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            visible: dynamicIslandConfigRoot.islandOn
            icon: "palette"
            title: Translation.tr("Island appearance")
            tooltip: Translation.tr("The body's shadow and background color.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "filter_drama"
                    text: Translation.tr("Floating Island drop-shadow")
                    checked: Config.options.bar.floatingNotch.dropShadow
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.dropShadow = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Shows a drop shadow underneath the floating island")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "contrast"
                    text: Translation.tr("AMOLED background")
                    checked: Config.options.bar.amoledBackground
                    onCheckedChanged: {
                        Config.options.bar.amoledBackground = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Pure black, always opaque background for the dynamic island and the bar. Only recolors backgrounds that are visible")
                    }
                }
            }
        }

        // ── Behavior ──────────────────────────────────────────────────────────
        ContentSection {
            visible: dynamicIslandConfigRoot.islandOn
            icon: "mouse"
            title: Translation.tr("Island behavior")
            tooltip: Translation.tr("When the island shows itself and how it reacts to the pointer.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Always hide floating island")
                    checked: Config.options.bar.floatingNotch.autoHide
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.autoHide = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Hides the island until a workspace, media, Bluetooth, notification, or other activity trigger reveals it")
                    }
                }

                ConfigSpinBox {
                    icon: "touch_app"
                    text: Translation.tr("Hover time to expand (ms)")
                    visible: Config.options.bar.floatingNotch.autoHide
                    value: Config.options.bar.floatingNotch.hoverExpandDelayMs
                    from: 0
                    to: 5000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.bar.floatingNotch.hoverExpandDelayMs = value;
                    }

                    StyledToolTip {
                        text: Translation.tr("Hovering shows the contracted island at once; resting the pointer this long opens the expanded view")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "touch_app"
                    text: Translation.tr("Hold to reveal")
                    checked: Config.options.dynamicIsland.behavior.holdToReveal
                    onCheckedChanged: {
                        if (checked === Config.options.dynamicIsland.behavior.holdToReveal)
                            return;
                        Config.options.dynamicIsland.behavior.holdToReveal = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("The dashboard opens once the pointer has rested on the island for this long. The island grows a little while it waits, so the hold is visible.")
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Hold time (ms)")
                    visible: Config.options.dynamicIsland.behavior.holdToReveal
                    value: Config.options.dynamicIsland.behavior.holdToRevealMs
                    from: 200
                    to: 3000
                    stepSize: 50
                    onValueChanged: {
                        Config.options.dynamicIsland.behavior.holdToRevealMs = value;
                    }

                    StyledToolTip {
                        text: Translation.tr("Hold the pointer on the island to open the dashboard")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("Keep dashboard in memory")
                    checked: Config.options.dynamicIsland.behavior.keepDashboardLoaded
                    onCheckedChanged: {
                        if (checked === Config.options.dynamicIsland.behavior.keepDashboardLoaded)
                            return;
                        Config.options.dynamicIsland.behavior.keepDashboardLoaded = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("The dashboard's quick-toggle grid is built once and kept in memory: every opening is instant, but it stays resident and uses extra RAM while idle.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Only show island on single monitor")
                    checked: Config.options.bar.floatingNotch.onlyShowOnSingleMonitor
                    onCheckedChanged: {
                        Config.options.bar.floatingNotch.onlyShowOnSingleMonitor = checked;
                        if (checked && Config.options.bar.floatingNotch.singleMonitorName === "" && Quickshell.screens.length > 0)
                            Config.options.bar.floatingNotch.singleMonitorName = Quickshell.screens[0].name;
                    }

                    StyledToolTip {
                        text: Translation.tr("Display the dynamic island on only one chosen monitor instead of following focus")
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Selected Monitor")
                    icon: "settings_input_hdmi"
                    visible: Config.options.bar.floatingNotch.onlyShowOnSingleMonitor

                    MonitorPicker {
                        currentValue: Config.options.bar.floatingNotch.singleMonitorName
                        onSelected: (newValue) => {
                            Config.options.bar.floatingNotch.singleMonitorName = newValue;
                        }
                    }
                }
            }
        }

        // ── Password prompts ──────────────────────────────────────────────────
        // Every route is opt-in; see AskpassService for what switching one on changes
        // outside the shell (a client, a sudo wrapper in ~/.local/bin, SUDO_ASKPASS).
        ContentSection {
            visible: dynamicIslandConfigRoot.islandOn
            icon: "password"
            title: Translation.tr("Password prompts")
            tooltip: Translation.tr("Answer sudo, polkit and ssh/git password prompts on the island. Each kind is off until you switch it on, and switching it off undoes what it set up.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    id: askSudo
                    buttonIcon: "admin_panel_settings"
                    text: Translation.tr("sudo -A and apps asking for sudo")
                    checked: Config.options.bar.floatingNotch.askpassSudo
                    onCheckedChanged: Config.options.bar.floatingNotch.askpassSudo = checked

                    StyledToolTip {
                        text: Translation.tr("Becomes your SUDO_ASKPASS, so `sudo -A` and programs without a terminal ask here. Works without any askpass set up: the shell installs its own client and exports SUDO_ASKPASS for programs started after this")
                    }
                }

                ConfigSwitch {
                    id: askTerminal
                    buttonIcon: "terminal"
                    text: Translation.tr("sudo typed in a terminal")
                    checked: Config.options.bar.floatingNotch.askpassTerminal
                    onCheckedChanged: Config.options.bar.floatingNotch.askpassTerminal = checked

                    StyledToolTip {
                        text: Translation.tr("Plain `sudo` in a terminal asks on the island too, as a compact pill, and the terminal keeps its own prompt: answer in either. Installs a small sudo wrapper in ~/.local/bin (never over one that is already there)")
                    }
                }

                ConfigSwitch {
                    id: askPolkit
                    buttonIcon: "shield_lock"
                    text: Translation.tr("Polkit (pkexec, apps asking for admin rights)")
                    checked: Config.options.bar.floatingNotch.askpassPolkit
                    onCheckedChanged: Config.options.bar.floatingNotch.askpassPolkit = checked

                    StyledToolTip {
                        text: Translation.tr("Shows polkit prompts on the island instead of the full-screen dialog")
                    }
                }

                ConfigSwitch {
                    id: askSsh
                    buttonIcon: "key"
                    text: Translation.tr("SSH and Git passphrases")
                    checked: Config.options.bar.floatingNotch.askpassSsh
                    onCheckedChanged: Config.options.bar.floatingNotch.askpassSsh = checked

                    StyledToolTip {
                        text: Translation.tr("Exports SSH_ASKPASS (with SSH_ASKPASS_REQUIRE=prefer) and GIT_ASKPASS, so key passphrases and HTTPS credentials are asked here. Programs started after this pick it up")
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: Config.options.bar.floatingNotch.askpassTerminal
                        && AskpassService.setupStatus.wrapper === "foreign"
                    materialIcon: "warning"
                    text: Translation.tr("~/.local/bin/sudo already exists and isn't the island's wrapper, so it was left alone and terminal sudo won't ask here. Remove or rename it to use this.")
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: Config.options.bar.floatingNotch.askpassTerminal
                        && AskpassService.setupStatus.binOnPath === false
                    materialIcon: "info"
                    text: Translation.tr("~/.local/bin is not on your PATH, so terminals won't find the sudo wrapper. Add it to PATH in your shell's config.")
                }

                ContentSubsection {
                    title: Translation.tr("Prompt style")
                    icon: "view_agenda"
                    visible: Config.options.bar.floatingNotch.askpassSudo
                        || Config.options.bar.floatingNotch.askpassPolkit
                        || Config.options.bar.floatingNotch.askpassSsh

                    ConfigSelectionArray {
                        id: askStyleArray
                        currentValue: Config.options.bar.floatingNotch.askpassStyle
                        onSelected: newValue => Config.options.bar.floatingNotch.askpassStyle = newValue
                        options: [{
                            "displayName": Translation.tr("Card"),
                            "icon": "web_asset",
                            "value": "card"
                        }, {
                            "displayName": Translation.tr("Pill"),
                            "icon": "toggle_on",
                            "value": "pill"
                        }]
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Terminal prompt style")
                    icon: "terminal"
                    visible: Config.options.bar.floatingNotch.askpassTerminal

                    ConfigSelectionArray {
                        id: askTerminalStyleArray
                        currentValue: Config.options.bar.floatingNotch.askpassTerminalStyle
                        onSelected: newValue => Config.options.bar.floatingNotch.askpassTerminalStyle = newValue
                        options: [{
                            "displayName": Translation.tr("Pill"),
                            "icon": "toggle_on",
                            "value": "pill"
                        }, {
                            "displayName": Translation.tr("Card"),
                            "icon": "web_asset",
                            "value": "card"
                        }]
                    }
                }
            }
        }

    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
