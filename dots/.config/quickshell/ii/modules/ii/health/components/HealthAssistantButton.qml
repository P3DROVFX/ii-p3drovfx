pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * The ✦ button, the seat Modes and Routines gave the assistant: an icon button that
 * opens the prompt pill and turns into the button that folds it away again. Hidden when
 * the assistant is switched off in Settings or by the shell-wide AI policy.
 */
ClockIconButton {
    id: root

    required property HealthAssistant assistant
    /// What this button explains ("finding:<id>", "crash:<exe>", "overview").
    required property string key
    /// Returns the facts about the subject at send time.
    property var provider: null
    property string label: Translation.tr("Explain with the assistant")

    readonly property bool open: root.assistant.isOpenOn(root.key)

    visible: root.assistant.allowed
    symbol: root.open ? "close" : "auto_awesome"
    toggled: root.open && root.assistant.phase === "idle"
    tooltip: root.open ? Translation.tr("Close the assistant") : root.label
    onClicked: root.assistant.toggle(root.key, root.provider)
}
