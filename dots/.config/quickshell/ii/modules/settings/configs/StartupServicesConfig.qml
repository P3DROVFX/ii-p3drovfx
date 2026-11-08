import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.startup
import qs.services

/**
 * Startup & Services. What runs when the session starts, in two halves picked by the hero
 * tiles (each tile is also its half's live summary):
 *
 *  - Startup: the exec lines of ~/.config/hypr/custom/execs.lua as cards — on/off is the line
 *    commented out or not, so the file stays as readable as one written by hand. Adding an
 *    app, a script/file or a command goes through startup/StartupEditConfig.qml.
 *  - Services: systemd units of the session and of the system, "Yours" first (unit files put
 *    by hand), with start/stop and start-at-boot inline; a row opens the unit's page.
 *
 * Backend: scripts/startup/ii-startup.py through services/StartupManager.qml.
 */
Item {
    id: startupConfigRoot

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    // "startup" | "services"
    property string tab: "startup"
    property string scope: "user"
    property string filter: "yours"
    property string query: ""
    property int shownLimit: 60

    function open(url) {
        startupConfigRoot.activeSubPage = Qt.resolvedUrl(url);
    }
    function openEntry(entry) {
        if (entry && !entry.editable) {
            StartupManager.openInEditor(StartupManager.execsPath);
            return;
        }
        StartupManager.editTarget = entry;
        StartupManager.addPreset = null;
        open("startup/StartupEditConfig.qml");
    }
    function addFrom(preset) {
        StartupManager.editTarget = null;
        StartupManager.addPreset = preset;
        open("startup/StartupEditConfig.qml");
    }
    function openUnit(name) {
        StartupManager.showUnit(startupConfigRoot.scope, name);
        open("startup/ServiceDetailConfig.qml");
    }
    function refreshAll() {
        StartupManager.refreshExecs();
        StartupManager.refreshUnits("user");
        StartupManager.refreshUnits("system");
    }

    Component.onCompleted: refreshAll()
    // back from a sub-page: what it changed (or what changed meanwhile) shows up
    onActiveSubPageChanged: if (activeSubPage.toString() === "") refreshAll()

    // ── derived ──
    readonly property var allUnits: StartupManager.userUnits.concat(StartupManager.systemUnits)
    readonly property int failedCount: allUnits.filter(u => u.active === "failed").length
    readonly property int mineCount: allUnits.filter(u => u.mine).length
    readonly property int mineRunning: allUnits.filter(u => u.mine && u.active === "active").length

    readonly property var scopeUnits: StartupManager.unitsFor(startupConfigRoot.scope)
    function matchesFilter(u, f) {
        switch (f) {
        case "yours": return u.mine || u.overridden;
        case "running": return u.active === "active" || u.active === "activating";
        case "failed": return u.active === "failed";
        case "off": return u.fileState === "disabled";
        default: return true;
        }
    }
    function countFor(f) {
        return startupConfigRoot.scopeUnits.filter(u => matchesFilter(u, f)).length;
    }
    readonly property var visibleUnits: {
        const q = startupConfigRoot.query.trim().toLowerCase();
        return startupConfigRoot.scopeUnits.filter(u => matchesFilter(u, startupConfigRoot.filter)
            && (q === "" || u.name.toLowerCase().includes(q) || (u.description ?? "").toLowerCase().includes(q)));
    }
    onFilterChanged: shownLimit = 60
    onQueryChanged: shownLimit = 60
    onScopeChanged: shownLimit = 60

    // autostart .desktop entries Hyprland never runs, minus the ones already added
    readonly property var strayAutostart: StartupManager.autostart.filter(a =>
        !StartupManager.entries.some(e => e.command.includes(a.command)))

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // ── hero: the two halves, each with its live summary ──
        Item {
            id: hero
            Layout.fillWidth: true
            readonly property bool stacked: width < 400
            implicitHeight: stacked ? 132 * 2 + 10 : 132

            SummaryTile {
                id: startupTile
                x: 0
                y: 0
                width: hero.stacked ? hero.width : (hero.width - 10) / 2
                symbol: "rocket_launch"
                shape: MaterialShape.Shape.Cookie9Sided
                title: Translation.tr("Startup")
                count: StartupManager.execsLoaded ? String(StartupManager.enabledCount) : "–"
                caption: StartupManager.entries.length === 0
                    ? Translation.tr("Nothing of yours starts with Hyprland yet")
                    : Translation.tr("%1 of %2 start with Hyprland").arg(StartupManager.enabledCount).arg(StartupManager.entries.length)
                chosen: startupConfigRoot.tab === "startup"
                onClicked: startupConfigRoot.tab = "startup"
            }
            SummaryTile {
                x: hero.stacked ? 0 : startupTile.width + 10
                y: hero.stacked ? 142 : 0
                width: startupTile.width
                symbol: "settings_suggest"
                shape: MaterialShape.Shape.Clover4Leaf
                title: Translation.tr("Services")
                count: StartupManager.userLoaded ? String(startupConfigRoot.mineCount) : "–"
                caption: Translation.tr("Yours, %1 running · session and system").arg(startupConfigRoot.mineRunning)
                alert: startupConfigRoot.failedCount > 0 ? Translation.tr("%1 failed").arg(startupConfigRoot.failedCount) : ""
                chosen: startupConfigRoot.tab === "services"
                onClicked: startupConfigRoot.tab = "services"
            }
        }

        // ── last error from the helper ──
        Rectangle {
            Layout.fillWidth: true
            visible: StartupManager.lastError !== ""
            implicitHeight: errorRow.implicitHeight + 20
            radius: Appearance.rounding.large
            color: Appearance.colors.colErrorContainer
            RowLayout {
                id: errorRow
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 8
                spacing: 10
                MaterialSymbol {
                    text: "error"
                    iconSize: 20
                    color: Appearance.colors.colOnErrorContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: StartupManager.lastError
                    color: Appearance.colors.colOnErrorContainer
                    wrapMode: Text.WordWrap
                }
                CircleAction {
                    symbol: "close"
                    colContent: Appearance.colors.colOnErrorContainer
                    colFill: "transparent"
                    onClicked: StartupManager.lastError = ""
                }
            }
        }

        // ════════════════════════ Startup ════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: startupConfigRoot.tab === "startup"
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr("At login")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge + 8
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Kept in hypr/custom/execs.lua, which updates never overwrite. Off comments the line out.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }

                CircleAction {
                    symbol: "description"
                    tip: Translation.tr("Open execs.lua")
                    size: 40
                    colFill: Appearance.colors.colSecondaryContainer
                    colContent: Appearance.colors.colOnSecondaryContainer
                    onClicked: StartupManager.openInEditor(StartupManager.execsPath)
                }

                RippleButton {
                    implicitHeight: 40
                    implicitWidth: addRow.implicitWidth + 32
                    buttonRadius: height / 2
                    buttonRadiusPressed: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: startupConfigRoot.openEntry(null)
                    contentItem: Item {
                        RowLayout {
                            id: addRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "add"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: Translation.tr("Add")
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }

            Grid {
                id: cardGrid
                Layout.fillWidth: true
                visible: StartupManager.entries.length > 0
                spacing: 10
                readonly property int maxCols: Math.max(1, Math.floor((width + spacing) / (280 + spacing)))
                columns: Math.min(maxCols, 3)
                readonly property real cardWidth: (width - spacing * (columns - 1)) / columns
                readonly property var shapes: [MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Sunny,
                    MaterialShape.Shape.Clover4Leaf, MaterialShape.Shape.Flower, MaterialShape.Shape.SoftBurst,
                    MaterialShape.Shape.Cookie12Sided]

                Repeater {
                    model: StartupManager.entries
                    delegate: StartupEntryCard {
                        required property var modelData
                        required property int index
                        entry: modelData
                        width: cardGrid.cardWidth
                        height: 156
                        shape: cardGrid.shapes[index % cardGrid.shapes.length]
                        onEditRequested: startupConfigRoot.openEntry(modelData)
                    }
                }
            }

            // empty: an invitation, not a blank space
            RippleButton {
                id: invite
                Layout.fillWidth: true
                visible: StartupManager.execsLoaded && StartupManager.entries.length === 0
                implicitHeight: 120
                buttonRadius: Appearance.rounding.verylarge
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: startupConfigRoot.openEntry(null)
                contentItem: RowLayout {
                    spacing: 16
                    Item { implicitWidth: 6 }
                    MaterialShapeWrappedMaterialSymbol {
                        text: "add"
                        iconSize: 28
                        padding: 14
                        shape: invite.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie7Sided
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            text: Translation.tr("Start something with your session")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("An app, a script or AppImage, or any command")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ── ~/.config/autostart: what other desktops would start ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                visible: startupConfigRoot.strayAutostart.length > 0
                spacing: 8

                ColumnLayout {
                    Layout.leftMargin: 4
                    spacing: 0
                    StyledText {
                        text: Translation.tr("Not started by Hyprland")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Autostart entries in ~/.config/autostart. GNOME and KDE run these, Hyprland does not. Add one to start it here.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: startupConfigRoot.strayAutostart
                        delegate: ColorsChip {
                            required property var modelData
                            symbol: "add"
                            label: modelData.name
                            onClicked: startupConfigRoot.addFrom({ name: modelData.name, command: modelData.command })
                            StyledToolTip {
                                text: modelData.command
                            }
                        }
                    }
                }
            }
        }

        // ════════════════════════ Services ════════════════════════
        ColumnLayout {
            id: servicesPane
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: startupConfigRoot.tab === "services"
            spacing: 12

            // scope + search: side by side, stacked when narrow
            Item {
                id: controls
                Layout.fillWidth: true
                readonly property bool stacked: width < 620
                implicitHeight: stacked ? 48 * 2 + 8 : 48

                ConnectedToggle {
                    id: scopeToggle
                    x: 0
                    y: 0
                    width: controls.stacked ? controls.width : 320
                    current: startupConfigRoot.scope
                    model: [
                        { key: "user", label: Translation.tr("Session"), symbol: "person", shape: MaterialShape.Shape.Cookie9Sided },
                        { key: "system", label: Translation.tr("System"), symbol: "computer", shape: MaterialShape.Shape.Clover4Leaf }
                    ]
                    onSelected: key => startupConfigRoot.scope = key
                }

                Rectangle {
                    x: controls.stacked ? 0 : scopeToggle.width + 10
                    y: controls.stacked ? 56 : 0
                    width: controls.stacked ? controls.width : controls.width - scopeToggle.width - 10
                    height: 48
                    radius: height / 2
                    color: Appearance.colors.colLayer1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 6
                        spacing: 10
                        MaterialSymbol {
                            text: "search"
                            iconSize: 20
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledTextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            clip: true
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                            onTextChanged: startupConfigRoot.query = text
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: searchInput.text.length === 0
                                text: Translation.tr("Search units")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        CircleAction {
                            visible: searchInput.text.length > 0
                            symbol: "close"
                            colFill: "transparent"
                            onClicked: searchInput.text = ""
                        }
                        CircleAction {
                            symbol: "refresh"
                            tip: Translation.tr("Refresh")
                            colFill: "transparent"
                            onClicked: StartupManager.refreshUnits(startupConfigRoot.scope)
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        { key: "yours", label: Translation.tr("Yours"), symbol: "person_edit" },
                        { key: "running", label: Translation.tr("Running"), symbol: "play_circle" },
                        { key: "failed", label: Translation.tr("Failed"), symbol: "error" },
                        { key: "off", label: Translation.tr("Off at boot"), symbol: "block" },
                        { key: "all", label: Translation.tr("All"), symbol: "list" }
                    ]
                    delegate: ColorsChip {
                        required property var modelData
                        symbol: modelData.symbol
                        label: modelData.label
                        count: startupConfigRoot.countFor(modelData.key)
                        chosen: startupConfigRoot.filter === modelData.key
                        onClicked: startupConfigRoot.filter = modelData.key
                    }
                }
            }

            Grid {
                id: unitGrid
                Layout.fillWidth: true
                spacing: 6
                columns: width >= 860 ? 2 : 1
                readonly property real rowWidth: (width - spacing * (columns - 1)) / columns

                Repeater {
                    model: startupConfigRoot.visibleUnits.slice(0, startupConfigRoot.shownLimit)
                    delegate: ServiceRow {
                        required property var modelData
                        unit: modelData
                        scope: startupConfigRoot.scope
                        width: unitGrid.rowWidth
                        onOpenRequested: startupConfigRoot.openUnit(modelData.name)
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 12
                visible: startupConfigRoot.visibleUnits.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: !(startupConfigRoot.scope === "user" ? StartupManager.userLoaded : StartupManager.systemLoaded)
                    ? Translation.tr("Reading units…")
                    : startupConfigRoot.filter === "yours" && startupConfigRoot.query === ""
                        ? Translation.tr("No unit files of yours here. Units you write go in %1.")
                            .arg(startupConfigRoot.scope === "user" ? "~/.config/systemd/user" : "/etc/systemd/system")
                        : Translation.tr("Nothing matches")
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                visible: startupConfigRoot.visibleUnits.length > startupConfigRoot.shownLimit
                implicitHeight: 40
                implicitWidth: moreText.implicitWidth + 36
                buttonRadius: height / 2
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: startupConfigRoot.shownLimit += 120
                contentItem: Item {
                    StyledText {
                        id: moreText
                        anchors.centerIn: parent
                        text: Translation.tr("Show %1 more").arg(Math.min(120, startupConfigRoot.visibleUnits.length - startupConfigRoot.shownLimit))
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
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
