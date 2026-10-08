import QtQuick
import qs.modules.common
import "WorkspacesCatalog.js" as Catalog

/**
 * What the page's previews draw: the saved options, with whatever the pointer is
 * resting on (`tryProps`) laid over them, plus the stage's own pretend focus.
 */
QtObject {
    id: root

    readonly property int previewLimit: 10
    readonly property int tourInterval: 1500
    readonly property int tourResume: 4000

    property var tryProps: ({})
    property bool playing: true
    property bool stageVisible: true
    property bool superHeld: false
    property int activeSlot: 0
    property int tourStep: 0

    readonly property var cfg: Config.options.bar.workspaces
    readonly property var icons: Config.options.appearance.icons

    function pick(key, fallback) {
        return root.tryProps[key] !== undefined ? root.tryProps[key] : fallback;
    }

    readonly property bool trying: Object.keys(root.tryProps).length > 0
    readonly property string styleId: root.pick("style", Config.options.bar.styles.workspaces)
    readonly property string colorMode: root.pick("colorMode", root.cfg.colorMode)
    readonly property string indicatorMode: root.pick("indicator", Catalog.indicatorOf(root.cfg))
    readonly property string indicatorShape: root.pick("indicatorShape", root.cfg.activeIndicatorShape)
    readonly property var numberMap: root.pick("numberMap", root.cfg.numberMap)
    readonly property int shown: root.pick("shown", root.cfg.shown)
    readonly property int count: Math.max(1, Math.min(root.previewLimit, root.shown))
    readonly property int maxWindows: root.pick("maxWindows", root.cfg.maxWindowCount)
    readonly property bool dynamic: root.pick("dynamic", root.cfg.dynamicWorkspaces)
    readonly property bool showIcons: root.pick("showIcons", root.cfg.showAppIcons)
    readonly property bool tintIcons: root.pick("tintIcons", root.cfg.monochromeIcons)
    readonly property real tintAmount: root.pick("tintAmount", Config.options.appearance.iconTintPercentage ?? 0.6)
    readonly property bool maskIcons: root.pick("maskIcons", root.icons.enableShapeMask)
    readonly property string maskShape: root.pick("maskShape", root.icons.shapeMask)
    readonly property bool alwaysNumbers: root.pick("alwaysNumbers", root.cfg.alwaysShowNumbers)
    readonly property int numberDelay: root.cfg.showNumberDelay
    readonly property bool showNumbers: root.alwaysNumbers || root.superHeld
    readonly property bool dockIndicator: root.pick("dockIndicator", root.cfg.dockShowActiveIndicator)
    readonly property bool dockDots: root.pick("dockDots", root.cfg.dockShowWindowDots)
    readonly property bool dockIcons: root.pick("dockIcons", root.cfg.dockShowAppIcons)

    function jumpTo(index) {
        root.activeSlot = Math.max(0, Math.min(root.count - 1, index));
        if (root.playing)
            root.resume.restart();
    }

    function advance() {
        const stops = Catalog.DEMO_TOUR.filter(i => i < root.count);
        if (stops.length === 0)
            return;
        root.tourStep = (root.tourStep + 1) % stops.length;
        root.activeSlot = stops[root.tourStep];
    }

    onCountChanged: {
        if (root.activeSlot >= root.count)
            root.activeSlot = root.count - 1;
    }

    property Timer tour: Timer {
        interval: root.tourInterval
        repeat: true
        running: root.playing && root.stageVisible && !root.resume.running
        onTriggered: root.advance()
    }

    property Timer resume: Timer {
        interval: root.tourResume
    }
}
