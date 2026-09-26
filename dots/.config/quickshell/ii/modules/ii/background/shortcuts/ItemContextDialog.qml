pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode

/**
 * A menu about one item (a desktop icon, today): a plate naming the item on
 * top, and under it the card of actions, with pages of its own.
 *
 * The card is the desktop menu's (DesktopMenuCard), so the two menus the
 * desktop can open are one kind of object: EditPanelRow rows in a grouped
 * run, the same card, the same enter/exit, pages that slide in from the
 * right with their own header (EditMenuPageHeader). What stays its own is
 * the plate - the item's icon, name and path above the card.
 *
 * closeRequested fires only after the exit motion; the host may then unload.
 */
FocusScope {
    id: root
    property string title: ""
    property string subtitle: ""
    property url iconSource: ""
    property point anchorPoint: Qt.point(0, 0)
    property var actions: []
    property Component pageComponent: null
    // How deep `pageComponent` sits: 0 is the actions, a page off them is 1,
    // a page off that is 2. It decides which way a page change slides.
    property int pageDepth: root.pageComponent ? 1 : 0
    property bool closing: false
    signal actionTriggered(string actionId)
    signal closeRequested()
    signal backRequested()
    // The host's selection, when the menu speaks of a set: Ctrl+A on the
    // action page asks the host to select everything it owns.
    signal selectAllRequested()
    // The action Repeater, published by the action page on create/destroy.
    property var actionRows: null

    // A row that just did its job (a copy) answers in place: it fills with
    // primary, its icon turns into a check and its label into `doneText`.
    // Kept beside `actions`, not in it - a new actions array would rebuild
    // every row and the fill would snap instead of easing in.
    property string doneId: ""
    property string doneText: ""
    function confirmAction(id: string, text: string): void {
        root.doneText = text;
        root.doneId = id;
    }

    readonly property int padding: 8
    readonly property real cardRadius: Appearance.rounding.windowRounding

    function dismiss() {
        if (root.closing)
            return;
        root.closing = true;
        enterMotion.stop();
        exitMotion.restart();
    }

    // ── Enter and exit ───────────────────────────────────────────────────────
    // The desktop menu's motion (DesktopMenuCard): plate and card grow out
    // of the corner under the pointer as one (0.85 -> 1 on elementMoveEnter)
    // while fading in on elementMoveFast, and leave as one on
    // elementMoveExit. No row cascade.
    property real grow: 0
    property real reveal: 0
    readonly property bool _motion: !Appearance.reducedMotion

    ParallelAnimation {
        id: enterMotion
        NumberAnimation {
            target: root; property: "grow"; to: 1
            duration: root._motion ? Appearance.animation.elementMoveEnter.duration : 0
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: root; property: "reveal"; to: 1
            duration: root._motion ? Appearance.animation.elementMoveFast.duration : 0
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    ParallelAnimation {
        id: exitMotion
        NumberAnimation {
            target: root; property: "grow"; to: 0.5
            duration: root._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root; property: "reveal"; to: 0
            duration: root._motion ? Appearance.animation.elementMoveExit.duration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        onFinished: root.closeRequested()
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    // The page on show lags the requested one by the out half of the slide:
    // the old page leaves toward where it came from, then the new one comes
    // in from the other side. Deeper slides left, shallower slides right.
    property Component displayedPage: null
    property int displayedDepth: 0
    property int _slideDir: 1
    readonly property real pageSlide: 36
    property real pageOffset: 0
    property real pageOpacity: 1

    onPageComponentChanged: {
        if (root.closing)
            return;
        root._slideDir = root.pageDepth >= root.displayedDepth ? 1 : -1;
        if (!root._motion || root.reveal < 1) {
            root.displayedPage = root.pageComponent;
            root.displayedDepth = root.pageDepth;
            return;
        }
        pageMotion.restart();
    }
    SequentialAnimation {
        id: pageMotion
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "pageOffset"; to: -root._slideDir * root.pageSlide
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            NumberAnimation {
                target: root; property: "pageOpacity"; to: 0
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
        }
        ScriptAction {
            script: {
                root.displayedPage = root.pageComponent;
                root.displayedDepth = root.pageDepth;
                root.pageOffset = root._slideDir * root.pageSlide;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "pageOffset"; to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                target: root; property: "pageOpacity"; to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }

    // ── Keyboard ─────────────────────────────────────────────────────────────
    // Arrow navigation over the action rows. The scope holds focus, so every
    // key lands here first. From "no row yet", Down enters at the top and Up
    // at the bottom. Only the action page: a page's own fields keep their
    // keys (rename's caret, search's list). A focused row reads as hovered
    // and takes Enter/Space itself (EditPanelRow).
    function navRows(delta: int): bool {
        const rep = root.actionRows;
        if (!rep || root.pageComponent || root.closing || rep.count === 0)
            return false;
        let idx = -1;
        for (let i = 0; i < rep.count; ++i) {
            if (rep.itemAt(i)?.activeFocus) {
                idx = i;
                break;
            }
        }
        // |delta| >= 9999 is Home/End: an absolute jump, never a walk.
        if (Math.abs(delta) >= 9999)
            idx = delta > 0 ? rep.count - 1 : 0;
        else if (idx === -1)
            idx = delta > 0 ? 0 : rep.count - 1;
        else
            idx = Math.max(0, Math.min(rep.count - 1, idx + delta));
        rep.itemAt(idx)?.forceActiveFocus();
        return true;
    }
    focus: true
    Component.onCompleted: {
        // Opened straight onto a page (F2 → rename), that page's field
        // claims focus itself — grabbing it here, after the children have
        // completed, would steal it back.
        if (!root.pageComponent)
            root.forceActiveFocus();
        root.displayedPage = root.pageComponent;
        root.displayedDepth = root.pageDepth;
        enterMotion.start();
    }
    Keys.onEscapePressed: event => {
        event.accepted = true;
        if (root.pageComponent && !root.closing)
            root.backRequested();
        else
            root.dismiss();
    }
    Keys.onUpPressed: event => {
        if (root.navRows(-1))
            event.accepted = true;
    }
    Keys.onDownPressed: event => {
        if (root.navRows(1))
            event.accepted = true;
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)
            && !root.pageComponent) {
            // Only the action page: on the rename page the field owns Ctrl+A.
            event.accepted = true;
            root.selectAllRequested();
        } else if (event.key === Qt.Key_Home) {
            if (root.navRows(-9999))
                event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            if (root.navRows(9999))
                event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
        onWheel: wheel => wheel.accepted = true
    }

    // Edit Mode shrinks the whole desktop; a menu that shrinks with it is
    // both hard to read and rasterized off its native grid. The host hands in
    // the factor to undo and the cards are laid out in SCREEN pixels:
    // anchorPoint arrives in surface coordinates and is converted here, the
    // clamp runs on the unscaled extent. 1 outside the mode.
    property real counterScale: 1
    ColumnLayout {
        id: cards
        x: Math.max(8, Math.min(root.anchorPoint.x / root.counterScale, root.width - width - 8)) * root.counterScale
        y: Math.max(8, Math.min(root.anchorPoint.y / root.counterScale, root.height - height - 8)) * root.counterScale
        width: Math.max(0, Math.min(300, root.width - 16))
        spacing: 6
        opacity: root.reveal
        scale: root.counterScale * (0.85 + 0.15 * root.grow)
        transformOrigin: Item.TopLeft
        enabled: !root.closing
        Behavior on y {
            enabled: root.counterScale === 1
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // The plate: what the menu is about.
        Item {
            Layout.fillWidth: true
            implicitHeight: 88

            StyledRectangularShadow {
                target: plate
            }
            Rectangle {
                id: plate
                anchors.fill: parent
                radius: root.cardRadius
                color: Appearance.m3colors.m3surfaceContainer
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    Rectangle {
                        implicitWidth: 64
                        implicitHeight: 64
                        radius: Math.max(Appearance.rounding.verysmall, root.cardRadius - 12)
                        color: Appearance.colors.colSurfaceContainerHigh
                        Image {
                            anchors.centerIn: parent
                            width: 48
                            height: 48
                            sourceSize: Qt.size(48, 48)
                            source: root.iconSource
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            Layout.fillWidth: true
                            text: root.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.subtitle
                            visible: text.length > 0
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }
        }

        // The card: the actions, or the page they opened.
        Item {
            Layout.fillWidth: true
            implicitHeight: card.implicitHeight

            StyledRectangularShadow {
                target: card
            }
            Rectangle {
                id: card
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: Math.min(Math.max(64, root.height - 110),
                    pageLoader.implicitHeight + root.padding * 2)
                radius: root.cardRadius
                color: Appearance.m3colors.m3surfaceContainer
                clip: true
                Behavior on implicitHeight {
                    enabled: !Appearance.reducedMotion && root.reveal >= 1
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
                }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

                ScrollView {
                    id: pageScroll
                    anchors.fill: parent
                    anchors.margins: root.padding
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    Loader {
                        id: pageLoader
                        width: pageScroll.availableWidth
                        opacity: root.pageOpacity
                        transform: Translate { x: root.pageOffset }
                        sourceComponent: root.displayedPage ?? actionPage
                        enabled: !pageMotion.running && !root.closing
                    }
                }
            }
        }
    }

    Component {
        id: actionPage
        ColumnLayout {
            spacing: 3
            Repeater {
                id: actionRepeater
                model: root.actions
                Component.onCompleted: root.actionRows = actionRepeater
                Component.onDestruction: root.actionRows = null
                delegate: EditPanelRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    hostRadius: root.cardRadius
                    hostPadding: root.padding
                    first: index === 0
                    last: index === root.actions.length - 1
                    readonly property bool done: modelData.id === root.doneId
                    symbol: done ? "check" : (modelData.icon ?? "")
                    title: done ? root.doneText : (modelData.text ?? "")
                    destructive: modelData.destructive === true
                    rowEnabled: modelData.enabled !== false
                    trailingKind: modelData.submenu === true ? "chevron"
                        : modelData.toggle === true ? "switch" : "none"
                    switchChecked: modelData.checked === true
                    selected: done
                    onActivated: root.actionTriggered(modelData.id)
                }
            }
        }
    }
}
