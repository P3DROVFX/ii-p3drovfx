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
    required property int    createdAt
    required property int    windowCount
    required property string workspaceIdsJson
    required property string windowsJson
    required property bool   hasDuplicateClasses
    required property bool   closeOthers
    required property bool   killOthers
    required property bool   pinned

    // ── internal state ──────────────────────────────────────────────────────
    property bool isRestoring:   false
    property bool restoreSuccess: false
    property bool restorePartial: false

    Connections {
        target: WorkspaceProfileService
        function onRestoringChanged() { root.updateRestoring() }
        function onRestoringSlugChanged() { root.updateRestoring() }
    }
    function updateRestoring() {
        root.isRestoring = WorkspaceProfileService.restoring && WorkspaceProfileService.restoringSlug === root.slug;
    }

    property string shortcutHint: ""
    property bool showDeleteConfirm: false
    property bool isEditing: false
    property string editNameValue: root.name
    property string editEmojiValue: root.emoji
    property string editDescriptionValue: root.description
    property bool expanded: false
    property bool showAddAppForm: false

    readonly property bool mutating: WorkspaceProfileService.busy && WorkspaceProfileService.activeMutationSlug === root.slug

    onExpandedChanged: {
        if (!expanded) {
            root.showAddAppForm = false;
            root.newAppClass = "";
            root.newAppWorkspace = "1";
            root.newAppAutolaunch = true;
            root.newAppLaunchCmd = "";
        }
    }
    property string newAppClass: ""
    property string newAppWorkspace: "1"
    property bool newAppAutolaunch: true
    property string newAppLaunchCmd: ""

    // ── signals ──────────────────────────────────────────────────────────────
    signal restoreRequested()
    signal deleteRequested()
    signal renameRequested(string newName)
    signal updateEmojiRequested(string newEmoji)
    signal toggleExpandedRequested()
    signal togglePinRequested()
    signal updateDescriptionRequested(string newDescription)

    function requestDeleteAction() {
        if (root.showDeleteConfirm) {
            root.deleteRequested();
        } else {
            root.showDeleteConfirm = true;
            deleteConfirmResetTimer.restart();
        }
    }

    readonly property var workspaceIds: {
        try { return JSON.parse(workspaceIdsJson); } catch(e) { return []; }
    }

    readonly property var windowsList: {
        try { return JSON.parse(windowsJson); } catch(e) { return []; }
    }

    // Height driven by content
    implicitHeight: cardBg.implicitHeight

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
    readonly property color colBg:          Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1 : Appearance.m3colors.m3surfaceContainerLow
    readonly property color colBgHover:     Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1Hover : Appearance.m3colors.m3surfaceContainer
    readonly property color colBorder:      Appearance.colors.colOutlineVariant
    readonly property color colOnSurface:   Appearance.colors.colOnSurface
    readonly property color colSubtle:      Appearance.colors.colOnSurfaceVariant
    readonly property color colPrimary:     Appearance.colors.colPrimary
    readonly property color colOnPrimary:   Appearance.colors.colOnPrimary
    readonly property color colChipBg:      Appearance.colors.colSecondaryContainer
    readonly property color colChipText:    Appearance.colors.colOnSecondaryContainer
    readonly property color colWarnBg:      Appearance.colors.colTertiaryContainer
    readonly property color colWarnText:    Appearance.colors.colOnTertiaryContainer
    readonly property color colErrorBg:     Appearance.colors.colErrorContainer
    readonly property color colErrorText:   Appearance.colors.colOnErrorContainer
    readonly property color colSuccessBg:   Appearance.m3colors.m3primaryContainer

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

    HoverHandler { id: hoverHandler }

    // ── staggered entrance animation ─────────────────────────────────────────
    opacity: 0.0
    scale: 0.97
    Component.onCompleted: {
        entranceDelayTimer.start();
        root.updateRestoring();
    }

    Timer {
        id: entranceDelayTimer
        interval: root.staggerDelay
        onTriggered: { entranceOpacity.start(); entranceScale.start(); }
    }
    NumberAnimation {
        id: entranceOpacity
        target: root; property: "opacity"
        from: 0.0; to: 1.0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }
    NumberAnimation {
        id: entranceScale
        target: root; property: "scale"
        from: 0.97; to: 1.0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    // ── card background ───────────────────────────────────────────────────────
    Rectangle {
        id: cardBg
        anchors { left: parent.left; right: parent.right; top: parent.top }
        radius: Appearance.rounding.large
        color: hoverHandler.hovered ? root.colBgHover : root.colBg
        border.width: Config.options.appearance.borderless ? 0 : 1
        border.color: root.colBorder
        implicitHeight: cardLayout.implicitHeight + 36
        clip: true
        opacity: root.mutating ? 0.85 : 1.0

        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        Behavior on opacity {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }

        // ── left accent bar ──────────────────────────────────────────────────
        Rectangle {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 4
            height: parent.height * 0.55
            radius: Appearance.rounding.full
            color: root.colPrimary
            opacity: 0.55
        }

        // ── subtle gradient overlay (top tint → transparent) ─────────────────
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: Config.options.appearance.transparency.enable
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(
                        root.colPrimary.r,
                        root.colPrimary.g,
                        root.colPrimary.b,
                        0.07
                    )
                }
                GradientStop { position: 0.55; color: "transparent" }
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
                        text: root.isEditing ? root.editEmojiValue : root.emoji
                        font.pixelSize: 20
                    }
                }

                // name display
                ColumnLayout {
                    visible: !root.isEditing
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

                // shortcut badge
                Rectangle {
                    visible: !root.isEditing && root.shortcutHint !== ""
                    color: Appearance.colors.colSurfaceContainerHighest
                    radius: Appearance.rounding.verysmall
                    implicitWidth: scText.implicitWidth + 10
                    implicitHeight: 22
                    Layout.alignment: Qt.AlignVCenter
                    StyledText {
                        id: scText
                        anchors.centerIn: parent
                        text: root.shortcutHint
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        font.weight: Font.Bold
                    }
                }

                // edit name text field
                MaterialTextField {
                    visible: root.isEditing
                    Layout.fillWidth: true
                    text: root.editNameValue
                    placeholderText: "Profile name…"
                    onTextChanged: root.editNameValue = text
                    font.pixelSize: Appearance.font.pixelSize.normal
                    onVisibleChanged: { if (visible) forceActiveFocus(); }
                    Keys.onReturnPressed: {
                        if (root.editNameValue.trim().length > 0) {
                            root.renameRequested(root.editNameValue.trim());
                            root.isEditing = false;
                        }
                    }
                    Keys.onEscapePressed: root.isEditing = false
                }

                // action buttons (rename / delete)
                RowLayout {
                    spacing: 4
                    visible: !root.isEditing

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
                        onClicked: {
                            root.editNameValue = root.name;
                            root.editEmojiValue = root.emoji;
                            root.editDescriptionValue = root.description || "";
                            root.isEditing = true;
                        }
                        StyledToolTip { text: "Rename" }
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
                        StyledToolTip { text: root.showDeleteConfirm ? "Confirm delete" : "Delete profile" }
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

                // confirm / cancel when editing
                RowLayout {
                    spacing: 4
                    visible: root.isEditing

                    RippleButton {
                        implicitWidth: 36; implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        enabled: root.editNameValue.trim().length > 0
                        onClicked: {
                            if (root.editNameValue.trim() !== root.name) {
                                root.renameRequested(root.editNameValue.trim());
                            }
                            if (root.editEmojiValue !== root.emoji) {
                                root.updateEmojiRequested(root.editEmojiValue);
                            }
                            if (root.editDescriptionValue.trim() !== (root.description || "")) {
                                root.updateDescriptionRequested(root.editDescriptionValue.trim());
                            }
                            root.isEditing = false;
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                    RippleButton {
                        implicitWidth: 36; implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        onClicked: root.isEditing = false
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: Appearance.font.pixelSize.small
                            color: root.colSubtle
                        }
                    }
                }
            }

            // edit emoji picker
            Flow {
                visible: root.isEditing
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: WorkspaceProfileService.presetEmojis
                    delegate: RippleButton {
                        required property var modelData
                        implicitWidth: 30; implicitHeight: 30
                        buttonRadius: Appearance.rounding.small
                        toggled: root.editEmojiValue === modelData
                        colBackgroundToggled: Appearance.colors.colPrimaryContainer

                        scale: toggled ? 1.15 : 1.0
                        Behavior on scale {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }

                        onClicked: root.editEmojiValue = modelData

                        StyledText {
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }

            // edit description text field
            MaterialTextField {
                visible: root.isEditing
                Layout.fillWidth: true
                text: root.editDescriptionValue
                placeholderText: "Add a description... (optional)"
                onTextChanged: root.editDescriptionValue = text
                font.pixelSize: Appearance.font.pixelSize.small
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

                        Behavior on leftFadeColor { ColorAnimation { duration: 150 } }
                        Behavior on rightFadeColor { ColorAnimation { duration: 150 } }

                        layer.enabled: chipsFlickable.contentWidth > chipsFlickable.width
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: chipsFlickable.width
                                height: chipsFlickable.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: chipsFlickable.leftFadeColor }
                                    GradientStop { position: Math.min(1.0, 72 / chipsFlickable.width); color: "white" }
                                    GradientStop { position: Math.max(0, (chipsFlickable.width - 72) / chipsFlickable.width); color: "white" }
                                    GradientStop { position: 1.0; color: chipsFlickable.rightFadeColor }
                                }
                            }
                        }

                        Row {
                            id: chipsRow
                            spacing: 6
                            height: parent.height

                            Repeater {
                                model: root.workspaceIds
                                delegate: Item {
                                    id: chipItem
                                    required property var modelData

                                    implicitWidth: chipRect.implicitWidth
                                    implicitHeight: chipRect.implicitHeight

                                    HoverHandler { id: chipHover }

                                    scale: chipHover.hovered ? 1.03 : 1.0
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: Appearance.animation.elementMoveFast.duration
                                            easing.type: Appearance.animation.elementMoveFast.type
                                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                        }
                                    }

                                    Rectangle {
                                        id: chipRect
                                        radius: Appearance.rounding.full
                                        color: root.colChipBg
                                        implicitWidth: chipRow.implicitWidth + 16
                                        implicitHeight: 36

                                        RowLayout {
                                            id: chipRow
                                            anchors.centerIn: parent
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
                        visible: chipsFlickable.contentWidth > chipsFlickable.width && chipsFlickable.contentX > 5

                        onClicked: {
                            scrollAnim.stop();
                            scrollAnim.to = Math.max(chipsFlickable.contentX - 120, 0);
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
                        visible: chipsFlickable.contentWidth > chipsFlickable.width && chipsFlickable.contentX < chipsFlickable.contentWidth - chipsFlickable.width - 5

                        onClicked: {
                            scrollAnim.stop();
                            scrollAnim.to = Math.min(chipsFlickable.contentX + 120, chipsFlickable.contentWidth - chipsFlickable.width);
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

                // duplicate-class warning badge
                Rectangle {
                    visible: root.hasDuplicateClasses
                    radius: Appearance.rounding.full
                    color: root.colWarnBg
                    implicitWidth: warnRow.implicitWidth + 14
                    implicitHeight: 36
                    scale: warnHover.hovered ? 1.05 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    HoverHandler { id: warnHover }

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
                        text: "Some apps share a window class (e.g. two terminals). " +
                              "Restore will match by workspace proximity—result may vary."
                    }
                }

                // window count badge
                Rectangle {
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                    implicitWidth: winCountText.implicitWidth + 12
                    implicitHeight: 24
                    opacity: 0.85

                    StyledText {
                        id: winCountText
                        anchors.centerIn: parent
                        text: `${root.windowCount} win${root.windowCount !== 1 ? "dows" : "dow"}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.colSubtle
                    }
                }


            }

            // ── restore button row ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // tune button — rotates 180° on expand
                RippleButton {
                    implicitWidth: 36; implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.expanded
                        ? Appearance.colors.colSecondaryContainer
                        : Appearance.colors.colLayer2
                    onClicked: root.toggleExpandedRequested()
                    StyledToolTip {
                        text: root.expanded ? "Collapse details" : "Configure autolaunch & windows"
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "tune"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.expanded
                            ? Appearance.colors.colOnSecondaryContainer
                            : root.colOnSurface

                        rotation: root.expanded ? 180 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: Appearance.animation.elementResize.duration
                                easing.type: Appearance.animation.elementResize.type
                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                        }
                    }
                }

                // Kill other windows switch
                RowLayout {
                    spacing: 8
                    Layout.leftMargin: 4

                    StyledText {
                        text: "Kill all other windows on restore"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.colOnSurface
                    }
                    StyledSwitch {
                        checked: root.killOthers
                        onCheckedChanged: {
                            if (checked !== root.killOthers) {
                                let newKill = checked;
                                let newClose = root.closeOthers;
                                if (newKill) newClose = false;
                                WorkspaceProfileService.updateProfileOptions(root.slug, newClose, newKill)
                            }
                        }
                    }
                }

                // Close other windows switch
                RowLayout {
                    spacing: 8
                    Layout.leftMargin: 20

                    StyledText {
                        text: "Close all other windows on restore"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.colOnSurface
                    }
                    StyledSwitch {
                        checked: root.closeOthers
                        onCheckedChanged: {
                            if (checked !== root.closeOthers) {
                                let newClose = checked;
                                let newKill = root.killOthers;
                                if (newClose) newKill = false;
                                WorkspaceProfileService.updateProfileOptions(root.slug, newClose, newKill)
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

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
                        color: root.restoreSuccess
                            ? Appearance.m3colors.m3primary
                            : Appearance.m3colors.m3tertiary
                        fill: 1
                    }
                    StyledText {
                        text: root.restoreSuccess ? "Restored" : "Partially restored"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.restoreSuccess
                            ? Appearance.m3colors.m3primary
                            : Appearance.m3colors.m3tertiary
                    }
                }

                MaterialLoadingIndicator {
                    visible: root.isRestoring || root.mutating
                    implicitWidth: 24; implicitHeight: 24
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

                    onClicked: root.restoreRequested()
                }
            }

            // ── expanded window settings section ──────────────────────────────
            // Animated slide + fade on expand/collapse
            Item {
                id: expandWrapper
                Layout.fillWidth: true
                height: root.expanded ? expandedContent.implicitHeight : 0
                implicitHeight: height
                opacity: root.expanded ? 1.0 : 0.0
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                ColumnLayout {
                    id: expandedContent
                    width: parent.width
                    spacing: 6
                    // top breathing room
                    Item { Layout.fillWidth: true; implicitHeight: 4 }

                    // divider + section header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: root.colBorder
                        opacity: 0.6
                    }

                    RowLayout {
                        spacing: 6
                        Layout.topMargin: 2

                        MaterialSymbol {
                            text: "tune"
                            iconSize: Appearance.font.pixelSize.small
                            color: root.colPrimary
                            fill: 1
                        }
                        StyledText {
                            text: "Configure Windows & Autolaunch"
                            font {
                                pixelSize: Appearance.font.pixelSize.small
                                weight: Font.Bold
                            }
                            color: root.colOnSurface
                        }
                    }

                    // Window rows
                    // Scrollable window rows container if they exceed height limits
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(windowRowsCol.implicitHeight, 280)
                        contentHeight: windowRowsCol.implicitHeight
                        clip: true
                        interactive: contentHeight > height

                        ColumnLayout {
                            id: windowRowsCol
                            anchors { left: parent.left; right: parent.right }
                            spacing: 6

                            Repeater {
                                model: root.windowsList
                                delegate: Item {
                                    id: windowRowItem
                                    required property int index
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: windowRow.implicitHeight + 40

                                    // alternating row tint
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Appearance.rounding.small
                                        color: Appearance.colors.colLayer2
                                        opacity: windowRowItem.index % 2 === 0 ? 0.45 : 0.0
                                    }

                                    RowLayout {
                                        id: windowRow
                                        anchors {
                                            left: parent.left; right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            leftMargin: 6; rightMargin: 4
                                        }
                                        spacing: 10

                                        // app avatar circle
                                        Rectangle {
                                            implicitWidth: 24; implicitHeight: 24
                                            radius: Appearance.rounding.full
                                            color: Appearance.colors.colSecondaryContainer

                                            Image {
                                                id: appIconImg
                                                anchors.centerIn: parent
                                                sourceSize: Qt.size(14, 14)
                                                source: {
                                                    const _ = TaskbarApps.iconThemeRevision;
                                                    return Quickshell.iconPath(AppSearch.guessIcon(windowRowItem.modelData.class || ""), "");
                                                }
                                                smooth: true
                                                visible: source.toString() !== "" && status !== Image.Error
                                            }

                                            StyledText {
                                                anchors.centerIn: parent
                                                visible: !appIconImg.visible
                                                text: (windowRowItem.modelData.class || "?").charAt(0).toUpperCase()
                                                font {
                                                    pixelSize: Appearance.font.pixelSize.smaller
                                                    weight: Font.Bold
                                                }
                                                color: Appearance.colors.colOnSecondaryContainer
                                            }
                                        }

                                        // class name + floating label
                                        ColumnLayout {
                                             Layout.alignment: Qt.AlignVCenter
                                             spacing: 2
                                             Layout.minimumWidth: 110
                                             Layout.fillWidth: true

                                            StyledText {
                                                text: windowRowItem.modelData.class || "unknown"
                                                font {
                                                    pixelSize: Appearance.font.pixelSize.small
                                                    weight: Font.DemiBold
                                                }
                                                color: root.colOnSurface
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            StyledText {
                                                visible: windowRowItem.modelData.floating
                                                text: "Floating"
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: root.colSubtle
                                            }
                                        }

                                        // Workspace ID field
                                        RowLayout {
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 6
                                            StyledText {
                                                text: "WS"
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: root.colSubtle
                                            }
                                            MaterialTextField {
                                                implicitWidth: 55
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                horizontalAlignment: TextInput.AlignHCenter
                                                verticalAlignment: TextInput.AlignVCenter
                                                topPadding: 0
                                                bottomPadding: 0
                                                text: {
                                                    let ws = windowRowItem.modelData.workspaceId;
                                                    if (typeof ws === "string" && ws.startsWith("special")) return "sp";
                                                    if (typeof ws === "number" && ws < 0) return "sp";
                                                    return ws.toString();
                                                }
                                                onEditingFinished: {
                                                    let val = text.trim();
                                                    if (val.toLowerCase() === "sp" || val.toLowerCase() === "special") {
                                                        val = "special:special";
                                                    } else {
                                                        let parsed = parseInt(val);
                                                        if (!isNaN(parsed)) val = parsed;
                                                    }
                                                    if (val !== windowRowItem.modelData.workspaceId) {
                                                        WorkspaceProfileService.updateWindowWorkspace(
                                                            root.slug,
                                                            windowRowItem.index,
                                                            val
                                                        );
                                                    }
                                                }
                                            }
                                        }

                                        // Autolaunch switch
                                        RowLayout {
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 6
                                            StyledText {
                                                text: "Autolaunch"
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: root.colSubtle
                                            }
                                            StyledSwitch {
                                                checked: windowRowItem.modelData.autolaunch || false
                                                onCheckedChanged: {
                                                    if (checked !== (windowRowItem.modelData.autolaunch || false)) {
                                                        WorkspaceProfileService.updateWindowOptions(
                                                            root.slug,
                                                            windowRowItem.index,
                                                            checked,
                                                            cmdField.text || (windowRowItem.modelData.launchCmd || "")
                                                        )
                                                    }
                                                }
                                            }
                                        }

                                        // Launch command
                                        MaterialTextField {
                                            id: cmdField
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 180
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: windowRowItem.modelData.launchCmd || ""
                                            placeholderText: "Add arguments..."
                                            enabled: windowRowItem.modelData.autolaunch || false

                                            StyledText {
                                                text: "Arguments for " + root.cleanAppName(windowRowItem.modelData.initialClass || windowRowItem.modelData.class)
                                                font.pixelSize: Appearance.font.pixelSize.small - 3
                                                font.weight: Font.DemiBold
                                                color: Appearance.m3colors.m3primary
                                                anchors.bottom: parent.top
                                                anchors.bottomMargin: 4
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                anchors.right: parent.right
                                                elide: Text.ElideRight
                                            }

                                            onEditingFinished: {
                                                if (text !== (windowRowItem.modelData.launchCmd || "")) {
                                                    WorkspaceProfileService.updateWindowOptions(
                                                        root.slug,
                                                        windowRowItem.index,
                                                        windowRowItem.modelData.autolaunch || false,
                                                        text
                                                    )
                                                }
                                            }
                                        }

                                        // Delete window button
                                        RippleButton {
                                            id: delBtn
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitWidth: 36; implicitHeight: 36
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: "transparent"
                                            colBackgroundHover: Appearance.colors.colErrorContainer
                                            onClicked: WorkspaceProfileService.deleteWindow(root.slug, windowRowItem.index)
                                            StyledToolTip { text: "Delete window entry" }
                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "delete"
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: delBtn.hovered ? Appearance.colors.colOnErrorContainer : root.colSubtle
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ScrollIndicator.vertical: ScrollIndicator {
                            anchors.right: parent.right
                        }
                    }

                    // Add App button / inline form
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Layout.topMargin: 16

                        // Add App button (form closed)
                        RippleButtonWithIcon {
                            visible: !root.showAddAppForm
                            Layout.alignment: Qt.AlignLeft
                            materialIcon: "add_circle"
                            materialIconFill: true
                            mainText: "Add App"
                            colText: Appearance.colors.colOnPrimaryContainer
                            colBackground: Appearance.colors.colPrimaryContainer
                            colBackgroundHover: Qt.lighter(Appearance.colors.colPrimaryContainer, 1.08)
                            buttonRadius: Appearance.rounding.full
                            implicitHeight: 36
                            onClicked: {
                                root.newAppClass = "";
                                root.newAppWorkspace = "1";
                                root.newAppAutolaunch = true;
                                root.newAppLaunchCmd = "";
                                root.showAddAppForm = true;
                            }
                        }

                        // Inline form (form open)
                        RowLayout {
                            visible: root.showAddAppForm
                            Layout.fillWidth: true
                            spacing: 10

                            MaterialTextField {
                                id: newClassField
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                Layout.preferredWidth: 150
                                font.pixelSize: Appearance.font.pixelSize.small
                                verticalAlignment: TextInput.AlignVCenter
                                topPadding: 0; bottomPadding: 0
                                placeholderText: "App class (e.g. kitty)"
                                text: root.newAppClass
                                onTextChanged: root.newAppClass = text
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 4
                                StyledText {
                                    text: "WS"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: root.colSubtle
                                }
                                MaterialTextField {
                                    implicitWidth: 55
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    topPadding: 0; bottomPadding: 0
                                    text: root.newAppWorkspace
                                    onTextChanged: root.newAppWorkspace = text
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 4
                                StyledText {
                                    text: "Auto"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: root.colSubtle
                                }
                                StyledSwitch {
                                    checked: root.newAppAutolaunch
                                    onCheckedChanged: root.newAppAutolaunch = checked
                                }
                            }

                            MaterialTextField {
                                id: newCmdField
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                Layout.preferredWidth: 150
                                font.pixelSize: Appearance.font.pixelSize.small
                                placeholderText: "(Optional)"
                                text: root.newAppLaunchCmd
                                onTextChanged: root.newAppLaunchCmd = text
                                enabled: root.newAppAutolaunch

                                StyledText {
                                    text: "Arguments"
                                    font.pixelSize: Appearance.font.pixelSize.small - 3
                                    font.weight: Font.DemiBold
                                    color: Appearance.m3colors.m3primary
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: 4
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 6

                                RippleButton {
                                    implicitWidth: 36; implicitHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    enabled: root.newAppClass.trim().length > 0 && root.newAppWorkspace.trim().length > 0
                                    onClicked: {
                                        let ws = root.newAppWorkspace.trim();
                                        if (ws.toLowerCase() === "sp" || ws.toLowerCase() === "special") {
                                            ws = "special:special";
                                        } else {
                                            let parsed = parseInt(ws);
                                            if (!isNaN(parsed)) ws = parsed;
                                            else ws = 1;
                                        }
                                        WorkspaceProfileService.addWindow(
                                            root.slug,
                                            root.newAppClass.trim(),
                                            ws,
                                            root.newAppAutolaunch,
                                            root.newAppLaunchCmd.trim()
                                        );
                                        root.showAddAppForm = false;
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "check"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 36; implicitHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colLayer2
                                    onClicked: root.showAddAppForm = false
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: root.colSubtle
                                    }
                                }
                            }
                        }
                    }

                    // bottom breathing room
                    Item { Layout.fillWidth: true; implicitHeight: 4 }
                }
            }
        }
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    function cleanAppName(cls) {
        if (!cls) return "";
        let name = cls.toLowerCase();
        if (name === "brave-browser" || name === "brave") return "Brave";
        if (name === "google-chrome" || name === "chrome") return "Chrome";
        if (name === "kitty") return "Kitty";
        if (name === "code" || name === "visual-studio-code") return "VS Code";
        if (name === "firefox") return "Firefox";
        if (name === "discord") return "Discord";
        if (name === "spotify") return "Spotify";
        if (name === "steam") return "Steam";
        if (name === "obs") return "OBS Studio";
        if (name === "thunderbird") return "Thunderbird";
        if (name === "dolphin") return "Dolphin";
        if (name === "thunar") return "Thunar";
        if (name === "nautilus") return "Files";
        if (name === "vlc") return "VLC";
        if (name === "mpv") return "mpv";
        if (name === "gimp") return "GIMP";
        if (name === "inkscape") return "Inkscape";
        if (name === "libreoffice-writer") return "Writer";
        if (name === "libreoffice-calc") return "Calc";
        name = name.replace(/[-_]/g, " ");
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function getWorkspaceApps(wsId) {
        let apps = [];
        for (const w of root.windowsList) {
            if (w.workspaceId === wsId) {
                let cleanName = cleanAppName(w.class || w.initialClass);
                if (cleanName && !apps.includes(cleanName)) apps.push(cleanName);
            }
        }
        return apps.length > 0
            ? apps.join(", ")
            : ((typeof wsId === "string" && wsId.startsWith("special")) || (typeof wsId === "number" && wsId < 0)
                ? "scratchpad"
                : `ws ${wsId}`);
    }

    function getWorkspaceClasses(wsId) {
        let classes = [];
        for (const w of root.windowsList) {
            if (w.workspaceId === wsId) {
                let className = w.class || w.initialClass;
                if (className && !classes.includes(className)) classes.push(className);
            }
        }
        return classes;
    }



    function _dateString(epoch) {
        const d = new Date(epoch * 1000);
        return d.toLocaleDateString(Qt.locale(), "dd MMM yyyy");
    }

    function _ageString(epoch) {
        const now   = Math.floor(Date.now() / 1000);
        const delta = now - epoch;
        if (delta < 60)        return "just now";
        if (delta < 3600)      return `${Math.floor(delta / 60)}m ago`;
        if (delta < 86400)     return `${Math.floor(delta / 3600)}h ago`;
        if (delta < 86400 * 7) return `${Math.floor(delta / 86400)}d ago`;
        return _dateString(epoch);
    }
}
