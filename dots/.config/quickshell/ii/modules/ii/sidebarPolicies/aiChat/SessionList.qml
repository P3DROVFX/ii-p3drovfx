pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The list of saved chats.
 *
 * The same component is the drawer's content on a narrow sidebar and the pane's
 * content on a wide one — only its host changes, so a chat is opened, renamed
 * or thrown away the same way at every width.
 *
 * Every action here is a button. The commands that used to be the only way to
 * save and load a chat still work, but nothing depends on them any more.
 */
Item {
    id: root

    signal closeRequested

    /** The drawer wants a way out; the pane does not need one. */
    property bool showCloseButton: false

    readonly property var sessions: Ai.sessions
    property string expandedId: ""
    property string renamingId: ""
    /** The chat whose labels are being written, "" when none is. */
    property string taggingId: ""

    /** The label the list is narrowed to, "" for all of them. */
    property string activeTag: ""

    readonly property var visibleEntries: {
        let entries = root.sessions.index ?? [];
        if (root.activeTag.length > 0)
            entries = entries.filter(entry => Array.from(entry.tags ?? []).indexOf(root.activeTag) >= 0);
        const needle = searchField.text.trim().toLowerCase();
        if (needle.length === 0)
            return entries;
        // Titles filter as the user types; bodies come back from the helper a
        // moment later and widen the same list.
        const matched = root.sessions.matchedIds;
        return entries.filter(entry => entry.title.toLowerCase().includes(needle) || (matched?.indexOf(entry.id) ?? -1) >= 0);
    }

    function whenText(stamp: real): string {
        const date = new Date(stamp);
        const now = new Date();
        const sameDay = date.toDateString() === now.toDateString();
        if (sameDay)
            return Qt.formatDateTime(date, "HH:mm");
        const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
        if (date.toDateString() === yesterday.toDateString())
            return Translation.tr("Yesterday");
        if (date.getFullYear() === now.getFullYear())
            return Qt.formatDateTime(date, "d MMM");
        return Qt.formatDateTime(date, "MMM yyyy");
    }

    Component.onCompleted: root.sessions.ensureLoaded()

    /** One label in the filter strip. */
    component TagChip: Rectangle {
        id: tagChip

        property string label: ""
        property bool selected: false

        signal chosen

        implicitWidth: tagChipLabel.implicitWidth + Appearance.rounding.small * 2
        height: Math.round(Appearance.font.pixelSize.huge * 1.3)
        anchors.verticalCenter: parent?.verticalCenter
        radius: Appearance.rounding.full
        color: tagChip.selected
            ? Appearance.colors.colPrimary
            : (tagChipMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            id: tagChipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tagChip.chosen()
        }

        StyledText {
            id: tagChipLabel
            anchors.centerIn: parent
            text: tagChip.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: tagChip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }
    }

    /**
     * Row metrics, shared by both pages so the circle, the card and the pills
     * are one height and the two pages line up as the row slides between them.
     */
    readonly property real rowHeight: Math.round(Appearance.font.pixelSize.huge * 2.5)
    readonly property real rowSpacing: Appearance.rounding.unsharpenmore
    readonly property real rowInset: Appearance.rounding.large
    readonly property real searchHeight: Math.round(Appearance.font.pixelSize.huge * 2)
    /** Side padding inside an action pill — a pill's inset, not a card's. */
    readonly property real pillPadding: Appearance.rounding.normal
    /**
     * Roughly what the five labelled pills and the back circle need side by
     * side. Below it the labels step aside and the tooltips carry the names,
     * which beats having the last pill cut off by the row's edge. Derived from
     * the type scale so it moves with the user's font size.
     */
    readonly property real actionsLabelledWidth: Appearance.font.pixelSize.small * 42

    /** The round control at either end of a row. */
    component RowActionCircle: Rectangle {
        id: rowCircle

        property string symbol: ""
        property color tint: Appearance.colors.colOnSurface
        property bool filled: false
        signal triggered

        Layout.preferredWidth: root.rowHeight
        Layout.fillHeight: true
        radius: height / 2
        color: rowCircle.filled
            ? (rowCircleMouse.containsPress ? Appearance.colors.colPrimaryActive
                : rowCircleMouse.containsMouse ? Appearance.colors.colPrimaryHover
                : Appearance.colors.colPrimary)
            : (rowCircleMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                : rowCircleMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                : Appearance.colors.colSurfaceContainerHighest)

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        MouseArea {
            id: rowCircleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rowCircle.triggered()
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: rowCircle.symbol
            fill: 1
            iconSize: 24
            color: rowCircle.tint
        }
    }

    /**
     * An inline action. Outlined by default and filled in the error colour
     * when it throws something away, the way the Bluetooth dialog separates
     * Connect from Forget.
     */
    component RowActionPill: Rectangle {
        id: rowPill

        property string symbol: ""
        property string label: ""
        property bool destructive: false
        property bool showLabel: true
        signal triggered

        // Hugs its own content. The pills live in a Row inside a scroller, so
        // the width is theirs to state — a layout that could squeeze them
        // below their label is what left the text spilling outside the shape.
        implicitWidth: rowPillRow.implicitWidth + root.pillPadding * 2
        width: implicitWidth
        height: parent ? parent.height : root.rowHeight
        radius: height / 2

        color: rowPill.destructive
            ? (rowPillMouse.containsPress ? Appearance.colors.colErrorContainerActive
                : rowPillMouse.containsMouse ? Appearance.colors.colErrorContainerHover
                : Appearance.colors.colErrorContainer)
            : "transparent"
        border.width: rowPill.destructive ? 0 : 2
        border.color: rowPillMouse.containsMouse
            ? Appearance.colors.colOnSurface
            : Appearance.colors.colOutline

        readonly property color colOn: rowPill.destructive
            ? Appearance.colors.colOnErrorContainer
            : (rowPillMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOutline)

        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }

        MouseArea {
            id: rowPillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rowPill.triggered()
        }

        RowLayout {
            id: rowPillRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: rowPill.symbol
                fill: 1
                iconSize: 18
                color: rowPill.colOn
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            StyledText {
                visible: rowPill.showLabel
                text: rowPill.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.bold: true
                color: rowPill.colOn
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        StyledToolTip {
            text: rowPill.label
            extraVisibleCondition: !rowPill.showLabel && rowPillMouse.containsMouse
        }
    }

    component ActionButton: RippleButton {
        id: actionButton

        property string symbol: ""
        property string tooltipText: ""

        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: actionButton.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer2
        }

        StyledToolTip {
            text: actionButton.tooltipText
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // No new-chat button here: the tools bar above this view already has
        // one, and two of them a few pixels apart read as two different things.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.searchHeight
            radius: height / 2
            color: Appearance.colors.colLayer2

            MouseArea {
                // The whole field is a text target, not just the glyphs in it.
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                acceptedButtons: Qt.LeftButton
                onClicked: searchField.forceActiveFocus()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.rowInset
                anchors.rightMargin: Appearance.rounding.unsharpenmore
                spacing: Appearance.rounding.unsharpenmore

                MaterialSymbol {
                    text: "search"
                    fill: 1
                    iconSize: 24
                    color: Appearance.colors.colSubtext
                }

                StyledTextInput {
                    id: searchField
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.normal
                    onTextChanged: searchDebounce.restart()
                    onAccepted: {
                        searchDebounce.stop();
                        root.sessions.search(searchField.text);
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.NoButton
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchField.text.length === 0
                        text: Translation.tr("Search chats")
                        color: Appearance.colors.colSubtext
                        font: searchField.font
                    }
                }

                ActionButton {
                    visible: searchField.text.length > 0
                    symbol: "close"
                    tooltipText: Translation.tr("Clear")
                    onClicked: {
                        searchField.clear();
                        root.sessions.search("");
                    }
                }
            }
        }

        Flickable {
            // The labels in use, as a row that scrolls when there are more of
            // them than fit. Nothing here until a chat has been labelled.
            id: tagStrip
            Layout.fillWidth: true
            implicitHeight: root.sessions.allTags.length > 0 ? Math.round(Appearance.font.pixelSize.huge * 1.6) : 0
            visible: implicitHeight > 0
            contentWidth: tagRow.implicitWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                enabled: tagStrip.interactive
                onWheel: wheel => {
                    const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                    const limit = tagStrip.contentWidth - tagStrip.width;
                    tagStrip.contentX = Math.max(0, Math.min(limit, tagStrip.contentX - delta));
                    wheel.accepted = true;
                }
            }

            Row {
                id: tagRow
                height: tagStrip.height
                spacing: Appearance.rounding.unsharpenmore

                TagChip {
                    label: Translation.tr("All")
                    selected: root.activeTag.length === 0
                    onChosen: root.activeTag = ""
                }

                Repeater {
                    model: ScriptModel {
                        values: root.sessions.allTags
                    }

                    delegate: TagChip {
                        required property var modelData
                        label: modelData
                        selected: root.activeTag === modelData
                        onChosen: root.activeTag = root.activeTag === modelData ? "" : modelData
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: sessionListView
        // The canvas slides this whole view in; rows used to be held
        // back because entering all at once read as a second, competing
        // entrance. Staggered they read as one motion instead — the page
        // filling top-down behind the slide — so they enter again.
        staggerStep: 22
                anchors.fill: parent
                spacing: root.rowSpacing
                clip: true

                model: ScriptModel {
                    values: root.visibleEntries
                }

                delegate: Item {
                    id: sessionRow
                    required property var modelData

                    readonly property bool current: sessionRow.modelData.id === root.sessions.currentId
                    readonly property bool renaming: sessionRow.modelData.id === root.renamingId
                    readonly property bool tagging: sessionRow.modelData.id === root.taggingId

                    anchors.left: parent?.left
                    anchors.right: parent?.right
                    // The labels open under the row rather than over it, so
                    // the list keeps its place while one chat is being filed.
                    implicitHeight: root.rowHeight + tagEditor.height
                    height: implicitHeight

                    Item {
                        // A Loader cannot be given a height of its own, so the
                        // strip that grows is this wrapper and the Loader only
                        // fills it.
                        id: tagEditor
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: root.rowHeight
                        height: sessionRow.tagging ? Math.round(Appearance.font.pixelSize.huge * 2.4) : 0
                        visible: height > 0
                        clip: true

                        Behavior on height {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }

                        Loader {
                            anchors.fill: parent
                            active: sessionRow.tagging

                            sourceComponent: Rectangle {
                            radius: Appearance.rounding.large
                            color: Appearance.colors.colLayer2

                            Component.onCompleted: tagField.forceActiveFocus()

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: root.rowInset
                                anchors.rightMargin: Appearance.rounding.unsharpenmore
                                spacing: Appearance.rounding.unsharpenmore

                                MaterialSymbol {
                                    text: "label"
                                    fill: 1
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                }

                                StyledTextInput {
                                    id: tagField
                                    Layout.fillWidth: true
                                    text: Array.from(sessionRow.modelData.tags ?? []).join(", ")
                                    color: Appearance.colors.colOnLayer2
                                    onAccepted: {
                                        root.sessions.setTags(sessionRow.modelData.id, tagField.text.split(","));
                                        root.taggingId = "";
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: tagField.text.length === 0
                                        text: Translation.tr("Labels, separated by commas")
                                        color: Appearance.colors.colSubtext
                                        font: tagField.font
                                    }
                                }

                                ActionButton {
                                    symbol: "check"
                                    tooltipText: Translation.tr("Save the labels")
                                    onClicked: {
                                        root.sessions.setTags(sessionRow.modelData.id, tagField.text.split(","));
                                        root.taggingId = "";
                                    }
                                }

                                ActionButton {
                                    symbol: "close"
                                    tooltipText: Translation.tr("Leave them as they were")
                                    onClicked: root.taggingId = ""
                                }
                            }
                            }
                        }
                    }

                    readonly property real rFull: height / 2

                    // Two pages side by side, the way the Bluetooth dialog
                    // shows a device and then what can be done with it: the
                    // circle on the right slides the row over rather than
                    // growing a panel underneath it.
                    Flickable {
                        id: rowFlick
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: root.rowHeight
                        contentWidth: rowFlick.width * 2 + root.rowSpacing
                        contentHeight: rowFlick.height
                        interactive: false
                        clip: true

                        property bool showActions: false
                        contentX: rowFlick.showActions ? (rowFlick.width + root.rowSpacing) : 0

                        Behavior on contentX {
                            NumberAnimation {
                                duration: 400
                                easing.type: Easing.OutExpo
                            }
                        }

                        Row {
                            height: rowFlick.height
                            spacing: root.rowSpacing

                            // PAGE 1 — the chat itself
                            RowLayout {
                                width: rowFlick.width
                                height: rowFlick.height
                                spacing: root.rowSpacing

                                Rectangle {
                                    id: sessionCard
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: sessionRow.rFull

                                    color: sessionRow.current
                                        ? (cardMouse.containsPress ? Appearance.colors.colPrimaryActive
                                            : cardMouse.containsMouse ? Appearance.colors.colPrimaryHover
                                            : Appearance.colors.colPrimary)
                                        : (cardMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                                            : cardMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                                            : Appearance.colors.colSurfaceContainerHighest)

                                    readonly property color colOn: sessionRow.current
                                        ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnSurface

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }

                                    MouseArea {
                                        id: cardMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !sessionRow.renaming
                                        onClicked: {
                                            Ai.openSession(sessionRow.modelData.id);
                                            root.closeRequested();
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.rowInset
                                        anchors.rightMargin: root.rowInset
                                        spacing: 12

                                        MaterialSymbol {
                                            text: sessionRow.modelData.pinned ? "keep" : "forum"
                                            fill: 1
                                            iconSize: 24
                                            color: sessionCard.colOn
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: !sessionRow.renaming
                                            text: sessionRow.modelData.title.length > 0
                                                ? sessionRow.modelData.title
                                                : Translation.tr("Untitled chat")
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.bold: true
                                            color: sessionCard.colOn
                                            elide: Text.ElideRight
                                        }

                                        Loader {
                                            Layout.fillWidth: true
                                            active: sessionRow.renaming
                                            visible: active
                                            sourceComponent: StyledTextInput {
                                                text: sessionRow.modelData.title
                                                color: sessionCard.colOn
                                                Component.onCompleted: {
                                                    forceActiveFocus();
                                                    selectAll();
                                                }
                                                onAccepted: {
                                                    root.sessions.rename(sessionRow.modelData.id, text);
                                                    root.renamingId = "";
                                                }
                                                Keys.onEscapePressed: root.renamingId = ""
                                            }
                                        }

                                        StyledText {
                                            text: root.whenText(sessionRow.modelData.updatedAt)
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.bold: true
                                            color: sessionCard.colOn
                                            opacity: 0.7
                                        }
                                    }
                                }

                                // The circle beside the row. Its icon turns
                                // into the direction it will travel on hover.
                                Rectangle {
                                    id: actionCircle
                                    Layout.preferredWidth: root.rowHeight
                                    Layout.fillHeight: true
                                    radius: sessionRow.rFull
                                    color: sessionRow.current
                                        ? (actionCircleMouse.containsPress ? Appearance.colors.colPrimaryActive
                                            : actionCircleMouse.containsMouse ? Appearance.colors.colPrimaryHover
                                            : Appearance.colors.colPrimary)
                                        : (actionCircleMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                                            : actionCircleMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                                            : Appearance.colors.colSurfaceContainerHighest)

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }

                                    MouseArea {
                                        id: actionCircleMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: rowFlick.showActions = true
                                    }

                                    Item {
                                        anchors.centerIn: parent
                                        width: 24
                                        height: 24

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: sessionRow.current ? "check" : "more_horiz"
                                            fill: 1
                                            iconSize: 24
                                            color: sessionCard.colOn
                                            opacity: actionCircleMouse.containsMouse ? 0 : 1
                                            scale: actionCircleMouse.containsMouse ? 0.5 : 1
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                        }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "arrow_back"
                                            fill: 1
                                            iconSize: 24
                                            color: sessionCard.colOn
                                            opacity: actionCircleMouse.containsMouse ? 1 : 0
                                            scale: actionCircleMouse.containsMouse ? 1 : 0.5
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }
                            }

                            // PAGE 2 — what can be done with the chat
                            RowLayout {
                                width: rowFlick.width
                                height: rowFlick.height
                                spacing: root.rowSpacing

                                RowActionCircle {
                                    symbol: "arrow_forward"
                                    tint: sessionCard.colOn
                                    filled: sessionRow.current
                                    onTriggered: rowFlick.showActions = false
                                }

                                // The actions scroll on their own. The row is
                                // as wide as the sidebar and the list of things
                                // a chat can do is not, so the alternative was
                                // the last pill being cut by the row's edge.
                                Flickable {
                                    id: actionsFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    contentWidth: actionsRow.implicitWidth
                                    contentHeight: height
                                    flickableDirection: Flickable.HorizontalFlick
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: actionsFlick.contentWidth > actionsFlick.width
                                    clip: true

                                    MouseArea {
                                        // Most mice only send a vertical wheel,
                                        // so it is turned sideways here. Left
                                        // alone when everything already fits,
                                        // where the list below should get it.
                                        anchors.fill: parent
                                        acceptedButtons: Qt.NoButton
                                        enabled: actionsFlick.interactive
                                        onWheel: wheel => {
                                            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                                            const limit = actionsFlick.contentWidth - actionsFlick.width;
                                            actionsFlick.contentX = Math.max(0, Math.min(limit, actionsFlick.contentX - delta));
                                            wheel.accepted = true;
                                        }
                                    }

                                    Row {
                                        id: actionsRow
                                        height: actionsFlick.height
                                        spacing: root.rowSpacing

                                        RowActionPill {
                                            showLabel: rowFlick.width >= root.actionsLabelledWidth
                                            symbol: "edit"
                                            label: Translation.tr("Rename")
                                            onTriggered: {
                                                root.renamingId = sessionRow.modelData.id;
                                                rowFlick.showActions = false;
                                            }
                                        }

                                        RowActionPill {
                                            showLabel: rowFlick.width >= root.actionsLabelledWidth
                                            symbol: sessionRow.modelData.pinned ? "keep_off" : "keep"
                                            label: sessionRow.modelData.pinned ? Translation.tr("Unpin") : Translation.tr("Pin")
                                            onTriggered: {
                                                root.sessions.setPinned(sessionRow.modelData.id, !sessionRow.modelData.pinned);
                                                rowFlick.showActions = false;
                                            }
                                        }

                                        RowActionPill {
                                            showLabel: rowFlick.width >= root.actionsLabelledWidth
                                            symbol: "label"
                                            label: Translation.tr("Labels")
                                            onTriggered: {
                                                root.taggingId = root.taggingId === sessionRow.modelData.id ? "" : sessionRow.modelData.id;
                                                rowFlick.showActions = false;
                                            }
                                        }

                                        RowActionPill {
                                            showLabel: rowFlick.width >= root.actionsLabelledWidth
                                            symbol: "content_copy"
                                            label: Translation.tr("Duplicate")
                                            onTriggered: {
                                                root.sessions.duplicate(sessionRow.modelData.id);
                                                rowFlick.showActions = false;
                                            }
                                        }

                                        RowActionPill {
                                            showLabel: rowFlick.width >= root.actionsLabelledWidth
                                            symbol: "download"
                                            label: Translation.tr("Export")
                                            onTriggered: {
                                                root.sessions.exportMarkdown(sessionRow.modelData.id);
                                                rowFlick.showActions = false;
                                            }
                                        }

                                        RowActionPill {
                                            showLabel: rowFlick.width >= root.actionsLabelledWidth
                                            symbol: "delete"
                                            label: Translation.tr("Delete")
                                            destructive: true
                                            onTriggered: {
                                                rowFlick.showActions = false;
                                                root.sessions.remove(sessionRow.modelData.id);
                                            }
                                        }
                                    }
                                }

                                // Says there is more to the right, and fades
                                // out once the end has been reached.
                                ScrollEdgeFade {
                                    // Overlays the viewport rather than the
                                    // scrolling content, and anchors itself to
                                    // its target, so no layout slot and no
                                    // anchors of our own here.
                                    parent: actionsFlick
                                    target: actionsFlick
                                    vertical: false
                                    color: Appearance.colors.colLayer1
                                }
                            }
                        }
                    }
                }
            }

            PagePlaceholder {
                shown: root.visibleEntries.length === 0
                icon: searchField.text.length > 0 ? "search_off" : "forum"
                title: searchField.text.length > 0 ? Translation.tr("Nothing found") : Translation.tr("No saved chats")
                description: searchField.text.length > 0 ? Translation.tr("No chat has that in its name or in what was said") : Translation.tr("Chats are saved as soon as you get an answer")
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.sessions.deletedEntry !== null
            visible: active
            sourceComponent: Rectangle {
                implicitHeight: undoRowLayout.implicitHeight + 8 * 2
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerHighest

                RowLayout {
                    id: undoRowLayout
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Deleted “%1”").arg(root.sessions.deletedEntry?.title ?? "")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }

                    RippleButton {
                        leftPadding: 12
                        rightPadding: 12
                        topPadding: 6
                        bottomPadding: 6
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.sessions.undoDelete()

                        contentItem: StyledText {
                            text: Translation.tr("Undo")
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.sessions.lastError.length > 0
            visible: active
            sourceComponent: StyledText {
                text: root.sessions.lastError
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
            }
        }
    }

    Timer {
        // Searching message bodies means opening every file, so it waits for
        // the typing to stop. Title matching is live either way.
        id: searchDebounce
        interval: 260
        onTriggered: root.sessions.search(searchField.text)
    }
}
