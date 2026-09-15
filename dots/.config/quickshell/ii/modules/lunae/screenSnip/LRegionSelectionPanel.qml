pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.utils
import qs.modules.common.widgets

PanelWindow {
    id: root

    enum MediaType { Image, Video }
    enum ImageAction { Copy, Menu, CharRecognition, Search, Translate }
    enum VideoAction { Record, RecordWithSound }
    enum SelectionMode { Rect, Window }
    enum Phase { Select, Post, Translate }

    signal closeRequested()

    required property var snip
    readonly property int mediaType: root.snip.mediaType
    readonly property int imageAction: root.snip.imageAction
    readonly property int videoAction: root.snip.videoAction
    property int selectionMode: LRegionSelectionPanel.SelectionMode.Rect
    property int phase: LRegionSelectionPanel.Phase.Select

    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: (root.primary && root.phase !== LRegionSelectionPanel.Phase.Post)
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor.scale
    readonly property real monitorOffsetX: hyprlandMonitor.x
    readonly property real monitorOffsetY: hyprlandMonitor.y

    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        if (a.floating === b.floating) return 0
        return a.floating ? -1 : 1
    }).map(w => Object.assign({}, w, {
        at: [w.at[0] - root.monitorOffsetX, w.at[1] - root.monitorOffsetY]
    }))

    property string screenshotDir: Directories.screenshotTemp
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`

    property bool isRecording: root.mediaType === LRegionSelectionPanel.MediaType.Video
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: root.isRecording
        command: ["pidof", "wf-recorder"]
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !screenshotProc.running
            root.recordingShouldStop = (exitCode === 0)
        }
    }

    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !checkRecordingProc.running
        }
    }
    readonly property bool primary: root.screen.name === root.snip.primaryScreen
    readonly property bool mayReveal: root.primary || root.snip.primaryRevealed

    property bool preparationDone: false
    onPreparationDoneChanged: {
        if (!preparationDone) return
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath])
            root.closeRequested()
            return
        }
        root.tryReveal()
    }
    onMayRevealChanged: root.tryReveal()

    function tryReveal() {
        if (!root.preparationDone || !root.mayReveal) return
        root.visible = true
        if (root.primary) releaseRest.restart()
    }

    Timer {
        id: releaseRest
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: root.snip.primaryRevealed = true
    }

    Connections {
        target: Persistent.states.screenRecord
        function onActiveChanged() {
            if (!Persistent.states.screenRecord.active && root.phase === LRegionSelectionPanel.Phase.Post) {
                root.closeRequested()
            }
        }
    }

    CursorTracker {
        id: cursor
        monitor: root.hyprlandMonitor
        active: root.visible
        onCursorYChanged: if (!cursor.moved && root.isWindowSelection)
            root.updateHoveredWindow(cursor.cursorX, cursor.cursorY)
    }

    property var mouseButton: Qt.LeftButton
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property bool dragging: false
    property real regionX: Math.min(dragStartX, draggingX)
    property real regionY: Math.min(dragStartY, draggingY)
    property real regionWidth: Math.abs(draggingX - dragStartX)
    property real regionHeight: Math.abs(draggingY - dragStartY)

    property bool isWindowSelection: root.selectionMode === LRegionSelectionPanel.SelectionMode.Window
    property var hoveredWindow: null
    property int winPadding: 1
    property int selectionX: isWindowSelection ? ((hoveredWindow?.at[0] ?? 0) - winPadding) : regionX
    property int selectionY: isWindowSelection ? ((hoveredWindow?.at[1] ?? 0) - winPadding) : regionY
    property int selectionWidth: isWindowSelection ? ((hoveredWindow?.size[0] ?? 0) + winPadding * 2) : regionWidth
    property int selectionHeight: isWindowSelection ? ((hoveredWindow?.size[1] ?? 0) + winPadding * 2) : regionHeight

    function updateHoveredWindow(mx, my) {
        hoveredWindow = root.windows.find(w => {
            const inCurrentWorkspace = w.workspace.id === HyprlandData.activeWorkspace.id
            return w.at[0] <= mx && mx <= w.at[0] + w.size[0]
                && w.at[1] <= my && my <= w.at[1] + w.size[1]
        }) ?? null
    }

    function getScreenshotAction() {
        if (root.mediaType === LRegionSelectionPanel.MediaType.Image
            && root.mouseButton === Qt.RightButton
            && (root.imageAction === LRegionSelectionPanel.ImageAction.Copy
                || root.imageAction === LRegionSelectionPanel.ImageAction.Menu)) {
            return ScreenshotAction.Action.Edit
        }
        switch (root.mediaType) {
        case LRegionSelectionPanel.MediaType.Image:
            switch (root.imageAction) {
            case LRegionSelectionPanel.ImageAction.Copy: return ScreenshotAction.Action.Copy
            case LRegionSelectionPanel.ImageAction.Menu: return ScreenshotAction.Action.Edit
            case LRegionSelectionPanel.ImageAction.CharRecognition: return ScreenshotAction.Action.CharRecognition
            case LRegionSelectionPanel.ImageAction.Search: return ScreenshotAction.Action.Search
            case LRegionSelectionPanel.ImageAction.Translate: return ScreenshotAction.Action.Copy
            default: return ScreenshotAction.Action.Copy
            }
        case LRegionSelectionPanel.MediaType.Video:
            switch (root.videoAction) {
            case LRegionSelectionPanel.VideoAction.Record: return ScreenshotAction.Action.Record
            case LRegionSelectionPanel.VideoAction.RecordWithSound: return ScreenshotAction.Action.RecordWithSound
            }
        }
        return ScreenshotAction.Action.Copy
    }

    function executeSnip() {
        if (selectionWidth <= 0 || selectionHeight <= 0) return

        if (root.imageAction === LRegionSelectionPanel.ImageAction.Translate
            && root.mediaType === LRegionSelectionPanel.MediaType.Image) {
            root.startTranslation()
            return
        }

        const saveDir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : ""
        const command = ScreenshotAction.getCommand(
            root.selectionX,
            root.selectionY,
            root.selectionWidth,
            root.selectionHeight,
            root.screenshotPath,
            root.getScreenshotAction(),
            saveDir,
            root.monitorScale,
            root.monitorOffsetX,
            root.monitorOffsetY
        )
        snipProc.command = command
        snipProc.startDetached()
        const isRec = root.mediaType === LRegionSelectionPanel.MediaType.Video
        if (isRec && Config.options.screenRecord.showBreathingBorder) {
            root.phase = LRegionSelectionPanel.Phase.Post
        } else {
            root.closeRequested()
        }
    }

    Process { id: snipProc }

    property var translateParagraphs: []
    property var translateTranslation: ({})
    property var translateColors: []
    property bool translateBusy: false

    readonly property string batchColorScriptPath: Quickshell.shellPath("scripts/images/batch-text-colors-venv.sh")

    function startTranslation() {
        if (!KeyringStorage.loaded) KeyringStorage.fetchKeyringData()

        const rx = Math.round(root.selectionX * root.monitorScale)
        const ry = Math.round(root.selectionY * root.monitorScale)
        const rw = Math.round(root.selectionWidth * root.monitorScale)
        const rh = Math.round(root.selectionHeight * root.monitorScale)
        const escapedPath = StringUtils.shellSingleQuoteEscape(root.screenshotPath)
        const cropCmd = `magick '${escapedPath}' -crop ${rw}x${rh}+${rx}+${ry} +repage '${escapedPath}'`

        const targetLang = Config.options.screenSnip.translator.targetLanguage
        const sourceLang = Config.options.screenSnip.translator.ocrLanguage
        const ocrBackend = Config.options.screenSnip.translator.ocrBackend
        const translationEngine = Config.options.screenSnip.translator.translationEngine

        let translationKey = ""
        if (translationEngine === "deepl") {
            translationKey = KeyringStorage.keyringData?.apiKeys?.deepl ?? ""
            if (!translationKey) {
                console.warn("[ScreenTranslate] No DeepL API key in keyring")
                root.closeRequested()
                return
            }
        }

        root.translateParagraphs = []
        root.translateTranslation = ({})
        root.translateColors = []
        root.translateBusy = true
        root.phase = LRegionSelectionPanel.Phase.Translate

        const googleVisionKey = KeyringStorage.keyringData?.apiKeys?.googleVision ?? ""
        if (ocrBackend === "google" && !googleVisionKey) {
            console.warn("[ScreenTranslate] No Google Vision API key in keyring")
            root.closeRequested()
            return
        }

        let cmd = `${cropCmd} && python3 '${Directories.screenTranslateScriptPath}' `
            + `'${escapedPath}' '${StringUtils.shellSingleQuoteEscape(translationKey || "unused")}' `
            + `'${StringUtils.shellSingleQuoteEscape(targetLang)}'`

        if (sourceLang && sourceLang !== "auto")
            cmd += ` '${StringUtils.shellSingleQuoteEscape(sourceLang)}'`

        cmd += ` --rich`
        cmd += ` --translation-engine ${translationEngine}`

        if (!Config.options.screenSnip.translator.usePreprocessing)
            cmd += ` --no-preprocess`

        cmd += ` --ocr ${ocrBackend}`
        if (ocrBackend === "google")
            cmd += ` --google-key '${StringUtils.shellSingleQuoteEscape(googleVisionKey)}'`

        cmd += " 2>/dev/null"

        translateProc.command = ["bash", "-c", cmd]
        translateProc.running = true
    }

    function translateText(s) {
        return root.translateTranslation[s] ?? s;
    }

    function runTranslateColorDetection() {
        if (root.translateParagraphs.length === 0) return;
        const regions = root.translateParagraphs.map(p => {
            const v = p.boundingBox.vertices;
            return { x: v[0].x, y: v[0].y, w: v[1].x - v[0].x, h: v[3].y - v[0].y };
        });
        const payload = JSON.stringify({ image: root.screenshotPath, regions: regions });
        translateColorProc.command = [
            "bash", "-c",
            `echo ${StringUtils.shellSingleQuoteEscape(payload)} | ${root.batchColorScriptPath}`
        ];
        translateColorProc.running = true;
    }

    Process {
        id: translateProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    if (result.error) {
                        console.warn("[ScreenTranslate]", result.error)
                        root.translateBusy = false
                        return
                    }
                    root.translateParagraphs = result.paragraphs ?? []
                    root.translateTranslation = result.translations ?? {}
                    Qt.callLater(() => {
                        root.translateBusy = false
                        root.runTranslateColorDetection()
                    })
                } catch (e) {
                    console.warn("[ScreenTranslate] bad JSON:", e, text)
                    root.translateBusy = false
                }
            }
        }
    }

    Process {
        id: translateColorProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.translateColors = JSON.parse(text) }
                catch (e) { }
            }
        }
    }

    mask: Region {
        item: (root.phase === LRegionSelectionPanel.Phase.Select
            || root.phase === LRegionSelectionPanel.Phase.Translate) ? mouseArea : maskEmpty
    }

    Item {
        id: maskEmpty
        width: 0
        height: 0
    }

    ScreencopyView {
        anchors.fill: parent
        live: false
        captureSource: root.screen
        visible: root.phase === LRegionSelectionPanel.Phase.Select
            || root.phase === LRegionSelectionPanel.Phase.Translate
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.phase !== LRegionSelectionPanel.Phase.Post
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor

        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.closeRequested()
            } else if (event.key === Qt.Key_E && event.modifiers & Qt.ControlModifier) {
                root.snip.imageAction = root.imageAction === LRegionSelectionPanel.ImageAction.Menu
                    ? LRegionSelectionPanel.ImageAction.Copy
                    : LRegionSelectionPanel.ImageAction.Menu
            }
        }

        onPressed: mouse => {
            root.mouseButton = mouse.button
            const px = cursor.localX(mouse.x)
            const py = cursor.localY(mouse.y)
            root.dragStartX = px
            root.dragStartY = py
            root.draggingX = px
            root.draggingY = py
            root.dragging = true
        }
        onPositionChanged: mouse => {
            if (!cursor.track(mouse.x, mouse.y)) return
            if (root.isWindowSelection) root.updateHoveredWindow(mouse.x, mouse.y)
            if (!root.dragging) return
            root.draggingX = mouse.x
            root.draggingY = mouse.y
        }
        onReleased: mouse => {
            root.dragging = false
            root.executeSnip()
        }

        LRectangularSelection {
            anchors.fill: parent
            regionX: root.selectionX
            regionY: root.selectionY
            regionWidth: root.selectionWidth
            regionHeight: root.selectionHeight
            breathingBorderOnly: root.phase === LRegionSelectionPanel.Phase.Post
        }

        SnipToolbar {
            visible: root.phase === LRegionSelectionPanel.Phase.Select
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: Config?.options?.lunae?.screenSnip?.toolbarPosition === "bottom" ? undefined : parent.top
                bottom: Config?.options?.lunae?.screenSnip?.toolbarPosition === "bottom" ? parent.bottom : undefined
                topMargin: Config?.options?.lunae?.screenSnip?.toolbarPosition === "bottom" ? 0 : 16
                bottomMargin: Config?.options?.lunae?.screenSnip?.toolbarPosition === "bottom" ? 16 : 0
            }
        }

        CursorGuide {
            visible: root.phase === LRegionSelectionPanel.Phase.Select && mouseArea.containsMouse
                && Config?.options?.lunae?.screenSnip?.cursorToolTip
            x: root.dragging ? root.selectionX + root.selectionWidth : cursor.cursorX
            y: root.dragging ? root.selectionY + root.selectionHeight : cursor.cursorY
            z: 999
        }

        Item {
            id: translateOverlay
            anchors.fill: parent
            visible: root.phase === LRegionSelectionPanel.Phase.Translate

            Item {
                id: translateMaskSource
                anchors.fill: parent
                visible: false
                Rectangle {
                    x: root.selectionX
                    y: root.selectionY
                    width: root.selectionWidth
                    height: root.selectionHeight
                    color: "black"
                }
            }

            Rectangle {
                id: translateDim
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.colors.colShadow, 0.3)
                visible: false
            }

            OpacityMask {
                anchors.fill: parent
                source: translateDim
                maskSource: translateMaskSource
                invert: true
            }

            Rectangle {
                x: root.selectionX - 2
                y: root.selectionY - 2
                width: root.selectionWidth + 4
                height: root.selectionHeight + 4
                color: "transparent"
                border.width: 2
                border.color: Appearance.colors.colPrimary
                radius: Appearance.rounding.small
            }

            Column {
                visible: root.translateBusy
                x: root.selectionX + (root.selectionWidth - width) / 2
                y: root.selectionY + (root.selectionHeight - height) / 2
                spacing: 12

                MaterialLoadingIndicator {
                    id: loadingSpinner
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitSize: Math.max(32, Math.min(64, Math.min(root.selectionWidth, root.selectionHeight) * 0.15))
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Translation.tr("Translating...")
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Math.max(14, loadingSpinner.implicitSize * 0.4)
                }
            }

            Item {
                x: root.selectionX
                y: root.selectionY
                width: root.selectionWidth
                height: root.selectionHeight
                clip: true

                Image {
                    id: cropImage
                    visible: false
                    width: parent.width
                    height: parent.height
                    source: root.translateParagraphs.length > 0 ? Qt.resolvedUrl(root.screenshotPath) : ""
                    sourceSize: Qt.size(parent.width * root.monitorScale, parent.height * root.monitorScale)
                    asynchronous: true
                    cache: false
                }

                Item {
                    id: blurMask
                    width: parent.width
                    height: parent.height
                    layer.enabled: true
                    visible: false
                    Repeater {
                        model: root.translateBusy ? [] : root.translateParagraphs
                        delegate: Rectangle {
                            required property var modelData
                            property list<var> verts: modelData.boundingBox.vertices
                            readonly property string paraText: modelData.text
                            readonly property string translated: root.translateText(paraText)
                            visible: translated !== paraText
                            x: verts[0].x / root.monitorScale
                            y: verts[0].y / root.monitorScale
                            width: (verts[1].x - verts[0].x) / root.monitorScale
                            height: (verts[3].y - verts[0].y) / root.monitorScale
                            radius: 4

                            property real dx: verts[1].x - verts[0].x
                            property real dy: verts[1].y - verts[0].y
                            transformOrigin: Item.TopLeft
                            rotation: Math.atan2(dy, dx) * 180 / Math.PI
                        }
                    }
                }

                MaskMultiEffect {
                    width: parent.width
                    height: parent.height
                    source: cropImage
                    maskSource: blurMask
                    blurEnabled: true
                    blur: 1
                    blurMax: 50
                    autoPaddingEnabled: false
                }

                Repeater {
                    model: root.translateBusy ? [] : root.translateParagraphs
                    delegate: Rectangle {
                        id: transBlock
                        required property var modelData
                        required property int index
                        property list<var> verts: modelData.boundingBox.vertices
                        readonly property string paraText: modelData.text
                        readonly property string translated: root.translateText(paraText)
                        visible: translated !== paraText

                        x: verts[0].x / root.monitorScale
                        y: verts[0].y / root.monitorScale
                        width: (verts[1].x - verts[0].x) / root.monitorScale
                        height: (verts[3].y - verts[0].y) / root.monitorScale
                        radius: 4

                        property real dx: verts[1].x - verts[0].x
                        property real dy: verts[1].y - verts[0].y
                        transformOrigin: Item.TopLeft
                        rotation: Math.atan2(dy, dx) * 180 / Math.PI

                        readonly property var colorData: root.translateColors[index] ?? null
                        readonly property real boxTransparency: 1 - (Config.options?.screenSnip?.translator?.textBoxOpacity ?? 0.85)

                        color: colorData?.background
                            ? ColorUtils.transparentize(colorData.background, boxTransparency)
                            : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, boxTransparency)
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        SqueezedAnnotationStyledText {
                            width: parent.width
                            height: parent.height
                            text: transBlock.translated
                            scaleFactor: 1
                            color: transBlock.colorData?.text ?? Appearance.colors.colOnSecondaryContainer

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: root.closeRequested()
            }
        }
    }

    component CursorGuide: Item {
        id: guide
        property int margins: 8
        implicitWidth: content.implicitWidth + margins * 2
        implicitHeight: content.implicitHeight + margins * 2

        property string materialSymbol: {
            if (root.mediaType === LRegionSelectionPanel.MediaType.Image) {
                switch (root.imageAction) {
                case LRegionSelectionPanel.ImageAction.Copy: return "content_cut"
                case LRegionSelectionPanel.ImageAction.Menu: return "edit"
                case LRegionSelectionPanel.ImageAction.CharRecognition: return "document_scanner"
                case LRegionSelectionPanel.ImageAction.Search: return "image_search"
                case LRegionSelectionPanel.ImageAction.Translate: return "translate"
                }
            } else {
                return "videocam"
            }
            return ""
        }

        property string description: {
            if (root.mediaType === LRegionSelectionPanel.MediaType.Image) {
                switch (root.imageAction) {
                case LRegionSelectionPanel.ImageAction.Copy: return Translation.tr("Copy (LMB) | Annotate (RMB)")
                case LRegionSelectionPanel.ImageAction.Menu: return Translation.tr("Annotate (LMB) | Copy (RMB)")
                case LRegionSelectionPanel.ImageAction.CharRecognition: return Translation.tr("Recognize text")
                case LRegionSelectionPanel.ImageAction.Search: return Translation.tr("Search image")
                case LRegionSelectionPanel.ImageAction.Translate: return Translation.tr("Translate text")
                }
            } else {
                return Translation.tr("Record region")
            }
            return ""
        }

        property bool showDescription: true
        Timer {
            id: descTimeout
            interval: 1500
            running: true
            onTriggered: guide.showDescription = false
        }
        Connections {
            target: root
            function onMediaTypeChanged() { guide.showDescription = true; descTimeout.restart() }
            function onImageActionChanged() { guide.showDescription = true; descTimeout.restart() }
            function onVideoActionChanged() { guide.showDescription = true; descTimeout.restart() }
        }

        Rectangle {
            id: content
            anchors.centerIn: parent

            property real padding: 8
            implicitHeight: 38
            implicitWidth: guide.showDescription ? contentRow.implicitWidth + padding * 2 : implicitHeight
            clip: true

            topLeftRadius: 6
            bottomLeftRadius: implicitHeight - topLeftRadius
            bottomRightRadius: bottomLeftRadius
            topRightRadius: bottomLeftRadius

            color: Appearance.colors.colPrimary

            Behavior on topLeftRadius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on implicitWidth {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Row {
                id: contentRow
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    leftMargin: content.padding
                }
                spacing: 12

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    iconSize: 22
                    color: Appearance.colors.colOnPrimary
                    text: guide.materialSymbol
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Appearance.colors.colOnPrimary
                    text: guide.description
                    opacity: guide.showDescription ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }

    component SnipButton: RippleButton {
        id: snipBtn
        property color colText: toggled
            ? Appearance.colors.colOnSecondaryContainer
            : Appearance.colors.colOnSurfaceVariant
        Layout.fillHeight: true
        implicitWidth: height
        buttonRadius: Appearance.rounding.small
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: 22
            text: snipBtn.text
            color: snipBtn.colText
            animateChange: true
        }
    }

    component GroupTabButton: RippleButton {
        id: tabBtn
        property string tabIcon: ""
        property string tabLabel: ""
        property bool active: false
        property color colText: active
            ? Appearance.colors.colOnSecondaryContainer
            : Appearance.colors.colOnSurfaceVariant
        Layout.fillHeight: true
        horizontalPadding: 12
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92)

        contentItem: Item {
            implicitWidth: tabRow.implicitWidth
            implicitHeight: tabRow.implicitHeight
            Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    iconSize: 20
                    text: tabBtn.tabIcon
                    color: tabBtn.colText
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tabBtn.tabLabel
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: tabBtn.colText
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }

    component SnipButtonGroup: Item {
        id: group
        property int currentIndex: 0
        default property alias buttons: buttonRow.data

        implicitWidth: buttonRow.implicitWidth
        implicitHeight: buttonRow.implicitHeight
        Layout.fillHeight: true

        Row {
            id: buttonRow
            z: 1
            spacing: 2
        }

        Rectangle {
            id: indicator
            z: 0
            color: Appearance.colors.colSecondaryContainer
            radius: Appearance.rounding.small
            y: 0
            height: group.height

            property Item targetItem: buttonRow.children[group.currentIndex]
            property real targetX: targetItem?.x ?? 0
            property real targetWidth: targetItem?.width ?? 0

            AnimatedTabIndexPair {
                id: leftBound
                idx1Duration: 50
                idx2Duration: 200
                index: indicator.targetX
            }
            AnimatedTabIndexPair {
                id: rightBound
                idx1Duration: 50
                idx2Duration: 200
                index: indicator.targetX + indicator.targetWidth
            }

            x: Math.min(leftBound.idx1, leftBound.idx2)
            width: Math.max(rightBound.idx1, rightBound.idx2) - x
        }
    }

    component SnipToolbar: Item {
        id: toolbar
        implicitWidth: toolbarBg.implicitWidth
        implicitHeight: toolbarBg.implicitHeight

        opacity: 0
        property int yOffset: Config?.options?.lunae?.screenSnip?.toolbarPosition === "bottom" ? 8 : -8
        transform: Translate { y: toolbar.yOffset }

        Component.onCompleted: {
            toolbar.opacity = 1
            toolbar.yOffset = 0
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on yOffset {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledRectangularShadow {
            target: toolbarBg
        }

        Rectangle {
            id: toolbarBg
            anchors.fill: parent
            color: Appearance.m3colors.m3surfaceContainer
            implicitHeight: 56
            implicitWidth: toolbarRow.implicitWidth + 12 * 2
            radius: Appearance.rounding.small

            RowLayout {
                id: toolbarRow
                spacing: 4
                anchors {
                    fill: parent
                    leftMargin: 12
                    rightMargin: 12
                    topMargin: 8
                    bottomMargin: 8
                }

                SnipButtonGroup {
                    currentIndex: root.mediaType === LRegionSelectionPanel.MediaType.Video ? 1 : 0

                    GroupTabButton {
                        tabIcon: "photo_camera"
                        tabLabel: Translation.tr("Image")
                        active: root.mediaType === LRegionSelectionPanel.MediaType.Image
                        onClicked: root.snip.mediaType = LRegionSelectionPanel.MediaType.Image
                    }
                    GroupTabButton {
                        tabIcon: "videocam"
                        tabLabel: Translation.tr("Video")
                        active: root.mediaType === LRegionSelectionPanel.MediaType.Video
                        onClicked: root.snip.mediaType = LRegionSelectionPanel.MediaType.Video
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    implicitHeight: 24
                    implicitWidth: 1
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.3
                }

                SnipButtonGroup {
                    currentIndex: root.selectionMode === LRegionSelectionPanel.SelectionMode.Window ? 1 : 0

                    GroupTabButton {
                        tabIcon: "crop"
                        tabLabel: Translation.tr("Region")
                        active: root.selectionMode === LRegionSelectionPanel.SelectionMode.Rect
                        onClicked: root.selectionMode = LRegionSelectionPanel.SelectionMode.Rect
                    }
                    GroupTabButton {
                        tabIcon: "select_window_2"
                        tabLabel: Translation.tr("Window")
                        active: root.selectionMode === LRegionSelectionPanel.SelectionMode.Window
                        onClicked: root.selectionMode = LRegionSelectionPanel.SelectionMode.Window
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    implicitHeight: 24
                    implicitWidth: 1
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.3
                }

                SnipButton {
                    text: "edit"
                    toggled: root.imageAction === LRegionSelectionPanel.ImageAction.Menu
                    enabled: root.mediaType === LRegionSelectionPanel.MediaType.Image
                    onClicked: {
                        root.snip.imageAction = root.imageAction === LRegionSelectionPanel.ImageAction.Menu
                            ? LRegionSelectionPanel.ImageAction.Copy
                            : LRegionSelectionPanel.ImageAction.Menu
                    }
                    StyledToolTip { text: Translation.tr("Quick markup (Ctrl+E)") }
                }

                SnipButton {
                    text: "image_search"
                    toggled: root.imageAction === LRegionSelectionPanel.ImageAction.Search
                        && root.mediaType === LRegionSelectionPanel.MediaType.Image
                    onClicked: {
                        if (toggled) {
                            root.snip.imageAction = LRegionSelectionPanel.ImageAction.Copy
                        } else {
                            root.snip.mediaType = LRegionSelectionPanel.MediaType.Image
                            root.snip.imageAction = LRegionSelectionPanel.ImageAction.Search
                        }
                    }
                    StyledToolTip { text: Translation.tr("Image search") }
                }

                SnipButton {
                    text: "colorize"
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c", "sleep 0.2; hyprpicker -a"])
                        root.closeRequested()
                    }
                    StyledToolTip { text: Translation.tr("Color picker") }
                }

                SnipButton {
                    text: "scan"
                    toggled: root.imageAction === LRegionSelectionPanel.ImageAction.CharRecognition
                        && root.mediaType === LRegionSelectionPanel.MediaType.Image
                    onClicked: {
                        if (toggled) {
                            root.snip.imageAction = LRegionSelectionPanel.ImageAction.Copy
                        } else {
                            root.snip.mediaType = LRegionSelectionPanel.MediaType.Image
                            root.snip.imageAction = LRegionSelectionPanel.ImageAction.CharRecognition
                        }
                    }
                    StyledToolTip { text: Translation.tr("Text extractor") }
                }

                SnipButton {
                    text: "translate"
                    toggled: root.imageAction === LRegionSelectionPanel.ImageAction.Translate
                        && root.mediaType === LRegionSelectionPanel.MediaType.Image
                    onClicked: {
                        if (toggled) {
                            root.snip.imageAction = LRegionSelectionPanel.ImageAction.Copy
                        } else {
                            root.snip.mediaType = LRegionSelectionPanel.MediaType.Image
                            root.snip.imageAction = LRegionSelectionPanel.ImageAction.Translate
                        }
                    }
                    StyledToolTip { text: Translation.tr("Translate text") }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    implicitHeight: 24
                    implicitWidth: 1
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.3
                }

                SnipButton {
                    text: "close"
                    onClicked: root.closeRequested()
                    StyledToolTip { text: Translation.tr("Close (Esc)") }
                }
            }
        }
    }
}
