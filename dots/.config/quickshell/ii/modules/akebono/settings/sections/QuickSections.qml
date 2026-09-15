import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    Layout.fillWidth: true
    spacing: 10

    ConfigRow {
        ContentSubsection {
            title: Translation.tr("Shelf position")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.shelf.position
                onSelected: newValue => Config.options.akebono.shelf.position = newValue
                options: [
                    {
                        displayName: Translation.tr("Top"),
                        icon: "arrow_upward",
                        value: "top"
                    },
                    {
                        displayName: Translation.tr("Bottom"),
                        icon: "arrow_downward",
                        value: "bottom"
                    }
                ]
            }
        }
        ContentSubsection {
            title: Translation.tr("Shelf style")
            ConfigSelectionArray {
                currentValue: Config.options.akebono.shelf.shape
                onSelected: newValue => Config.options.akebono.shelf.shape = newValue
                options: [
                    { displayName: Translation.tr("Float"), icon: "flip_to_front", value: "float" },
                    { displayName: Translation.tr("Inverse hug"), icon: "rounded_corner", value: "inverseHug" },
                    { displayName: Translation.tr("Hug"), icon: "line_curve", value: "hug" },
                    { displayName: Translation.tr("Rect"), icon: "crop_square", value: "rect" }
                ]
            }
        }
    }
}
