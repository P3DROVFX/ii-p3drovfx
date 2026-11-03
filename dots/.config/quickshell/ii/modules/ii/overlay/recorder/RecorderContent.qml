pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overlay

/**
 * Body of the game overlay's Recorder widget, apart from its overlay frame so
 * it can be rendered on its own. `recordState` and `lastRecording` are the only
 * inputs; both default to the live ones.
 */
OverlayBackground {
    id: root
    implicitWidth: Math.max(310, contentColumn.implicitWidth + 24)
    implicitHeight: contentColumn.implicitHeight + 24

    // The state record.sh keeps in states.json. Every surface (bar, island,
    // this widget) reads the same object, so a recording started elsewhere shows
    // up here as soon as the file changes.
    property var recordState: Persistent.states.screenRecord
    // Off for a static render: no folder scan, the given lastRecording stays.
    property bool liveLastRecording: true
    readonly property bool recording: recordState?.active === true
    readonly property bool paused: recording && recordState?.paused === true
    readonly property bool starting: !recording && recordState?.loading === true
    readonly property int elapsed: recordState?.seconds ?? 0

    readonly property string savePath: Config.options.screenRecord.savePath
    property var lastRecording: null
    readonly property string thumbDir: FileUtils.trimFileProtocol(`${Directories.cache}/recorder/thumbs`)

    function clock(totalSeconds) {
        const s = Math.max(0, Math.floor(totalSeconds));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        const pad = value => String(value).padStart(2, "0");
        return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${pad(m)}:${pad(sec)}`;
    }

    function humanSize(bytes) {
        if (!(bytes > 0)) return "";
        const units = ["B", "KB", "MB", "GB"];
        let value = bytes, unit = 0;
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
        return `${value.toFixed(unit >= 2 ? 1 : 0)} ${units[unit]}`;
    }

    // Closing the overlay unloads this widget on the spot (its window only
    // stays mapped while something is pinned), so every action that closes it
    // does its work first and closes last: nothing on `root` exists afterwards.
    function closeOverlay() { GlobalStates.overlayOpen = false; }

    function runRecordScript(args) {
        Quickshell.execDetached([Directories.recordScriptPath].concat(args || []));
    }

    function refreshLastRecording() {
        if (!root.savePath || !root.liveLastRecording) return;
        lastRecordingProcess.running = false;
        lastRecordingProcess.running = true;
    }

    function openLastVideo() {
        if (!root.lastRecording?.path) return;
        Qt.openUrlExternally(`file://${root.lastRecording.path}`);
        root.closeOverlay();
    }

    // Opens the folder with the file selected where the file manager supports
    // FileManager1 (Dolphin, Nautilus, Nemo…), the plain folder otherwise.
    function showLastVideoInFolder() {
        if (!root.lastRecording?.path) return;
        Quickshell.execDetached(["bash", "-c",
            'gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 '
            + '--method org.freedesktop.FileManager1.ShowItems "[\'file://$1\']" "" >/dev/null 2>&1 || xdg-open "$(dirname "$1")"',
            "_", root.lastRecording.path]);
        root.closeOverlay();
    }

    // Same route as the "Recording finished" prompt: LosslessCut when the user
    // chose it, the built-in editor otherwise.
    function editLastVideo() {
        const path = root.lastRecording?.path;
        if (!path) return;
        GlobalStates.videoEditorPopupOpen = false;
        if (Config.options.screenRecord.openInLosslessCut) {
            GlobalStates.launchLosslessCut(path);
        } else {
            GlobalStates.videoEditorPath = path;
            GlobalStates.videoEditorRenderPageOpen = false;
            GlobalStates.videoEditorOpen = true;
        }
        root.closeOverlay();
    }

    Component.onCompleted: refreshLastRecording()
    onSavePathChanged: refreshLastRecording()
    onRecordingChanged: if (!recording) finishedRefresh.restart()

    Connections {
        target: GlobalStates
        function onOverlayOpenChanged() {
            if (GlobalStates.overlayOpen) root.refreshLastRecording();
        }
        // record.sh hands every finished file to the editor prompt: the most
        // reliable moment to know the file is complete.
        function onVideoEditorPathChanged() { root.refreshLastRecording(); }
    }

    // wf-recorder flushes on SIGINT and OBS needs a moment to finalise; reading
    // the folder right as `active` drops would still see the half-written file.
    Timer {
        id: finishedRefresh
        interval: 2500
        onTriggered: root.refreshLastRecording()
    }

    Process {
        id: lastRecordingProcess
        // While recording, the newest file is the one being written, so the
        // second newest is the last finished recording.
        command: ["bash", "-c", `
            dir="$1"; cache="$2"; skip="$3"
            mkdir -p "$cache"
            f=$(find "$dir" -maxdepth 1 -type f \\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.gif' \\) \\
                -printf '%T@\\t%p\\n' 2>/dev/null | sort -nr | sed -n "$((skip + 1))p" | cut -f2-)
            [ -z "$f" ] && { echo '{}'; exit 0; }
            mtime=$(stat -c %Y "$f"); size=$(stat -c %s "$f")
            key=$(printf '%s:%s' "$f" "$mtime" | md5sum | cut -c1-16)
            thumb="$cache/$key.png"
            [ -s "$thumb" ] || ffmpegthumbnailer -i "$f" -o "$thumb" -s 320 -t 20% >/dev/null 2>&1 || rm -f "$thumb"
            ls -1t "$cache"/*.png 2>/dev/null | tail -n +9 | xargs -r rm -f
            dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
            jq -nc --arg path "$f" --arg thumb "$([ -s "$thumb" ] && echo "$thumb")" --arg dur "$dur" \\
                --argjson mtime "$mtime" --argjson size "$size" \\
                '{path: $path, thumb: $thumb, duration: ($dur | tonumber? // 0), mtime: $mtime, size: $size}'
        `, "_", root.savePath, root.thumbDir, root.recording ? "1" : "0"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(text.trim() || "{}");
                    root.lastRecording = info?.path ? info : null;
                } catch (error) {
                    root.lastRecording = null;
                }
            }
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.centerIn: parent
        width: Math.max(implicitWidth, parent.width - 24)
        spacing: 10

        // ── Recording status ─────────────────────────────────────────
        Rectangle {
            id: statusPill
            visible: root.recording || root.starting
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: statusRow.implicitWidth + 24
            implicitHeight: statusRow.implicitHeight + 10
            radius: Appearance.rounding.full
            color: root.paused ? Appearance.colors.colSecondaryContainer : Appearance.colors.colErrorContainer
            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            readonly property color ink: root.paused ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer

            RowLayout {
                id: statusRow
                anchors.centerIn: parent
                spacing: 8
                Rectangle {
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: root.paused ? statusPill.ink : Appearance.colors.colError
                    visible: !root.starting
                    SequentialAnimation on opacity {
                        running: root.recording && !root.paused && GlobalStates.overlayOpen
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) parent.opacity = 1
                        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
                MaterialSymbol {
                    visible: root.starting
                    text: "hourglass_top"
                    iconSize: Appearance.font.pixelSize.normal
                    color: statusPill.ink
                }
                StyledText {
                    text: root.starting ? Translation.tr("Starting…")
                        : (root.paused ? Translation.tr("Paused") : Translation.tr("Recording"))
                    font.weight: Font.DemiBold
                    color: statusPill.ink
                }
                StyledText {
                    visible: !root.starting
                    text: root.clock(root.elapsed)
                    font.family: Appearance.font.family.numbers
                    font.features: ({ "tnum": 1 })
                    color: statusPill.ink
                }
            }
        }

        // ── Main actions ─────────────────────────────────────────────
        Row {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            spacing: 10

            BigRecorderButton {
                materialSymbol: "screenshot_region"
                name: Translation.tr("Screenshot region")
                onClicked: {
                    GlobalStates.overlayOpen = false;
                    Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
                }
            }

            BigRecorderButton {
                materialSymbol: "photo_camera"
                name: Translation.tr("Screenshot")
                onClicked: {
                    GlobalStates.overlayOpen = false;
                    Quickshell.execDetached(["bash", "-c", "grim - | wl-copy"]);
                }
            }

            // Idle: the two ways to start. Recording: pause/resume and stop,
            // whoever started it (bar, keybind, island or this widget).
            BigRecorderButton {
                visible: !root.recording
                enabled: !root.starting
                materialSymbol: "screen_record"
                name: Translation.tr("Record region")
                onClicked: {
                    GlobalStates.overlayOpen = false;
                    Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "recordWithSound"]);
                }
            }

            BigRecorderButton {
                visible: !root.recording
                enabled: !root.starting
                materialSymbol: "capture"
                name: Translation.tr("Record screen")
                onClicked: {
                    root.runRecordScript(["--fullscreen", "--sound"]);
                    root.closeOverlay();
                }
            }

            BigRecorderButton {
                visible: root.recording
                materialSymbol: root.paused ? "play_arrow" : "pause"
                name: root.paused ? Translation.tr("Resume recording") : Translation.tr("Pause recording")
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                symbolColor: Appearance.colors.colOnSecondaryContainer
                onClicked: root.runRecordScript(["--pause"])
            }

            BigRecorderButton {
                visible: root.recording
                materialSymbol: "stop"
                name: Translation.tr("Stop recording")
                colBackground: Appearance.colors.colError
                colBackgroundHover: ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colOnError, 0.88)
                colRipple: ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colOnError, 0.75)
                symbolColor: Appearance.colors.colOnError
                onClicked: root.runRecordScript([])
            }
        }

        // ── Quick toggles ────────────────────────────────────────────
        // Before a recording they set what the next one starts with; during
        // one they act on it right away.
        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 4 * 66 + 3 * 10
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            QuickChip {
                symbol: "keyboard"
                label: Translation.tr("Keys")
                active: root.recording ? KeypressService.recordingEnabled
                    : Config.options.screenRecord.keypress.showWhileRecording
                tooltip: root.recording ? Translation.tr("Show keystrokes on screen now")
                    : Translation.tr("Show keystrokes while recording")
                onClicked: {
                    if (root.recording)
                        KeypressService.toggleForRecording();
                    else
                        Config.options.screenRecord.keypress.showWhileRecording = !Config.options.screenRecord.keypress.showWhileRecording;
                }
            }

            QuickChip {
                symbol: "mouse"
                label: Translation.tr("Clicks")
                active: Config.options.screenRecord.keypress.showMouseButtons
                tooltip: Translation.tr("Include mouse clicks in the keystroke display")
                onClicked: Config.options.screenRecord.keypress.showMouseButtons = !Config.options.screenRecord.keypress.showMouseButtons
            }

            QuickChip {
                visible: LiveDraw.enabled
                symbol: "draw"
                label: Translation.tr("Draw")
                active: LiveDraw.trayOpen
                tooltip: Translation.tr("Draw on screen (closes the overlay)")
                onClicked: {
                    LiveDraw.toggle();
                    root.closeOverlay();
                }
            }

            QuickChip {
                readonly property bool micMuted: Pipewire.defaultAudioSource?.audio?.muted ?? false
                visible: Pipewire.defaultAudioSource !== null
                symbol: micMuted ? "mic_off" : "mic"
                label: Translation.tr("Mic")
                active: !micMuted
                warn: micMuted
                tooltip: micMuted ? Translation.tr("Microphone muted") : Translation.tr("Microphone on")
                onClicked: Audio.toggleMicMute()
            }

            QuickChip {
                symbol: Notifications.silent ? "notifications_off" : "notifications"
                label: Translation.tr("Silent")
                active: Notifications.silent
                tooltip: Translation.tr("Do not disturb: keep notification popups out of the recording")
                onClicked: Notifications.silent = !Notifications.silent
            }
        }

        // ── Last recording ───────────────────────────────────────────
        Rectangle {
            visible: root.lastRecording !== null
            Layout.fillWidth: true
            Layout.maximumWidth: 4 * 66 + 3 * 10
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: lastRow.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer3

            RowLayout {
                id: lastRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 8
                }
                spacing: 10

                // Thumbnail; a click plays the video.
                Rectangle {
                    implicitWidth: 96
                    implicitHeight: 54
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    clip: true

                    StyledImage {
                        id: thumbImage
                        anchors.fill: parent
                        source: root.lastRecording?.thumb ? `file://${root.lastRecording.thumb}` : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: thumbImage.status !== Image.Ready
                        text: "movie"
                        iconSize: 24
                        color: Appearance.colors.colSubtext
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 3
                        visible: (root.lastRecording?.duration ?? 0) > 0
                        implicitWidth: durationText.implicitWidth + 8
                        implicitHeight: durationText.implicitHeight + 2
                        radius: Appearance.rounding.verysmall
                        color: ColorUtils.transparentize("#000000", 0.35)
                        StyledText {
                            id: durationText
                            anchors.centerIn: parent
                            text: root.clock(root.lastRecording?.duration ?? 0)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: "white"
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openLastVideo()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Last recording")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: FileUtils.fileNameForPath(root.lastRecording?.path ?? "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer3
                        elide: Text.ElideMiddle
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: [
                            root.lastRecording ? Qt.formatDateTime(new Date(root.lastRecording.mtime * 1000), "dd/MM HH:mm") : "",
                            root.humanSize(root.lastRecording?.size ?? 0)
                        ].filter(part => part !== "").join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.topMargin: 4
                        spacing: 2
                        SmallActionButton {
                            symbol: "play_arrow"
                            tooltip: Translation.tr("Open video")
                            onClicked: root.openLastVideo()
                        }
                        SmallActionButton {
                            symbol: "folder_open"
                            tooltip: Translation.tr("Show in folder")
                            onClicked: root.showLastVideoInFolder()
                        }
                        SmallActionButton {
                            symbol: "movie_edit"
                            tooltip: Config.options.screenRecord.openInLosslessCut
                                ? Translation.tr("Edit in LosslessCut") : Translation.tr("Edit in video editor")
                            onClicked: root.editLastVideo()
                        }
                    }
                }
            }
        }

        RippleButton {
            visible: root.lastRecording === null
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Layout.fillWidth: false
            readonly property int fullRadius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
            buttonRadius: fullRadius
            colBackground: Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: {
                Qt.openUrlExternally(`file://${root.savePath}`);
                root.closeOverlay();
            }
            contentItem: Row {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "animated_images"
                    iconSize: 20
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Open recordings folder")
                }
            }
        }
    }

    component BigRecorderButton: RippleButton {
        id: bigButton
        required property string materialSymbol
        required property string name
        property color symbolColor: Appearance.colors.colOnLayer3
        implicitHeight: 66
        implicitWidth: 66
        opacity: enabled ? 1 : 0.5
        readonly property int fullRadius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
        buttonRadius: fullRadius

        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: bigButton.materialSymbol
            iconSize: 28
            fill: 1
            color: bigButton.symbolColor
        }

        StyledToolTip {
            text: bigButton.name
        }
    }

    component QuickChip: RippleButton {
        id: chip
        required property string symbol
        required property string label
        property bool active: false
        property bool warn: false
        property string tooltip: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: chipColumn.implicitHeight + 14
        implicitWidth: chipColumn.implicitWidth + 8
        buttonRadius: Appearance.rounding.normal
        colBackground: chip.warn ? Appearance.colors.colErrorContainer
            : (chip.active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3)
        colBackgroundHover: chip.warn ? Appearance.colors.colErrorContainerHover
            : (chip.active ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
        colRipple: chip.active ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer3Active
        readonly property color ink: chip.warn ? Appearance.colors.colOnErrorContainer
            : (chip.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3)

        contentItem: Item {
            ColumnLayout {
                id: chipColumn
                anchors.centerIn: parent
                spacing: 1
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: chip.symbol
                    iconSize: 20
                    fill: chip.active || chip.warn ? 1 : 0
                    color: chip.ink
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: chip.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: chip.ink
                }
            }
        }

        StyledToolTip {
            extraVisibleCondition: chip.tooltip !== ""
            text: chip.tooltip
        }
    }

    component SmallActionButton: RippleButton {
        id: smallButton
        required property string symbol
        property string tooltip: ""
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: smallButton.symbol
            iconSize: 20
            color: Appearance.colors.colOnLayer3
        }
        StyledToolTip { text: smallButton.tooltip }
    }
}
