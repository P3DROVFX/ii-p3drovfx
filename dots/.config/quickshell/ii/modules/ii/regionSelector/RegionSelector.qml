pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    // Bumped on every open so grim starts before (or while) the overlay tree
    // is created, instead of waiting for RegionSelection to finish loading.
    property int captureToken: 0

    function beginCapture() {
        root.captureToken += 1
    }

    function openSelector() {
        root.beginCapture()
        GlobalStates.regionSelectorOpen = true
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: monitorScope
            required property var modelData

            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(monitorScope.modelData)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
            readonly property bool monitorWantsSelector: !Config.options.regionSelector.showOnlyOnFocusedMonitor || monitorIsFocused
            // Keep the overlay tree after the first open so later screenshots
            // only wait on grim, not on rebuilding ~2k lines of QML.
            property bool stickyLoaded: false

            TempScreenshotProcess {
                id: captureProc
                running: false
                screen: monitorScope.modelData
                screenshotDir: Directories.screenshotTemp
                format: "ppm"
                screenshotPath: `${Directories.screenshotTemp}/image-${monitorScope.modelData.name}.ppm`
            }

            Connections {
                target: root
                function onCaptureTokenChanged() {
                    if (!monitorScope.monitorWantsSelector)
                        return
                    captureProc.recapture(root.captureToken)
                }
            }

            Loader {
                id: regionSelectorLoader
                active: (GlobalStates.regionSelectorOpen && monitorScope.monitorWantsSelector) || monitorScope.stickyLoaded
                asynchronous: !GlobalStates.regionSelectorOpen
                onLoaded: monitorScope.stickyLoaded = true

                sourceComponent: RegionSelection {
                    screen: monitorScope.modelData
                    screenshotPath: captureProc.screenshotPath
                    captureReady: captureProc.completed && captureProc.startedToken === root.captureToken
                    captureToken: root.captureToken
                    onDismiss: root.dismiss()
                    action: root.action
                    selectionMode: root.selectionMode
                }
            }
        }
    }

    function screenshot() {
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        root.openSelector()
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function record() {
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function recordWithSound() {
        root.action = RegionSelection.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function edit() {
        root.action = RegionSelection.SnipAction.Edit
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    /** Grabs a region and attaches it to the chat. */
    function askAi() {
        root.action = RegionSelection.SnipAction.AskAI
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    Connections {
        target: GlobalStates
        function onSnipForAiRequested() {
            root.askAi();
        }
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        function edit() {
            root.edit()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function askAi() {
            root.askAi()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}
