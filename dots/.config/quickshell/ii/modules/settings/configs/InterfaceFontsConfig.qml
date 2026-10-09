pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.interface
import qs.modules.settings.configs.windows
import qs.services

/**
 * Settings → Interface & Fonts.
 *
 * Every control says what it changes by showing it: the shell families as cards, the
 * corner radius and animation timing as sliders over a stage drawn with their own value
 * (shapes that round, a dot that crosses the track on the real curve), the settings
 * memory as a stepped timeline, and the switches as tiles whose footer samples the
 * effect (letterforms that round, a scrollbar that takes colour). Search indexes
 * sections/InterfaceFontsOptionsSection.qml for everything drawn here.
 */
Item {
    id: interfaceFontsRoot

    readonly property real sliderMin: 360
    readonly property real tileMin: 300
    readonly property real tileHeight: 208
    readonly property real choiceHeight: 132
    readonly property real choiceGap: 8
    readonly property real defaultRadius: 24
    readonly property real radiusMax: 48
    readonly property real timingDefault: 1.0
    readonly property real timingEpsilon: 0.05
    readonly property var appearance: Config.options.appearance
    readonly property var familyShapes: ({
        "ii": MaterialShape.Shape.Cookie12Sided,
        "tablet": MaterialShape.Shape.Clover4Leaf,
        "waffle": MaterialShape.Shape.Flower
    })
    readonly property var unloadDelays: [
        { seconds: 0, label: Translation.tr("Instantly") },
        { seconds: 60, label: Translation.tr("1 min") },
        { seconds: 300, label: Translation.tr("5 min") },
        { seconds: 900, label: Translation.tr("15 min") },
        { seconds: -1, label: Translation.tr("Never") }
    ]

    readonly property real radiusValue: interfaceFontsRoot.appearance.roundingValue >= 0 ? interfaceFontsRoot.appearance.roundingValue : interfaceFontsRoot.defaultRadius
    readonly property real timing: interfaceFontsRoot.appearance.animationMultiplier ?? interfaceFontsRoot.timingDefault
    readonly property string timingWord: interfaceFontsRoot.timing < interfaceFontsRoot.timingDefault - interfaceFontsRoot.timingEpsilon ? Translation.tr("Faster")
        : interfaceFontsRoot.timing > interfaceFontsRoot.timingDefault + interfaceFontsRoot.timingEpsilon ? Translation.tr("Slower") : Translation.tr("Default")
    readonly property int unloadIndex: Math.max(0, interfaceFontsRoot.unloadDelays.findIndex(entry => entry.seconds === interfaceFontsRoot.appearance.settingsUnloadDelay))

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function openSubPage(file) {
        interfaceFontsRoot.activeSubPage = Qt.resolvedUrl("widgets/" + file);
    }

    function setCustomFonts(enabled) {
        const fonts = interfaceFontsRoot.appearance.fonts;
        fonts.enableCustom = enabled;
        if (enabled) {
            const saved = Persistent.states.settings.fonts;
            fonts.main = saved.main;
            fonts.numbers = saved.numbers;
            fonts.title = saved.title;
            fonts.monospace = saved.monospace;
            fonts.iconNerd = saved.iconNerd;
            fonts.reading = saved.reading;
            fonts.expressive = saved.expressive;
        } else {
            fonts.main = "Google Sans Flex";
            fonts.numbers = "Google Sans Flex";
            fonts.title = "Google Sans Flex";
            fonts.iconNerd = "JetBrainsMono Nerd Font";
            fonts.monospace = "JetBrainsMono Nerd Font";
            fonts.reading = "Readex Pro";
            fonts.expressive = "Space Grotesk";
        }
    }

    function setFontRoundness(enabled) {
        interfaceFontsRoot.appearance.fonts.roundnessFull = enabled;
        Persistent.states.settings.fonts.roundnessFull = enabled;
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Which shell you get ───────────────────────────────────────────
        // A preference, not a mode: it takes one tap and it is the first thing on the page
        // about how the interface looks. Without it a desktop user had no path to the
        // other two families at all (a keybind, IPC, a touch gesture or the tablet bubble).
        ContentSection {
            title: Translation.tr("Shell family")
            icon: "space_dashboard"

            WindowsChoiceCards {
                cardHeight: interfaceFontsRoot.choiceHeight
                minCardWidth: 160
                currentValue: PanelFamily.current
                options: PanelFamily.available.map(family => ({
                    value: family.id,
                    title: Translation.tr(family.name),
                    summary: Translation.tr(family.summary),
                    icon: family.icon,
                    shape: interfaceFontsRoot.familyShapes[family.id] ?? MaterialShape.Shape.Cookie9Sided
                }))
                onSelected: value => PanelFamily.select(value)
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: interfaceFontsRoot.choiceGap
                Layout.leftMargin: interfaceFontsRoot.choiceGap
                Layout.rightMargin: interfaceFontsRoot.choiceGap
                text: Translation.tr(PanelFamily.entry(PanelFamily.current)?.description ?? "")
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            NoticeBox {
                Layout.fillWidth: true
                Layout.topMargin: interfaceFontsRoot.choiceGap
                materialIcon: "info"
                text: Translation.tr("Switching rebuilds every surface, so the screen goes briefly blank. Your settings are kept — each family simply draws a different set of them.")
            }
        }

        // ── Motion & shape ────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Motion & Shape")
            icon: "motion_photos_on"

            InterfaceGrid {
                id: sliderGrid
                belowNotice: false
                minCell: interfaceFontsRoot.sliderMin
                maxColumns: 2

                InterfaceSliderCard {
                    width: sliderGrid.cellWidth
                    symbol: "rounded_corner"
                    title: Translation.tr("Corner radius")
                    hint: Translation.tr("How round every card, button and window is")
                    valueText: Math.round(interfaceFontsRoot.radiusValue) + " px"
                    markers: [Translation.tr("Sharp"), Translation.tr("Round")]
                    from: 0
                    to: interfaceFontsRoot.radiusMax
                    stepSize: 1
                    stopIndicatorValues: [interfaceFontsRoot.defaultRadius]
                    value: interfaceFontsRoot.radiusValue
                    onMoved: next => {
                        interfaceFontsRoot.appearance.roundingValue = next;
                        interfaceFontsRoot.appearance.sharpMode = (next === 0);
                    }

                    InterfaceRadiusSample {
                        radiusValue: interfaceFontsRoot.radiusValue
                    }
                }

                InterfaceSliderCard {
                    id: timingCard
                    width: sliderGrid.cellWidth
                    symbol: "speed"
                    title: Translation.tr("Animation timing")
                    hint: interfaceFontsRoot.timingWord + " · " + Translation.tr("Multiplies how long every animation takes")
                    valueText: interfaceFontsRoot.timing.toFixed(2) + "x"
                    markers: [Translation.tr("Faster"), Translation.tr("Slower")]
                    from: 0.25
                    to: 2.5
                    stepSize: 0.05
                    stopIndicatorValues: [interfaceFontsRoot.timingDefault]
                    value: interfaceFontsRoot.timing
                    onMoved: next => interfaceFontsRoot.appearance.animationMultiplier = next

                    InterfaceMotionSample {
                        active: timingCard.hovered
                    }
                }
            }

            InterfaceSliderCard {
                Layout.fillWidth: true
                Layout.topMargin: 8
                symbol: "timer"
                shapeIdle: MaterialShape.Shape.Clover4Leaf
                shapeEngaged: MaterialShape.Shape.Flower
                title: Translation.tr("Free Settings memory after closing")
                hint: Translation.tr("Until its memory is freed, Settings reopens instantly on the page you left. Freeing it sooner uses less RAM.")
                valueText: interfaceFontsRoot.unloadDelays[interfaceFontsRoot.unloadIndex].label
                markers: interfaceFontsRoot.unloadDelays.map(entry => entry.label)
                from: 0
                to: interfaceFontsRoot.unloadDelays.length - 1
                stepSize: 1
                stopIndicatorValues: [0, 1, 2, 3, 4]
                value: interfaceFontsRoot.unloadIndex
                onMoved: next => interfaceFontsRoot.appearance.settingsUnloadDelay = interfaceFontsRoot.unloadDelays[Math.round(next)].seconds
            }

            InterfaceGrid {
                id: switchGrid
                minCell: interfaceFontsRoot.sliderMin
                maxColumns: 2

                ColorsFeatureTile {
                    width: switchGrid.cellWidth
                    height: interfaceFontsRoot.tileHeight
                    symbol: "speed"
                    shapeOn: MaterialShape.Shape.Cookie7Sided
                    title: Translation.tr("Reduce settings animations")
                    summary: checked
                        ? Translation.tr("Settings opens without animations, expensive effects or scroll bounce")
                        : Translation.tr("Settings is animated, with the scroll bounce at both ends")
                    checked: interfaceFontsRoot.appearance.settingsPerformanceMode
                    onToggled: value => interfaceFontsRoot.appearance.settingsPerformanceMode = value
                }

                ColorsFeatureTile {
                    id: scrollbarTile
                    width: switchGrid.cellWidth
                    height: interfaceFontsRoot.tileHeight
                    symbol: "colors"
                    shapeOn: MaterialShape.Shape.SoftBurst
                    title: Translation.tr("Colorful scrollbar")
                    summary: checked
                        ? Translation.tr("Scrollbars and slider tracks borrow the primary colours")
                        : Translation.tr("Scrollbars and slider tracks stay neutral")
                    checked: interfaceFontsRoot.appearance.colorfulScrollbar
                    onToggled: value => interfaceFontsRoot.appearance.colorfulScrollbar = value

                    InterfaceScrollbarSample {
                        colorful: scrollbarTile.checked
                    }
                }
            }
        }

        // ── Icons & fonts ─────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Icons & Fonts")
            icon: "text_format"

            InterfaceIconsCard {
                symbol: "magic_button"
                shapeOn: MaterialShape.Shape.Cookie12Sided
                title: Translation.tr("Themed icons")
                summary: checked
                    ? Translation.tr("The Matugen icon pack, recoloured with your theme (experimental)")
                    : Translation.tr("Your own icon theme, untouched (experimental option)")
                checked: interfaceFontsRoot.appearance.icons.enableThemed
                onConfigureRequested: interfaceFontsRoot.openSubPage("ThemedIconsConfig.qml")
                onToggled: value => interfaceFontsRoot.appearance.icons.enableThemed = value
            }

            InterfaceGrid {
                id: iconGrid
                minCell: interfaceFontsRoot.tileMin
                maxColumns: 2

                ColorsFeatureTile {
                    width: iconGrid.cellWidth
                    height: interfaceFontsRoot.tileHeight
                    symbol: "custom_typography"
                    shapeOn: MaterialShape.Shape.Flower
                    title: Translation.tr("Custom fonts")
                    summary: checked
                        ? Translation.tr("Your own families, set one role at a time")
                        : Translation.tr("Google Sans Flex, Readex Pro and the other defaults")
                    checked: interfaceFontsRoot.appearance.fonts.enableCustom
                    configurable: true
                    onConfigureRequested: interfaceFontsRoot.openSubPage("CustomFontsConfig.qml")
                    onToggled: value => interfaceFontsRoot.setCustomFonts(value)
                }

                ColorsFeatureTile {
                    id: roundnessTile
                    width: iconGrid.cellWidth
                    height: interfaceFontsRoot.tileHeight
                    symbol: "rounded_corner"
                    shapeOn: MaterialShape.Shape.Clover4Leaf
                    title: Translation.tr("Full font roundness")
                    summary: checked
                        ? Translation.tr("Letterforms fully rounded (ROND 100)")
                        : Translation.tr("Letterforms in their regular shape")
                    checked: interfaceFontsRoot.appearance.fonts.roundnessFull
                    onToggled: value => interfaceFontsRoot.setFontRoundness(value)

                    InterfaceFontSample {
                        rounded: roundnessTile.checked
                        color: roundnessTile.colContent
                    }
                }
            }
        }
    }

    // Sub-page overlay
    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
