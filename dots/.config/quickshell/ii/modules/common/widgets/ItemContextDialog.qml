pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common

// closeRequested fires only after exit motion. The host may then unload safely.
FocusScope {
    id: root
    property string title: ""
    property string subtitle: ""
    property url iconSource: ""
    property point anchorPoint: Qt.point(0, 0)
    property var actions: []
    property Component pageComponent: null
    property Component displayedPage: null
    property real reveal: 0
    property bool closing: false
    signal actionTriggered(string actionId)
    signal closeRequested()
    signal backRequested()
    // The host's selection, when the menu speaks of a set: Ctrl+A on the
    // action page asks the host to select everything it owns.
    signal selectAllRequested()
    // The action Repeater, published by the action page on create/destroy.
    // The id lives inside a nested Component and is not visible here, and
    // a var property costs nothing to keep.
    property var actionRows: null

    function dismiss() {
        if (closing)
            return;
        closing = true;
        pageMotion.stop();
        revealMotion.stop();
        revealMotion.to = 0;
        revealMotion.start();
    }
    // ── The popup's cascade ────────────────────────────────────────────────
    // Same rule as the edit-mode toolbar (EditModeChromeContent): one scalar,
    // arithmetic on it, zero timers. `reveal` is the single animation; the
    // body, the plate and every row read their own slice of it, so the
    // cascade plays BACKWARDS on the way out for free — the row that arrived
    // last leaves first — and an interrupting close retargets mid-flight
    // without a restart. A per-row animation could do neither.
    //
    // The scalar runs LINEAR and EVERY SLICE EASES ITSELF (smoothstep). That
    // is the edit-mode sidebar's rhythm (StaggeredEntrance: each row owns a
    // ~400 ms fade, 26 ms apart). Easing the scalar globally was the blink;
    // and the two clocks must stay SEPARATE: the body+plate land inside the
    // first quarter of the window (the menu pops in and STANDS STILL), and
    // only then do the rows unfurl inside it. A body that grows for the
    // whole window makes the menu itself the cascade item and hides the
    // rows' wave behind its own drift — the sidebar never does that.
    //
    // The step self-normalizes against the action count so any menu,
    // 3 rows or 12, still ends its last row exactly at reveal = 1.
    readonly property real bodySpan: 0.22
    readonly property real plateSpan: 0.22
    readonly property real rowLead: 0.2
    readonly property real rowSpan: 0.55
    function ease(t: real): real {
        return t * t * (3 - 2 * t);
    }
    readonly property real bodyReveal: root.ease(Math.min(1, root.reveal / root.bodySpan))
    readonly property real plateReveal: root.ease(Math.min(1, root.reveal / root.plateSpan))

    function rowReveal(index: int, count: int): real {
        const step = count > 1
            ? Math.min(0.041, (1 - root.rowLead - root.rowSpan) / (count - 1)) : 0;
        const t = (root.reveal - root.rowLead - index * step) / root.rowSpan;
        return root.ease(Math.max(0, Math.min(1, t)));
    }
    // Arrow navigation over the action rows. The scope holds focus (it is a
    // FocusScope, and rows do not handle Up/Down), so every key lands here
    // first. From "no row yet", Down enters at the top and Up at the
    // bottom — the menu-activation convention. Only the action page: a
    // page's own fields keep their keys (rename's caret, search's list).
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
        revealMotion.start();
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
    // Home/End ride the generic handler: Keys has no onEndPressed attached
    // signal in this Qt, and one switch is tidier than a half-set of
    // per-key ones.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)
            && !root.pageComponent) {
            // Only the action page: on the rename page the field owns Ctrl+A
            // (select-all of the text), and the bubble must not steal it.
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
    onPageComponentChanged: {
        if (!closing)
            pageMotion.restart();
    }
    NumberAnimation {
        id: revealMotion
        target: root
        property: "reveal"
        to: 1
        // LINEAR on purpose: the easing lives in every slice (see above).
        // Reduced motion collapses both directions to an instant, and
        // onFinished still delivers closeRequested so the host unloads
        // exactly the same way.
        duration: Appearance.reducedMotion ? 0
            : root.closing ? Appearance.animation.popupExit.duration
                : Appearance.animation.popupEnter.duration
        easing.type: Easing.Linear
        onFinished: { if (root.closing) root.closeRequested(); }
    }
    SequentialAnimation {
        id: pageMotion
        NumberAnimation {
            target: pageLoader; property: "opacity"; to: 0
            duration: Appearance.animation.elementMoveFast.duration / 2
            easing.type: Appearance.animation.elementMoveFast.type
        }
        ScriptAction { script: root.displayedPage = root.pageComponent }
        NumberAnimation {
            target: pageLoader; property: "opacity"; to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
        onWheel: wheel => wheel.accepted = true
    }
    // Edit Mode shrinks the whole desktop; a menu that shrinks with it is
    // both hard to read and rasterized off its native grid (jagged icons,
    // symbols and glyph edges). The host hands in the factor to undo — the
    // align bar's counter-scale pattern — and the card is then laid out and
    // drawn in SCREEN pixels: anchorPoint arrives in surface coordinates
    // and is converted here, the clamp runs on the unscaled extent, and
    // `width` below already reads as screen px because the two transforms
    // (×k here, ×s on the surface) cancel. 1 outside the mode, where every
    // expression below collapses to the old one.
    property real counterScale: 1
    ColumnLayout {
        id: cards
        x: Math.max(8, Math.min(root.anchorPoint.x / root.counterScale, root.width - width - 8)) * root.counterScale
        y: Math.max(8, Math.min(root.anchorPoint.y / root.counterScale, root.height - height - 8)) * root.counterScale
        width: Math.max(0, Math.min(360, root.width - 16))
        spacing: 6
        // The body pops up from under the cursor's corner and is SETTLED by
        // ~140 ms (first slice of the scalar): opacity lands almost at once,
        // grow and rise finish on the body's own eased slice. TopLeft origin:
        // the corner under the pointer holds while it unfolds down-right —
        // and the SAME origin carries the counter-scale, multiplied into the
        // body's grow so one binding owns the final transform. While the
        // body stands still, the rows wave in inside it.
        opacity: Math.min(1, root.reveal * 8)
        scale: root.counterScale * (0.94 + 0.06 * root.bodyReveal)
        transformOrigin: Item.TopLeft
        transform: Translate { y: (1 - root.bodyReveal) * 10 }
        enabled: !root.closing
        Behavior on y {
            enabled: root.counterScale === 1
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Rectangle {
            id: plate
            Layout.fillWidth: true
            implicitHeight: 88
            // The plate leads the cascade: it rises into place during the
            // first slice of the scalar while the rows are still invisible.
            opacity: root.plateReveal
            transform: Translate { y: (1 - root.plateReveal) * 10 }
            radius: Appearance.rounding.windowRounding
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                Rectangle {
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: Appearance.rounding.normal
                    color: Appearance.m3colors.m3surfaceContainerHigh
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
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.min(Math.max(64, root.height - 110), pageLoader.implicitHeight + 12)
            Behavior on implicitHeight { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            radius: Appearance.rounding.windowRounding
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            ScrollView {
                anchors.fill: parent
                anchors.margins: 6
                id: pageScroll
                // The style's ScrollView hardcodes clip:true; overriding it on
                // the instance is what actually lets a hovered row's 1.01
                // swell grow into the 6px margin instead of being shaved at
                // the viewport edge.
                clip: false
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Loader {
                    id: pageLoader
                    width: pageScroll.availableWidth
                    sourceComponent: root.displayedPage ?? actionPage
                    enabled: !pageMotion.running && !root.closing
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
                delegate: ContextActionButton {
                    required property var modelData
                    required property int index
                    readonly property real arrived: root.rowReveal(index, root.actions.length)
                    textLabel: modelData.text
                    symbol: modelData.icon
                    symbolFill: modelData.filled === true ? 1 : 0
                    destructive: modelData.destructive === true
                    submenu: modelData.submenu === true
                    enabled: modelData.enabled !== false
                    // The cascade owns opacity and scale while it is in
                    // flight; RippleButton's interaction Behaviors chase a
                    // target that moves every tick (AGENTS §5b), so they
                    // come back only once the scalar has landed.
                    opacity: arrived
                    // The sidebar's exact pair: fade + settle from 0.965.
                    // No position slide — StaggeredEntrance never moves the
                    // row, and a rise under a growing card is how the old
                    // version read as flicker instead of a wave.
                    visualScale: 0.965 + 0.035 * arrived
                    transformOrigin: Item.TopLeft
                    opacityBehaviorEnabled: root.reveal >= 1
                    onClicked: root.actionTriggered(modelData.id)
                }
            }
        }
    }
}
