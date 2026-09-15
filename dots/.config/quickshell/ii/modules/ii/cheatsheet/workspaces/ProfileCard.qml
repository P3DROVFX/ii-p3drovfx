pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects

/**
 * ProfileCard — a single saved workspace profile displayed in CheatsheetWorkspaces.
 *
 * Props exposed by the parent via model delegation:
 *   slug, name, emoji, description, createdAt, windowCount, workspaceIds, hasDuplicateClasses
 */
Item {
    id: root

    // ── required props ──────────────────────────────────────────────────────
    required property string slug
    required property string name
    required property string emoji
    required property string description
    required property int createdAt
    required property int windowCount
    required property string workspaceIdsJson
    required property string windowsJson
    required property bool hasDuplicateClasses
    required property bool closeOthers
    required property bool killOthers
    required property bool pinned

    // ── internal state ──────────────────────────────────────────────────────
    property bool isRestoring: false
    property bool restoreSuccess: false
    property bool restorePartial: false

    Connections {
        target: WorkspaceProfileService
        function onRestoringChanged() {
            root.updateRestoring();
        }
        function onRestoringSlugChanged() {
            root.updateRestoring();
        }
    }
    function updateRestoring() {
        root.isRestoring = WorkspaceProfileService.restoring && WorkspaceProfileService.restoringSlug === root.slug;
    }

    property string shortcutHint: ""
    property bool showDeleteConfirm: false

    readonly property bool mutating: WorkspaceProfileService.busy && WorkspaceProfileService.activeMutationSlug === root.slug

    // ── signals ──────────────────────────────────────────────────────────────
    signal restoreRequested
    signal deleteRequested
    signal editRequested
    signal togglePinRequested

    function requestDeleteAction() {
        if (root.showDeleteConfirm) {
            root.deleteRequested();
        } else {
            root.showDeleteConfirm = true;
            deleteConfirmResetTimer.restart();
        }
    }

    readonly property var workspaceIds: {
        try {
            return JSON.parse(workspaceIdsJson);
        } catch (e) {
            return [];
        }
    }

    readonly property var windowsList: {
        try {
            return JSON.parse(windowsJson);
        } catch (e) {
            return [];
        }
    }

    property bool hasMatches: true
    property bool entered: false

    visible: hasMatches || opacity > 0.0
    opacity: entered && hasMatches ? 1.0 : 0.0
    scale: entered && hasMatches ? 1.0 : 0.97

    // Height driven by content and filter matching
    height: entered && hasMatches ? implicitHeight : 0
    implicitHeight: entered && hasMatches ? cardBg.implicitHeight : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasized
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasized
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasized
        }
    }

    function _slugHash() {
        var h = 0;
        for (var i = 0; i < root.slug.length; i++) {
            h = (h * 31 + root.slug.charCodeAt(i)) & 0xFFFF;
        }
        return h;
    }

    // ── shape cycling — derived from slug hash so no model index needed ──────
    readonly property var cardShapes: ["Circle", "Cookie9Sided", "Flower"]
    readonly property string cardShape: cardShapes[_slugHash() % cardShapes.length]
    
    // stagger delay derived from same hash (0–3 steps of 45 ms)
    readonly property int staggerDelay: (_slugHash() % 4) * 45

    // ── colours (from M3 tokens) ─────────────────────────────────────────────
    readonly property color colBg: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1 : Appearance.m3colors.m3surfaceContainerHigh
    readonly property color colBgHover: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1Hover : Appearance.m3colors.m3surfaceContainer
    readonly property color colBorder: Appearance.colors.colOutlineVariant
    readonly property color colOnSurface: Appearance.colors.colOnSurface
    readonly property color colSubtle: Appearance.colors.colOnSurfaceVariant
    readonly property color colPrimary: Appearance.colors.colPrimary
    readonly property color colOnPrimary: Appearance.colors.colOnPrimary
    readonly property color colChipBg: Appearance.colors.colSecondaryContainer
    readonly property color colChipText: Appearance.colors.colOnSecondaryContainer
    readonly property color colWarnBg: Appearance.colors.colTertiaryContainer
    readonly property color colWarnText: Appearance.colors.colOnTertiaryContainer
    readonly property color colErrorBg: Appearance.colors.colErrorContainer
    readonly property color colErrorText: Appearance.colors.colOnErrorContainer
    readonly property color colSuccessBg: Appearance.m3colors.m3primaryContainer

    // ── reset feedback state when signals arrive ─────────────────────────────
    Connections {
        target: WorkspaceProfileService

        function onRestoreFinished(success, errors) {
            if (root.isRestoring) {
                root.restoreSuccess = success && errors === 0;
                root.restorePartial = !root.restoreSuccess;
                feedbackResetTimer.restart();
            }
        }
    }

    Timer {
        id: feedbackResetTimer
        interval: 2500
        onTriggered: {
            root.restoreSuccess = false;
            root.restorePartial = false;
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    // ── staggered entrance animation ─────────────────────────────────────────
    Component.onCompleted: {
        entranceDelayTimer.start();
        root.updateRestoring();
    }

    Timer {
        id: entranceDelayTimer
        interval: root.staggerDelay
        onTriggered: {
            root.entered = true;
        }
    }

    // ── card background ──────────────────────────────────────────────────────
    Rectangle {
        id: cardBg
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        radius: Appearance.rounding.large
        color: hoverHandler.hovered ? root.colBgHover : root.colBg
        border.width: Config.options.appearance.borderless ? 0 : 1
        border.color: root.colBorder
        implicitHeight: cardLayout.implicitHeight + 36
        clip: true
        opacity: root.mutating ? 0.85 : 1.0

        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
            }
        }


        ColumnLayout {
            id: cardLayout
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: 20; rightMargin: 16; topMargin: 16
            }
            spacing: 10

            // ── header row ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // MaterialShape cycling emoji badge
                MaterialShape {
                    shapeString: root.cardShape
                    implicitSize: 40
                    color: Appearance.colors.colPrimaryContainer

                    StyledText {
                        anchors.centerIn: parent
                        text: root.emoji
                        font.pixelSize: 20
                    }
                }

                // name display
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    RowLayout {
                        spacing: 6
                        Layout.fillWidth: true

                        StyledText {
                            text: root.name
                            font {
                                pixelSize: Appearance.font.pixelSize.large
                                weight: Font.Bold
                            }
                            color: root.colOnSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        MaterialSymbol {
                            visible: root.pinned
                            text: "push_pin"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colPrimary
                            fill: 1
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    StyledText {
                        visible: root.description.length > 0
                        text: root.description
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.colSubtle
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }



                // action buttons (rename / delete)
                RowLayout {
                    spacing: 4

                    RippleButton {
                        implicitWidth: 36; implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.pinned ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                        colBackgroundHover: root.pinned ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSecondaryContainerHover
                        onClicked: root.togglePinRequested()
                        StyledToolTip { text: root.pinned ? "Unpin profile" : "Pin profile" }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "push_pin"
                            fill: root.pinned
                            iconSize: Appearance.font.pixelSize.small
                            color: root.pinned ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    RippleButton {
                        implicitWidth: 36; implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.editRequested()
                        StyledToolTip { text: "Edit profile" }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "edit"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    RippleButton {
                        implicitWidth: 36; implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.showDeleteConfirm
                            ? Appearance.colors.colError
                            : Appearance.colors.colErrorContainer
                        colBackgroundHover: root.showDeleteConfirm
                            ? Appearance.colors.colErrorHover
                            : Appearance.colors.colErrorContainerHover
                        onClicked: {
                            if (root.showDeleteConfirm) {
                                root.deleteRequested();
                            } else {
                                root.showDeleteConfirm = true;
                                deleteConfirmResetTimer.restart();
                            }
                        }
                        StyledToolTip { text: root.showDeleteConfirm ? "Confirm delete" : qsTr("Delete profile") }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.showDeleteConfirm ? "warning" : "delete"
                            iconSize: Appearance.font.pixelSize.small
                            color: root.showDeleteConfirm
                                ? Appearance.colors.colOnError
                                : Appearance.colors.colOnErrorContainer
                        }
                        Timer {
                            id: deleteConfirmResetTimer
                            interval: 3000
                            onTriggered: root.showDeleteConfirm = false
                        }
                    }
                }
            }

            // ── workspace chips row + duplicate warning ───────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                // Container for horizontal scrolling of workspace chips
                Item {
                    id: chipsContainer
                    Layout.fillWidth: true
                    implicitHeight: 36
                    clip: true

                    Flickable {
                        id: chipsFlickable
                        anchors.fill: parent
                        contentWidth: chipsRow.implicitWidth
                        contentHeight: 36
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick
                        clip: true

                        onMovementStarted: scrollAnim.stop()

                        readonly property bool showLeftFade: contentX > 5
                        readonly property bool showRightFade: contentWidth > width && contentX < contentWidth - width - 5

                        property color leftFadeColor: showLeftFade ? "transparent" : "white"
                        property color rightFadeColor: showRightFade ? "transparent" : "white"

                        Behavior on leftFadeColor {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                        Behavior on rightFadeColor {
                            ColorAnimation {
                                duration: 150
                            }
                        }

                        layer.enabled: chipsFlickable.contentWidth > chipsFlickable.width
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: chipsFlickable.width
                                height: chipsFlickable.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop {
                                        position: 0.0
                                        color: chipsFlickable.leftFadeColor
                                    }
                                    GradientStop {
                                        position: 0.07
                                        color: "white"
                                    }
                                    GradientStop {
                                        position: 0.93
                                        color: "white"
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: chipsFlickable.rightFadeColor
                                    }
                                }
                            }
                        }

                        RowLayout {
                            id: chipsRow
                            height: 36
                            spacing: 8

                            Repeater {
                                model: root.workspaceIds
                                delegate: Rectangle {
                                    id: chipItem
                                    required property var modelData
                                    radius: Appearance.rounding.full
                                    color: root.colChipBg
                                    implicitWidth: chipRow.implicitWidth + 12 + 2
                                    implicitHeight: 28

                                    RowLayout {
                                        id: chipRow
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        Repeater {
                                            model: root.getWorkspaceClasses(chipItem.modelData)
                                            delegate: Image {
                                                required property var modelData
                                                sourceSize: Qt.size(16, 16)
                                                source: {
                                                    const _ = TaskbarApps.iconThemeRevision;
                                                    return Quickshell.iconPath(AppSearch.guessIcon(modelData), "");
                                                }
                                                visible: source.toString() !== "" && status !== Image.Error
                                                smooth: true
                                            }
                                        }

                                        StyledText {
                                            id: chipLabel
                                            text: root.getWorkspaceApps(chipItem.modelData)
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: root.colChipText
                                        }

                                        Rectangle {
                                            id: workspaceBadge
                                            implicitWidth: 24
                                            implicitHeight: 24
                                            radius: 12
                                            color: Appearance.colors.colTertiary
                                            Layout.alignment: Qt.AlignVCenter

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: {
                                                    let val = chipItem.modelData;
                                                    if (typeof val === "string" && val.startsWith("special:")) {
                                                        return "S";
                                                    }
                                                    return val.toString();
                                                }
                                                font.pixelSize: text.length > 1 ? 8 : 10
                                                font.weight: Font.Light
                                                color: Appearance.colors.colOnTertiary
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    NumberAnimation {
                        id: scrollAnim
                        target: chipsFlickable
                        property: "contentX"
                        duration: 250
                        easing.type: Easing.OutCubic
                    }

                    RippleButton {
                        id: scrollLeftBtn
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        visible: chipsFlickable.showLeftFade
                        onClicked: {
                            scrollAnim.stop();
                            scrollAnim.to = Math.max(0, chipsFlickable.contentX - 100);
                            scrollAnim.start();
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_left"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    RippleButton {
                        id: scrollRightBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        visible: chipsFlickable.showRightFade
                        onClicked: {
                            scrollAnim.stop();
                            scrollAnim.to = Math.min(chipsFlickable.contentWidth - chipsFlickable.width, chipsFlickable.contentX + 100);
                            scrollAnim.start();
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }

                // duplicate apps warning badge (if any classes overlap)
                Rectangle {
                    visible: root.hasDuplicateClasses
                    radius: Appearance.rounding.full
                    color: root.colWarnBg
                    implicitWidth: warnRow.implicitWidth + 20
                    implicitHeight: 28
                    scale: warnHover.hovered ? 1.05 : 1.0
                    antialiasing: true

                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    HoverHandler {
                        id: warnHover
                    }

                    RowLayout {
                        id: warnRow
                        anchors.centerIn: parent
                        spacing: 3

                        MaterialSymbol {
                            text: "info"
                            iconSize: Appearance.font.pixelSize.small
                            color: root.colWarnText
                        }
                        StyledText {
                            text: "best-effort"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: root.colWarnText
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: warnHover.hovered
                        text: "Some apps share a window class (e.g. two terminals). " + "Restore will match by workspace proximity—result may vary."
                    }
                }

            }

            // ── restore button row ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // window count badge
                Rectangle {
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                    implicitWidth: winCountText.implicitWidth + 12
                    implicitHeight: 24
                    opacity: 0.85
                    Layout.alignment: Qt.AlignVCenter

                    StyledText {
                        id: winCountText
                        anchors.centerIn: parent
                        text: `${root.windowCount} win${root.windowCount !== 1 ? "dows" : "dow"}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.colSubtle
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // feedback
                RowLayout {
                    spacing: 6
                    visible: root.restoreSuccess || root.restorePartial || opacity > 0.0
                    opacity: (root.restoreSuccess || root.restorePartial) ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    MaterialSymbol {
                        text: root.restoreSuccess ? "check_circle" : "warning"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.restoreSuccess ? Appearance.m3colors.m3primary : Appearance.m3colors.m3tertiary
                        fill: 1
                    }
                    StyledText {
                        text: root.restoreSuccess ? "Restored" : "Partially restored"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.restoreSuccess ? Appearance.m3colors.m3primary : Appearance.m3colors.m3tertiary
                    }
                }

                MaterialLoadingIndicator {
                    visible: root.isRestoring || root.mutating
                    implicitWidth: 24
                    implicitHeight: 24
                }

                StyledText {
                    visible: root.shortcutHint !== ""
                    text: `Restore: ${root.shortcutHint} ◦ Delete: ${root.shortcutHint.replace("Ctrl+", "Ctrl+Alt+")}`
                    font {
                        pixelSize: Appearance.font.pixelSize.smaller
                        weight: Font.Bold
                    }
                    color: root.colSubtle
                    opacity: 0.6
                    Layout.alignment: Qt.AlignVCenter
                }

                // restore button — larger for prominence
                RippleButtonWithIcon {
                    id: restoreBtn
                    materialIcon: "play_arrow"
                    materialIconFill: true
                    mainText: "Restore"
                    enabled: WorkspaceProfileService.restoringSlug !== root.slug
                    colText: Appearance.colors.colOnPrimary
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    buttonRadius: Appearance.rounding.full
                    implicitHeight: 40
                    leftPadding: 18
                    rightPadding: 18
                    StyledToolTip { text: qsTr("Restore") }

                    onClicked: root.restoreRequested()
                }
            }
        }
    }

    // ── helpers ──────────────────────────────────────────────────────────────
    function cleanAppName(cls) {
        if (!cls)
            return "";
        let name = cls.toLowerCase();
        if (name === "brave-browser" || name === "brave")
            return "Brave";
        if (name === "google-chrome" || name === "chrome")
            return "Chrome";
        if (name === "kitty")
            return "Kitty";
        if (name === "code" || name === "visual-studio-code")
            return "VS Code";
        if (name === "firefox")
            return "Firefox";
        if (name === "discord")
            return "Discord";
        if (name === "spotify")
            return "Spotify";
        if (name === "steam")
            return "Steam";
        if (name === "obs")
            return "OBS Studio";
        if (name === "thunderbird")
            return "Thunderbird";
        if (name === "dolphin")
            return "Dolphin";
        if (name === "thunar")
            return "Thunar";
        if (name === "nautilus")
            return "Files";
        if (name === "vlc")
            return "VLC";
        if (name === "mpv")
            return "mpv";
        if (name === "gimp")
            return "GIMP";
        if (name === "inkscape")
            return "Inkscape";
        if (name === "libreoffice-writer")
            return "Writer";
        if (name === "libreoffice-calc")
            return "Calc";
        name = name.replace(/[-_]/g, " ");
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function getWorkspaceApps(wsId) {
        let apps = [];
        for (const w of root.windowsList) {
            if (w.workspaceId === wsId) {
                let cleanName = cleanAppName(w.class || w.initialClass);
                if (cleanName && !apps.includes(cleanName))
                    apps.push(cleanName);
            }
        }
        return apps.length > 0 ? apps.join(", ") : ((typeof wsId === "string" && wsId.startsWith("special")) || (typeof wsId === "number" && wsId < 0) ? "scratchpad" : `ws ${wsId}`);
    }

    function getWorkspaceClasses(wsId) {
        let classes = [];
        for (const w of root.windowsList) {
            if (w.workspaceId === wsId) {
                let className = w.class || w.initialClass;
                if (className && !classes.includes(className))
                    classes.push(className);
            }
        }
        return classes;
    }

    function _dateString(epoch) {
        const d = new Date(epoch * 1000);
        return d.toLocaleDateString(Qt.locale(), "dd MMM yyyy");
    }

    function _ageString(epoch) {
        const now = Math.floor(Date.now() / 1000);
        const delta = now - epoch;
        if (delta < 60)
            return "just now";
        if (delta < 3600)
            return `${Math.floor(delta / 60)}m ago`;
        if (delta < 86400)
            return `${Math.floor(delta / 3600)}h ago`;
        if (delta < 86400 * 7)
            return `${Math.floor(delta / 86400)}d ago`;
        return _dateString(epoch);
    }
}
