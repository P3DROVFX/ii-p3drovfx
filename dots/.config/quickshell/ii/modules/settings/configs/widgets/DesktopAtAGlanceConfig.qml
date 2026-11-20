pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.utility
import qs.modules.settings.configs.widgets

/*
 * At a Glance, configured the Smartspacer way: an ordered list of Targets, an
 * ordered list of Complications (each with settings and All/Any
 * requirements), and the widget's paging, colour, pinning, lock screen and
 * Expanded options. The preview is the real widget over the wallpaper.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var options: Config.options.background.widgets.at_a_glance
    readonly property var targets: AtAGlanceService.listOf(root.options.targets)
    readonly property var complications: AtAGlanceService.listOf(root.options.complications)
    property string openId: ""

    function listFor(kind) {
        return kind === "complication" ? root.complications.slice() : root.targets.slice();
    }
    function write(kind, list) {
        if (kind === "complication")
            root.options.complications = list;
        else
            root.options.targets = list;
    }
    function move(kind, index, delta) {
        const list = root.listFor(kind);
        const to = index + delta;
        if (to < 0 || to >= list.length)
            return;
        const [item] = list.splice(index, 1);
        list.splice(to, 0, item);
        root.write(kind, list);
    }
    function replace(kind, index, item) {
        const list = root.listFor(kind);
        list[index] = item;
        root.write(kind, list);
    }
    function remove(kind, index) {
        const list = root.listFor(kind);
        list.splice(index, 1);
        root.write(kind, list);
    }
    function add(kind, type) {
        const list = root.listFor(kind);
        const item = AtAGlanceService.newItem(kind, type);
        list.push(item);
        root.write(kind, list);
        root.openId = item.id;
    }

    WidgetPageHeader {
        title: Translation.tr("At a Glance Widget Options")
        onBack: root.goBack()
    }

    // ── Preview: the real widget over the wallpaper ────────────────────────────
    ClippingRectangle {
        id: preview
        Layout.fillWidth: true
        implicitHeight: Math.max(160, previewWidget.implicitHeight * previewWidget.scale + 48)
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        Image {
            anchors.fill: parent
            source: {
                const bg = Config.options.background;
                const path = Wallpapers.isVideoFile(bg.wallpaperPath ?? "") ? (bg.thumbnailPath ?? "") : (bg.wallpaperPath ?? "");
                return path ? "file://" + path : "";
            }
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 1200
            asynchronous: true
        }

        AtAGlanceWidget {
            id: previewWidget
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 24
            isPreview: true
            transformOrigin: Item.Left
            scale: Math.min(1, (preview.width - 48) / Math.max(1, implicitWidth))
        }
    }

    // ── Targets ────────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Targets")
        icon: "view_carousel"
        tooltip: Translation.tr("Targets are the pages of At a Glance. They show in this order; one may produce several pages (one per event or notification).")

        Repeater {
            model: root.targets.length
            delegate: AtAGlanceItemCard {
                required property int index
                kind: "target"
                item: root.targets[index] ?? ({})
                count: root.targets.length
                open: root.openId === (item.id ?? "")
                onToggleOpen: root.openId = open ? "" : item.id
                onMoved: delta => root.move("target", index, delta)
                onRemoved: root.remove("target", index)
                onChanged: next => root.replace("target", index, next)
            }
        }

        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "add"
            textRole: "displayName"
            model: [{ displayName: Translation.tr("Add Target…"), type: "" }].concat(
                AtAGlanceService.targetTypes
                    .filter(t => !t.single || !root.targets.some(i => i.type === t.type))
                    .map(t => ({ displayName: t.name, type: t.type })))
            currentIndex: 0
            onActivated: index => {
                const type = model[index]?.type ?? "";
                currentIndex = 0;
                if (type !== "")
                    root.add("target", type);
            }
        }
    }

    // ── Complications ──────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Complications")
        icon: "widgets"
        tooltip: Translation.tr("Small items shown next to the Date, Greeting and Blank targets, two at a time. Any left over get pages of their own after the Targets.")

        Repeater {
            model: root.complications.length
            delegate: AtAGlanceItemCard {
                required property int index
                kind: "complication"
                item: root.complications[index] ?? ({})
                count: root.complications.length
                open: root.openId === (item.id ?? "")
                onToggleOpen: root.openId = open ? "" : item.id
                onMoved: delta => root.move("complication", index, delta)
                onRemoved: root.remove("complication", index)
                onChanged: next => root.replace("complication", index, next)
            }
        }

        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "add"
            textRole: "displayName"
            model: [{ displayName: Translation.tr("Add Complication…"), type: "" }].concat(
                AtAGlanceService.complicationTypes.map(t => ({ displayName: t.name, type: t.type })))
            currentIndex: 0
            onActivated: index => {
                const type = model[index]?.type ?? "";
                currentIndex = 0;
                if (type !== "")
                    root.add("complication", type);
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("Complication on Date")
        }
        ConfigSelectionArray {
            currentValue: root.options.complicationOnDate ?? "always"
            onSelected: value => root.options.complicationOnDate = value
            options: [
                { displayName: Translation.tr("Always"), icon: "done_all", value: "always" },
                { displayName: Translation.tr("Weather only"), icon: "partly_cloudy_day", value: "weather" },
                { displayName: Translation.tr("Never"), icon: "block", value: "never" }
            ]
        }
    }

    // ── Widget ─────────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Widget")
        icon: "view_day"

        WidgetSizeSlider {
            options: root.options
        }

        ContentSubsectionLabel {
            text: Translation.tr("Width")
        }
        ConfigSelectionArray {
            currentValue: root.options.widthCells ?? 3
            onSelected: value => root.options.widthCells = value
            options: [
                { displayName: Translation.tr("Compact"), icon: "crop_7_5", value: 2 },
                { displayName: Translation.tr("Regular"), icon: "crop_16_9", value: 3 },
                { displayName: Translation.tr("Wide"), icon: "panorama_wide_angle", value: 4 }
            ]
        }

        ContentSubsectionLabel {
            text: Translation.tr("Layout")
        }
        ConfigSelectionArray {
            currentValue: root.options.layout ?? "horizontal"
            onSelected: value => root.options.layout = value
            options: [
                { displayName: Translation.tr("Horizontal"), icon: "view_carousel", value: "horizontal" },
                { displayName: Translation.tr("Vertical"), icon: "view_agenda", value: "vertical" }
            ]
        }

        ConfigRow {
            Layout.fillWidth: true
            uniform: true
            ConfigSwitch {
                buttonIcon: "filter_1"
                text: Translation.tr("Single Page")
                checked: root.options.singlePage ?? false
                onCheckedChanged: root.options.singlePage = checked
                StyledToolTip { text: Translation.tr("Only show the top Target and its Complications") }
            }
            ConfigSwitch {
                buttonIcon: "animation"
                text: Translation.tr("Animate Changes")
                checked: root.options.animateChanges ?? true
                onCheckedChanged: root.options.animateChanges = checked
                StyledToolTip { text: Translation.tr("Slide and fade between pages") }
            }
        }
        ConfigRow {
            Layout.fillWidth: true
            uniform: true
            ConfigSwitch {
                buttonIcon: "more_horiz"
                text: Translation.tr("Show Page Controls")
                checked: root.options.showPageControls ?? true
                onCheckedChanged: root.options.showPageControls = checked
                StyledToolTip { text: Translation.tr("Dots or arrows to change pages; they loop back to the first page. The mouse wheel also pages") }
            }
            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Invisible Controls")
                checked: root.options.invisibleControls ?? false
                onCheckedChanged: root.options.invisibleControls = checked
                StyledToolTip { text: Translation.tr("Hide the page controls, keeping them clickable") }
            }
        }
        ConfigSelectionArray {
            visible: (root.options.layout ?? "horizontal") === "horizontal" && (root.options.showPageControls ?? true)
            currentValue: root.options.pageControlStyle ?? "dots"
            onSelected: value => root.options.pageControlStyle = value
            options: [
                { displayName: Translation.tr("Dots"), icon: "more_horiz", value: "dots" },
                { displayName: Translation.tr("Arrows"), icon: "unfold_more", value: "arrows" }
            ]
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "padding"
            text: Translation.tr("Extra Padding")
            checked: root.options.extraPadding ?? false
            onCheckedChanged: root.options.extraPadding = checked
            StyledToolTip { text: Translation.tr("Add more space around the widget's content") }
        }
    }

    // ── Appearance ─────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Appearance")
        icon: "palette"

        ConfigRow {
            Layout.fillWidth: true
            uniform: true
            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Material You Style")
                checked: root.options.materialYouStyle ?? false
                onCheckedChanged: root.options.materialYouStyle = checked
                StyledToolTip { text: Translation.tr("Draw the widget on a card with the widget color scheme instead of over the wallpaper") }
            }
            ConfigSwitch {
                buttonIcon: "shadow"
                text: Translation.tr("Text Shadow")
                checked: root.options.textShadow ?? true
                enabled: !(root.options.materialYouStyle ?? false)
                onCheckedChanged: root.options.textShadow = checked
                StyledToolTip { text: Translation.tr("Shadow behind text and icons, for legibility over the wallpaper") }
            }
        }
        ContentSubsectionLabel {
            visible: !(root.options.materialYouStyle ?? false)
            text: Translation.tr("Tint Colour")
        }
        ConfigSelectionArray {
            visible: !(root.options.materialYouStyle ?? false)
            currentValue: root.options.tintColour ?? "automatic"
            onSelected: value => root.options.tintColour = value
            options: [
                { displayName: Translation.tr("Automatic (Wallpaper Based)"), icon: "wallpaper", value: "automatic" },
                { displayName: Translation.tr("White"), icon: "light_mode", value: "white" },
                { displayName: Translation.tr("Black"), icon: "dark_mode", value: "black" }
            ]
        }
    }

    // ── Pinning ────────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Widget Pinning")
        icon: "push_pin"

        ConfigSelectionArray {
            currentValue: root.options.pinMode ?? "none"
            onSelected: value => root.options.pinMode = value
            options: [
                { displayName: Translation.tr("None (cycle through all)"), icon: "view_carousel", value: "none" },
                { displayName: Translation.tr("Pin to Page Position"), icon: "looks_one", value: "position" },
                { displayName: Translation.tr("Pin to Specific Target"), icon: "push_pin", value: "target" }
            ]
        }
        ConfigSpinBox {
            Layout.fillWidth: true
            visible: (root.options.pinMode ?? "none") === "position"
            icon: "looks_one"
            text: Translation.tr("Page")
            from: 1
            to: 20
            stepSize: 1
            value: root.options.pinPosition ?? 1
            onValueChanged: root.options.pinPosition = value
        }
        StyledComboBox {
            id: pinTargetCombo
            Layout.fillWidth: true
            visible: (root.options.pinMode ?? "none") === "target"
            buttonIcon: "push_pin"
            textRole: "displayName"
            readonly property var entries: root.targets.map((t, i) => ({
                displayName: (i + 1) + ". " + AtAGlanceService.typeInfo("target", t.type).name,
                id: t.id
            }))
            model: entries
            currentIndex: Math.max(0, entries.findIndex(e => e.id === (root.options.pinTargetId ?? "")))
            onActivated: index => root.options.pinTargetId = entries[index]?.id ?? ""
        }
        ContentSubsectionLabel {
            visible: (root.options.pinMode ?? "none") !== "none"
            text: Translation.tr("When Unavailable")
        }
        ConfigSelectionArray {
            visible: (root.options.pinMode ?? "none") !== "none"
            currentValue: root.options.whenUnavailable ?? "date"
            onSelected: value => root.options.whenUnavailable = value
            options: [
                { displayName: Translation.tr("Show date"), icon: "today", value: "date" },
                { displayName: Translation.tr("Show first available target"), icon: "first_page", value: "first" },
                { displayName: Translation.tr("Hide widget content"), icon: "visibility_off", value: "hide" }
            ]
        }
    }

    // ── Lock screen ────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Hide Sensitive Targets")
        icon: "lock"
        tooltip: Translation.tr("On the lock screen, for Targets that carry personal content (calendar events, notifications, tasks, email)")

        ConfigSelectionArray {
            currentValue: root.options.hideSensitive ?? "none"
            onSelected: value => root.options.hideSensitive = value
            options: [
                { displayName: Translation.tr("Do not hide"), icon: "visibility", value: "none" },
                { displayName: Translation.tr("Hide contents"), icon: "password", value: "contents" },
                { displayName: Translation.tr("Hide target"), icon: "visibility_off", value: "target" }
            ]
        }
    }

    // ── Expanded ───────────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Expanded At a Glance")
        icon: "open_in_full"
        tooltip: Translation.tr("A card with every Target and a grid of every Complication, opened from the widget")

        ConfigRow {
            Layout.fillWidth: true
            uniform: true
            ConfigSwitch {
                buttonIcon: "open_in_full"
                text: Translation.tr("Enable Expanded")
                checked: root.options.expandedEnabled ?? true
                onCheckedChanged: root.options.expandedEnabled = checked
            }
            ConfigSwitch {
                buttonIcon: "vertical_align_top"
                text: Translation.tr("Complications First")
                checked: root.options.complicationsFirst ?? false
                enabled: root.options.expandedEnabled ?? true
                onCheckedChanged: root.options.complicationsFirst = checked
                StyledToolTip { text: Translation.tr("Show the Complications grid above all the Targets") }
            }
        }
        ContentSubsectionLabel {
            visible: root.options.expandedEnabled ?? true
            text: Translation.tr("Open on tap")
        }
        ConfigSelectionArray {
            visible: root.options.expandedEnabled ?? true
            currentValue: root.options.expandedOpenMode ?? "expanded"
            onSelected: value => root.options.expandedOpenMode = value
            options: [
                { displayName: Translation.tr("Never"), icon: "block", value: "never" },
                { displayName: Translation.tr("If the Target has expanded options"), icon: "unfold_more", value: "expanded" },
                { displayName: Translation.tr("Always"), icon: "done_all", value: "always" }
            ]
        }
    }
}
