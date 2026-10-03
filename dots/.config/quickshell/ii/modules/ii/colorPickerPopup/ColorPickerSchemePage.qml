pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

import "../../common/functions/colorNames.js" as ColorNames

/**
 * The picked color as a whole shell scheme: every Material scheme generated from
 * it at once (scripts/colors/color_overrides.py schemes), a preview drawn in the
 * chosen one, and the two ways out — apply it, or keep it as a custom theme the
 * Colors & Themes page lists under "Custom".
 */
ColumnLayout {
    id: root

    property string seedHex: "#000000"
    signal back

    readonly property var schemeNames: ({
        "scheme-tonal-spot": "Tonal spot",
        "scheme-content": "Content",
        "scheme-fidelity": "Fidelity",
        "scheme-intense": "Intense",
        "scheme-vibrant": "Vibrant",
        "scheme-expressive": "Expressive",
        "scheme-fruit-salad": "Fruit salad",
        "scheme-rainbow": "Rainbow",
        "scheme-neutral": "Neutral",
        "scheme-monochrome": "Monochrome"
    })
    readonly property var schemeOrder: Object.keys(root.schemeNames)

    property var schemes: null
    property string selected: root.schemeOrder.indexOf(Config.options.appearance.palette.type) !== -1
        ? Config.options.appearance.palette.type : "scheme-tonal-spot"
    property bool dark: Appearance.m3colors.darkmode
    readonly property var p: root.schemes?.[root.selected]?.[root.dark ? "dark" : "light"] ?? null

    function roleColor(role: string, fallback: color): color {
        return root.p ? root.p[role] : fallback;
    }

    property bool applied: false
    property string savedName: ""
    property bool saveFailed: false

    spacing: 12

    Process {
        id: schemesProcess
        running: true
        command: ["bash", `${Directories.scriptPath}/colors/color_overrides.sh`, "schemes", "--color", root.seedHex]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.schemes = JSON.parse(this.text);
                } catch (e) {
                    root.schemes = null;
                }
            }
        }
    }
    onSeedHexChanged: {
        root.schemes = null;
        root.applied = false;
        root.savedName = "";
        schemesProcess.running = false;
        schemesProcess.running = true;
    }

    // ── Saving as a custom theme ────────────────────────────────────────
    function themeName(): string {
        const base = `${ColorNames.getColorName(root.seedHex)} ${root.schemeNames[root.selected]}`
            .toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
        const taken = Config.options.appearance.customColorSchemes ?? [];
        let name = base;
        for (let i = 2; taken.indexOf(name) !== -1; i++)
            name = `${base}_${i}`;
        return name;
    }
    property string pendingName: ""
    function save() {
        const name = root.themeName();
        const dir = `${Directories.shellConfig}/themes`;
        root.pendingName = name;
        root.saveFailed = false;
        saveProcess.command = ["bash", `${Directories.scriptPath}/colors/color_overrides.sh`, "theme",
            "--color", root.seedHex, "--scheme", root.selected,
            "--dark", `${dir}/${name}.json`, "--light", `${dir}/${name}_light.json`];
        saveProcess.running = true;
    }
    Process {
        id: saveProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.saveFailed = true;
                return;
            }
            const list = Array.from(Config.options.appearance.customColorSchemes ?? []);
            if (list.indexOf(root.pendingName) === -1)
                list.push(root.pendingName);
            Config.options.appearance.customColorSchemes = list;
            root.savedName = root.pendingName;
        }
    }

    function apply() {
        Config.options.appearance.palette.type = root.selected;
        Config.saveOptionsNow();
        // --type too: switchwall must not race the config write for it.
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch",
            "--mode", root.dark ? "dark" : "light", "--type", root.selected, "--color", root.seedHex]);
        root.applied = true;
        appliedTimer.restart();
    }
    Timer {
        id: appliedTimer
        interval: 2200
        onTriggered: root.applied = false
    }

    // ── Header ──────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        CircleAction {
            symbol: "arrow_back"
            onClicked: root.back()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Color scheme")
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: `${ColorNames.getColorName(root.seedHex)} · ${root.seedHex.toUpperCase()}`
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        // Light / dark preview as a connected pair
        Row {
            spacing: 3
            Repeater {
                model: [{ dark: false, symbol: "light_mode" }, { dark: true, symbol: "dark_mode" }]
                RippleButton {
                    id: modeButton
                    required property var modelData
                    required property int index
                    readonly property bool current: root.dark === modeButton.modelData.dark
                    implicitWidth: 40
                    implicitHeight: 36
                    topLeftRadius: modeButton.index === 0 || modeButton.current ? height / 2 : Appearance.rounding.verysmall
                    bottomLeftRadius: topLeftRadius
                    topRightRadius: modeButton.index === 1 || modeButton.current ? height / 2 : Appearance.rounding.verysmall
                    bottomRightRadius: topRightRadius
                    colBackground: modeButton.current ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: modeButton.current ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    colRipple: modeButton.current ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
                    onClicked: root.dark = modeButton.modelData.dark
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: modeButton.modelData.symbol
                        iconSize: 18
                        fill: modeButton.current ? 1 : 0
                        color: modeButton.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    // ── Preview in the chosen scheme ────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 120
        radius: Appearance.rounding.large
        color: root.roleColor("surface", Appearance.colors.colLayer2)
        border.width: 1
        border.color: root.roleColor("outline_variant", "transparent")

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialLoadingIndicator {
            anchors.centerIn: parent
            visible: root.schemes === null
            loading: visible
            implicitSize: 40
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            visible: root.p !== null

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    text: "palette"
                    iconSize: 20
                    padding: 8
                    fill: 1
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: root.roleColor("primary_container", "transparent")
                    colSymbol: root.roleColor("on_primary_container", "transparent")
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.schemeNames[root.selected]
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: root.roleColor("on_surface", "transparent")
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.dark ? qsTr("Dark") : qsTr("Light")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.roleColor("on_surface_variant", "transparent")
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                PreviewPill { label: qsTr("Primary"); fillRole: "primary"; textRole: "on_primary" }
                PreviewPill { label: qsTr("Secondary"); fillRole: "secondary_container"; textRole: "on_secondary_container" }
                PreviewPill { label: qsTr("Tertiary"); fillRole: "tertiary_container"; textRole: "on_tertiary_container" }
            }
        }
    }

    // ── Schemes ─────────────────────────────────────────────────────────
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 6
        rowSpacing: 6

        Repeater {
            model: root.schemeOrder

            RippleButton {
                id: option
                required property string modelData
                readonly property bool chosen: root.selected === option.modelData
                readonly property var colors: root.schemes?.[option.modelData]?.[root.dark ? "dark" : "light"] ?? null

                Layout.fillWidth: true
                implicitHeight: 40
                buttonRadius: option.chosen ? height / 2 : Appearance.rounding.normal
                colBackground: option.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: option.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                colRipple: option.chosen ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active
                onClicked: root.selected = option.modelData

                contentItem: RowLayout {
                    spacing: 8

                    Row {
                        Layout.leftMargin: 4
                        spacing: -5
                        Repeater {
                            model: ["primary", "secondary", "tertiary"]
                            Rectangle {
                                required property string modelData
                                width: 16
                                height: 16
                                radius: 8
                                color: option.colors ? option.colors[modelData] : Appearance.colors.colLayer3
                                border.width: 1.5
                                border.color: option.colBackground
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.schemeNames[option.modelData]
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: option.chosen ? Font.DemiBold : Font.Normal
                        color: option.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Actions ─────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ActionButton {
            Layout.fillWidth: true
            enabled: root.schemes !== null && !saveProcess.running
            symbol: root.savedName.length > 0 ? "check" : root.saveFailed ? "error" : "bookmark_add"
            label: root.savedName.length > 0 ? qsTr("Saved to themes")
                : root.saveFailed ? qsTr("Could not save") : qsTr("Save as theme")
            filled: false
            onClicked: root.save()
        }
        ActionButton {
            Layout.fillWidth: true
            enabled: root.schemes !== null
            symbol: root.applied ? "check" : "format_color_fill"
            label: root.applied ? qsTr("Applied") : qsTr("Apply")
            filled: true
            onClicked: root.apply()
        }
    }

    // ── Pieces ──────────────────────────────────────────────────────────
    component PreviewPill: Rectangle {
        id: pill
        property string label
        property string fillRole
        property string textRole
        Layout.fillWidth: true
        implicitHeight: 32
        radius: height / 2
        color: root.roleColor(pill.fillRole, "transparent")
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        StyledText {
            anchors.centerIn: parent
            width: parent.width - 12
            horizontalAlignment: Text.AlignHCenter
            text: pill.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: root.roleColor(pill.textRole, "transparent")
            elide: Text.ElideRight
        }
    }

    component CircleAction: RippleButton {
        id: circle
        property string symbol
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: height / 2
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: circle.symbol
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }

    component ActionButton: RippleButton {
        id: action
        property string symbol
        property string label
        property bool filled: false
        implicitHeight: 44
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.normal
        colBackground: action.filled ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colBackgroundHover: action.filled ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colRipple: action.filled ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
        opacity: action.enabled ? 1 : 0.5

        contentItem: Item {
            implicitWidth: actionRow.implicitWidth
            RowLayout {
                id: actionRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: action.symbol
                    iconSize: 18
                    fill: 1
                    color: action.filled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    text: action.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: action.filled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }
}
