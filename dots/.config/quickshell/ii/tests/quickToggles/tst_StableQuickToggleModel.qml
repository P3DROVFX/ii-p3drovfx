import QtQuick
import QtTest
import QtQml.Models
import "../../modules/common/quickToggles/androidStyle" as QuickToggleStyle

TestCase {
    id: root
    name: "StableQuickToggleModel"

    property var sourceValues: []

    component ToggleSlot: Item {
        required property int index
        required property var modelData
        property string stableId: modelData.id
        property string stableType: modelData.type
        property int stableSizeW: modelData.sizeW
        property int stableSizeH: modelData.sizeH
    }

    QuickToggleStyle.StableQuickToggleModel {
        id: stableModel
        sourceValues: root.sourceValues
    }

    Item {
        Repeater {
            id: repeater
            model: stableModel
            delegate: DelegateChooser {
                role: "toggleType"
                DelegateChoice { roleValue: "network"; ToggleSlot {} }
                DelegateChoice { roleValue: "darkMode"; ToggleSlot {} }
                DelegateChoice { roleValue: "mediaWidget"; ToggleSlot {} }
                DelegateChoice { roleValue: "tailscale"; ToggleSlot {} }
                DelegateChoice { roleValue: "volumeSlider"; ToggleSlot {} }
            }
        }
    }

    function item(id, type, width, height, x, y) {
        return { id: id, type: type, sizeW: width, sizeH: height, layoutX: x, layoutY: y };
    }

    function init() {
        root.sourceValues = [];
        tryCompare(repeater, "count", 0);
    }

    function test_removing_middle_item_removes_its_delegate_not_the_last_one() {
        root.sourceValues = [
            item("network", "network", 1, 1, 0, 0),
            item("darkMode", "darkMode", 2, 1, 86, 0),
            item("mediaWidget", "mediaWidget", 4, 2, 0, 62)
        ];
        tryCompare(repeater, "count", 3);
        var networkDelegate = repeater.itemAt(0);
        var mediaDelegate = repeater.itemAt(2);

        root.sourceValues = [
            item("network", "network", 1, 1, 0, 0),
            item("mediaWidget", "mediaWidget", 4, 2, 0, 62)
        ];

        tryCompare(repeater, "count", 2);
        compare(repeater.itemAt(0), networkDelegate);
        compare(repeater.itemAt(1), mediaDelegate);
        compare(repeater.itemAt(1).stableId, "mediaWidget");
        compare(repeater.itemAt(1).stableType, "mediaWidget");
    }

    function test_reorder_moves_identity_and_size_together() {
        root.sourceValues = [
            item("tailscale", "tailscale", 1, 1, 0, 0),
            item("darkMode", "darkMode", 2, 1, 86, 0),
            item("volumeSlider", "volumeSlider", 4, 1, 0, 62)
        ];
        tryCompare(repeater, "count", 3);
        var tailscaleDelegate = repeater.itemAt(0);
        var darkModeDelegate = repeater.itemAt(1);
        var volumeDelegate = repeater.itemAt(2);

        root.sourceValues = [
            item("volumeSlider", "volumeSlider", 4, 1, 0, 0),
            item("tailscale", "tailscale", 1, 1, 0, 62),
            item("darkMode", "darkMode", 2, 1, 86, 62)
        ];

        compare(repeater.itemAt(0), volumeDelegate);
        compare(repeater.itemAt(1), tailscaleDelegate);
        compare(repeater.itemAt(2), darkModeDelegate);
        compare(volumeDelegate.stableType, "volumeSlider");
        compare(volumeDelegate.stableSizeW, 4);
        compare(tailscaleDelegate.stableType, "tailscale");
        compare(tailscaleDelegate.stableSizeW, 1);
        compare(darkModeDelegate.stableType, "darkMode");
        compare(darkModeDelegate.stableSizeW, 2);
    }
}
