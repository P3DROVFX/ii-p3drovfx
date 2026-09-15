pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    readonly property int surfaceWidth: Config.options.akebono.runner.glyphPickerWidth
    readonly property int surfaceHeight: Config.options.akebono.runner.glyphPickerHeight
    readonly property real contentScale: Config.options.akebono.runner.glyphPickerScale / 100
    readonly property int glyphSize: Math.round(Appearance.font.pixelSize.huge * root.contentScale)
    readonly property int fieldHeight: Math.round(root.glyphSize * 1.5)
    readonly property int contentMargin: Math.round(root.glyphSize * 0.45)
    readonly property int screenMargin: 8

    property real cursorX: 0
    property real cursorY: 0
    property bool cursorKnown: false

    readonly property string activeScreen: {
        const x = root.cursorX;
        const y = root.cursorY;
        const hit = Quickshell.screens.find(s => {
            const g = s.geometry;
            return x >= g.x && x < g.x + g.width && y >= g.y && y < g.y + g.height;
        });
        return hit ? hit.name : (Quickshell.primaryScreen?.name ?? "");
    }

    readonly property bool shown: GlobalStates.desktopGlyphPickerOpen && root.cursorKnown
    onShownChanged: {
        if (!root.shown)
            exitTimer.restart();
    }

    Timer {
        id: exitTimer
        interval: Appearance.animation.elementMoveFast.duration
    }

    function close(): void {
        GlobalStates.desktopGlyphPickerOpen = false;
    }

    Connections {
        target: GlobalStates
        function onDesktopGlyphPickerOpenChanged() {
            if (GlobalStates.desktopGlyphPickerOpen)
                cursorProc.running = true;
            else
                root.cursorKnown = false;
        }
        function onDesktopRunnerOpenChanged() {
            if (GlobalStates.desktopRunnerOpen)
                root.close();
        }
    }

    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split(",");
                root.cursorX = parseInt(parts[0]) || 0;
                root.cursorY = parseInt(parts[1]) || 0;
                root.cursorKnown = true;
            }
        }
    }

    IpcHandler {
        target: "akebonoGlyphPicker"
        function toggle(): void { GlobalStates.desktopGlyphPickerOpen = !GlobalStates.desktopGlyphPickerOpen }
        function open(): void { GlobalStates.desktopGlyphPickerOpen = true }
        function close(): void { root.close() }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData

            Loader {
                active: (root.shown || exitTimer.running) && root.activeScreen === screenScope.modelData.name

                sourceComponent: PanelWindow {
                    id: pickerWindow
                    screen: screenScope.modelData
                    visible: !GlobalStates.screenLocked
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.namespace: "quickshell:akebonoGlyphPicker"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }

                    Squircle {
                        id: surface
                        x: Math.max(root.screenMargin, Math.min(root.cursorX - screenScope.modelData.x, pickerWindow.width - root.surfaceWidth - root.screenMargin))
                        y: Math.max(root.screenMargin, Math.min(root.cursorY - screenScope.modelData.y, pickerWindow.height - root.surfaceHeight - root.screenMargin))
                        implicitWidth: root.surfaceWidth
                        implicitHeight: root.surfaceHeight
                        color: Appearance.colors.colLayer0
                        radius: Appearance.rounding.normal
                        smoothing: AkebonoAppearance.squircleSmoothing

                        readonly property string query: searchInput.text
                        readonly property var source: LauncherSearch.glyphSourceFor(surface.query) ?? LauncherSearch.glyphSources[0]
                        readonly property var entries: LauncherSearch.glyphEntries(surface.query, surface.source)

                        property bool revealed: false
                        opacity: surface.revealed && root.shown ? 1 : 0
                        layer.enabled: surface.opacity < 1
                        layer.smooth: true

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        Component.onCompleted: {
                            surface.revealed = true;
                            searchInput.forceActiveFocus();
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.contentMargin
                            spacing: Math.round(root.contentMargin * 0.8)

                            Squircle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.fieldHeight
                                color: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                smoothing: AkebonoAppearance.squircleSmoothing

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "mood"
                                        iconSize: Math.round(Appearance.font.pixelSize.large * root.contentScale)
                                        color: Appearance.colors.colSubtext
                                    }

                                    ToolbarTextField {
                                        id: searchInput
                                        Layout.fillWidth: true
                                        colBackground: "transparent"
                                        font.pixelSize: Math.round(Appearance.font.pixelSize.small * root.contentScale)
                                        placeholderText: Translation.tr("Emoji, %1 symbols, %2 kaomoji").arg(Config.options.search.prefix.symbols).arg(Config.options.search.prefix.kaomojis)

                                        onAccepted: {
                                            if (surface.entries.length > 0)
                                                glyphGrid.chosen(surface.entries[0].glyph);
                                        }
                                        Keys.onPressed: event => {
                                            if (event.key === Qt.Key_Escape) {
                                                root.close();
                                                event.accepted = true;
                                            } else if (event.key === Qt.Key_Down) {
                                                glyphGrid.currentIndex = 0;
                                                glyphGrid.forceActiveFocus();
                                                event.accepted = true;
                                            }
                                        }
                                    }
                                }
                            }

                            GlyphGrid {
                                id: glyphGrid
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                entries: surface.entries
                                listMode: LauncherSearch.glyphListMode(surface.query, surface.source)
                                cellSize: root.glyphSize * 2
                                cellAspect: root.glyphSize * 2 - 2
                                glyphSize: root.glyphSize

                                onChosen: glyph => {
                                    Quickshell.clipboardText = glyph;
                                    root.close();
                                }
                                onDismissRequested: root.close()
                                onTopEdgeReached: searchInput.forceActiveFocus()
                                onBackspaceRequested: {
                                    searchInput.forceActiveFocus();
                                    searchInput.text = searchInput.text.slice(0, -1);
                                }
                                onTextTyped: text => {
                                    searchInput.forceActiveFocus();
                                    searchInput.text += text;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
