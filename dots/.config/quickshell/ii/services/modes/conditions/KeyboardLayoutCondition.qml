import QtQuick
import qs.services
import ".."

/**
 * The active keyboard layout's code is `code` ("fr", "us").
 */
ModeCondition {
    id: root
    readonly property string code: String(root.params?.code ?? "").toLowerCase()
    readonly property string current: String(HyprlandXkb.currentLayoutCode ?? "").toLowerCase()

    satisfied: root.code.length > 0 && root.current === root.code
    reason: HyprlandXkb.currentLayoutName || root.current
}
