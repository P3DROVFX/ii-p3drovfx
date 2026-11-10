import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * Startup & Services → one systemd unit. The hero states it in words (running since, PID,
 * memory, next trigger for a timer) with start/stop/restart and start-at-boot; below, the
 * unit file (editable: user units are written directly, system units through pkexec + a
 * daemon-reload) beside its journal, stacked on narrow pages.
 */
ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    readonly property string scope: StartupManager.detailScope
    readonly property string unitName: StartupManager.detailUnit
    readonly property var d: StartupManager.detail
    readonly property var p: root.d?.props ?? ({})

    readonly property bool running: ["active", "activating", "reloading"].includes(root.p.ActiveState)
    readonly property bool failed: root.p.ActiveState === "failed"
    readonly property bool isTimer: root.unitName.endsWith(".timer")
    readonly property string fileState: root.p.UnitFileState ?? ""
    readonly property bool bootOn: root.fileState === "enabled" || root.fileState === "enabled-runtime"
    readonly property bool canToggleBoot: ["enabled", "disabled", "enabled-runtime"].includes(root.fileState)

    property string loadedContent: ""
    readonly property bool dirty: editor.text !== root.loadedContent
    onDChanged: {
        if (!root.d)
            return;
        // keep an edit in progress across a refresh
        if (!root.dirty || root.loadedContent === "") {
            root.loadedContent = root.d.content ?? "";
            editor.text = root.loadedContent;
        } else {
            root.loadedContent = root.d.content ?? "";
        }
    }

    function stamp(v) {
        // "Sat 2026-11-07 14:02:11 -03" → "Sat 14:02"
        if (!v || v === "n/a" || v === "0")
            return "";
        const m = v.match(/^(\w+)\s+\S+\s+(\d+:\d+)/);
        return m ? `${m[1]} ${m[2]}` : v;
    }
    function memory(bytes) {
        const b = Number(bytes);
        if (!b || b > 1e18)
            return "";
        return b > 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : Math.round(b / 1048576) + " MB";
    }
    readonly property string stateLine: {
        if (!root.d)
            return Translation.tr("Reading…");
        if (root.failed)
            return Translation.tr("Failed (%1) at %2").arg(root.p.Result ?? "").arg(stamp(root.p.InactiveEnterTimestamp));
        if (root.isTimer) {
            const next = stamp(root.p.NextElapseUSecRealtime);
            return root.running ? (next ? Translation.tr("Next run %1").arg(next) : Translation.tr("Waiting")) : Translation.tr("Stopped");
        }
        if (root.running) {
            const parts = [Translation.tr("Running since %1").arg(stamp(root.p.ActiveEnterTimestamp))];
            if (Number(root.p.MainPID) > 0)
                parts.push("PID " + root.p.MainPID);
            const mem = memory(root.p.MemoryCurrent);
            if (mem)
                parts.push(mem);
            return parts.join(" · ");
        }
        const since = stamp(root.p.InactiveEnterTimestamp);
        return since ? Translation.tr("Stopped since %1").arg(since) : Translation.tr("Stopped");
    }

    // ── header ──
    ConfigSubPageHeader {
        visible: root.showBackButton
        title: root.unitName
        onBack: root.goBack()
    }

    // ── hero ──
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: heroCol.implicitHeight + 40
        radius: Appearance.rounding.verylarge
        color: root.failed ? Appearance.colors.colErrorContainer : root.running ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        readonly property color colContent: root.failed ? Appearance.colors.colOnErrorContainer : root.running ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
        readonly property color colStrong: root.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
        readonly property color colOnStrong: root.failed ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
        id: hero

        ColumnLayout {
            id: heroCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 20
            }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: root.failed ? "error" : root.isTimer ? "schedule" : root.running ? "play_arrow" : "stop"
                    iconSize: 32
                    padding: 16
                    fill: 1
                    shape: root.failed ? MaterialShape.Shape.SoftBurst : root.running ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                    color: root.running || root.failed ? hero.colStrong : Appearance.colors.colSurfaceContainerHighest
                    colSymbol: root.running || root.failed ? hero.colOnStrong : Appearance.colors.colOnSurface
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.p.Description || root.unitName
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge + 4
                        color: hero.colContent
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.stateLine
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: hero.colContent
                        opacity: 0.85
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // facts as chips
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: {
                        const out = [];
                        out.push(root.scope === "user" ? Translation.tr("Session unit") : Translation.tr("System unit"));
                        if (root.d?.mine)
                            out.push(Translation.tr("Written by you"));
                        if (root.fileState)
                            out.push(root.fileState);
                        if ((root.d?.dropins ?? []).length > 0)
                            out.push(Translation.tr("%1 override(s)").arg(root.d.dropins.length));
                        if (root.p.TriggeredBy)
                            out.push(Translation.tr("Triggered by %1").arg(root.p.TriggeredBy));
                        if (root.p.Triggers)
                            out.push(Translation.tr("Runs %1").arg(root.p.Triggers));
                        if (Number(root.p.NRestarts) > 0)
                            out.push(Translation.tr("Restarted %1×").arg(root.p.NRestarts));
                        return out;
                    }
                    delegate: Rectangle {
                        required property string modelData
                        implicitHeight: 28
                        implicitWidth: chipText.implicitWidth + 20
                        radius: Appearance.rounding.full
                        color: ColorUtils.transparentize(hero.colContent, 0.88)
                        StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: hero.colContent
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButton {
                    implicitHeight: 44
                    implicitWidth: primaryRow.implicitWidth + 34
                    buttonRadius: height / 2
                    buttonRadiusPressed: Appearance.rounding.small
                    enabled: !!root.d && !StartupManager.busy && root.fileState !== "masked"
                    opacity: enabled ? 1 : 0.5
                    colBackground: hero.colStrong
                    colBackgroundHover: ColorUtils.mix(hero.colStrong, hero.colOnStrong, 0.9)
                    colRipple: ColorUtils.mix(hero.colStrong, hero.colOnStrong, 0.8)
                    onClicked: StartupManager.unitAction(root.scope, root.unitName, root.running ? "stop" : "start")
                    contentItem: Item {
                        RowLayout {
                            id: primaryRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: root.running ? "stop" : "play_arrow"
                                iconSize: 20
                                color: hero.colOnStrong
                            }
                            StyledText {
                                text: root.running ? Translation.tr("Stop") : Translation.tr("Start")
                                font.weight: Font.DemiBold
                                color: hero.colOnStrong
                            }
                        }
                    }
                }

                RippleButton {
                    implicitHeight: 44
                    implicitWidth: restartRow.implicitWidth + 30
                    buttonRadius: height / 2
                    visible: root.running && !root.isTimer
                    enabled: !StartupManager.busy
                    colBackground: ColorUtils.transparentize(hero.colContent, 0.88)
                    colBackgroundHover: ColorUtils.transparentize(hero.colContent, 0.8)
                    colRipple: ColorUtils.transparentize(hero.colContent, 0.7)
                    onClicked: StartupManager.unitAction(root.scope, root.unitName, "restart")
                    contentItem: Item {
                        RowLayout {
                            id: restartRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "restart_alt"
                                iconSize: 20
                                color: hero.colContent
                            }
                            StyledText {
                                text: Translation.tr("Restart")
                                font.weight: Font.DemiBold
                                color: hero.colContent
                            }
                        }
                    }
                }

                RippleButton {
                    implicitHeight: 44
                    implicitWidth: unmaskText.implicitWidth + 30
                    buttonRadius: height / 2
                    visible: root.fileState === "masked"
                    colBackground: ColorUtils.transparentize(hero.colContent, 0.88)
                    colBackgroundHover: ColorUtils.transparentize(hero.colContent, 0.8)
                    onClicked: StartupManager.unitAction(root.scope, root.unitName, "unmask")
                    contentItem: Item {
                        StyledText {
                            id: unmaskText
                            anchors.centerIn: parent
                            text: Translation.tr("Unmask")
                            font.weight: Font.DemiBold
                            color: hero.colContent
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    visible: root.canToggleBoot
                    text: root.scope === "user" ? Translation.tr("Start at login") : Translation.tr("Start at boot")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: hero.colContent
                }
                StyledSwitch {
                    visible: root.canToggleBoot
                    sizeScale: 0.9
                    checked: root.bootOn
                    enabled: !StartupManager.busy
                    activeColor: hero.colStrong
                    activeThumbColor: hero.colOnStrong
                    onToggled: StartupManager.unitAction(root.scope, root.unitName, checked ? "enable" : "disable")
                }
            }
        }
    }

    // ── unit file | journal ──
    Item {
        id: panes
        Layout.fillWidth: true
        readonly property bool stacked: width < 860
        readonly property int paneHeight: 440
        implicitHeight: stacked ? paneHeight * 2 + 12 : paneHeight

        // unit file
        Rectangle {
            id: filePane
            x: 0
            y: 0
            width: panes.stacked ? panes.width : (panes.width - 12) * 0.55
            height: panes.paneHeight
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            RowLayout {
                id: fileHeader
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 16
                    leftMargin: 20
                }
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr("Unit file")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.d?.path || Translation.tr("No file (generated or transient)")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideMiddle
                    }
                }
                CircleAction {
                    visible: root.dirty
                    symbol: "undo"
                    tip: Translation.tr("Revert")
                    onClicked: editor.text = root.loadedContent
                }
                RippleButton {
                    visible: root.dirty
                    implicitHeight: 36
                    implicitWidth: saveText.implicitWidth + 28
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    enabled: !StartupManager.busy
                    onClicked: StartupManager.saveUnit(root.scope, root.unitName, root.d.path, editor.text)
                    contentItem: Item {
                        StyledText {
                            id: saveText
                            anchors.centerIn: parent
                            text: root.d?.writable || root.scope === "user" ? Translation.tr("Save") : Translation.tr("Save as admin")
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
                CircleAction {
                    visible: !!root.d?.path
                    symbol: "open_in_new"
                    tip: Translation.tr("Open in editor")
                    onClicked: StartupManager.openInEditor(root.d.path)
                }
            }

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: fileHeader.bottom
                    bottom: parent.bottom
                    margins: 8
                    topMargin: 12
                }
                radius: Appearance.rounding.verylarge - 8
                color: Appearance.colors.colLayer2

                StyledFlickable {
                    id: editorFlick
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    contentWidth: Math.max(width, editor.implicitWidth)
                    contentHeight: editor.implicitHeight

                    TextEdit {
                        id: editor
                        width: Math.max(editorFlick.width, implicitWidth)
                        readOnly: !root.d?.path
                        selectByMouse: true
                        wrapMode: TextEdit.NoWrap
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                        selectionColor: Appearance.colors.colSecondaryContainer
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }

        // journal
        Rectangle {
            x: panes.stacked ? 0 : filePane.width + 12
            y: panes.stacked ? panes.paneHeight + 12 : 0
            width: panes.stacked ? panes.width : panes.width - filePane.width - 12
            height: panes.paneHeight
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            RowLayout {
                id: logHeader
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 16
                    leftMargin: 20
                }
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr("Log")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Last 80 lines of the journal")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
                CircleAction {
                    symbol: "refresh"
                    tip: Translation.tr("Refresh")
                    enabled: !StartupManager.detailLoading
                    onClicked: StartupManager.showUnit(root.scope, root.unitName)
                }
            }

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: logHeader.bottom
                    bottom: parent.bottom
                    margins: 8
                    topMargin: 12
                }
                radius: Appearance.rounding.verylarge - 8
                color: Appearance.colors.colLayer2

                StyledFlickable {
                    id: logFlick
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    contentHeight: logText.implicitHeight
                    // newest lines at the bottom: start there
                    onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                    TextEdit {
                        id: logText
                        width: logFlick.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: (root.d?.log ?? "") !== "" ? root.d.log : Translation.tr("No journal entries (or no permission to read the system journal).")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer2
                        selectionColor: Appearance.colors.colSecondaryContainer
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
