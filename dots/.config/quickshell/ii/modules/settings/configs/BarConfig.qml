pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode
import qs.modules.settings.configs.bar
import qs.services

/**
 * Settings → Bar.
 *
 * Where the bar sits and how big it is, drawn rather than listed: the edge picked on a
 * drawing of the screen, the height in big digits with a gauge, the shell mode as one
 * sliding track, and the auto-hide trigger as cards that draw their zone. The look and
 * the layout are a card each that shows what is behind it. Plain behaviour stays in the
 * original switches. Search indexes sections/BarPlacementSection.qml for all of it.
 */
Item {
    id: barConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property real gap: 12
    readonly property real wideBreak: 620
    readonly property real entryBreak: 720
    readonly property real entryHeight: 204
    readonly property real entryCompactHeight: 92

    readonly property var bar: Config.options.bar

    property string autoSwitchNoticeMessage: ""
    // The island hangs from the top edge of a horizontal bar: hiding the bar under it
    // leaves a floating island with nothing to retract into and stacks the reveal
    // strip against the island's own hover region. Auto-hide is the island's setting
    // (`floatingNotch.autoHide`), not the bar's, while this combination is on.
    readonly property bool islandOwnsTopEdge: (barConfigRoot.bar.floatingNotch.enable
        || barConfigRoot.bar.floatingNotch.centerInBar) && !barConfigRoot.bar.vertical
    readonly property bool autoHideLocked: ShellModePolicy.barPositionLocked || barConfigRoot.islandOwnsTopEdge
    readonly property bool tablet: Config.options.panelFamily === "tablet"

    readonly property var layouts: barConfigRoot.bar.layouts
    readonly property int barWidgetCount: (barConfigRoot.layouts.left?.length ?? 0)
        + (barConfigRoot.layouts.center?.length ?? 0)
        + (barConfigRoot.layouts.right?.length ?? 0)

    readonly property var cornerNames: [Translation.tr("Hug"), Translation.tr("Float"), Translation.tr("Rect"), Translation.tr("Island")]
    readonly property var backgroundNames: [Translation.tr("Transparent"), Translation.tr("Visible"), Translation.tr("Adaptive"), Translation.tr("Islands")]
    readonly property var groupNames: [Translation.tr("Pills"), Translation.tr("Island groups"), Translation.tr("No groups")]

    readonly property var revealPresets: [
        { "value": "instant", "label": Translation.tr("Instant"), "width": 6, "delay": 0 },
        { "value": "dwell", "label": Translation.tr("Hold"), "width": 16, "delay": 250 },
        { "value": "wide", "label": Translation.tr("Wide edge"), "width": 32, "delay": 0 },
        { "value": "cautious", "label": Translation.tr("Cautious"), "width": 32, "delay": 250 }
    ]

    Timer {
        id: autoSwitchNoticeTimer
        interval: 6000
        onTriggered: barConfigRoot.autoSwitchNoticeMessage = ""
    }

    function triggerAutoSwitchNotice(msg: string) {
        barConfigRoot.autoSwitchNoticeMessage = msg;
        autoSwitchNoticeTimer.restart();
    }

    function openSubPage(file) {
        barConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/" + file);
    }

    function openWidgetPage(componentId) {
        page.openWidgetPage(componentId);
    }

    function setPosition(value) {
        const isVertical = (value & 2) !== 0;
        const isBottom = (value & 1) !== 0;
        if (!isVertical && !isBottom && barConfigRoot.bar.floatingNotch.enable)
            barConfigRoot.triggerAutoSwitchNotice(Translation.tr("Floating Dynamic Island is not supported with the bar at the Top. It was automatically disabled."));
        if (!isVertical && barConfigRoot.bar.cornerStyle === 3 && Config.options.sidebar.sidebarStyle === "connect")
            barConfigRoot.triggerAutoSwitchNotice(Translation.tr("Dynamic Island is only supported in vertical orientation in Connect mode. Shell mode was automatically switched to Default."));
        ShellModePolicy.setBarPosition(value);
    }

    /** Glyphs of the first widgets of a layout list, from the registry. */
    function glyphsOf(list, count) {
        const out = [];
        for (const entry of (list ?? [])) {
            const info = BarComponentRegistry.getComponent(entry.id);
            if (info && info.icon)
                out.push(info.icon);
            if (out.length >= count)
                break;
        }
        return out;
    }

    ContentPage {
        id: page

        function openWidgetPage(componentId) {
            const compInfo = BarComponentRegistry.getComponent(componentId);
            if (!compInfo)
                return;
            if (typeof compInfo.pageId !== "undefined") {
                const win = barConfigRoot.QsWindow.window;
                if (win && win.pageIndexById !== undefined) {
                    if (compInfo.sectionTitle)
                        win.pendingSectionHighlight = Translation.tr(compInfo.sectionTitle);
                    win.currentPage = win.pageIndexById(compInfo.pageId);
                }
            } else if (compInfo.configPage) {
                barConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/" + compInfo.configPage);
            }
        }

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // ── Where it sits ─────────────────────────────────────────────────
        ContentSection {
            icon: "space_bar"
            title: Translation.tr("Bar basics & placement")

            Item {
                id: placement
                Layout.fillWidth: true

                readonly property bool wide: width >= barConfigRoot.wideBreak
                // Position beside the size on a wide page, above it on a narrow one; the
                // shell mode spans the row under both.
                readonly property real positionWidth: placement.wide ? Math.round((width - barConfigRoot.gap) * 0.55) : width
                readonly property real sideX: placement.wide ? placement.positionWidth + barConfigRoot.gap : 0
                readonly property real sideY: placement.wide ? 0 : positionCard.height + barConfigRoot.gap
                readonly property real topRowHeight: placement.wide ? Math.max(positionCard.height, dials.height) : placement.sideY + dials.height

                implicitHeight: placement.topRowHeight + barConfigRoot.gap + modeToggle.implicitHeight

                // Position: Edit Mode's chips, on a slab like the panel they come from.
                Rectangle {
                    id: positionCard
                    width: placement.positionWidth
                    height: placement.wide ? Math.max(positionChips.implicitHeight + 28, dials.height) : positionChips.implicitHeight + 28
                    radius: Appearance.rounding.verylarge
                    color: Appearance.colors.colLayer1

                    EditOptionChips {
                        id: positionChips
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 14
                        }
                        compact: false
                        enabled: !barConfigRoot.tablet
                        label: Translation.tr("Position")
                        currentValue: barConfigRoot.tablet ? 0 : (barConfigRoot.bar.bottom ? 1 : 0) | (barConfigRoot.bar.vertical ? 2 : 0)
                        options: {
                            const locked = ShellModePolicy.barPositionLocked || barConfigRoot.tablet;
                            return [
                                { "displayName": Translation.tr("Top"), "icon": "arrow_upward", "value": 0 },
                                { "displayName": Translation.tr("Left"), "icon": "arrow_back", "value": 2, "enabled": !locked },
                                { "displayName": Translation.tr("Bottom"), "icon": "arrow_downward", "value": 1, "enabled": !locked },
                                { "displayName": Translation.tr("Right"), "icon": "arrow_forward", "value": 3, "enabled": !locked }
                            ];
                        }
                        onSelected: value => barConfigRoot.setPosition(value)
                    }
                }

                Row {
                    id: dials
                    x: placement.sideX
                    y: placement.sideY
                    width: placement.width - placement.sideX
                    spacing: barConfigRoot.gap
                    readonly property int count: barConfigRoot.bar.vertical ? 2 : 1
                    readonly property real cell: (width - spacing * (count - 1)) / count
                    height: heightDial.implicitHeight

                    BarSizeDial {
                        id: heightDial
                        width: dials.cell
                        caption: Translation.tr("Bar height")
                        symbol: "height"
                        value: barConfigRoot.bar.sizes.height
                        from: 30
                        to: 50
                        onMoved: next => Config.options.bar.sizes.height = next
                    }
                    BarSizeDial {
                        visible: barConfigRoot.bar.vertical
                        width: dials.cell
                        caption: Translation.tr("Bar width")
                        symbol: "width"
                        value: barConfigRoot.bar.sizes.width
                        from: 30
                        to: 50
                        onMoved: next => Config.options.bar.sizes.width = next
                    }
                }

                BarModeToggle {
                    id: modeToggle
                    y: placement.topRowHeight + barConfigRoot.gap
                    width: placement.width
                    currentValue: Config.options.sidebar.sidebarStyle
                    options: [
                        {
                            "value": "default",
                            "label": Translation.tr("Default"),
                            "caption": Translation.tr("Bar, search and sidebars as separate panels"),
                            "icon": "view_sidebar",
                            "shape": MaterialShape.Shape.Cookie9Sided,
                            "enabled": ShellModePolicy.canSelectDefault
                        },
                        {
                            "value": "connect",
                            "label": Translation.tr("Connect"),
                            "caption": Translation.tr("Bar, search and sidebars join into one panel"),
                            "icon": "link",
                            "shape": MaterialShape.Shape.Clover4Leaf,
                            "enabled": ShellModePolicy.canSelectConnect
                        }
                    ]
                    onSelected: value => ShellModePolicy.setMode(value)
                }
            }

            // Why something above is locked, one line each.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: visibleChildren.length > 0 ? 4 : 0
                spacing: 4

                BarHint {
                    visible: barConfigRoot.autoSwitchNoticeMessage.length > 0
                    icon: "info"
                    text: barConfigRoot.autoSwitchNoticeMessage
                }
                BarHint {
                    visible: barConfigRoot.tablet
                    icon: "tablet_android"
                    text: Translation.tr("Tablet mode keeps the bar at the top.")
                }
                BarHint {
                    visible: !barConfigRoot.tablet && ShellModePolicy.barPositionLocked
                    icon: "lock"
                    text: Translation.tr("Top and Default only while the island sits in the bar centre.")
                    linkText: Translation.tr("Island")
                    targetPageId: "dynamicIsland"
                    targetSectionTitle: Translation.tr("Dynamic Island in Bar Center")
                }
                BarHint {
                    visible: ShellModePolicy.connectBlockedReasonKey.length > 0 && !ShellModePolicy.barPositionLocked
                    icon: "lock"
                    text: Translation.tr(ShellModePolicy.connectBlockedReasonKey)
                }
                BarHint {
                    visible: ShellModePolicy.defaultBlockedReasonKey.length > 0
                    icon: "lock"
                    text: Translation.tr(ShellModePolicy.defaultBlockedReasonKey)
                    linkText: Translation.tr("Island")
                    targetPageId: "dynamicIsland"
                    targetSectionTitle: Translation.tr("Floating Dynamic Island")
                }
            }
        }

        // ── Hiding ────────────────────────────────────────────────────────
        ContentSection {
            icon: "visibility_off"
            title: Translation.tr("Auto-hide")

            BarPair {
                id: pair1
                ConfigSwitch {
                    groupHorizontal: pair1.horizontal
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Automatically hide")
                    checked: barConfigRoot.bar.autoHide.enable
                    enabled: !barConfigRoot.autoHideLocked
                    onCheckedChanged: Config.options.bar.autoHide.enable = checked
                    StyledToolTip {
                        text: barConfigRoot.autoHideLocked
                            ? Translation.tr("Auto-hide is locked while the Dynamic Island is active on a horizontal bar; the island has its own auto-hide.")
                            : Translation.tr("Automatically hide the bar when not in use")
                    }
                }
                ConfigSwitch {
                    groupHorizontal: pair1.horizontal
                    buttonIcon: "keyboard"
                    text: Translation.tr("Reveal with Super key")
                    enabled: barConfigRoot.bar.autoHide.enable
                    checked: barConfigRoot.bar.autoHide.showWhenPressingSuper.enable
                    onCheckedChanged: Config.options.bar.autoHide.showWhenPressingSuper.enable = checked
                    StyledToolTip {
                        text: Translation.tr("Temporarily reveals the bar while holding the Super/Windows key")
                    }
                }
            }

            BarRevealPicker {
                Layout.fillWidth: true
                Layout.topMargin: 8
                visible: barConfigRoot.bar.autoHide.enable
                presets: barConfigRoot.revealPresets
                currentWidth: barConfigRoot.bar.autoHide.hoverRegionWidth
                currentDelay: barConfigRoot.bar.autoHide.hoverDelay
                onSelected: preset => {
                    Config.options.bar.autoHide.mode = preset.value;
                    Config.options.bar.autoHide.hoverRegionWidth = preset.width;
                    Config.options.bar.autoHide.hoverDelay = preset.delay;
                }
            }

            BarPair {
                id: pair2
                Layout.topMargin: 4
                visible: barConfigRoot.bar.autoHide.enable
                ConfigSpinBox {
                    groupHorizontal: pair2.horizontal
                    icon: "straighten"
                    text: Translation.tr("Trigger area (px)")
                    from: 2
                    to: 64
                    stepSize: 2
                    value: barConfigRoot.bar.autoHide.hoverRegionWidth
                    onValueChanged: Config.options.bar.autoHide.hoverRegionWidth = value
                    StyledToolTip {
                        text: Translation.tr("Width of the interactive edge zone that detects the pointer")
                    }
                }
                ConfigSpinBox {
                    groupHorizontal: pair2.horizontal
                    icon: "hourglass_top"
                    text: Translation.tr("Hold delay (ms)")
                    from: 0
                    to: 1000
                    stepSize: 50
                    value: barConfigRoot.bar.autoHide.hoverDelay
                    onValueChanged: Config.options.bar.autoHide.hoverDelay = value
                    StyledToolTip {
                        text: Translation.tr("Delay in milliseconds the pointer must stay on the edge before the bar reveals")
                    }
                }
            }

            BarHint {
                Layout.topMargin: 4
                visible: barConfigRoot.bar.autoHide.enable && ShellModePolicy.connectModeActive
                icon: "travel_explore"
                text: Translation.tr("Connect's drop search needs the bar on screen.")
            }
        }

        // ── Its look and its contents ─────────────────────────────────────
        ContentSection {
            icon: "palette"
            title: Translation.tr("Look & layout")

            Item {
                id: entries
                Layout.fillWidth: true
                readonly property bool row: width >= barConfigRoot.entryBreak
                readonly property real cardWidth: entries.row ? Math.floor((width - barConfigRoot.gap * 2) / 3) : width
                readonly property real cardHeight: entries.row ? barConfigRoot.entryHeight : barConfigRoot.entryCompactHeight
                implicitHeight: entries.row ? entries.cardHeight : entries.cardHeight * 3 + barConfigRoot.gap * 2

                // Appearance: the corner style as a big condensed word.
                BarEntryCard {
                    id: lookCard
                    x: 0
                    y: 0
                    width: entries.cardWidth
                    height: entries.cardHeight
                    compact: !entries.row
                    symbol: "palette"
                    shapeIdle: MaterialShape.Shape.Cookie9Sided
                    shapeHover: MaterialShape.Shape.Flower
                    title: Translation.tr("Appearance & style")
                    summary: (barConfigRoot.backgroundNames[barConfigRoot.bar.barBackgroundStyle] ?? "") + " · "
                        + (barConfigRoot.groupNames[barConfigRoot.bar.barGroupStyle] ?? "")
                    onClicked: barConfigRoot.openSubPage("BarAppearanceConfig.qml")

                    StyledText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        text: barConfigRoot.cornerNames[barConfigRoot.bar.cornerStyle] ?? ""
                        horizontalAlignment: lookCard.compact ? Text.AlignRight : Text.AlignLeft
                        font.family: Appearance.font.family.main
                        font.pixelSize: Math.round(Math.min(lookCard.compact ? 34 : 56, parent.height))
                        font.variableAxes: ({ "wght": 800, "wdth": 28, "ROND": 0 })
                        font.capitalization: Font.AllUppercase
                        color: Appearance.colors.colPrimary
                        elide: Text.ElideRight
                    }
                }

                // Layout: how many widgets, split by where they sit.
                BarEntryCard {
                    id: layoutCard
                    x: entries.row ? entries.cardWidth + barConfigRoot.gap : 0
                    y: entries.row ? 0 : entries.cardHeight + barConfigRoot.gap
                    width: entries.cardWidth
                    height: entries.cardHeight
                    compact: !entries.row
                    symbol: "view_stream"
                    shapeIdle: MaterialShape.Shape.Cookie7Sided
                    shapeHover: MaterialShape.Shape.Clover4Leaf
                    compactDisplayWidth: 56
                    title: Translation.tr("Widgets & layout")
                    summary: Translation.tr("Left, centre and right")
                    onClicked: barConfigRoot.openSubPage("BarLayoutConfig.qml")

                    Item {
                        anchors.fill: parent

                        StyledText {
                            id: countDigits
                            anchors.verticalCenter: parent.verticalCenter
                            x: layoutCard.compact ? parent.width - width : 0
                            text: barConfigRoot.barWidgetCount
                            font.family: Appearance.font.family.main
                            font.pixelSize: Math.round(Math.min(layoutCard.compact ? 38 : 60, parent.height))
                            font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                            color: Appearance.colors.colPrimary
                        }

                        // Three sections, each as wide as its share of the widgets.
                        Row {
                            id: split
                            visible: !layoutCard.compact
                            anchors.verticalCenter: parent.verticalCenter
                            x: countDigits.width + 14
                            width: parent.width - x
                            spacing: 3
                            readonly property var counts: [barConfigRoot.layouts.left?.length ?? 0, barConfigRoot.layouts.center?.length ?? 0, barConfigRoot.layouts.right?.length ?? 0]
                            readonly property var lists: [barConfigRoot.layouts.left, barConfigRoot.layouts.center, barConfigRoot.layouts.right]
                            readonly property int used: split.counts.filter(c => c > 0).length
                            readonly property int firstUsed: split.counts.findIndex(c => c > 0)
                            readonly property int lastUsed: 2 - [...split.counts].reverse().findIndex(c => c > 0)
                            readonly property real unit: (width - spacing * (split.used - 1) - split.used * 28) / Math.max(1, barConfigRoot.barWidgetCount)

                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    id: segment
                                    required property int index
                                    readonly property int count: split.counts[segment.index]
                                    visible: segment.count > 0
                                    width: segment.count > 0 ? 28 + split.unit * segment.count : -split.spacing
                                    height: 30
                                    topLeftRadius: segment.index === split.firstUsed ? height / 2 : Appearance.rounding.verysmall
                                    bottomLeftRadius: segment.index === split.firstUsed ? height / 2 : Appearance.rounding.verysmall
                                    topRightRadius: segment.index === split.lastUsed ? height / 2 : Appearance.rounding.verysmall
                                    bottomRightRadius: segment.index === split.lastUsed ? height / 2 : Appearance.rounding.verysmall
                                    color: segment.index === 1 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                                    clip: true

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Repeater {
                                            model: barConfigRoot.glyphsOf(split.lists[segment.index], Math.max(1, Math.floor((segment.width - 12) / 16)))
                                            delegate: MaterialSymbol {
                                                required property string modelData
                                                text: modelData
                                                iconSize: 14
                                                color: segment.index === 1 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Widget settings: the widgets that have options of their own.
                BarEntryCard {
                    id: widgetsCard
                    x: entries.row ? (entries.cardWidth + barConfigRoot.gap) * 2 : 0
                    y: entries.row ? 0 : (entries.cardHeight + barConfigRoot.gap) * 2
                    width: entries.cardWidth
                    height: entries.cardHeight
                    compact: !entries.row
                    symbol: "widgets"
                    shapeIdle: MaterialShape.Shape.Cookie6Sided
                    shapeHover: MaterialShape.Shape.SoftBurst
                    compactDisplayWidth: 84
                    title: Translation.tr("Widgets & Waffle")
                    summary: Translation.tr("Clock, weather, battery and more")
                    onClicked: barConfigRoot.openSubPage("BarWidgetsWaffleConfig.qml")

                    // Overlapping glyph discs, the first one primary.
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: widgetsCard.compact ? parent.width - width : 0
                        spacing: -8
                        Repeater {
                            model: widgetsCard.compact ? ["schedule", "partly_cloudy_day", "battery_full"]
                                : ["schedule", "partly_cloudy_day", "battery_full", "music_note", "grid_view"]
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                width: widgetsCard.compact ? 34 : 44
                                height: width
                                radius: width / 2
                                z: -index
                                color: index === 0 ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                border.width: 3
                                border.color: widgetsCard.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData
                                    iconSize: widgetsCard.compact ? 16 : 20
                                    fill: 1
                                    color: index === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Behaviour ─────────────────────────────────────────────────────
        ContentSection {
            icon: "tune"
            title: Translation.tr("Behavior & Interactions")

            BarPair {
                id: pair3
                ConfigSwitch {
                    groupHorizontal: pair3.horizontal
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Scroll actions")
                    checked: barConfigRoot.bar.enableVolumeScroll || barConfigRoot.bar.enableBrightnessScroll
                    configPage: Qt.resolvedUrl("widgets/BarScrollActionsConfig.qml")
                    property bool readyForToggle: false
                    Component.onCompleted: readyForToggle = true
                    onCheckedChanged: {
                        if (!readyForToggle)
                            return;
                        Config.options.bar.enableVolumeScroll = checked;
                        Config.options.bar.enableBrightnessScroll = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Scroll over the bar's ends to change volume and brightness")
                    }
                }
                ConfigSwitch {
                    groupHorizontal: pair3.horizontal
                    buttonIcon: "left_click"
                    text: Translation.tr("Click bar to open sidebars")
                    checked: barConfigRoot.bar.sidebarClickOpen
                    onCheckedChanged: Config.options.bar.sidebarClickOpen = checked
                    StyledToolTip {
                        text: Translation.tr("Left-clicking empty bar space toggles the left and right sidebars (Float, Hug and Rect styles)")
                    }
                }
            }

            BarPair {
                id: pair4
                ConfigSwitch {
                    groupHorizontal: pair4.horizontal
                    buttonIcon: "tooltip"
                    text: Translation.tr("Bar popups")
                    checked: barConfigRoot.bar.tooltips.enableTooltips
                    configPage: Qt.resolvedUrl("widgets/BarTooltipsConfig.qml")
                    property bool readyForToggle: false
                    Component.onCompleted: readyForToggle = true
                    onCheckedChanged: {
                        if (!readyForToggle || !Config.ready)
                            return;
                        Config.options.bar.tooltips.enableTooltips = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Small popups that open when hovering widgets on the bar")
                    }
                }
                ConfigSwitch {
                    groupHorizontal: pair4.horizontal
                    buttonIcon: "open_in_new"
                    text: Translation.tr("Floating popups")
                    checked: barConfigRoot.bar.tooltips.enablePopups
                    configPage: Qt.resolvedUrl("widgets/BarPopupsConfig.qml")
                    property bool readyForToggle: false
                    Component.onCompleted: readyForToggle = true
                    onCheckedChanged: {
                        if (!readyForToggle || !Config.ready)
                            return;
                        Config.options.bar.tooltips.enablePopups = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Cards that appear on their own: keyboard layout, display modes and others")
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Only show bar on single monitor")
                checked: barConfigRoot.bar.onlyShowOnSingleMonitor
                onCheckedChanged: {
                    Config.options.bar.onlyShowOnSingleMonitor = checked;
                    if (checked && Config.options.bar.singleMonitorName === "" && Quickshell.screens.length > 0)
                        Config.options.bar.singleMonitorName = Quickshell.screens[0].name;
                }
                StyledToolTip {
                    text: Translation.tr("Display the bar on only one chosen monitor instead of all monitors")
                }
            }

            MonitorPicker {
                visible: barConfigRoot.bar.onlyShowOnSingleMonitor
                Layout.topMargin: 4
                currentValue: barConfigRoot.bar.singleMonitorName
                onSelected: newValue => Config.options.bar.singleMonitorName = newValue
            }
        }
    }

    // ── Sub-page overlay (slides in from the right) ───────────────────────
    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
