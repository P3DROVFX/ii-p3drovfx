import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.windows

Item {
    id: windowsRoot
    anchors.fill: parent

    property alias contentY: pageRoot.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var appearance: Config.options.appearance
    readonly property var transparency: Config.options.appearance.transparency
    readonly property var anim: Config.options.appearance.appLaunchAnimation
    readonly property var switcher: Config.options.windowSwitcher
    readonly property string transparencyMode: !windowsRoot.transparency.enable ? "off"
        : windowsRoot.transparency.automatic ? "auto" : "custom"

    property bool animationEdited: false
    // What the preview marks: the value being adjusted below it.
    readonly property string lookHighlight: gapsInSlider.hovered || gapsInSlider.pressed ? "gapsIn"
        : gapsOutSlider.hovered || gapsOutSlider.pressed ? "gapsOut"
        : borderSlider.hovered || borderSlider.pressed || borderColours.hovered ? "border"
        : glassHover.hovered ? "glass" : ""

    // The animation settings are on screen: the previews keep playing them.
    readonly property bool animationsOnScreen: animationsSection.y < pageRoot.contentY + pageRoot.height
        && animationsSection.y + animationsSection.height > pageRoot.contentY + sticky.cardHeight
        && !subPageOverlay.isOpen

    readonly property var hyprlandEntries: HyprlandSettings.appLaunchEntries(windowsRoot.anim)
    readonly property bool animationUnsaved: Config.ready && HyprlandGui.ready
        && !HyprlandGui.animationsSaved(windowsRoot.hyprlandEntries)

    function applyAnimation(): void {
        windowsRoot.animationEdited = true;
        HyprlandSettings.updateAppLaunchAnimation(windowsRoot.anim);
    }

    Component.onCompleted: HyprlandGui.attach()
    Component.onDestruction: HyprlandGui.detach()

    ContentPage {
        id: pageRoot
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── The desktop, drawn with everything below ────────────────────────
        WindowsLookPreview {
            id: lookHero
            autoLoop: windowsRoot.animationsOnScreen && !sticky.wanted
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(Math.max(220, Math.min(340, width / 2.4)))
            highlight: windowsRoot.lookHighlight
        }


        // ── Frame ───────────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Window frame")
            icon: "select_window"

            ConfigSlider {
                id: gapsInSlider
                buttonIcon: "view_column"
                text: Translation.tr("Gaps between windows")
                from: 0
                to: 60
                stepSize: 1
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: `${Math.round(value)} px`
                tooltipContent: badgeText
                value: windowsRoot.appearance.gapsIn ?? 4
                onMoved: windowsRoot.appearance.gapsIn = Math.round(value)
            }

            ConfigSlider {
                id: gapsOutSlider
                buttonIcon: "fit_screen"
                text: Translation.tr("Gaps around the screen")
                from: 0
                to: 60
                stepSize: 1
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: `${Math.round(value)} px`
                tooltipContent: badgeText
                value: windowsRoot.appearance.gapsOut ?? 5
                onMoved: windowsRoot.appearance.gapsOut = Math.round(value)
            }

            // Borderless is the slider's zero; the width it had comes back past zero.
            ConfigSlider {
                id: borderSlider
                buttonIcon: "border_outer"
                text: Translation.tr("Border width")
                from: 0
                to: 20
                stepSize: 1
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: Math.round(value) === 0 ? Translation.tr("Borderless") : `${Math.round(value)} px`
                tooltipContent: badgeText
                value: windowsRoot.appearance.borderless ? 0 : (windowsRoot.appearance.borderWidth ?? 1)
                onMoved: {
                    const width = Math.round(value);
                    if (width <= 0) {
                        windowsRoot.appearance.borderless = true;
                        return;
                    }
                    windowsRoot.appearance.borderWidth = width;
                    windowsRoot.appearance.borderless = false;
                }
            }

            ContentSubsection {
                id: borderColours
                title: Translation.tr("Active border colour")
                icon: "border_color"
                Layout.fillWidth: true
                enabled: !windowsRoot.appearance.borderless
                opacity: enabled ? 1 : 0.5

                readonly property bool hovered: colourHover.hovered
                HoverHandler {
                    id: colourHover
                }

                ConfigSelectionArray {
                    currentValue: windowsRoot.appearance.borderColorType
                    onSelected: newValue => windowsRoot.appearance.borderColorType = newValue
                    options: [
                        { displayName: Translation.tr("Primary"), shape: "Circle", color: Appearance.colors.colPrimary, value: "primary" },
                        { displayName: Translation.tr("Secondary"), shape: "Circle", color: Appearance.colors.colSecondary, value: "secondary" },
                        { displayName: Translation.tr("Tertiary"), shape: "Circle", color: Appearance.colors.colTertiary, value: "tertiary" },
                        { displayName: Translation.tr("Primary Container"), shape: "Circle", color: Appearance.colors.colPrimaryContainer, value: "primaryContainer" },
                        { displayName: Translation.tr("Surface"), shape: "Circle", color: Appearance.colors.colOutlineVariant, value: "surface" }
                    ]
                }
            }
        }

        // ── Glass ───────────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Transparency & Blur")
            icon: "opacity"

            HoverHandler {
                id: glassHover
            }

            // The old "Enable" and "Automatic" switches, as one choice.
            ContentSubsection {
                title: Translation.tr("Shell panels")
                icon: "layers"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: windowsRoot.transparencyMode
                    onSelected: newValue => {
                        windowsRoot.transparency.enable = newValue !== "off";
                        if (newValue !== "off")
                            windowsRoot.transparency.automatic = newValue === "auto";
                    }
                    options: [
                        { displayName: Translation.tr("Solid"), icon: "rectangle", value: "off",
                          tooltip: Translation.tr("Opaque panels; blur has nothing to show through") },
                        { displayName: Translation.tr("Automatic"), icon: "auto_awesome", value: "auto",
                          tooltip: Translation.tr("Calculate transparency automatically based on wallpaper colors") },
                        { displayName: Translation.tr("Custom"), icon: "tune", value: "custom",
                          tooltip: Translation.tr("Your own levels") }
                    ]
                }
            }

            // Hyprland's own blur, for windows and shell surfaces alike.
            ContentSubsection {
                title: Translation.tr("Compositor blur")
                icon: "blur_on"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: windowsRoot.appearance.blur.mode ?? "live"
                    onSelected: newValue => windowsRoot.appearance.blur.mode = newValue
                    options: [
                        { displayName: Translation.tr("Live"), icon: "blur_on", value: "live",
                          tooltip: Translation.tr("Blur whatever is behind, windows included. The heaviest on the GPU: every animation behind a blurred surface blurs it again") },
                        { displayName: Translation.tr("Wallpaper only"), icon: "wallpaper", value: "xray",
                          tooltip: Translation.tr("Blur only the wallpaper, computed once and reused. Glass stays, animations stay smooth") },
                        { displayName: Translation.tr("Off"), icon: "blur_off", value: "off",
                          tooltip: Translation.tr("No compositor blur anywhere, for the lightest rendering") }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("App windows")
                icon: "select_window"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: windowsRoot.appearance.blur.opaqueWindows ?? false
                    onSelected: newValue => windowsRoot.appearance.blur.opaqueWindows = newValue
                    options: [
                        { displayName: Translation.tr("Per app"), icon: "opacity", value: false,
                          tooltip: Translation.tr("Each app keeps the opacity your window rules give it") },
                        { displayName: Translation.tr("Opaque"), icon: "rectangle", value: true,
                          tooltip: Translation.tr("Every window fully opaque, over any opacity rule. Nothing behind them is drawn or blurred") }
                    ]
                }
            }

            ConfigSlider {
                visible: windowsRoot.transparencyMode === "custom"
                buttonIcon: "blur_on"
                text: Translation.tr("Background transparency")
                value: windowsRoot.transparency.backgroundTransparency
                onMoved: windowsRoot.transparency.backgroundTransparency = Math.round(value * 100) / 100
            }

            ConfigSlider {
                visible: windowsRoot.transparencyMode === "custom"
                buttonIcon: "opacity"
                text: Translation.tr("Content transparency")
                value: windowsRoot.transparency.contentTransparency
                onMoved: windowsRoot.transparency.contentTransparency = Math.round(value * 100) / 100
            }

            ConfigSlider {
                buttonIcon: "lens_blur"
                text: Translation.tr("Blur Size")
                from: 0
                to: 50
                stepSize: 1
                snapMode: Slider.NoSnap
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: Math.round(value) === 0 ? Translation.tr("Off") : `${Math.round(value)} px`
                tooltipContent: badgeText
                value: windowsRoot.appearance.blurSize
                onMoved: windowsRoot.appearance.blurSize = Math.round(value)
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: windowsRoot.appearance.blurSize >= 30
                materialIcon: "battery_alert"
                text: Translation.tr("Heavy blur effects can significantly impact battery life and performance on weaker GPUs.")
            }

            // Hyprland's ignore_alpha: it decides *where* blur applies, so it sits
            // with the blur size rather than among the advanced options.
            ConfigSlider {
                id: blurThresholdSlider
                buttonIcon: "gradient"
                text: Translation.tr("Blur threshold")
                value: windowsRoot.appearance.ignoreAlpha
                from: 0
                to: 1
                stepSize: 0.001
                snapMode: Slider.NoSnap
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: Translation.tr("Above %1%").arg((value * 100).toFixed(1))
                tooltipContent: Translation.tr("Only parts more than %1% opaque are blurred").arg((value * 100).toFixed(1))
                onMoved: windowsRoot.appearance.ignoreAlpha = Math.round(value * 1000) / 1000
                StyledToolTip {
                    text: Translation.tr("Blur is applied only behind parts of the shell that are more opaque than this. Lower it to blur more transparent surfaces; raise it to keep blur off soft shadows and edges. Above a surface's own opacity, that surface is not blurred at all.")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: Math.round(blurThresholdSlider.value * 100) <= 30
                materialIcon: "info"
                text: Translation.tr("A low threshold also blurs shadows and soft edges, which can show as a frosted halo around panels and widgets.")
            }

            ConfigSwitch {
                buttonIcon: "web_asset"
                text: Translation.tr("Transparency in popups")
                enabled: windowsRoot.transparency.enable
                checked: windowsRoot.transparency.popups
                onCheckedChanged: windowsRoot.transparency.popups = checked
                StyledToolTip {
                    text: Translation.tr("Menus and tooltips of the shell follow the transparency too")
                }
            }

            // A page away, not a switch: the finer blur settings.
            RippleButton {
                id: advancedBlurRow
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: advancedRow.implicitHeight + 24
                buttonRadius: Appearance.rounding.large
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: windowsRoot.activeSubPage = Qt.resolvedUrl("widgets/WindowsBlurConfig.qml")

                contentItem: Item {
                    RowLayout {
                        id: advancedRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                            rightMargin: 14
                        }
                        spacing: 12

                        MaterialShapeWrappedMaterialSymbol {
                            text: "deblur"
                            iconSize: 20
                            padding: 7
                            shape: advancedBlurRow.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                            color: Appearance.colors.colPrimary
                            colSymbol: Appearance.colors.colOnPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Advanced blur")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("%1 passes · noise %2% · vibrancy %3%")
                                    .arg(windowsRoot.appearance.blur.passes)
                                    .arg(Math.round(windowsRoot.appearance.blur.noise * 100))
                                    .arg(Math.round(windowsRoot.appearance.blur.vibrancy * 100))
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                                opacity: 0.8
                                elide: Text.ElideRight
                            }
                        }
                        MaterialSymbol {
                            text: "chevron_right"
                            iconSize: 24
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }

        // ── Motion ──────────────────────────────────────────────────────────
        ContentSection {
            id: animationsSection
            Layout.topMargin: 12
            title: Translation.tr("Window Animations")
            icon: "animation"

            // Off, or which way windows arrive: the old switch and style choice as one.
            WindowsChoiceCards {
                currentValue: !(windowsRoot.anim.enable ?? true) ? "off" : (windowsRoot.anim.style ?? "scale")
                onSelected: value => {
                    windowsRoot.anim.enable = value !== "off";
                    if (value !== "off")
                        windowsRoot.anim.style = value;
                    windowsRoot.applyAnimation();
                }
                options: [
                    { value: "off", title: Translation.tr("Off"), icon: "block", shape: MaterialShape.Shape.Square,
                      summary: Translation.tr("Windows appear at once") },
                    { value: "scale", title: Translation.tr("Scale"), icon: "zoom_in_map", shape: MaterialShape.Shape.Cookie9Sided,
                      summary: Translation.tr("Grow from %1% of their size").arg(windowsRoot.anim.startPercent ?? 20) },
                    { value: "slide", title: Translation.tr("Slide"), icon: "swipe_right", shape: MaterialShape.Shape.Cookie7Sided,
                      summary: Translation.tr("Glide in from a screen edge") }
                ]
            }

            ContentSubsection {
                title: Translation.tr("Slide direction")
                icon: "swipe"
                Layout.fillWidth: true
                visible: (windowsRoot.anim.style ?? "scale") === "slide"
                enabled: windowsRoot.anim.enable ?? true

                ConfigSelectionArray {
                    currentValue: windowsRoot.anim.slideDirection ?? "auto"
                    onSelected: newValue => {
                        windowsRoot.anim.slideDirection = newValue;
                        windowsRoot.applyAnimation();
                    }
                    options: [
                        { displayName: Translation.tr("Nearest edge"), icon: "near_me", value: "auto" },
                        { displayName: Translation.tr("Bottom"), icon: "south", value: "bottom" },
                        { displayName: Translation.tr("Top"), icon: "north", value: "top" },
                        { displayName: Translation.tr("Left"), icon: "west", value: "left" },
                        { displayName: Translation.tr("Right"), icon: "east", value: "right" }
                    ]
                }
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Opening initial scale")
                visible: (windowsRoot.anim.style ?? "scale") !== "slide"
                enabled: windowsRoot.anim.enable ?? true
                from: 5
                to: 90
                stepSize: 5
                snapMode: Slider.SnapAlways
                stopIndicatorValues: [5, 20, 40, 60, 80, 90]
                value: windowsRoot.anim.startPercent ?? 20
                onMoved: {
                    windowsRoot.anim.startPercent = Math.round(value);
                    windowsRoot.applyAnimation();
                }
            }

            ConfigSlider {
                buttonIcon: "timer"
                text: Translation.tr("Animation duration")
                enabled: windowsRoot.anim.enable ?? true
                from: 1.0
                to: 8.0
                stepSize: 0.2
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: `${Math.round(value * 100)} ms`
                tooltipContent: badgeText
                value: windowsRoot.anim.speed ?? 4.0
                onMoved: {
                    windowsRoot.anim.speed = Math.round(value * 10) / 10;
                    windowsRoot.applyAnimation();
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: windowsRoot.animationEdited && Config.ready && HyprlandGui.ready
                materialIcon: HyprlandGui.lastError !== "" ? "error" : "info"
                text: HyprlandGui.lastError !== "" ? HyprlandGui.lastError
                    : windowsRoot.animationUnsaved
                        ? Translation.tr("Animation preview active. Save animations to Hyprland to keep them after reloads and restarts.")
                        : Translation.tr("Animations saved to Hyprland.")
            }
        }

        // ── Alt+Tab, with its own preview ───────────────────────────────────
        WindowsSwitcherPreview {
            id: switcherHero
            Layout.topMargin: 24
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(Math.max(260, Math.min(400, width / 2.2)))
        }

        ContentSection {
            title: Translation.tr("Window switcher")
            icon: "tab"

            KeyboardShortcutBox {
                Layout.fillWidth: true
                text: Translation.tr("Hold Alt and press Tab to cycle windows; release Alt to switch. Type to search - releasing Alt then keeps the search open until Enter. Alt+1…9 picks a window, Home/End the first or last, Delete closes the selected one")
                keys: ["Alt", "Tab"]
            }

            KeyboardShortcutBox {
                Layout.fillWidth: true
                visible: !WindowSwitcher.sameAppConflict
                text: Translation.tr("The same, through the windows of the app you are in only")
                keys: ["Alt", "`"]
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "keyboard_off"
                text: Translation.tr("Alt+Tab is already bound in your Hyprland config, so the switcher stays off. Remove that bind to use it.")
                visible: windowsRoot.switcher.enable && WindowSwitcher.conflict
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "keyboard"
                text: Translation.tr("The key above Tab already has an Alt bind in your Hyprland config, so switching between one app's windows is left off.")
                visible: windowsRoot.switcher.enable && !WindowSwitcher.conflict && WindowSwitcher.sameAppConflict
            }

            ConfigSwitch {
                buttonIcon: "tab"
                text: Translation.tr("Enable Alt+Tab window switcher")
                checked: windowsRoot.switcher.enable
                onCheckedChanged: windowsRoot.switcher.enable = checked
                StyledToolTip {
                    text: Translation.tr("With the Dynamic Island on, the island becomes the switcher; otherwise a panel opens on the focused monitor")
                }
            }

            // The same choice as the Dynamic Island page's switch, so every switcher setting is here.
            WindowsChoiceCards {
                enabled: windowsRoot.switcher.enable
                opacity: enabled ? 1 : 0.5
                currentValue: !Config.options.bar.floatingNotch.disableWindowSwitcher
                onSelected: value => Config.options.bar.floatingNotch.disableWindowSwitcher = !value
                options: [
                    { value: true, title: Translation.tr("Island cover flow"), icon: "view_carousel", shape: MaterialShape.Shape.Pill,
                      summary: Translation.tr("The Dynamic Island grows into live window previews") },
                    { value: false, title: Translation.tr("Floating panel"), icon: "grid_view", shape: MaterialShape.Shape.Cookie4Sided,
                      summary: Translation.tr("A grid of windows in the middle of the focused monitor") }
                ]
            }

            // What it lists and shows, as tiles: 4, 2 or 1 per row, never 3 + 1.
            Item {
                id: switcherTiles
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: switcherFlow.implicitHeight
                enabled: windowsRoot.switcher.enable
                opacity: enabled ? 1 : 0.5

                readonly property int gap: 8
                readonly property int fits: Math.max(1, Math.floor((width + gap) / (220 + gap)))
                readonly property int columns: fits >= 4 ? 4 : fits >= 2 ? 2 : 1
                readonly property int tileWidth: Math.floor((width - gap * (columns - 1)) / columns)
                readonly property int tileHeight: 150

                Flow {
                    id: switcherFlow
                    width: parent.width
                    spacing: switcherTiles.gap

                    ColorsFeatureTile {
                        width: switcherTiles.tileWidth
                        height: switcherTiles.tileHeight
                        symbol: "workspaces"
                        shapeOn: MaterialShape.Shape.Cookie12Sided
                        title: Translation.tr("Every workspace")
                        summary: windowsRoot.switcher.includeOtherWorkspaces ? Translation.tr("Windows from all workspaces, special ones too")
                            : Translation.tr("Only this workspace and a special one over it")
                        checked: windowsRoot.switcher.includeOtherWorkspaces
                        onToggled: value => windowsRoot.switcher.includeOtherWorkspaces = value
                    }
                    ColorsFeatureTile {
                        width: switcherTiles.tileWidth
                        height: switcherTiles.tileHeight
                        symbol: "monitor"
                        shapeOn: MaterialShape.Shape.Square
                        title: Translation.tr("This monitor only")
                        summary: windowsRoot.switcher.currentMonitorOnly ? Translation.tr("Windows of other monitors are left out")
                            : Translation.tr("Windows of every monitor")
                        checked: windowsRoot.switcher.currentMonitorOnly
                        onToggled: value => windowsRoot.switcher.currentMonitorOnly = value
                    }
                    ColorsFeatureTile {
                        width: switcherTiles.tileWidth
                        height: switcherTiles.tileHeight
                        symbol: "photo_library"
                        shapeOn: MaterialShape.Shape.Flower
                        title: Translation.tr("Live previews")
                        summary: windowsRoot.switcher.showThumbnails ? Translation.tr("Each window as it looks right now")
                            : Translation.tr("App icons instead of pictures")
                        checked: windowsRoot.switcher.showThumbnails
                        onToggled: value => windowsRoot.switcher.showThumbnails = value
                    }
                    ColorsFeatureTile {
                        width: switcherTiles.tileWidth
                        height: switcherTiles.tileHeight
                        symbol: "keyboard"
                        shapeOn: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("Key hints")
                        summary: Translation.tr("A short line under the switcher with the keys it takes")
                        checked: windowsRoot.switcher.showKeyHints
                        onToggled: value => windowsRoot.switcher.showKeyHints = value
                    }
                }
            }

            // Peeking: the delay's zero is off.
            ConfigSlider {
                buttonIcon: "visibility"
                text: Translation.tr("Peek after holding")
                enabled: windowsRoot.switcher.enable
                from: 0
                to: 3000
                stepSize: 100
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: Math.round(value) === 0 ? Translation.tr("Off") : `${Math.round(value)} ms`
                tooltipContent: badgeText
                value: windowsRoot.switcher.peekDelayMs
                onMoved: windowsRoot.switcher.peekDelayMs = Math.round(value / 100) * 100
            }

            ConfigSwitch {
                buttonIcon: "select_window"
                text: Translation.tr("Peek at the whole workspace")
                enabled: windowsRoot.switcher.enable && windowsRoot.switcher.peekDelayMs > 0
                checked: windowsRoot.switcher.peekWholeWorkspace
                onCheckedChanged: windowsRoot.switcher.peekWholeWorkspace = checked
                StyledToolTip {
                    text: Translation.tr("The peek shows the window with the rest of its workspace around it - its other windows, and the bar kept on screen. Off: the window alone over the wallpaper")
                }
            }

            ConfigSwitch {
                buttonIcon: "search"
                text: Translation.tr("Search windows with Alt+letter anywhere")
                enabled: windowsRoot.switcher.enable
                checked: windowsRoot.switcher.searchAnywhere
                onCheckedChanged: windowsRoot.switcher.searchAnywhere = checked
                StyledToolTip {
                    text: Translation.tr("Off: type while holding Alt after Alt+Tab to filter the windows. On: Alt+letter from anywhere opens the switcher already searching, which takes Alt+letter shortcuts away from apps")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "keyboard"
                text: Translation.tr("Alt+%1 already have binds in your Hyprland config and are left to them.")
                    .arg(WindowSwitcher.searchConflicts.map(key => key.toUpperCase()).join(", "))
                visible: windowsRoot.switcher.enable && windowsRoot.switcher.searchAnywhere
                    && WindowSwitcher.searchConflicts.length > 0
            }
        }

        ContentSection {
            Layout.topMargin: 12
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

                // The tiling engine (dwindle, master, scrolling…) is Hyprland's general:layout.
                RelatedChip {
                    pageId: "hyprland"
                    label: Translation.tr("Tiling engine")
                    sectionHighlight: Translation.tr("Tiling engine")
                }
                RelatedChip {
                    pageId: "wallpaper"
                    label: Translation.tr("Wallpaper blur")
                }
                RelatedChip {
                    pageId: "lockScreen"
                    label: Translation.tr("Lock screen blur")
                    sectionHighlight: Translation.tr("Blur style")
                }
            }
        }
    }

    FloatingActionButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 25
        z: 10
        opacity: windowsRoot.animationEdited && !subPageOverlay.isOpen ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        iconText: HyprlandGui.busy ? "hourglass_top" : windowsRoot.animationUnsaved ? "save" : "check"
        buttonText: Translation.tr("Save animations to Hyprland")
        expanded: windowsRoot.animationUnsaved || HyprlandGui.busy
        enabled: Config.ready && HyprlandGui.ready && !HyprlandGui.busy
        colBackground: windowsRoot.animationUnsaved ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
        colBackgroundHover: windowsRoot.animationUnsaved ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainerHover
        colBackgroundActive: windowsRoot.animationUnsaved ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimaryContainerActive
        colOnBackground: windowsRoot.animationUnsaved ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
        onClicked: HyprlandGui.saveAnimations(windowsRoot.hyprlandEntries)

        StyledToolTip {
            text: Translation.tr("Save only window animations to ~/.config/hypr/custom/general.lua. A backup is created before writing.")
        }
    }

    // A small copy of the hero stays on top while the sliders it shows are scrolled to,
    // and leaves once the window switcher (which has its own preview) comes up.
    Item {
        id: sticky

        readonly property int cardHeight: 150
        readonly property bool wanted: pageRoot.contentY > lookHero.y + lookHero.height - sticky.cardHeight * 0.5
            && pageRoot.contentY + sticky.cardHeight + 24 < switcherHero.y
            && !subPageOverlay.isOpen

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: sticky.cardHeight + 12
        z: 5
        opacity: sticky.wanted ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // The page behind it, so rows scrolling under do not show through.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
        }
        // Clicks and hover stop here instead of reaching the rows under it; the wheel still scrolls.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = false
        }

        Loader {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: sticky.cardHeight
            active: sticky.visible
            y: sticky.wanted ? 0 : -16
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            sourceComponent: WindowsLookPreview {
                compact: true
                autoLoop: windowsRoot.animationsOnScreen
                highlight: windowsRoot.lookHighlight
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
