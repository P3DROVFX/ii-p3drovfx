pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Settings → Devices & Phone → ii tools → Deck commands:
 * Expressive Google Material 3 workspace for the phone Stream Deck:
 * MultiEffect-clipped hero, one-click starter templates, live keycap preview,
 * quick icon picker chips, reorder/test-run actions, and bash command editor.
 */
AppSettingsSection {
    id: section

    readonly property bool deckOn: Config.options.iiTools.deck.enable
    readonly property var commands: Array.from(Config.options.iiTools.deck.commands ?? [])
    readonly property int readyCount: section.commands.filter(c => String(c?.command ?? "").trim() !== "").length

    readonly property var _starterPresets: [
        { name: Translation.tr("Notify ping"), icon: "notifications_active", command: "notify-send \"ii deck\" \"Triggered from phone\"" },
        { name: Translation.tr("Open terminal"), icon: "terminal", command: "kitty || foot || alacritty" },
        { name: Translation.tr("Home folder"), icon: "folder_open", command: "xdg-open \"$HOME\"" },
        { name: Translation.tr("Clear clipboard"), icon: "content_paste_off", command: "wl-copy --clear" }
    ]

    function addCommand(preset): void {
        const list = Array.from(Config.options.iiTools.deck.commands ?? []);
        list.push({
            id: Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(36),
            name: preset?.name ?? Translation.tr("New command"),
            icon: preset?.icon ?? "terminal",
            command: preset?.command ?? ""
        });
        Config.options.iiTools.deck.commands = list;
    }

    function moveCommand(fromIndex, toIndex): void {
        const list = Array.from(Config.options.iiTools.deck.commands ?? []);
        if (fromIndex < 0 || toIndex < 0 || fromIndex >= list.length || toIndex >= list.length)
            return;
        const item = list.splice(fromIndex, 1)[0];
        list.splice(toIndex, 0, item);
        Config.options.iiTools.deck.commands = list;
    }

    function removeCommand(index): void {
        const list = Array.from(Config.options.iiTools.deck.commands ?? []);
        if (index < 0 || index >= list.length)
            return;
        list.splice(index, 1);
        Config.options.iiTools.deck.commands = list;
    }

    symbol: "grid_view"
    title: Translation.tr("Stream Deck & commands")
    description: Translation.tr("Custom macro keys synced live to the phone deck alongside shell actions and apps.")

    // ── Expressive Stream Deck Showcase Hero ────────────────────────────
    Item {
        id: deckHero
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        implicitHeight: heroContent.implicitHeight + 40

        Rectangle {
            id: deckHeroMask
            width: deckHeroSurface.width
            height: deckHeroSurface.height
            radius: Appearance.rounding.verylarge
            visible: false
            layer.enabled: true
        }

        Item {
            id: deckHeroSurface
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: deckHeroMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer1
            }

            Rectangle {
                anchors.fill: parent
                visible: section.deckOn
                color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08)
            }

            MaterialShape {
                implicitSize: deckHero.height * 1.4
                x: deckHero.width - implicitSize * 0.42
                y: deckHero.height - implicitSize * 0.58
                shape: section.deckOn ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Circle
                color: Appearance.colors.colPrimary
                opacity: 0.07
            }
        }

        ColumnLayout {
            id: heroContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    shape: section.deckOn ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Circle
                    implicitSize: 52
                    padding: 8
                    iconSize: 24
                    text: "grid_view"
                    fill: section.deckOn ? 1 : 0
                    color: section.deckOn ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colSymbol: section.deckOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Translation.tr("PHONE STREAM DECK")
                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                        font.variableAxes: ({ "wght": 800, "wdth": 115, "ROND": 0 })
                        font.letterSpacing: 1.5
                        color: section.deckOn ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Translation.tr("Deck commands")
                        font.pixelSize: 22
                        font.variableAxes: ({ "wght": 800, "wdth": 105, "ROND": 0 })
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledSwitch {
                    checked: section.deckOn
                    onToggled: value => Config.options.iiTools.deck.enable = value
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                lineHeight: 1.25
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: section.deckOn
                    ? Translation.tr("Each key runs with bash on this PC when tapped on your phone. Customize icons, test locally, or reorder keys.")
                    : Translation.tr("Deck integration is currently off. Turn it on to expose shell actions, apps, and custom commands to your phone.")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    DeckBadge {
                        symbol: "bolt"
                        text: section.commands.length === 1
                            ? Translation.tr("1 custom key")
                            : Translation.tr("%1 custom keys").arg(section.commands.length)
                        highlighted: section.deckOn && section.readyCount > 0
                    }

                    DeckBadge {
                        visible: section.deckOn
                        symbol: IiLinkService.phoneConnected ? "sync" : "schedule"
                        text: IiLinkService.phoneConnected
                            ? Translation.tr("Synced live")
                            : Translation.tr("Syncs on connect")
                        secondary: IiLinkService.phoneConnected
                    }
                }

                RippleButtonWithIcon {
                    visible: section.deckOn
                    materialIcon: "add"
                    mainText: Translation.tr("Add command")
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colText: Appearance.colors.colOnPrimary
                    onClicked: section.addCommand(null)
                }
            }
        }
    }

    // ── Empty State + Starter Macro Presets ─────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: section.deckOn && section.commands.length === 0
        implicitHeight: emptyCol.implicitHeight + 36
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: emptyCol
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    shape: MaterialShape.Shape.Cookie7Sided
                    implicitSize: 44
                    padding: 7
                    iconSize: 20
                    text: "touch_app"
                    color: Appearance.colors.colSecondaryContainer
                    colSymbol: Appearance.colors.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("No custom deck keys yet")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Pick a starter macro below or create a blank key to run any bash command from your phone.")
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: section._starterPresets

                    delegate: RippleButtonWithIcon {
                        required property var modelData
                        materialIcon: modelData.icon
                        mainText: modelData.name
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colText: Appearance.colors.colOnLayer2
                        onClicked: section.addCommand(modelData)
                    }
                }
            }
        }
    }

    // ── Active Command Cards ────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: section.deckOn && section.commands.length > 0
        spacing: 12

        Repeater {
            model: section.commands

            delegate: DeckCommandCard {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                command: modelData
                commandIndex: index
                totalCount: section.commands.length
            }
        }
    }

    // ── Quick Add Presets Strip when list already has items ──────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: section.deckOn && section.commands.length > 0
        spacing: 8

        StyledText {
            text: Translation.tr("Quick templates:")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: section._starterPresets

                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: tplRow.implicitWidth + 18
                    implicitHeight: 28
                    radius: Appearance.rounding.full
                    color: tplHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1

                    RowLayout {
                        id: tplRow
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: 15
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    RippleButton {
                        anchors.fill: parent
                        buttonRadius: parent.radius
                        colBackground: "transparent"
                        colBackgroundHover: "transparent"
                        onClicked: section.addCommand(modelData)
                    }

                    HoverHandler {
                        id: tplHover
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }
    }

    // ── Components ──────────────────────────────────────────────────────
    component DeckBadge: Rectangle {
        id: badge
        property string symbol: ""
        property string text: ""
        property bool highlighted: false
        property bool secondary: false

        implicitWidth: badgeRow.implicitWidth + 18
        implicitHeight: 28
        radius: Appearance.rounding.full
        color: badge.highlighted
            ? Appearance.colors.colPrimary
            : (badge.secondary ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2)

        RowLayout {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: badge.symbol
                iconSize: 15
                fill: (badge.highlighted || badge.secondary) ? 1 : 0
                color: badge.highlighted
                    ? Appearance.colors.colOnPrimary
                    : (badge.secondary ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext)
            }

            StyledText {
                text: badge.text
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: badge.highlighted
                    ? Appearance.colors.colOnPrimary
                    : (badge.secondary ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2)
            }
        }
    }

    component DeckCommandCard: Rectangle {
        id: card
        property var command
        property int commandIndex: 0
        property int totalCount: 0
        property bool iconPickerOpen: false
        property bool justRan: false

        readonly property bool hasCmd: cmdField.text.trim() !== ""
        readonly property string liveIcon: (iconField.text.trim() || "terminal")
        readonly property string liveName: (nameField.text.trim() || Translation.tr("Untitled key"))
        readonly property var quickIcons: [
            "terminal", "rocket_launch", "screenshot_region", "folder_open",
            "music_note", "volume_off", "lock", "bolt",
            "code", "notifications_active", "home", "power_settings_new"
        ]

        function commit(field, value): void {
            const list = Array.from(Config.options.iiTools.deck.commands ?? []);
            if (card.commandIndex < 0 || card.commandIndex >= list.length)
                return;
            const next = Object.assign({}, list[card.commandIndex]);
            next[field] = value;
            list[card.commandIndex] = next;
            Config.options.iiTools.deck.commands = list;
        }

        implicitHeight: cardLayout.implicitHeight + 36
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: card.hasCmd
            color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.04)
        }

        Timer {
            id: ranResetTimer
            interval: 1200
            onTriggered: card.justRan = false
        }

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ── Header: Live Phone Keycap Preview + Actions ─────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // Live keycap tile preview
                Rectangle {
                    implicitWidth: 58
                    implicitHeight: 58
                    radius: Appearance.rounding.large
                    color: card.hasCmd ? Appearance.colors.colPrimary : Appearance.colors.colLayer2

                    MaterialShapeWrappedMaterialSymbol {
                        anchors.centerIn: parent
                        shape: card.hasCmd ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
                        implicitSize: 42
                        padding: 6
                        iconSize: 22
                        text: card.liveIcon
                        fill: card.hasCmd ? 1 : 0
                        color: card.hasCmd
                            ? ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.16)
                            : Appearance.colors.colLayer1
                        colSymbol: card.hasCmd
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer2
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: card.liveName
                            font.pixelSize: 17
                            font.variableAxes: ({ "wght": 750, "wdth": 100, "ROND": 0 })
                            color: Appearance.colors.colOnLayer1
                        }

                        Rectangle {
                            implicitWidth: keyStatusText.implicitWidth + 14
                            implicitHeight: 22
                            radius: Appearance.rounding.full
                            color: card.hasCmd ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2

                            StyledText {
                                id: keyStatusText
                                anchors.centerIn: parent
                                text: card.hasCmd ? Translation.tr("Ready") : Translation.tr("Needs command")
                                font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                font.weight: Font.DemiBold
                                color: card.hasCmd ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: card.hasCmd ? `$ ${cmdField.text}` : Translation.tr("Enter a bash command below to publish this key")
                    }
                }

                // Controls: Test run, Move Up/Down, Icon picker, Delete
                RowLayout {
                    spacing: 6

                    RippleButtonWithIcon {
                        enabled: card.hasCmd
                        materialIcon: card.justRan ? "check" : "play_arrow"
                        mainText: card.justRan ? Translation.tr("Ran") : Translation.tr("Test")
                        buttonRadius: Appearance.rounding.full
                        colBackground: card.justRan ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                        colBackgroundHover: card.justRan ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                        colText: card.justRan ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        onClicked: {
                            Quickshell.execDetached(["bash", "-c", String(cmdField.text)]);
                            card.justRan = true;
                            ranResetTimer.restart();
                        }
                    }

                    RippleButtonWithIcon {
                        enabled: card.commandIndex > 0
                        materialIcon: "keyboard_arrow_up"
                        mainText: ""
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colText: Appearance.colors.colOnLayer2
                        onClicked: section.moveCommand(card.commandIndex, card.commandIndex - 1)
                        StyledToolTip { text: Translation.tr("Move up") }
                    }

                    RippleButtonWithIcon {
                        enabled: card.commandIndex < card.totalCount - 1
                        materialIcon: "keyboard_arrow_down"
                        mainText: ""
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colText: Appearance.colors.colOnLayer2
                        onClicked: section.moveCommand(card.commandIndex, card.commandIndex + 1)
                        StyledToolTip { text: Translation.tr("Move down") }
                    }

                    RippleButtonWithIcon {
                        materialIcon: "delete"
                        mainText: ""
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colText: Appearance.colors.colOnLayer2
                        onClicked: section.removeCommand(card.commandIndex)
                        StyledToolTip { text: Translation.tr("Remove command") }
                    }
                }
            }

            // ── Editor Plate (tonal inner plate, zero borders) ──────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: editorCol.implicitHeight + 24
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0

                ColumnLayout {
                    id: editorCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        MaterialTextField {
                            id: nameField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Key label")
                            text: card.command?.name ?? ""
                            onEditingFinished: card.commit("name", text.trim())
                        }

                        MaterialTextField {
                            id: iconField
                            Layout.preferredWidth: 180
                            placeholderText: Translation.tr("Material Symbol")
                            text: card.command?.icon ?? ""
                            onEditingFinished: card.commit("icon", text.trim())
                        }

                        RippleButtonWithIcon {
                            materialIcon: card.iconPickerOpen ? "expand_less" : "palette"
                            mainText: Translation.tr("Icons")
                            buttonRadius: Appearance.rounding.full
                            colBackground: card.iconPickerOpen ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                            colText: card.iconPickerOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            onClicked: card.iconPickerOpen = !card.iconPickerOpen
                        }
                    }

                    // Expandable 1-click Material Symbol icon picker
                    Flow {
                        Layout.fillWidth: true
                        visible: card.iconPickerOpen
                        spacing: 6

                        Repeater {
                            model: card.quickIcons

                            delegate: Rectangle {
                                id: iconChip
                                required property string modelData
                                readonly property bool chosen: card.liveIcon === modelData
                                implicitWidth: 34
                                implicitHeight: 34
                                radius: Appearance.rounding.full
                                color: iconChip.chosen
                                    ? Appearance.colors.colPrimary
                                    : (iconChipHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: iconChip.modelData
                                    iconSize: 18
                                    color: iconChip.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                }

                                RippleButton {
                                    anchors.fill: parent
                                    buttonRadius: parent.radius
                                    colBackground: "transparent"
                                    colBackgroundHover: "transparent"
                                    onClicked: {
                                        iconField.text = iconChip.modelData;
                                        card.commit("icon", iconChip.modelData);
                                    }
                                }

                                HoverHandler {
                                    id: iconChipHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                StyledToolTip {
                                    text: iconChip.modelData
                                }
                            }
                        }
                    }

                    MaterialTextField {
                        id: cmdField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Command, e.g. notify-send hi")
                        font.family: Appearance.font.family.monospace
                        text: card.command?.command ?? ""
                        onEditingFinished: card.commit("command", text)
                    }
                }
            }
        }
    }
}
