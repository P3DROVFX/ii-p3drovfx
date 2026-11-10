pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The ✦ on a row whose subject has an assistant answer waiting: steady for a saved
 * one, breathing while one is being written. Takes no room otherwise.
 */
MaterialSymbol {
    id: root

    property var assistant: null
    property string key: ""

    readonly property bool writing: root.assistant !== null && root.assistant.runKey === root.key && root.assistant.phase === "running"
    readonly property bool saved: root.key.length > 0 && HealthAnswers.entries[root.key] !== undefined

    visible: root.writing || root.saved
    text: "auto_awesome"
    iconSize: ClockStyle.iconSmall
    fill: 1

    HoverHandler {
        id: markHover
    }
    // Only on hover: a symbol has no hover of its own, which a tooltip reads as
    // always hovered.
    StyledToolTip {
        extraVisibleCondition: markHover.hovered
        text: root.writing ? Translation.tr("The assistant is answering") : Translation.tr("An assistant answer is waiting")
    }

    SequentialAnimation on opacity {
        running: root.writing && !ClockStyle.reducedMotion
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
    }
}
