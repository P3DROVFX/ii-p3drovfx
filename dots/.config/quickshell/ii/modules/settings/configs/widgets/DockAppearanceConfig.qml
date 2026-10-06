pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.dock

/**
 * Dock → Icons & motion. The hero is the dock's apps, live, with the tint, dimming,
 * mask and spacing set here; its two buttons play the launch and notification
 * animations on them (choosing one plays it too). The options stay in their
 * original sections. The dock's style, size and corners live on the Dock page.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var dock: Config.options.dock
    readonly property var attentionAnimationOptions: [{
        "displayName": Translation.tr("None"),
        "icon": "block",
        "value": "none"
    }, {
        "displayName": Translation.tr("Bounce"),
        "icon": "sports_basketball",
        "value": "bounce"
    }, {
        "displayName": Translation.tr("Hop"),
        "icon": "north",
        "value": "hop"
    }, {
        "displayName": Translation.tr("Pulse"),
        "icon": "radio_button_checked",
        "value": "pulse"
    }, {
        "displayName": Translation.tr("Wiggle"),
        "icon": "vibration",
        "value": "wiggle"
    }, {
        "displayName": Translation.tr("Ripple"),
        "icon": "radar",
        "value": "ripple"
    }]

    // A new choice plays at once on the preview.
    Connections {
        target: Config.options.dock
        function onLaunchAnimationChanged() {
            hero.playAttention("launch");
        }
        function onNotificationAnimationChanged() {
            hero.playAttention("notification");
        }
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
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
                text: Translation.tr("Icons & motion")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Hero: the dock's apps, live ─────────────────────────────────────
        DockPreviewStage {
            id: hero
            Layout.fillWidth: true
            Layout.preferredHeight: hero.preferredHeight
            hiddenTypes: ["action", "file", "media", "weather", "sports", "tasks", "phone", "livePreview", "widgetStack", "utility"]

            Rectangle {
                id: heroTag
                anchors.left: parent.left
                anchors.margins: 11
                y: hero.pillEdge === "top" ? 11 : hero.height - height - 11
                height: tagColumn.implicitHeight + 12
                width: Math.min(hero.width - playButtons.width - 34, tagColumn.implicitWidth + 36)
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
                        text: Translation.tr("Your apps")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const parts = [];
                            parts.push(root.dock.monochromeIcons ? Translation.tr("Tinted") : root.dock.dimInactiveIcons ? Translation.tr("Idle ones dimmed") : Translation.tr("Full colour"));
                            if (root.dock.enableShapeMask)
                                parts.push(Translation.tr("Adaptive"));
                            return parts.join(" · ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            // Play the two animations on the icons; same height as the tag.
            Row {
                id: playButtons
                anchors.right: parent.right
                anchors.margins: 11
                y: heroTag.y
                spacing: 6
                PlayButton {
                    stage: hero
                    kind: "launch"
                    symbol: "rocket_launch"
                    label: Translation.tr("Launch")
                    height: heroTag.height
                }
                PlayButton {
                    stage: hero
                    kind: "notification"
                    symbol: "notifications_active"
                    label: Translation.tr("Notification")
                    height: heroTag.height
                }
            }
        }

        // ── Icons ───────────────────────────────────────────────────────────
        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Icons")
            icon: "apps"

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Tint dock icons")
                    checked: root.dock.monochromeIcons
                    onCheckedChanged: Config.options.dock.monochromeIcons = checked
                    StyledToolTip {
                        text: Translation.tr("Applies monochrome tint to dock icons")
                    }
                }
                ConfigSwitch {
                    enabled: !root.dock.monochromeIcons
                    buttonIcon: "tonality"
                    text: Translation.tr("Dim inactive dock icons")
                    checked: root.dock.dimInactiveIcons
                    onCheckedChanged: Config.options.dock.dimInactiveIcons = checked
                    StyledToolTip {
                        text: Translation.tr("Greyscale icons for pinned apps that are not running.\nDisabled when 'Tint dock icons' is active.")
                    }
                }
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "space_bar"
                text: Translation.tr("Icon spacing")
                value: root.dock.iconSpacing
                from: -4
                to: 16
                stepSize: 1
                usePercentTooltip: false
                onValueChanged: Config.options.dock.iconSpacing = value
            }

            ConfigSlider {
                Layout.fillWidth: true
                buttonIcon: "rounded_corner"
                text: Translation.tr("Widget corner radius") + (root.dock.widgetRadius < 0 ? " (" + Translation.tr("Auto") + ")" : "")
                value: root.dock.widgetRadius < 0 ? 0 : root.dock.widgetRadius
                from: 0
                to: 30
                stepSize: 1
                usePercentTooltip: false
                onValueChanged: Config.options.dock.widgetRadius = value === 0 ? -1 : value
            }
        }

        // ── Adaptive icons ──────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Adaptive icons")
            icon: "interests"
            tooltip: Translation.tr("Crops dock icons using Material Design shapes.")

            ConfigSwitch {
                buttonIcon: "interests"
                text: Translation.tr("Adaptive icons")
                checked: root.dock.enableShapeMask
                onCheckedChanged: Config.options.dock.enableShapeMask = checked
                StyledToolTip {
                    text: Translation.tr("Crops the icons using the selected material shape")
                }
            }

            ContentSubsection {
                visible: root.dock.enableShapeMask
                title: Translation.tr("Mask shape")
                icon: "shape_line"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: root.dock.shapeMask
                    onSelected: newValue => Config.options.dock.shapeMask = newValue
                    options: (["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]).map(shape => ({
                        "displayName": "",
                        "shape": shape,
                        "value": shape
                    }))
                }
            }
        }

        // ── Animations ──────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Animations")
            icon: "animation"
            tooltip: Translation.tr("What an icon does when its app opens or calls for you. Choosing one plays it on the preview.")

            ContentSubsection {
                title: Translation.tr("Launch animation")
                icon: "rocket_launch"
                tooltip: Translation.tr("Played when you open an app from the dock.")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: root.dock.launchAnimation
                    onSelected: newValue => Config.options.dock.launchAnimation = newValue
                    options: root.attentionAnimationOptions
                }
            }

            ContentSubsection {
                title: Translation.tr("Notification animation")
                icon: "notifications_active"
                tooltip: Translation.tr("Played when a docked app sends a notification.")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: root.dock.notificationAnimation
                    onSelected: newValue => Config.options.dock.notificationAnimation = newValue
                    options: root.attentionAnimationOptions
                }
            }
        }
    }

    // A pill on the hero that plays one animation on the preview's icons.
    component PlayButton: RippleButton {
        id: play
        property string kind: ""
        property string symbol: ""
        property string label: ""
        property var stage: null
        readonly property bool compact: (play.stage?.width ?? 0) < 560
        implicitWidth: play.compact ? play.height : playContent.implicitWidth + 32
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.small
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        onClicked: play.stage?.playAttention(play.kind)
        StyledToolTip {
            visible: play.compact && play.hovered
            text: play.label
        }
        contentItem: Item {
            RowLayout {
                id: playContent
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: play.symbol
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
                StyledText {
                    visible: !play.compact
                    text: play.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
