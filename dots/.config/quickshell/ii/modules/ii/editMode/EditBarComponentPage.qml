import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One bar widget's page: where it sits, and which of its looks it wears.
 *
 * Nearly every bar component ships two or more variants - the clock alone has
 * several, the media player five - and the ONLY place to choose between them
 * was a combo box on a Settings row. A mode about arranging the bar that
 * cannot say what a widget looks like is half a mode, so the variants live
 * here, one row each, marked the way every other choice in the panel is.
 *
 * The style key is a preference and is written straight through. Placement is
 * a layout edit and goes back out through the drawer to the chrome, which owns
 * every write to `bar.layouts` and the history entry around it.
 */
StyledFlickable {
    id: root

    property string componentId: ""

    signal placeRequested(string bucket)
    signal removeRequested()

    contentHeight: column.implicitHeight
    clip: true

    readonly property var info: BarComponentRegistry.getComponent(root.componentId)
    readonly property string styleKey: root.info?.styleConfigKey ?? ""
    readonly property var styleOptions: root.info?.styleOptions ?? []
    readonly property string currentStyle: root.styleKey !== ""
        ? String(Config.options.bar.styles[root.styleKey] ?? "default") : "default"

    // Which of the three lists holds it, "" for none. The centre list is the
    // one BarLayout splits into three drawn sections, so "Centre" here means
    // that list rather than the middle of the screen.
    readonly property string bucket: {
        const layouts = Config.options.bar.layouts;
        for (const name of ["left", "center", "right"])
            if ((layouts[name] ?? []).some(entry => entry && entry.id === root.componentId))
                return name;
        return "";
    }
    readonly property bool centreBlocked: ShellModePolicy.barCenterActive

    ColumnLayout {
        id: column
        width: root.width
        spacing: 4

        EditPanelSectionLabel {
            Layout.topMargin: 0
            text: Translation.tr("Placement")
        }

        EditOptionChips {
            currentValue: root.bucket === "" ? "none" : root.bucket
            lockedNote: root.centreBlocked
                ? Translation.tr("The centre group is unavailable while the Dynamic Island sits in the bar's centre.")
                : ""
            options: [
                { "displayName": Translation.tr("Off the bar"), "icon": "block", "value": "none" },
                { "displayName": Translation.tr("Left"), "icon": "align_horizontal_left", "value": "left" },
                { "displayName": Translation.tr("Centre"), "icon": "align_horizontal_center", "value": "center",
                    "enabled": !root.centreBlocked },
                { "displayName": Translation.tr("Right"), "icon": "align_horizontal_right", "value": "right" }
            ]
            onSelected: value => {
                if (value === "none") {
                    root.removeRequested();
                    return;
                }
                root.placeRequested(value);
            }
        }

        EditPanelSectionLabel {
            text: Translation.tr("Style")
        }

        EditPanelNotice {
            Layout.fillWidth: true
            visible: root.styleKey === "" || root.styleOptions.length === 0
            symbol: "style"
            text: Translation.tr("This widget has one look.")
        }

        Repeater {
            model: root.styleKey === "" ? [] : root.styleOptions

            delegate: EditPanelRow {
                required property var modelData
                required property int index
                staggerIndex: index
                Layout.fillWidth: true
                first: index === 0
                last: index === root.styleOptions.length - 1
                symbol: modelData.icon ?? "style"
                title: modelData.displayName ?? String(modelData.value)
                selected: String(modelData.value ?? "default") === root.currentStyle
                trailingKind: selected ? "check" : "none"
                rowEnabled: modelData.enabled !== false
                onActivated: Config.options.bar.styles[root.styleKey] = String(modelData.value ?? "default")
            }
        }

        // The variants above are the ones the registry publishes. Several
        // widgets carry more inside their own Settings page - the weather
        // widget's families, the clock's formats - and this page is not the
        // place to mirror a whole config tree, so it points at it instead.
        EditPanelRow {
            Layout.fillWidth: true
            Layout.topMargin: 10
            first: true
            last: true
            visible: root.componentId !== ""
            symbol: "settings"
            title: Translation.tr("All of this widget's settings")
            trailingKind: "chevron"
            onActivated: GlobalStates.openSettingsPage(root.info?.pageId ?? "bar")
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 8
        }
    }
}
