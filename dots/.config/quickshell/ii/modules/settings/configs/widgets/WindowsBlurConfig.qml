import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.windows

/**
 * Advanced blur, a page away from Windows: the same preview the Windows page leads with
 * (glass only), the look under it, then how it behaves and where else it applies.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var appearance: Config.options.appearance
    readonly property var blur: Config.options.appearance.blur

    function resetLook(): void {
        subPageRoot.blur.passes = 3;
        subPageRoot.blur.noise = 0.05;
        subPageRoot.blur.contrast = 0.89;
        subPageRoot.blur.brightness = 1.0;
        subPageRoot.blur.vibrancy = 0.2;
        subPageRoot.blur.vibrancyDarkness = 0.2;
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Advanced blur")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            visible: !subPageRoot.appearance.transparency.enable
            text: Translation.tr("Shell panels are solid, so their blur has nothing to show through. Set Transparency to Auto or Custom on the Windows page to see it.")
        }

        // The glass, large, above the values that shape it.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12

            WindowsLookPreview {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(Math.max(260, Math.min(440, width / 1.9)))
                showAnimation: false
                highlight: "glass"
            }

            ContentSection {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                icon: "lens_blur"
                title: Translation.tr("Blur look")

                ConfigSlider {
                    buttonIcon: "layers"
                    text: Translation.tr("Blur Passes")
                    from: 1
                    to: 10
                    stepSize: 1
                    snapMode: Slider.SnapAlways
                    stopIndicatorValues: []
                    usePercentTooltip: false
                    badgeText: String(Math.round(value))
                    tooltipContent: badgeText
                    value: subPageRoot.blur.passes
                    onMoved: subPageRoot.blur.passes = Math.round(value)
                }
                ConfigSlider {
                    buttonIcon: "grain"
                    text: Translation.tr("Blur noise")
                    from: 0
                    to: 1
                    stepSize: 0.001
                    snapMode: Slider.NoSnap
                    stopIndicatorValues: []
                    usePercentTooltip: false
                    badgeText: (value * 100).toFixed(1) + "%"
                    tooltipContent: badgeText
                    value: subPageRoot.blur.noise
                    onMoved: subPageRoot.blur.noise = Math.round(value * 1000) / 1000
                }
                ConfigSlider {
                    buttonIcon: "contrast"
                    text: Translation.tr("Blur contrast")
                    from: 0
                    to: 2
                    stepSize: 0.001
                    snapMode: Slider.NoSnap
                    stopIndicatorValues: [1]
                    usePercentTooltip: false
                    badgeText: (value * 100).toFixed(1) + "%"
                    tooltipContent: badgeText
                    value: subPageRoot.blur.contrast
                    onMoved: subPageRoot.blur.contrast = Math.round(value * 1000) / 1000
                }
                ConfigSlider {
                    buttonIcon: "brightness_6"
                    text: Translation.tr("Blur brightness")
                    from: 0
                    to: 2
                    stepSize: 0.001
                    snapMode: Slider.NoSnap
                    stopIndicatorValues: [1]
                    usePercentTooltip: false
                    badgeText: (value * 100).toFixed(1) + "%"
                    tooltipContent: badgeText
                    value: subPageRoot.blur.brightness
                    onMoved: subPageRoot.blur.brightness = Math.round(value * 1000) / 1000
                }
                ConfigSlider {
                    buttonIcon: "palette"
                    text: Translation.tr("Blur vibrancy")
                    from: 0
                    to: 1
                    stepSize: 0.001
                    snapMode: Slider.NoSnap
                    stopIndicatorValues: []
                    usePercentTooltip: false
                    badgeText: (value * 100).toFixed(1) + "%"
                    tooltipContent: badgeText
                    value: subPageRoot.blur.vibrancy
                    onMoved: subPageRoot.blur.vibrancy = Math.round(value * 1000) / 1000
                }
                ConfigSlider {
                    buttonIcon: "tonality"
                    text: Translation.tr("Vibrancy in dark areas")
                    from: 0
                    to: 1
                    stepSize: 0.001
                    snapMode: Slider.NoSnap
                    stopIndicatorValues: []
                    usePercentTooltip: false
                    badgeText: (value * 100).toFixed(1) + "%"
                    tooltipContent: badgeText
                    value: subPageRoot.blur.vibrancyDarkness
                    onMoved: subPageRoot.blur.vibrancyDarkness = Math.round(value * 1000) / 1000
                }

                RippleButton {
                    Layout.alignment: Qt.AlignRight
                    implicitHeight: 36
                    implicitWidth: resetRow.implicitWidth + 28
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: subPageRoot.resetLook()

                    contentItem: Item {
                        RowLayout {
                            id: resetRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "restart_alt"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: Translation.tr("Reset look")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "deblur"
            title: Translation.tr("Blur behavior")

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "opacity"
                    text: Translation.tr("Keep blur strength when windows fade")
                    checked: subPageRoot.blur.ignoreOpacity
                    onCheckedChanged: {
                        if (Config.ready && checked !== subPageRoot.blur.ignoreOpacity)
                            subPageRoot.blur.ignoreOpacity = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Ignore window opacity when calculating blur intensity.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "speed"
                    text: Translation.tr("Optimize blur rendering")
                    checked: subPageRoot.blur.newOptimizations
                    onCheckedChanged: {
                        if (Config.ready && checked !== subPageRoot.blur.newOptimizations)
                            subPageRoot.blur.newOptimizations = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Reuse the blurred background to reduce GPU work.")
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "filter_none"
                    text: Translation.tr("X-ray blur for floating windows")
                    enabled: subPageRoot.blur.newOptimizations
                    checked: subPageRoot.blur.xray
                    onCheckedChanged: {
                        if (Config.ready && checked !== subPageRoot.blur.xray)
                            subPageRoot.blur.xray = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Ignore tiled windows behind floating windows. Requires optimized blur rendering.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "space_dashboard"
                    text: Translation.tr("Blur behind special workspaces")
                    checked: subPageRoot.blur.special
                    onCheckedChanged: {
                        if (Config.ready && checked !== subPageRoot.blur.special)
                            subPageRoot.blur.special = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Blur the desktop behind a special workspace. Uses more GPU resources.")
                    }
                }
            }

            ConfigSlider {
                id: ignoreAlphaSlider
                buttonIcon: "gradient"
                text: Translation.tr("Ignore Alpha")
                value: subPageRoot.appearance.ignoreAlpha
                from: 0
                to: 1
                stepSize: 0.001
                snapMode: Slider.NoSnap
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: (value * 100).toFixed(1) + "%"
                tooltipContent: badgeText
                onMoved: subPageRoot.appearance.ignoreAlpha = Math.round(value * 1000) / 1000
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: Math.round(ignoreAlphaSlider.value * 100) <= 30
                materialIcon: "info"
                text: Translation.tr("Low Ignore Alpha values can cause visual artifacts around element borders. It is recommended to keep this value high.")
            }
        }

        ContentSection {
            icon: "web_asset"
            title: Translation.tr("Blur in application popups")

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "menu_open"
                    text: Translation.tr("Blur application menus")
                    checked: subPageRoot.blur.popups
                    onCheckedChanged: {
                        if (Config.ready && checked !== subPageRoot.blur.popups)
                            subPageRoot.blur.popups = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Apply blur to application popups, such as right-click menus.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Blur input method popups")
                    checked: subPageRoot.blur.inputMethods
                    onCheckedChanged: {
                        if (Config.ready && checked !== subPageRoot.blur.inputMethods)
                            subPageRoot.blur.inputMethods = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Apply blur to input method windows, such as Fcitx5 candidate lists.")
                    }
                }
            }

            ConfigSlider {
                buttonIcon: "gradient"
                text: Translation.tr("Application menu alpha threshold")
                enabled: subPageRoot.blur.popups
                from: 0
                to: 1
                stepSize: 0.001
                snapMode: Slider.NoSnap
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: (value * 100).toFixed(1) + "%"
                tooltipContent: badgeText
                value: subPageRoot.blur.popupsIgnoreAlpha
                onMoved: subPageRoot.blur.popupsIgnoreAlpha = Math.round(value * 1000) / 1000
            }
            ConfigSlider {
                buttonIcon: "gradient"
                text: Translation.tr("Input method alpha threshold")
                enabled: subPageRoot.blur.inputMethods
                from: 0
                to: 1
                stepSize: 0.001
                snapMode: Slider.NoSnap
                stopIndicatorValues: []
                usePercentTooltip: false
                badgeText: (value * 100).toFixed(1) + "%"
                tooltipContent: badgeText
                value: subPageRoot.blur.inputMethodsIgnoreAlpha
                onMoved: subPageRoot.blur.inputMethodsIgnoreAlpha = Math.round(value * 1000) / 1000
            }
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Related settings")

            Flow {
                Layout.fillWidth: true
                spacing: 8

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
}
