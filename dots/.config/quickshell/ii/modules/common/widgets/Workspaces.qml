import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: root.QsWindow.window?.screen?.index ?? 0
    property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0

    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((monitor?.activeWorkspace?.id - root.workspaceOffset - 1) / root.workspacesShown)
    property list<bool> workspaceOccupied: []
    property int workspaceIndexInGroup: dynamicWorkspaces
        ? visibleWorkspaceIds.indexOf(monitor?.activeWorkspace?.id ?? -1)
        : (monitor?.activeWorkspace?.id - root.workspaceOffset - 1) % root.workspacesShown
    property var monitorWindows

    function wsIdAt(index) {
        if (dynamicWorkspaces) return visibleWorkspaceIds[index] ?? -1
        return workspaceOffset + workspaceGroup * workspacesShown + index + 1
    }
    readonly property int classicCount: dynamicWorkspaces ? visibleWorkspaceIds.length : workspacesShown

    property int individualIconBoxHeight: 24
    property int iconBoxWrapperSize: 28
    property int workspaceDotSize: 4
    property real iconRatio: 0.8

    property int dotSize: 19
    property int dotActiveSize: 29
    property int dotSpacing: 8
    property int dotPillPaddingSide: 8
    property int dotPillPaddingLength: 24
    property bool dotPillBackground: true

    property int windowCellLength: 38
    property int windowCellThickness: 27
    property bool showIcons: Config.options.bar.workspaces.showAppIcons
    property bool customAppIcons: Config.options.bar.workspaces.customAppIcons
    property int workspaceStyle: Config.options.bar.workspaces.style
    property bool dynamicWorkspaces: Config.options.bar.workspaces.dynamic

    readonly property var categoryIcons: ({
        WebBrowser: "web",
        Printing: "print",
        Security: "security",
        Network: "chat",
        Archiving: "archive",
        Compression: "archive",
        Development: "code",
        IDE: "code",
        TextEditor: "edit_note",
        Audio: "music_note",
        Music: "music_note",
        Player: "music_note",
        Recorder: "mic",
        Game: "sports_esports",
        FileTools: "files",
        FileManager: "files",
        Filesystem: "files",
        FileTransfer: "files",
        Settings: "settings",
        DesktopSettings: "settings",
        HardwareSettings: "settings",
        TerminalEmulator: "terminal",
        ConsoleOnly: "terminal",
        Utility: "build",
        Monitor: "monitor_heart",
        Midi: "graphic_eq",
        Mixer: "graphic_eq",
        AudioVideoEditing: "video_settings",
        AudioVideo: "music_video",
        Video: "videocam",
        Building: "construction",
        Graphics: "photo_library",
        "2DGraphics": "photo_library",
        RasterGraphics: "photo_library",
        TV: "tv",
        System: "host",
        Office: "content_paste",
    })

    function getAppCategoryIcon(name) {
        if (!name) return "desktop_windows"
        if (name.startsWith("steam_app_")) return "sports_esports"
        const categories = DesktopEntries.heuristicLookup(name)?.categories
        if (categories)
            for (const [key, value] of Object.entries(categoryIcons))
                if (categories.includes(key))
                    return value
        return "desktop_windows"
    }

    property var visibleWorkspaceIds: []

    function updateVisibleWorkspaceIds() {
        const base = root.workspaceOffset + root.workspaceGroup * root.workspacesShown
        if (!root.dynamicWorkspaces) {
            visibleWorkspaceIds = Array.from({ length: root.workspacesShown }, (_, i) => base + i + 1)
            return
        }
        const activeId = root.monitor?.activeWorkspace?.id ?? -1
        const allWs = Hyprland.workspaces.values
        const ids = new Set()
        if (activeId > 0) ids.add(activeId)
        for (const ws of allWs) {
            if (ws.id > 0)
                ids.add(ws.id)
        }
        visibleWorkspaceIds = [...ids].sort((a, b) => a - b)
    }

    function updateWorkspaceOccupied() {
        workspaceOccupied = Array.from({ length: root.workspacesShown }, (_, i) => {
            return Hyprland.workspaces.values.some(ws => ws.id === workspaceOffset + workspaceGroup * root.workspacesShown + i + 1);
        })
    }

    function workspaceDisplayText(workspaceId) {
        return Config.options?.bar.workspaces.numberMap[workspaceId - 1] || workspaceId.toString()
    }

    function hasWindowsInWorkspace(workspaceId) {
        return HyprlandData.windowList.some(w => w.workspace.id === workspaceId);
    }


    function updateMonitorWindows() {
        const windowsOnMonitor = HyprlandData.windowList.filter(win => win.monitor === root.monitor?.id && !win.floating)
        windowsOnMonitor.sort((a, b) => a.at[0] - b.at[0])
        root.monitorWindows = windowsOnMonitor.map(win => ({
            icon: Quickshell.iconPath(AppSearch.guessIcon(win?.class), "image-missing"),
            className: win?.class ?? "",
            workspace: win.workspace?.id
        }))
    }

    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            root.updateMonitorWindows()
        }
    }

    Component.onCompleted: {
        updateWorkspaceOccupied()
        updateMonitorWindows()
        updateVisibleWorkspaceIds()
    }
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateWorkspaceOccupied();
            updateVisibleWorkspaceIds();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateWorkspaceOccupied();
            updateVisibleWorkspaceIds();
        }
    }
    onWorkspaceGroupChanged: {
        updateWorkspaceOccupied();
        updateVisibleWorkspaceIds();
    }
    onDynamicWorkspacesChanged: {
        updateWorkspaceOccupied();
        updateVisibleWorkspaceIds();
    }

    WheelHandler {
        onWheel: (event) => {
            if (event.angleDelta.y < 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: (event) => {
            if (event.button === Qt.BackButton) {
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
            }
        }
    }


    readonly property Item activeLayout: workspaceStyle === 1 ? dotsWrapper
        : workspaceStyle === 2 ? windowsWrapper
        : contentLayout

    property real crossAxisSize: root.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

    implicitWidth: root.vertical ? root.crossAxisSize : root.activeLayout.implicitWidth
    implicitHeight: root.vertical ? root.activeLayout.implicitHeight : root.crossAxisSize

    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    Rectangle {
        id: activeIndicator
        visible: root.workspaceStyle === 0
        z: 2
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
        color: Appearance.colors.colPrimary
        radius: Appearance.rounding.full

        property int safeIndex: Math.max(0, Math.min(root.workspaceIndexInGroup, root.classicCount - 1))

        AnimatedTabIndexPair {
            id: idxPair
            index: activeIndicator.safeIndex
        }

        function offsetFor(idx) {
            let y = 0
            const bound = Math.min(idx, contentLayout.children.length)
            for (let i = 0; i < bound; i++) {
                const item = contentLayout.children[i]
                y += root.vertical ? item?.height - baseHeight : item?.width - baseHeight
            }
            return y
        }

        property int baseHeight: root.iconBoxWrapperSize

        property real indicatorMargin: 7
        property real emptyWorkspaceMargin: 2

        property real clampedMin: Math.min(Math.max(0, idxPair.idx1), Math.max(0, idxPair.idx2))
        property real clampedMax: Math.max(Math.max(0, idxPair.idx1), Math.max(0, idxPair.idx2))
        property real pairSpan: clampedMax - clampedMin

        property real offset: {
            const item = contentLayout.children[safeIndex]
            const itemSize = root.vertical ? item?.height : item?.width
            return (itemSize ?? baseHeight) - baseHeight
        }

        property real indicatorPosition: {
            const basePos = clampedMin * root.iconBoxWrapperSize
            const accumulatedOffset = offsetFor(safeIndex + 1)
            return basePos + accumulatedOffset - offset + indicatorMargin / 2
        }

        property real indicatorLength: {
            const baseLength = (pairSpan + 1) * root.iconBoxWrapperSize
            return baseLength + offset - indicatorMargin
        }

        property int workspacePadding: !hasWindowsInWorkspace(root.wsIdAt(safeIndex)) || !root.showIcons ? emptyWorkspaceMargin : 0

        property real logicalPosition: indicatorPosition - workspacePadding
        property real logicalLength: indicatorLength + workspacePadding * 2

        y: root.vertical ? logicalPosition : 0
        x: root.vertical ? 0 : logicalPosition
        implicitHeight: root.vertical ? logicalLength : individualIconBoxHeight
        implicitWidth: root.vertical ? individualIconBoxHeight : logicalLength
    }



    GridLayout {
        visible: root.workspaceStyle === 0
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
        z: 1

        columns: root.vertical ? 1 : 99
        rows: root.vertical ? 99 : 1

        Repeater {
            model: root.classicCount
            delegate: Rectangle {
                Layout.alignment: Qt.AlignCenter

                property int wsId: root.wsIdAt(index)
                property bool isOccupied: root.dynamicWorkspaces
                    ? root.hasWindowsInWorkspace(wsId)
                    : (root.workspaceOccupied[index] && !(!activeWindow?.activated && monitor?.activeWorkspace?.id === index + 1))
                property bool prevOccupied: index > 0 && (root.dynamicWorkspaces
                    ? root.hasWindowsInWorkspace(root.wsIdAt(index - 1))
                    : (root.workspaceOccupied[index - 1] && !(!activeWindow?.activated && monitor?.activeWorkspace?.id === index)))
                property bool nextOccupied: index < root.classicCount - 1 && (root.dynamicWorkspaces
                    ? root.hasWindowsInWorkspace(root.wsIdAt(index + 1))
                    : (root.workspaceOccupied[index + 1] && !(!activeWindow?.activated && monitor?.activeWorkspace?.id === index + 2)))
                property var radiusPrev: prevOccupied ? 0 : (width / 2)
                property var radiusNext: nextOccupied ? 0 : (width / 2)

                topLeftRadius: radiusPrev
                bottomLeftRadius: root.vertical ? radiusNext : radiusPrev
                topRightRadius: root.vertical ? radiusPrev : radiusNext
                bottomRightRadius: radiusNext

                implicitWidth: root.vertical ? root.iconBoxWrapperSize : contentLayout.children[index]?.width ?? 0
                implicitHeight: root.vertical ? contentLayout.children[index]?.height ?? 0 : root.iconBoxWrapperSize

                color: ColorUtils.transparentize(Appearance.m3colors.m3secondaryContainer, 0.4)
                opacity: isOccupied ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on radiusPrev {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on radiusNext {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
            }
        }
    }

    GridLayout {
        visible: root.workspaceStyle === 0
        id: contentLayout
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
        z: 3

        columns: root.vertical ? 1 : 99
        rows: root.vertical ? 99 : 1

        Repeater {
            id: workspaceRepeater
            model: root.classicCount

            delegate: MouseArea {
                id: background
                Layout.alignment: Qt.AlignCenter
                property int wsId: root.wsIdAt(index)
                implicitWidth: root.vertical ? root.iconBoxWrapperSize : Math.max(layout.implicitWidth + 8, root.iconBoxWrapperSize)
                implicitHeight: root.vertical ? Math.max(layout.implicitHeight + 8, root.iconBoxWrapperSize) : root.iconBoxWrapperSize
                onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${wsId}})`)

                WorkspaceBackgroundIndicator {
                    workspaceValue: background.wsId
                    activeWorkspace: monitor?.activeWorkspace?.id === workspaceValue
                }

                GridLayout {
                    id: layout
                    anchors.centerIn: parent
                    columnSpacing: 0
                    rowSpacing: 0
                    columns: root.vertical ? 1 : 99
                    rows: root.vertical ? 99 : 1


                    Repeater {
                        property int workspaceIndex: background.wsId
                        model: root.showIcons ? root.monitorWindows?.filter(win => win.workspace === workspaceIndex).slice(0, Config.options.bar.workspaces.maxWindowCount) : []
                        delegate: Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: root.individualIconBoxHeight
                            height: root.individualIconBoxHeight

                            MaterialSymbol {
                                visible: root.customAppIcons
                                anchors.centerIn: parent
                                text: root.getAppCategoryIcon(modelData.className)
                                iconSize: root.individualIconBoxHeight * root.iconRatio
                                color: root.monitor?.activeWorkspace?.id === background.wsId
                                    ? Appearance.m3colors.m3onPrimary
                                    : Appearance.m3colors.m3onSecondaryContainer

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }

                            IconImage {
                                id: mainAppIcon
                                visible: !root.customAppIcons
                                anchors.centerIn: parent
                                source: modelData.icon
                                implicitSize: root.individualIconBoxHeight * root.iconRatio
                            }
                            Loader {
                                active: !root.customAppIcons && Config.options.bar.workspaces.monochromeIcons
                                anchors.fill: mainAppIcon
                                sourceComponent: Item {
                                    Desaturate {
                                        id: desaturatedIcon
                                        visible: false
                                        anchors.fill: parent
                                        source: mainAppIcon
                                        desaturation: 0.8
                                    }
                                    ColorOverlay {
                                        anchors.fill: desaturatedIcon
                                        source: desaturatedIcon
                                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.9)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property bool showWorkspaceNumbers: false
    Timer {
        id: superHeldTimer
        interval: Config.options.bar.workspaces.showNumberDelay
        onTriggered: root.showWorkspaceNumbers = true
    }
    Connections {
        enabled: Config.options.bar.workspaces.showNumberOnSuperHold
        target: GlobalStates
        function onSuperDownChanged() {
            if (GlobalStates.superDown) superHeldTimer.restart()
            else { superHeldTimer.stop(); root.showWorkspaceNumbers = false }
        }
    }

    Item {
        id: dotsWrapper
        visible: root.workspaceStyle === 1
        anchors.centerIn: parent
        readonly property int dotCount: root.visibleWorkspaceIds.length
        readonly property int dotSize: root.dotSize
        readonly property int dotSpacing: root.dotSpacing
        readonly property int pillPaddingSide: root.dotPillPaddingSide
        readonly property int pillPaddingLength: root.dotPillPaddingLength

        readonly property int activeExtra: Math.max(0, root.dotActiveSize - dotSize)

        implicitWidth: root.vertical
            ? dotSize + pillPaddingSide
            : dotCount * dotSize + activeExtra + (dotCount - 1) * dotSpacing + pillPaddingLength
        implicitHeight: root.vertical
            ? dotCount * dotSize + activeExtra + (dotCount - 1) * dotSpacing + pillPaddingLength
            : dotSize + pillPaddingSide

        Rectangle {
            anchors.fill: parent
            visible: root.dotPillBackground
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer1Hover
        }

        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        GridLayout {
            id: dotsLayout
            anchors.centerIn: parent
            columns: root.vertical ? 1 : -1
            columnSpacing: root.dotSpacing
            rowSpacing: root.dotSpacing

            Repeater {
                model: ScriptModel { values: root.visibleWorkspaceIds }
                delegate: Item {
                    required property int modelData
                    property int wsId: modelData
                    property bool isActive: root.monitor?.activeWorkspace?.id === wsId

                    Layout.alignment: Qt.AlignCenter
                    implicitWidth: (!root.vertical && isActive) ? root.dotActiveSize : root.dotSize
                    implicitHeight: (root.vertical && isActive) ? root.dotActiveSize : root.dotSize

                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Rectangle {
                        x: (parent.width - width) / 2
                        y: (parent.height - height) / 2
                        width: root.vertical ? root.dotSize : (isActive ? root.dotActiveSize : root.dotSize)
                        height: root.vertical ? (isActive ? root.dotActiveSize : root.dotSize) : root.dotSize
                        radius: Appearance.rounding.full
                        color: isActive ? Appearance.m3colors.m3tertiary : Appearance.m3colors.m3primary

                        Behavior on width {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        StyledText {
                            anchors.fill: parent
                            text: wsId.toString()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: isActive ? Appearance.m3colors.m3onTertiary : Appearance.m3colors.m3onPrimary
                            opacity: root.showWorkspaceNumbers ? 1 : 0

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${wsId}})`)
                    }
                }
            }
        }
    }

    component WorkspaceBackgroundIndicator: Rectangle {
        property bool showNumbers: Config.options.bar.workspaces.alwaysShowNumbers || root.showWorkspaceNumbers
        property int workspaceValue
        property bool activeWorkspace
        property bool occupied: root.dynamicWorkspaces ? root.hasWindowsInWorkspace(workspaceValue) : root.workspaceOccupied[index]
        property color indColor: activeWorkspace ? Appearance.m3colors.m3onPrimary : (occupied ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1Inactive)

        anchors.centerIn: parent
        width: root.workspaceDotSize
        height: width
        radius: width / 2
        visible: layout.implicitHeight + 8 < root.iconBoxWrapperSize
        color: !showNumbers ? indColor : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        property string displayText: Config.options?.bar.workspaces.numberMap[workspaceValue - 1] || workspaceValue.toString()
        property bool renderMaterial: Config.options?.bar?.workspaces?.renderMaterialSymbols === true
        property bool isCustomIcon: renderMaterial && (displayText === "spark" || displayText === "distro")
        property bool isMaterialIcon: renderMaterial && !isCustomIcon && /^[a-z_]+$/.test(displayText)
        property real materialFill: activeWorkspace ? 1 : 0
        Behavior on materialFill {
            enabled: isMaterialIcon
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledText {
            visible: !isCustomIcon
            opacity: showNumbers ? 1 : 0
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: displayText
            elide: Text.ElideRight
            color: indColor
            font.family: isMaterialIcon
                ? (Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded")
                : defaultFont
            font.pixelSize: isMaterialIcon
                ? Appearance.font.pixelSize.small
                : (Appearance.font.pixelSize.small - ((text.length - 1) * (text !== "10") * 2))
            font.hintingPreference: isMaterialIcon ? Font.PreferNoHinting : Font.PreferDefaultHinting
            font.weight: isMaterialIcon
                ? Font.Normal + (Font.DemiBold - Font.Normal) * materialFill.toFixed(1)
                : Font.Normal
            font.variableAxes: isMaterialIcon
                ? ({ "FILL": materialFill.toFixed(1), "opsz": Appearance.font.pixelSize.small })
                : (shouldUseNumberFont ? ({}) : Appearance.font.variableAxes.main)

            Behavior on opacity {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }

        Loader {
            active: isCustomIcon
            anchors.centerIn: parent
            sourceComponent: CustomIcon {
                opacity: showNumbers ? 1 : 0
                width: Appearance.font.pixelSize.small
                height: Appearance.font.pixelSize.small
                source: displayText === "distro" ? SystemInfo.distroIcon : `${displayText}-symbolic`
                colorize: true
                color: indColor

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }
    }

    GridLayout {
        id: windowsWrapper
        visible: root.workspaceStyle === 2
        anchors.centerIn: parent
        columns: root.vertical ? 1 : -1
        columnSpacing: 2
        rowSpacing: 2

        Repeater {
            model: ScriptModel { values: root.visibleWorkspaceIds }

            delegate: Rectangle {
                required property int modelData
                readonly property int wsId: modelData
                readonly property bool isActive: root.monitor?.activeWorkspace?.id === wsId
                readonly property bool isOccupied: root.hasWindowsInWorkspace(wsId)

                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.vertical ? root.windowCellThickness : root.windowCellLength
                implicitHeight: root.vertical ? root.windowCellLength : root.windowCellThickness
                radius: Appearance.rounding.verysmall
                color: isActive ? Appearance.colors.colPrimary
                    : isOccupied ? Qt.alpha(Appearance.colors.colPrimary, 0.22)
                    : "transparent"
                border.width: 1
                border.color: isActive ? Appearance.colors.colPrimary
                    : Qt.alpha(Appearance.colors.colPrimary, isOccupied ? 0.85 : 0.5)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                StyledText {
                    anchors.centerIn: parent
                    text: root.workspaceDisplayText(parent.wsId)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: parent.isActive ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
                    opacity: (Config.options.bar.workspaces.alwaysShowNumbers || root.showWorkspaceNumbers) ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch(`hl.dsp.focus({workspace = ${parent.wsId}})`)
                }
            }
        }
    }
}
