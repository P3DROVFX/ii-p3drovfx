pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.bar
import qs.services

/**
 * Settings → Bar → Appearance & style.
 *
 * The bar itself, live and pinned to the top (BarPreviewStage: its real style file, widgets
 * and wallpaper), over the choices that change it: corner style, grouping, background and
 * screen corners as expressive cards (BarChoiceCards — pointing at a corner style tries it
 * on the bar above), the colour themes as swatches from the bar's theme table, and the
 * brand icon as a grid under a big badge. Plain switches stay the original ones.
 * Search indexes sections/BarAppearanceSection.qml for the pickers.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property real gap: 12
    readonly property var bar: Config.options.bar
    readonly property bool centredIsland: ShellModePolicy.centerInBarActive

    readonly property var cornerNames: [Translation.tr("Hug"), Translation.tr("Float"), Translation.tr("Rect"), Translation.tr("Dynamic Island")]
    readonly property var backgroundNames: [Translation.tr("Transparent"), Translation.tr("Visible"), Translation.tr("Adaptive"), Translation.tr("Islands")]
    readonly property var groupNames: [Translation.tr("Pills"), Translation.tr("Island"), Translation.tr("Transparent")]
    readonly property var roundingNames: [Translation.tr("No"), Translation.tr("Yes"), Translation.tr("Windowed"), Translation.tr("Wrapped"), Translation.tr("Edge")]

    // What the pointer is trying on the preview, named; "" when nothing differs from the saved look.
    readonly property string tryingName: {
        const pick = (tried, saved, names) => tried !== null && tried !== undefined && tried !== saved ? names[tried] : "";
        return pick(shapePicker.tried, root.bar.cornerStyle, root.cornerNames)
            || pick(groupPicker.tried, root.bar.barGroupStyle, root.groupNames)
            || pick(backdropPicker.tried, root.bar.barBackgroundStyle, root.backgroundNames)
            || pick(roundingPicker.tried, Config.options.appearance.fakeScreenRounding, root.roundingNames);
    }

    readonly property var cornerOptions: {
        const islandsBackground = root.bar.barBackgroundStyle === 3;
        const opts = [
            { "value": 0, "label": Translation.tr("Hug"), "description": Translation.tr("Edge to edge, the screen curving into it"), "icon": "line_curve", "shape": MaterialShape.Shape.Cookie9Sided },
            { "value": 1, "label": Translation.tr("Float"), "description": Translation.tr("A rounded bar off the edge"), "icon": "page_header", "shape": MaterialShape.Shape.Clover4Leaf, "enabled": !ShellModePolicy.wrappedFrameActive },
            { "value": 2, "label": Translation.tr("Rect"), "description": Translation.tr("Square corners, off the edge"), "icon": "toolbar", "shape": MaterialShape.Shape.Cookie4Sided, "enabled": !islandsBackground },
            { "value": 3, "label": Translation.tr("Island"), "description": Translation.tr("A pill hanging from the centre"), "icon": "water_drop", "shape": MaterialShape.Shape.SoftBurst, "enabled": !islandsBackground }
        ];
        // Which styles the centred island fits in is ShellModePolicy's to state.
        if (root.centredIsland) {
            const centred = ShellModePolicy.centerInBarStyles;
            opts[1].enabled = opts[1].enabled !== false && centred.indexOf(1) !== -1;
            opts[2].enabled = opts[2].enabled !== false && centred.indexOf(2) !== -1;
        }
        // The tablet family renders no dynamic island at all.
        return PanelFamily.isTablet ? opts.slice(0, 3) : opts;
    }

    function setCornerStyle(value) {
        if (value === 3 && !root.bar.vertical && Config.options.sidebar.sidebarStyle === "connect")
            Config.options.sidebar.sidebarStyle = "default";
        Config.options.bar.cornerStyle = value;
    }

    function setBackgroundStyle(value) {
        Config.options.bar.barBackgroundStyle = value;
        if (value === 3 && (root.bar.cornerStyle === 2 || root.bar.cornerStyle === 3))
            Config.options.bar.cornerStyle = 0;
        if (value === 3) {
            const centerList = root.bar.layouts.center;
            if (centerList.some(item => item.centered))
                Config.options.bar.layouts.center = centerList.map(item => ({
                    "id": item.id,
                    "centered": false,
                    "visible": item.visible
                }));
        }
    }

    // ── Back button and title (only when opened as a sub-page) ────────────
    RowLayout {
        id: header
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: root.showBackButton ? implicitHeight : 0
        visible: root.showBackButton
        spacing: Appearance.sizes.elevationMargin
        z: 5
        RippleButton {
            implicitWidth: Appearance.sizes.elevationMargin * 4
            implicitHeight: implicitWidth
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()
            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
        StyledText {
            text: Translation.tr("Bar appearance")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── The bar, live and pinned ──────────────────────────────────────────
    Item {
        id: hero
        anchors {
            top: header.bottom
            topMargin: root.showBackButton ? root.gap : 0
            left: parent.left
            right: parent.right
        }
        height: stage.preferredHeight + caption.height + 10
        z: 5

        BarPreviewStage {
            id: stage
            width: parent.width
            height: stage.preferredHeight
            styleOverride: shapePicker.tried ?? -1
            groupOverride: groupPicker.tried ?? -1
            backgroundOverride: backdropPicker.tried ?? -1
            roundingOverride: roundingPicker.tried ?? -1
        }

        // What the bar above is wearing, or what is being tried on it.
        RowLayout {
            id: caption
            anchors {
                left: parent.left
                right: parent.right
                top: stage.bottom
                topMargin: 10
                leftMargin: 6
                rightMargin: 6
            }
            height: 22
            spacing: 8

            Rectangle {
                implicitWidth: 7
                implicitHeight: 7
                radius: 3.5
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                text: root.tryingName.length > 0
                    ? Translation.tr("Trying %1").arg(root.tryingName)
                    : [root.cornerNames[root.bar.cornerStyle], root.backgroundNames[root.bar.barBackgroundStyle], root.groupNames[root.bar.barGroupStyle]].join(" · ")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.tryingName.length > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
            StyledText {
                visible: root.bar.vertical
                text: Translation.tr("Shown horizontally")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    ContentPage {
        id: page
        anchors.fill: undefined
        anchors {
            top: hero.bottom
            topMargin: root.gap
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        forceWidth: false

        // ── Shape ─────────────────────────────────────────────────────────
        ContentSection {
            icon: "rounded_corner"
            title: Translation.tr("Corner & Group Style")

            BarChoiceCards {
                id: shapePicker
                Layout.fillWidth: true
                options: root.cornerOptions
                currentValue: root.bar.cornerStyle
                onSelected: value => root.setCornerStyle(value)
            }

            BarHint {
                Layout.topMargin: 4
                visible: root.bar.barBackgroundStyle === 3
                icon: "lock"
                text: Translation.tr("Rect and Island need a background other than Islands.")
            }
            BarHint {
                Layout.topMargin: 4
                visible: ShellModePolicy.floatStyleBlockedReasonKey.length > 0
                icon: "lock"
                text: Translation.tr(ShellModePolicy.floatStyleBlockedReasonKey)
            }
            BarHint {
                Layout.topMargin: 4
                visible: ShellModePolicy.barStyleBlockedByCenterInBarReasonKey.length > 0
                icon: "lock"
                text: Translation.tr(ShellModePolicy.barStyleBlockedByCenterInBarReasonKey)
                linkText: Translation.tr("Island")
                targetPageId: "dynamicIsland"
                targetSectionTitle: Translation.tr("Dynamic Island in Bar Center")
            }

            // What only some corner styles have.
            BarPair {
                id: stylePair
                Layout.topMargin: 4
                visible: root.bar.cornerStyle === 1 || (!PanelFamily.isTablet && root.bar.cornerStyle === 3)

                ConfigSwitch {
                    groupHorizontal: stylePair.horizontal
                    visible: root.bar.cornerStyle === 1
                    buttonIcon: "shadow"
                    text: Translation.tr("Show shadow in Float style")
                    checked: root.bar.floatStyleShadow ?? true
                    onCheckedChanged: Config.options.bar.floatStyleShadow = checked
                    StyledToolTip {
                        text: Translation.tr("Shows a subtle drop shadow behind the bar when floating.")
                    }
                }
                ConfigSwitch {
                    groupHorizontal: stylePair.horizontal
                    visible: !PanelFamily.isTablet && root.bar.cornerStyle === 3
                    buttonIcon: "auto_fix"
                    text: Translation.tr("Auto spacing")
                    checked: root.bar.dynamicIslandLoadBalance
                    onCheckedChanged: Config.options.bar.dynamicIslandLoadBalance = checked
                    StyledToolTip {
                        text: Translation.tr("Balances the space on both sides of the island")
                    }
                }
                ConfigSlider {
                    visible: !PanelFamily.isTablet && root.bar.cornerStyle === 3 && !root.bar.dynamicIslandLoadBalance
                    buttonIcon: "space_bar"
                    text: Translation.tr("Dynamic Island spacing")
                    usePercentTooltip: false
                    from: root.bar.vertical ? 16 : 48
                    to: root.bar.vertical ? 100 : 250
                    stepSize: 1
                    value: root.bar.vertical ? root.bar.dynamicIslandSpacingVertical : root.bar.dynamicIslandSpacingHorizontal
                    onValueChanged: {
                        if (root.bar.vertical)
                            Config.options.bar.dynamicIslandSpacingVertical = value;
                        else
                            Config.options.bar.dynamicIslandSpacingHorizontal = value;
                    }
                }
            }

            ContentSubsectionLabel {
                Layout.topMargin: 10
                text: Translation.tr("Group style")
            }

            BarChoiceCards {
                id: groupPicker
                Layout.fillWidth: true
                options: [
                    { "value": 0, "label": Translation.tr("Pills"), "description": Translation.tr("Round plates, joined"), "icon": "location_chip", "shape": MaterialShape.Shape.Cookie4Sided },
                    { "value": 1, "label": Translation.tr("Island"), "description": Translation.tr("Plates with window corners"), "icon": "crop_square", "shape": MaterialShape.Shape.Cookie6Sided },
                    { "value": 2, "label": Translation.tr("Transparent"), "description": Translation.tr("Widgets straight on the bar"), "icon": "opacity", "shape": MaterialShape.Shape.Flower }
                ]
                currentValue: root.bar.barGroupStyle
                onSelected: value => Config.options.bar.barGroupStyle = value
            }

            ConfigSwitch {
                Layout.topMargin: 4
                visible: root.bar.barGroupStyle !== 2
                buttonIcon: "colorize"
                text: Translation.tr("Expressive group color")
                checked: root.bar.expressiveGroupColor
                onCheckedChanged: Config.options.bar.expressiveGroupColor = checked
                StyledToolTip {
                    text: Translation.tr("Use primary container color for pill/island group backgrounds")
                }
            }
        }

        // ── Background ────────────────────────────────────────────────────
        ContentSection {
            icon: "format_paint"
            title: Translation.tr("Background & Colors")

            BarChoiceCards {
                id: backdropPicker
                Layout.fillWidth: true
                options: [
                    { "value": 1, "label": Translation.tr("Visible"), "description": Translation.tr("Always a solid bar"), "icon": "visibility", "shape": MaterialShape.Shape.Cookie9Sided, "enabled": !ShellModePolicy.barPositionLocked },
                    { "value": 2, "label": Translation.tr("Adaptive"), "description": Translation.tr("Solid only while windows are open"), "icon": "masked_transitions", "shape": MaterialShape.Shape.Cookie12Sided, "enabled": !ShellModePolicy.barPositionLocked },
                    { "value": 0, "label": Translation.tr("Transparent"), "description": Translation.tr("Widgets on the wallpaper"), "icon": "opacity", "shape": MaterialShape.Shape.Flower },
                    { "value": 3, "label": Translation.tr("Islands"), "description": Translation.tr("One plate per group"), "icon": "grid_view", "shape": MaterialShape.Shape.Clover4Leaf }
                ]
                currentValue: root.bar.barBackgroundStyle
                onSelected: value => root.setBackgroundStyle(value)
            }

            BarHint {
                Layout.topMargin: 4
                visible: ShellModePolicy.barPositionLocked
                icon: "lock"
                text: Translation.tr("Transparent or Islands only while the island sits in the bar centre.")
                linkText: Translation.tr("Island")
                targetPageId: "dynamicIsland"
                targetSectionTitle: Translation.tr("Dynamic Island in Bar Center")
            }

            BarPair {
                id: effectsPair
                Layout.topMargin: 4

                ConfigSwitch {
                    groupHorizontal: effectsPair.horizontal
                    buttonIcon: "format_color_fill"
                    text: Translation.tr("Expressive bar solid colors")
                    checked: root.bar.expressiveColors
                    onCheckedChanged: Config.options.bar.expressiveColors = checked
                    StyledToolTip {
                        text: Translation.tr("Use expressive solid layer colors")
                    }
                }
                ConfigSwitch {
                    groupHorizontal: effectsPair.horizontal
                    buttonIcon: "contrast"
                    text: Translation.tr("AMOLED background")
                    checked: root.bar.amoledBackground
                    onCheckedChanged: Config.options.bar.amoledBackground = checked
                    StyledToolTip {
                        text: Translation.tr("Pure black, always opaque background for the bar and the dynamic island. Only recolors backgrounds that are visible")
                    }
                }
                ConfigSwitch {
                    groupHorizontal: effectsPair.horizontal
                    buttonIcon: "filter_drama"
                    text: Translation.tr("Bar drop-shadow")
                    enabled: !ShellModePolicy.barDropShadowBlocked
                    checked: root.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
                    onCheckedChanged: {
                        if (!ShellModePolicy.barDropShadowBlocked)
                            Config.options.bar.dropShadow = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Shows a soft drop shadow underneath the status bar")
                    }
                }
                ConfigSwitch {
                    groupHorizontal: effectsPair.horizontal
                    visible: root.bar.barBackgroundStyle === 0
                    buttonIcon: "blur_on"
                    text: Translation.tr("Transparent bar blur/dim")
                    checked: root.bar.transparentGlow
                    onCheckedChanged: Config.options.bar.transparentGlow = checked
                    StyledToolTip {
                        text: Translation.tr("Adds a soft blur and dim gradient under the transparent bar")
                    }
                }
            }

            BarHint {
                Layout.topMargin: 4
                visible: ShellModePolicy.barDropShadowBlocked && !ShellModePolicy.lowIgnoreAlphaBlocksDropShadow
                icon: "lock"
                text: Translation.tr("No drop-shadow while Connect mode and transparency are both on.")
            }
            BarHint {
                Layout.topMargin: 4
                visible: ShellModePolicy.lowIgnoreAlphaBlocksDropShadow
                icon: "lock"
                text: Translation.tr("No drop-shadow while Ignore Alpha is below 30%.")
                linkText: Translation.tr("Windows")
                targetPageId: "windows"
                targetSectionTitle: Translation.tr("Transparency & Blur")
            }

            ContentSubsectionLabel {
                Layout.topMargin: 10
                visible: root.bar.expressiveColors
                text: Translation.tr("Expressive color theme")
            }
            BarThemeSwatches {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.bar.expressiveColors
                options: [
                    { "value": "content", "label": Translation.tr("Content") },
                    { "value": "primary", "label": Translation.tr("Vibrant") },
                    { "value": "secondary", "label": Translation.tr("Secondary") },
                    { "value": "surface", "label": Translation.tr("Surface") }
                ]
                currentValue: root.bar.expressiveColorTheme
                onSelected: value => Config.options.bar.expressiveColorTheme = value
            }
        }

        // ── Screen corners ────────────────────────────────────────────────
        ContentSection {
            icon: "fullscreen_exit"
            title: Translation.tr("Fake screen rounding")

            BarChoiceCards {
                id: roundingPicker
                Layout.fillWidth: true
                options: [
                    { "value": 0, "label": Translation.tr("No"), "description": Translation.tr("Square screen corners"), "icon": "crop_square", "shape": MaterialShape.Shape.Square },
                    { "value": 1, "label": Translation.tr("Yes"), "description": Translation.tr("Rounded corners, always"), "icon": "rounded_corner", "shape": MaterialShape.Shape.Cookie9Sided },
                    { "value": 2, "label": Translation.tr("Windowed"), "description": Translation.tr("Square while a window is fullscreen"), "icon": "fullscreen_exit", "shape": MaterialShape.Shape.Cookie7Sided },
                    { "value": 3, "label": Translation.tr("Wrapped"), "description": Translation.tr("A frame around the screen"), "icon": "capture", "shape": MaterialShape.Shape.Cookie12Sided, "enabled": !ShellModePolicy.barPositionLocked && !ShellModePolicy.floatStyleActive },
                    { "value": 4, "label": Translation.tr("Edge"), "description": Translation.tr("Curves where the bar meets the edge"), "icon": "border_top", "shape": MaterialShape.Shape.SoftBurst, "enabled": !ShellModePolicy.barPositionLocked }
                ]
                currentValue: Config.options.appearance.fakeScreenRounding
                onSelected: value => Config.options.appearance.fakeScreenRounding = value
            }

            BarHint {
                Layout.topMargin: 4
                visible: ShellModePolicy.barPositionLocked
                icon: "lock"
                text: Translation.tr("Wrapped and Edge would float over the island in the bar centre.")
            }
            BarHint {
                Layout.topMargin: 4
                visible: ShellModePolicy.wrappedFrameBlockedReasonKey.length > 0 && !ShellModePolicy.barPositionLocked
                icon: "lock"
                text: Translation.tr(ShellModePolicy.wrappedFrameBlockedReasonKey)
            }

            ConfigSpinBox {
                Layout.topMargin: 4
                visible: Config.options.appearance.fakeScreenRounding === 3
                icon: "line_weight"
                text: Translation.tr("Wrapped frame thickness")
                value: Config.options.appearance.wrappedFrameThickness
                from: 5
                to: 25
                stepSize: 1
                onValueChanged: Config.options.appearance.wrappedFrameThickness = value
            }
        }

        // ── Brand icon ────────────────────────────────────────────────────
        LazyBlock {
            placeholderHeight: 320
            ContentSection {
                icon: "brand_family"
                title: Translation.tr("Top-left brand icon")

                BarBrandPicker {
                    Layout.fillWidth: true
                    symbolMode: root.bar.useMaterialSymbolForTopLeftIcon
                    symbolName: root.bar.topLeftIcon
                    currentValue: root.bar.useMaterialSymbolForTopLeftIcon ? "" : root.bar.topLeftIcon
                    onSelected: value => Config.options.bar.topLeftIcon = value
                    options: [
                        { "displayName": Translation.tr("Distro"), "symbol": SystemInfo.distroIcon, "value": "distro" },
                        { "displayName": "Arch", "symbol": "arch-symbolic", "value": "arch" },
                        { "displayName": "CachyOS", "symbol": "cachyos-symbolic", "value": "cachyos" },
                        { "displayName": "EndeavourOS", "symbol": "endeavouros-symbolic", "value": "endeavouros" },
                        { "displayName": "Fedora", "symbol": "fedora-symbolic", "value": "fedora" },
                        { "displayName": "Red Hat", "symbol": "redhat-symbolic", "value": "redhat" },
                        { "displayName": "Debian", "symbol": "debian-symbolic", "value": "debian" },
                        { "displayName": "Ubuntu", "symbol": "ubuntu-symbolic", "value": "ubuntu" },
                        { "displayName": "Mint", "symbol": "mint-symbolic", "value": "mint" },
                        { "displayName": "Pop!_OS", "symbol": "popos-symbolic", "value": "popos" },
                        { "displayName": "Manjaro", "symbol": "manjaro-symbolic", "value": "manjaro" },
                        { "displayName": "NixOS", "symbol": "nixos-symbolic", "value": "nixos" },
                        { "displayName": "openSUSE", "symbol": "opensuse-symbolic", "value": "opensuse" },
                        { "displayName": "Gentoo", "symbol": "gentoo-symbolic", "value": "gentoo" },
                        { "displayName": "Void", "symbol": "void-symbolic", "value": "void" },
                        { "displayName": "Alpine", "symbol": "alpine-symbolic", "value": "alpine" },
                        { "displayName": "Kali", "symbol": "kali-symbolic", "value": "kali" },
                        { "displayName": "FreeBSD", "symbol": "freebsd-symbolic", "value": "freebsd" },
                        { "displayName": "SteamOS", "symbol": "steamos-symbolic", "value": "steamos" },
                        { "displayName": "Linux", "symbol": "linux-symbolic", "value": "linux" },
                        { "displayName": "Android", "symbol": "android-symbolic", "value": "android" },
                        { "displayName": "Apple", "symbol": "apple-symbolic", "value": "apple" },
                        { "displayName": "Windows", "symbol": "microsoft-symbolic", "value": "microsoft" },
                        { "displayName": "Spark", "symbol": "spark-symbolic", "value": "spark" },
                        { "displayName": "Nyarch", "symbol": "nyarch-symbolic", "value": "nyarch" },
                        { "displayName": "Docker", "symbol": "docker.svg", "value": "docker" },
                        { "displayName": "Flatpak", "symbol": "flatpak-symbolic", "value": "flatpak" },
                        { "displayName": "GitHub", "symbol": "github-symbolic", "value": "github" },
                        { "displayName": "Desktop", "symbol": "desktop-symbolic", "value": "desktop" },
                        { "displayName": "Crosshair", "symbol": "crosshair-symbolic", "value": "crosshair" },
                        { "displayName": "Cloudflare", "symbol": "cloudflare-dns-symbolic", "value": "cloudflare-dns" },
                        { "displayName": "Gemini", "symbol": "google-gemini-symbolic", "value": "google-gemini" },
                        { "displayName": "DeepSeek", "symbol": "deepseek-symbolic", "value": "deepseek" },
                        { "displayName": "OpenAI", "symbol": "openai-symbolic", "value": "openai" },
                        { "displayName": "Mistral", "symbol": "mistral-symbolic", "value": "mistral" },
                        { "displayName": "Ollama", "symbol": "ollama-symbolic", "value": "ollama" },
                        { "displayName": "OpenRouter", "symbol": "openrouter-symbolic", "value": "openrouter" }
                    ]
                }

                ConfigSwitch {
                    Layout.topMargin: 6
                    buttonIcon: "text_fields"
                    text: Translation.tr("Use Material Symbol for top-left icon")
                    checked: root.bar.useMaterialSymbolForTopLeftIcon
                    onCheckedChanged: Config.options.bar.useMaterialSymbolForTopLeftIcon = checked
                    StyledToolTip {
                        text: Translation.tr("Any Google Material Symbol, by name, instead of a preset")
                    }
                }

                ConfigTextField {
                    id: topLeftIconField
                    visible: root.bar.useMaterialSymbolForTopLeftIcon
                    text: Translation.tr("Material Symbol name")
                    icon: "search"
                    tooltip: Translation.tr("Type any Google Material Symbol identifier (e.g. spark, terminal, favorite, home).")
                    placeholderText: Translation.tr("e.g. spark, terminal, favorite...")
                    Component.onCompleted: inputText = Config.options.bar.topLeftIcon
                    textField.onTextChanged: {
                        const val = textField.text.trim();
                        if (val !== "" && textField.activeFocus)
                            Config.options.bar.topLeftIcon = val;
                    }

                    Connections {
                        target: Config.options.bar
                        function onTopLeftIconChanged() {
                            topLeftIconField.textField.text = Config.options.bar.topLeftIcon;
                        }
                    }
                }

                BarHint {
                    Layout.topMargin: 4
                    visible: root.bar.useMaterialSymbolForTopLeftIcon
                    icon: "info"
                    text: Translation.tr("Thousands of symbols, by name.")
                    linkText: Translation.tr("Open Icons Page")
                    onLinkClicked: Quickshell.execDetached(["xdg-open", "https://fonts.google.com/icons"])
                }
            }
        }
    }
}
