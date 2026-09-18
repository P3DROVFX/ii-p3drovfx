import QtQuick
import qs
import qs.modules.common
import qs.modules.ii.dynamicIsland.core

// Computes leftList / centerList / rightList from Config.options.bar.layouts.center.
// A widget with { centered: true } becomes the single centerList item;
// everything before it goes to leftList, everything after to rightList.
// If no centered widget exists, all items go to centerList (legacy behavior).
Item {
    id: root
    visible: false

    readonly property var _emptyLayout: []
    readonly property var fullModel: {
        const model = Config.options.bar.layouts.center;
        return (model && model.length > 0) ? model : root._emptyLayout;
    }
    // Islands background style overrides centered — widgets must follow the

    // island layout, not their own centering.
    readonly property int centerIdx: Config.options.bar.barBackgroundStyle === 3 ? -1 : fullModel.findIndex(item => item.centered)

    readonly property var leftList: centerIdx === -1 ? root._emptyLayout : fullModel.slice(0, centerIdx)
    // The centre is only surrendered when the island will actually be there. Reading the
    // raw config surrendered it for bar styles the island refuses to draw in, which hid
    // the user's centre widgets and put nothing in their place.
    readonly property var centerList: IslandPolicy.centerInBar ? root._emptyLayout : (centerIdx === -1 ? fullModel.slice() : [fullModel[centerIdx]])
    readonly property var rightList: centerIdx === -1 ? root._emptyLayout : fullModel.slice(centerIdx + 1)
}
