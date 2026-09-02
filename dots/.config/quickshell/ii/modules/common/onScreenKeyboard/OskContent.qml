import qs.services
import qs.modules.common
import "layouts.js" as Layouts
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property var layouts: Layouts.byName

    // "auto" follows Hyprland, which HyprlandXkb used to arrange by writing the layout into the
    // config. It reports and nothing more now, so the keyboard does the resolving. deckFor names a
    // layout for any xkb code and falls back to the default one, which is the answer anyway for a
    // code no classic table covers.
    readonly property string requestedLayout: {
        const configured = Config.options?.osk.layout ?? "auto";
        return configured === "auto" ? Layouts.deckFor(HyprlandXkb.currentLayoutCode).name : configured;
    }
    property var activeLayoutName: (layouts.hasOwnProperty(root.requestedLayout))
        ? root.requestedLayout
        : Layouts.defaultLayout
    property var currentLayout: layouts[activeLayoutName]

    implicitWidth: keyRows.implicitWidth
    implicitHeight: keyRows.implicitHeight

    ColumnLayout {
        id: keyRows
        anchors.fill: parent
        spacing: 5

        Repeater {
            model: root.currentLayout.keys

            delegate: RowLayout {
                id: keyRow
                required property var modelData
                spacing: 5
                
                Repeater {
                    model: modelData
                    // A normal key looks like this: {label: "a", labelShift: "A", shape: "normal", keycode: 30, type: "normal"}
                    delegate: OskKey { 
                        required property var modelData
                        keyData: modelData
                    }
                }
            }
        }
    }
}
