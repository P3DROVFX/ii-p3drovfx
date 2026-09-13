pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property var hints: []
    property bool showKeys: true
    property color surface: Appearance.colors.colSurfaceContainerHigh
    property color onSurface: Appearance.colors.colOnSurface

    property real spacing: 8
    // A Flow retains the single-row appearance when there is space and wraps
    // complete label/key pairs when a host becomes narrower. Its implicit
    // height makes the enclosing layout reserve the resulting extra rows.
    implicitHeight: hintFlow.implicitHeight
    implicitWidth: {
        let total = 0;
        for (let index = 0; index < hintRepeater.count; index++) {
            const hint = hintRepeater.itemAt(index);
            if (hint && hint.visible)
                total += hint.implicitWidth + root.spacing;
        }
        return Math.max(0, total - root.spacing);
    }

    Flow {
        id: hintFlow
        width: root.width
        height: implicitHeight
        spacing: root.spacing

        Repeater {
            id: hintRepeater
            model: root.hints

            delegate: RowLayout {
                required property var modelData

                spacing: 4

                StyledText {
                    text: modelData.label ?? ""
                    color: root.onSurface
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }

                ConfiguredKeyHint {
                    visible: root.showKeys && (modelData.keys ?? []).length > 0
                    actionId: modelData.actionId ?? ""
                    fallbackKeys: modelData.keys ?? []
                    surface: root.surface
                    onSurface: root.onSurface
                }
            }
        }
    }
}
