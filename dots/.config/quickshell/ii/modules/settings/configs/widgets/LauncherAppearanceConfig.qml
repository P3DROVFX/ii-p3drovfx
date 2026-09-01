import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
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
                text: Translation.tr("Panel appearance & layout")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Position & Screen Placement ───────────────────────────────────────
        ContentSection {
            icon: "center_focus_strong"
            title: Translation.tr("Position & Initial View")
            tooltip: Translation.tr("Configure screen alignment, vertical centering, and empty query behavior.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Center Search on Screen")
                    description: Translation.tr("Places Search at the screen center; disable it to keep the Overview-aligned position.")
                    checked: Config.options.search.positionStyle === "center"
                    onCheckedChanged: Config.options.search.positionStyle = checked ? "center" : "default"
                }

                ConfigSlider {
                    visible: Config.options.search.positionStyle === "center"
                    buttonIcon: "vertical_align_center"
                    text: Translation.tr("Centered search vertical position")
                    value: Config.options.search.centerVerticalRatio * 100
                    from: 10
                    to: 90
                    stepSize: 1
                    usePercentTooltip: true
                    onValueChanged: Config.options.search.centerVerticalRatio = value / 100
                }

                ConfigSwitch {
                    buttonIcon: "apps"
                    text: Translation.tr("Always list apps on empty query")
                    description: Translation.tr("Shows applications before you type instead of keeping Search as a compact empty field.")
                    checked: Config.options.search.alwaysListApps
                    onCheckedChanged: {
                        Config.options.search.alwaysListApps = checked;
                        if (checked)
                            Config.options.overview.enable = false;
                    }
                }

                NoticeBox {
                    Layout.fillWidth: true
                    visible: Config.options.search.alwaysListApps
                    materialIcon: "apps"
                    text: Translation.tr("Search now opens directly with applications. The workspace Overview has been disabled and remains locked until this option is turned off.")
                }
            }
        }

        // ── Dimensions & Sizing ───────────────────────────────────────────────
        ContentSection {
            icon: "aspect_ratio"
            title: Translation.tr("Dimensions & Sizing")
            tooltip: Translation.tr("Adjust search bar, window dimensions, and expandable tool panel sizes.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsectionLabel {
                    text: Translation.tr("Search Window Dimensions")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ConfigSlider {
                        Layout.fillWidth: true
                        buttonIcon: "width"
                        text: Translation.tr("Search base width (px)")
                        value: Config.options.search.baseWidth
                        from: 360
                        to: 1000
                        stepSize: 10
                        usePercentTooltip: false
                        onValueChanged: Config.options.search.baseWidth = value
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        buttonIcon: "height"
                        text: Translation.tr("Search max height (px)")
                        value: Config.options.search.baseHeight
                        from: 300
                        to: 900
                        stepSize: 10
                        usePercentTooltip: false
                        onValueChanged: Config.options.search.baseHeight = value
                    }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Tool Panel Dimensions")
                    Layout.topMargin: 4
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ConfigSlider {
                        Layout.fillWidth: true
                        buttonIcon: "width"
                        text: Translation.tr("Tool panel width (px)")
                        value: Config.options.search.appearance.panelWidth
                        from: 720
                        to: 1200
                        stepSize: 20
                        usePercentTooltip: false
                        onValueChanged: Config.options.search.appearance.panelWidth = value
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        buttonIcon: "height"
                        text: Translation.tr("Tool panel content height (px)")
                        value: Config.options.search.appearance.panelBodyHeight
                        from: 320
                        to: 640
                        stepSize: 20
                        usePercentTooltip: false
                        onValueChanged: Config.options.search.appearance.panelBodyHeight = value
                    }
                }
            }
        }

        // ── Visual Accents & Hints ────────────────────────────────────────────
        ContentSection {
            icon: "palette"
            title: Translation.tr("Visual Accents & Hints")
            tooltip: Translation.tr("Configure dynamic Material You accent colors, keyboard shortcuts, and action strip.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "format_paint"
                    text: Translation.tr("Accent keyword panels")
                    description: Translation.tr("Uses the dynamic Material You accent surface for tools opened from Search.")
                    checked: Config.options.search.appearance.accentPanels
                    onCheckedChanged: Config.options.search.appearance.accentPanels = checked
                }

                ConfigSlider {
                    visible: Config.options.search.appearance.accentPanels
                    buttonIcon: "opacity"
                    text: Translation.tr("Accent strength")
                    value: Config.options.search.appearance.accentStrength * 100
                    from: 0
                    to: 30
                    stepSize: 1
                    usePercentTooltip: true
                    onValueChanged: Config.options.search.appearance.accentStrength = value / 100
                }

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Show keyboard hints")
                    description: Translation.tr("Shows the available action shortcuts for the selected result or panel.")
                    checked: Config.options.search.appearance.showKeyHints
                    onCheckedChanged: Config.options.search.appearance.showKeyHints = checked
                }

                ConfigSwitch {
                    buttonIcon: "space_bar"
                    text: Translation.tr("Show hint bar")
                    description: Translation.tr("Keeps the Raycast-style action strip visible at the bottom of panels.")
                    checked: Config.options.search.appearance.showKeyHintBar
                    onCheckedChanged: Config.options.search.appearance.showKeyHintBar = checked
                }
            }
        }

        // ── Suggestions & Empty Query ─────────────────────────────────────────
        ContentSection {
            icon: "auto_awesome"
            title: Translation.tr("Suggestions & Query Chips")
            tooltip: Translation.tr("Configure empty-query suggestions, quick filters and visual chips.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Empty-query suggestions")
                    description: Translation.tr("Fills the normal Search results with your most-used apps, panels, toggles and more as soon as it opens.")
                    checked: Config.options.search.suggestions.enable
                    configPage: Qt.resolvedUrl("LauncherSuggestionsConfig.qml")
                    onCheckedChanged: {
                        Config.options.search.suggestions.enable = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Toggle idle Search suggestions. Click the button text to choose which sections show.")
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
