import qs.services
import qs.modules.common.models.quickToggles

AndroidQuickToggleButton {
    toggleModel: NetworkToggle {}
    backgroundIcon: Network.ethernet ? "" : "wifi"
    expandedIconShape: "Cookie7Sided"
    centerExpandedIcon: true
    expandedStatusTransparency: 0.4
}
