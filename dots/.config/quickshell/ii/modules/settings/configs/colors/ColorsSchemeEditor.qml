pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Hand-picked key colors on top of the generated scheme. The user changes one of
 * the four key colors — primary, secondary, tertiary, surface — and
 * scripts/colors/color_overrides.py rebuilds the roles that belong to it
 * (containers, "on" colors, the surface ladder) when switchwall regenerates.
 * Overrides are kept per mode, in appearance.palette.overrides.<mode>.
 */
ColumnLayout {
    id: root

    property real availableWidth: width
    readonly property bool wide: root.availableWidth >= 640

    /// The mode switchwall generates for; gsettings is what it reads too.
    property string mode: Appearance.m3colors.darkmode ? "dark" : "light"
    readonly property var overrides: Config.options.appearance.palette.overrides[root.mode]

    readonly property var roles: [
        { key: "primary", label: Translation.tr("Primary"), shape: MaterialShape.Shape.Cookie9Sided },
        { key: "secondary", label: Translation.tr("Secondary"), shape: MaterialShape.Shape.Cookie7Sided },
        { key: "tertiary", label: Translation.tr("Tertiary"), shape: MaterialShape.Shape.Clover4Leaf },
        { key: "surface", label: Translation.tr("Surface"), shape: MaterialShape.Shape.Square }
    ]
    property string selectedRole: "primary"
    readonly property var selectedInfo: root.roles.find(r => r.key === root.selectedRole)

    function liveColor(role: string): color {
        return Appearance.m3colors["m3" + role];
    }
    function hexOf(c: color): string {
        const s = String(c);
        return (s.length === 9 ? "#" + s.slice(3) : s).toUpperCase();
    }
    function isCustom(role: string): bool {
        return String(root.overrides?.[role] ?? "").length > 0;
    }
    readonly property int customCount: root.roles.filter(r => root.isCustom(r.key)).length

    readonly property var families: ({
        primary: [["Primary", "m3primary"], ["On primary", "m3onPrimary"], ["Container", "m3primaryContainer"],
            ["On container", "m3onPrimaryContainer"], ["Fixed", "m3primaryFixed"], ["Fixed dim", "m3primaryFixedDim"]],
        secondary: [["Secondary", "m3secondary"], ["On secondary", "m3onSecondary"], ["Container", "m3secondaryContainer"],
            ["On container", "m3onSecondaryContainer"], ["Fixed", "m3secondaryFixed"], ["Fixed dim", "m3secondaryFixedDim"]],
        tertiary: [["Tertiary", "m3tertiary"], ["On tertiary", "m3onTertiary"], ["Container", "m3tertiaryContainer"],
            ["On container", "m3onTertiaryContainer"], ["Fixed", "m3tertiaryFixed"], ["Fixed dim", "m3tertiaryFixedDim"]],
        surface: [["Lowest", "m3surfaceContainerLowest"], ["Surface", "m3surface"], ["Low", "m3surfaceContainerLow"],
            ["Container", "m3surfaceContainer"], ["High", "m3surfaceContainerHigh"], ["Highest", "m3surfaceContainerHighest"],
            ["On surface", "m3onSurface"], ["Outline", "m3outline"]]
    })

    // ── Draft: what the picker shows, kept as HSV so hue survives grey ──
    property real draftHue: 0
    property real draftSat: 0
    property real draftVal: 0
    readonly property color draftColor: Qt.hsva(root.draftHue, root.draftSat, root.draftVal, 1)
    property bool editing: false

    function syncDraft() {
        if (root.editing || applier.busy)
            return;
        const c = root.liveColor(root.selectedRole);
        root.setDraft(c);
    }
    function setDraft(c: color) {
        if (c.hsvHue >= 0)
            root.draftHue = c.hsvHue;
        root.draftSat = c.hsvSaturation;
        root.draftVal = c.hsvValue;
    }
    onSelectedRoleChanged: {
        root.editing = false;
        root.syncDraft();
    }
    Component.onCompleted: root.syncDraft()
    Connections {
        target: Appearance.m3colors
        function onM3primaryChanged() { root.syncDraft(); }
        function onM3secondaryChanged() { root.syncDraft(); }
        function onM3tertiaryChanged() { root.syncDraft(); }
        function onM3surfaceChanged() { root.syncDraft(); }
    }

    // ── Applying ────────────────────────────────────────────────────────
    function commit(role: string, hex: string) {
        Config.options.appearance.palette.overrides[root.mode][role] = hex;
        applier.request();
    }
    function resetRole(role: string) {
        root.editing = false;
        root.commit(role, "");
    }
    function resetAll() {
        root.editing = false;
        for (const r of root.roles)
            Config.options.appearance.palette.overrides[root.mode][r.key] = "";
        applier.request();
    }

    QtObject {
        id: applier
        property bool pending: false
        readonly property bool busy: applyProcess.running || saveDelay.running || pending

        function request() {
            Config.saveOptionsNow();
            // Let the atomic write land before switchwall reads the file.
            saveDelay.restart();
        }
    }
    Timer {
        id: saveDelay
        interval: 200
        onTriggered: {
            if (applyProcess.running) {
                applier.pending = true;
                return;
            }
            applyProcess.running = true;
        }
    }
    Process {
        id: applyProcess
        command: [Directories.wallpaperSwitchScriptPath, "--noswitch", "--mode", root.mode]
        onExited: {
            if (applier.pending) {
                applier.pending = false;
                applyProcess.running = true;
                return;
            }
            root.editing = false;
            root.syncDraft();
        }
    }
    Timer {
        id: commitDelay
        interval: 350
        onTriggered: root.commit(root.selectedRole, root.hexOf(root.draftColor))
    }
    function scheduleCommit() {
        root.editing = true;
        commitDelay.restart();
    }

    Process {
        id: modeProcess
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim();
                if (value.length > 0)
                    root.mode = value.indexOf("dark") !== -1 ? "dark" : "light";
            }
        }
    }
    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() { modeProcess.running = true; }
    }

    Process {
        id: eyedropper
        command: ["bash", "-c", "sleep 0.15; hyprpicker -f hex"]
        stdout: StdioCollector {
            onStreamFinished: {
                const hex = this.text.trim();
                if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
                    root.setDraft(Qt.color(hex));
                    root.editing = true;
                    root.commit(root.selectedRole, hex.toUpperCase());
                }
            }
        }
    }

    spacing: 12

    // ── Key colors ──────────────────────────────────────────────────────
    GridLayout {
        Layout.fillWidth: true
        columns: root.availableWidth >= 520 ? 4 : 2
        columnSpacing: 8
        rowSpacing: 8

        Repeater {
            model: root.roles

            RoleTile {}
        }
    }

    // ── Editor slab ─────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: editorGrid.implicitHeight + 32
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        GridLayout {
            id: editorGrid
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
            }
            columns: root.wide ? 2 : 1
            columnSpacing: 20
            rowSpacing: 16

            // Saturation/value field + hue bar
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wide ? 1 : -1
                Layout.alignment: Qt.AlignTop
                spacing: 12

                Item {
                    id: svField
                    Layout.fillWidth: true
                    implicitHeight: 196

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#ffffff" }
                            GradientStop { position: 1; color: Qt.hsva(root.draftHue, 1, 1, 1) }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: "#000000" }
                        }
                    }
                    Thumb {
                        x: root.draftSat * svField.width - width / 2
                        y: (1 - root.draftVal) * svField.height - height / 2
                        fillColor: root.draftColor
                        active: svArea.pressed
                    }
                    MouseArea {
                        id: svArea
                        anchors.fill: parent
                        cursorShape: Qt.CrossCursor
                        preventStealing: true
                        function pick(mouse) {
                            root.editing = true;
                            commitDelay.stop();
                            root.draftSat = Math.max(0, Math.min(1, mouse.x / width));
                            root.draftVal = Math.max(0, Math.min(1, 1 - mouse.y / height));
                        }
                        onPressed: mouse => pick(mouse)
                        onPositionChanged: mouse => pick(mouse)
                        onReleased: root.scheduleCommit()
                    }
                }

                Item {
                    id: hueBar
                    Layout.fillWidth: true
                    implicitHeight: 20

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0 / 6; color: "#ff0000" }
                            GradientStop { position: 1 / 6; color: "#ffff00" }
                            GradientStop { position: 2 / 6; color: "#00ff00" }
                            GradientStop { position: 3 / 6; color: "#00ffff" }
                            GradientStop { position: 4 / 6; color: "#0000ff" }
                            GradientStop { position: 5 / 6; color: "#ff00ff" }
                            GradientStop { position: 6 / 6; color: "#ff0000" }
                        }
                    }
                    Thumb {
                        x: root.draftHue * (hueBar.width - hueBar.height) + hueBar.height / 2 - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        fillColor: Qt.hsva(root.draftHue, 1, 1, 1)
                        active: hueArea.pressed
                    }
                    MouseArea {
                        id: hueArea
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true
                        function pick(mouse) {
                            root.editing = true;
                            commitDelay.stop();
                            const span = hueBar.width - hueBar.height;
                            root.draftHue = Math.max(0, Math.min(0.9999, (mouse.x - 6 - hueBar.height / 2) / span));
                        }
                        onPressed: mouse => pick(mouse)
                        onPositionChanged: mouse => pick(mouse)
                        onReleased: root.scheduleCommit()
                    }
                }
            }

            // Value, actions and what the script derived from it
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wide ? 1 : -1
                Layout.alignment: Qt.AlignTop
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    MaterialShape {
                        implicitSize: 56
                        shape: root.selectedInfo?.shape ?? MaterialShape.Shape.Circle
                        color: root.draftColor
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.selectedInfo?.label ?? ""
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: applier.busy ? Translation.tr("Regenerating the scheme…")
                                : root.isCustom(root.selectedRole)
                                    ? Translation.tr("Custom · %1 mode").arg(root.mode === "dark" ? Translation.tr("dark") : Translation.tr("light"))
                                    : Translation.tr("Generated by the scheme")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    MaterialLoadingIndicator {
                        visible: applier.busy
                        implicitSize: 32
                        loading: applier.busy
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        id: hexField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Hex")
                        font.family: Appearance.font.family.monospace
                        text: root.hexOf(root.draftColor)
                        error: text.length > 0 && !/^#?[0-9a-fA-F]{6}$/.test(text.trim())
                        onAccepted: {
                            let value = text.trim();
                            if (!/^#?[0-9a-fA-F]{6}$/.test(value))
                                return;
                            if (!value.startsWith("#"))
                                value = "#" + value;
                            root.setDraft(Qt.color(value));
                            root.editing = true;
                            root.commit(root.selectedRole, value.toUpperCase());
                            hexField.focus = false;
                        }
                    }

                    IconAction {
                        symbol: "colorize"
                        tip: Translation.tr("Pick a color from the screen")
                        onClicked: {
                            eyedropper.running = false;
                            eyedropper.running = true;
                        }
                    }
                    IconAction {
                        symbol: "restart_alt"
                        tip: Translation.tr("Back to the generated color")
                        enabled: root.isCustom(root.selectedRole)
                        onClicked: root.resetRole(root.selectedRole)
                    }
                }

                StyledText {
                    Layout.topMargin: 2
                    text: Translation.tr("Derived from it")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.families[root.selectedRole] ?? []

                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property color swatch: Appearance.m3colors[chip.modelData[1]]
                            implicitWidth: 40
                            implicitHeight: 40
                            radius: Appearance.rounding.small
                            color: chip.swatch
                            border.width: 1
                            border.color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            HoverHandler { id: chipHover }
                            StyledToolTip {
                                extraVisibleCondition: chipHover.hovered
                                text: `${Translation.tr(chip.modelData[0])} · ${root.hexOf(chip.swatch)}`
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Footer ──────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: root.customCount > 0
                ? Translation.tr("%1 of 4 key colors are yours in %2 mode; the rest of the palette follows them.")
                    .arg(root.customCount).arg(root.mode === "dark" ? Translation.tr("dark") : Translation.tr("light"))
                : Translation.tr("Pick a key color and the containers, text colors and surfaces are rebuilt from it.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        ColorsChip {
            visible: root.customCount > 0
            symbol: "restart_alt"
            label: Translation.tr("Reset all")
            onClicked: root.resetAll()
        }
    }

    // ── Pieces ──────────────────────────────────────────────────────────
    component Thumb: Rectangle {
        property color fillColor
        property bool active: false
        width: active ? 26 : 22
        height: width
        radius: width / 2
        color: fillColor
        border.width: 3
        border.color: "#ffffff"

        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    component IconAction: RippleButton {
        id: action
        property string symbol
        property string tip
        implicitWidth: 44
        implicitHeight: 44
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.small
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        opacity: action.enabled ? 1 : 0.4

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: action.symbol
            iconSize: 20
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledToolTip {
            text: action.tip
        }
    }

    component RoleTile: RippleButton {
        id: tile
        required property var modelData
        readonly property bool chosen: root.selectedRole === tile.modelData.key
        readonly property bool custom: root.isCustom(tile.modelData.key)
        readonly property color swatch: root.liveColor(tile.modelData.key)

        Layout.fillWidth: true
        implicitHeight: 76
        buttonRadius: Appearance.rounding.large
        colBackground: tile.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: tile.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
        colRipple: tile.chosen ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active
        onClicked: root.selectedRole = tile.modelData.key

        contentItem: RowLayout {
            spacing: 12

            Item {
                Layout.leftMargin: 6
                implicitWidth: 44
                implicitHeight: 44

                // Ring 2 px off the swatch on the chosen one (settings-expressive §3).
                Rectangle {
                    anchors.centerIn: parent
                    width: 44 + 9
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 2.5
                    border.color: Appearance.colors.colPrimary
                    opacity: tile.chosen ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                MaterialShape {
                    anchors.centerIn: parent
                    implicitSize: 44
                    shape: tile.custom ? tile.modelData.shape : MaterialShape.Shape.Circle
                    color: tile.swatch
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: tile.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: tile.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: tile.custom ? `${root.hexOf(tile.swatch)} · ${Translation.tr("Custom")}` : root.hexOf(tile.swatch)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: tile.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }
    }
}
