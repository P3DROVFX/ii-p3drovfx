import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

AndroidQuickToggleButton {
    id: root
    toggleModel: ModesToggle {
        // The model's "nothing to toggle" fallback lands on the menu.
        altAction: () => root.openMenu()
    }
}
