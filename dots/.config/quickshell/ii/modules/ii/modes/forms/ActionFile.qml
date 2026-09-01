pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `file` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
RowLayout {
    required property var row

    spacing: 8

    PlainField {
        Layout.fillWidth: true
        value: String(row.value ?? "")
        placeholder: Translation.tr("Absolute path to an image")
        onCommitted: v => row.setValue(v)
    }

    SmallButton {
        buttonText: Translation.tr("Use current")
        onClicked: row.setValue(Config.options.background.wallpaperPath)
    }
}
