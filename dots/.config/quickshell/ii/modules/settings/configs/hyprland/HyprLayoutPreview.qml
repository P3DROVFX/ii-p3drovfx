pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Where the next window would land, drawn from the values that are actually set.
 *
 * force_split, split_bias and default_split_ratio are the options people cargo-cult hardest,
 * because nothing about them shows until several windows deep. This runs the same arithmetic the
 * layout does over an empty workspace and draws the result; the highlighted window is the one
 * that just opened. The screen box is the focused monitor's real aspect ratio, because on
 * dwindle the aspect is what decides whether a split is side by side or stacked.
 */
ColumnLayout {
    id: root

    /// Which layout to draw. Anything unrecognised falls back to a single full-screen window.
    property string engine: "dwindle"
    property int windowCount: 4

    readonly property var optionKeys: [
        "dwindle:default_split_ratio", "dwindle:split_width_multiplier", "dwindle:force_split",
        "dwindle:split_bias", "dwindle:smart_split", "dwindle:preserve_split",
        "master:mfact", "master:orientation", "master:new_status", "master:new_on_top",
        "master:slave_count_for_center_master", "master:center_master_fallback",
        "scrolling:column_width", "scrolling:direction", "scrolling:fullscreen_on_one_column"
    ]

    function numberOption(key: string, fallback: real): real {
        const value = Number(HyprlandGui.displayValue(key, fallback));
        return isNaN(value) ? fallback : value;
    }

    function flagOption(key: string, fallback: bool): bool {
        const value = HyprlandGui.displayValue(key, fallback);
        return value === true || value === 1 || value === "true";
    }

    function stringOption(key: string, fallback: string): string {
        const value = HyprlandGui.displayValue(key, fallback);
        return value === undefined || value === null || value === "" ? fallback : String(value);
    }

    readonly property real splitRatio: root.numberOption("dwindle:default_split_ratio", 1)
    readonly property real widthMultiplier: root.numberOption("dwindle:split_width_multiplier", 1)
    readonly property int forceSplit: Math.round(root.numberOption("dwindle:force_split", 0))
    readonly property int splitBias: Math.round(root.numberOption("dwindle:split_bias", 0))
    readonly property bool smartSplit: root.flagOption("dwindle:smart_split", false)
    readonly property bool preserveSplit: root.flagOption("dwindle:preserve_split", false)

    readonly property real masterFactor: root.numberOption("master:mfact", 0.55)
    readonly property string orientation: root.stringOption("master:orientation", "left")
    readonly property string newStatus: root.stringOption("master:new_status", "slave")
    readonly property bool newOnTop: root.flagOption("master:new_on_top", false)
    readonly property int slavesForCenter:
        Math.round(root.numberOption("master:slave_count_for_center_master", 2))
    readonly property string centerFallback: root.stringOption("master:center_master_fallback", "left")

    readonly property real columnWidth: root.numberOption("scrolling:column_width", 0.5)
    readonly property string scrollDirection: root.stringOption("scrolling:direction", "right")
    readonly property bool fullscreenOnOneColumn:
        root.flagOption("scrolling:fullscreen_on_one_column", true)

    /// A rotated monitor reports its untransformed size, so the odd transforms swap the axes.
    readonly property real screenAspect: {
        const monitor = Hyprland.focusedMonitor;
        const width = Number(monitor?.width ?? 0);
        const height = Number(monitor?.height ?? 0);
        if (!(width > 0) || !(height > 0)) return 16 / 10;
        return (Math.round(Number(monitor?.transform ?? 0)) % 2) === 1 ? height / width : width / height;
    }

    function dwindleWindows(): var {
        const share = Math.max(0.08, Math.min(0.92, root.splitRatio / 2));
        // force_split 1 puts the new window on the left or top; 0 follows the pointer, and the
        // diagram has to pick a side for that, so it picks the one it lands on most of the time.
        const newIsFirst = root.forceSplit === 1;
        // split_bias 1 hands the ratio to the window that was already there, wherever it ends up.
        const firstShare = (root.splitBias === 1 && newIsFirst) ? 1 - share : share;
        const out = [{ "x": 0, "y": 0, "w": 1, "h": 1, "label": "1", "isNew": false }];
        for (let index = 2; index <= root.windowCount; index++) {
            const target = out[out.length - 1];
            const sideBySide = target.w * root.screenAspect > target.h * root.widthMultiplier;
            const first = sideBySide
                ? { "x": target.x, "y": target.y, "w": target.w * firstShare, "h": target.h }
                : { "x": target.x, "y": target.y, "w": target.w, "h": target.h * firstShare };
            const second = sideBySide
                ? { "x": target.x + target.w * firstShare, "y": target.y,
                    "w": target.w * (1 - firstShare), "h": target.h }
                : { "x": target.x, "y": target.y + target.h * firstShare,
                    "w": target.w, "h": target.h * (1 - firstShare) };
            const kept = newIsFirst ? second : first;
            const fresh = newIsFirst ? first : second;
            out[out.length - 1] = { "x": kept.x, "y": kept.y, "w": kept.w, "h": kept.h,
                "label": target.label, "isNew": false };
            out.push({ "x": fresh.x, "y": fresh.y, "w": fresh.w, "h": fresh.h,
                "label": String(index), "isNew": index === root.windowCount });
        }
        return out;
    }

    function masterWindows(): var {
        const slaves = Math.max(0, root.windowCount - 1);
        const orientation = (root.orientation === "center" && slaves < root.slavesForCenter)
            ? root.centerFallback : root.orientation;
        const factor = Math.max(0.1, Math.min(0.9, root.masterFactor));
        const masterIsNew = root.newStatus === "master";
        const out = [];

        function stack(count, x, y, w, h, vertical, offset) {
            for (let index = 0; index < count; index++) {
                const step = index / count;
                const size = 1 / count;
                out.push({
                    "x": vertical ? x : x + w * step,
                    "y": vertical ? y + h * step : y,
                    "w": vertical ? w : w * size,
                    "h": vertical ? h * size : h,
                    "label": "",
                    // The freshest slave sits at the top of the stack, or at its end.
                    "isNew": !masterIsNew && index === (root.newOnTop ? 0 : count - 1) && offset === 0
                });
            }
        }

        if (orientation === "center") {
            const side = (1 - factor) / 2;
            const left = Math.ceil(slaves / 2);
            stack(left, 0, 0, side, 1, true, 0);
            stack(slaves - left, side + factor, 0, side, 1, true, 1);
            out.push({ "x": side, "y": 0, "w": factor, "h": 1, "label": "M", "isNew": masterIsNew });
            return out;
        }

        const vertical = orientation === "left" || orientation === "right";
        const before = orientation === "right" || orientation === "bottom";
        const masterRect = vertical
            ? { "x": before ? 1 - factor : 0, "y": 0, "w": factor, "h": 1 }
            : { "x": 0, "y": before ? 1 - factor : 0, "w": 1, "h": factor };
        const stackRect = vertical
            ? { "x": before ? 0 : factor, "y": 0, "w": 1 - factor, "h": 1 }
            : { "x": 0, "y": before ? 0 : factor, "w": 1, "h": 1 - factor };
        stack(slaves, stackRect.x, stackRect.y, stackRect.w, stackRect.h, vertical, 0);
        out.push({ "x": masterRect.x, "y": masterRect.y, "w": masterRect.w, "h": masterRect.h,
            "label": "M", "isNew": masterIsNew });
        return out;
    }

    function scrollingWindows(): var {
        const width = (root.windowCount === 1 && root.fullscreenOnOneColumn)
            ? 1 : Math.max(0.1, Math.min(1, root.columnWidth));
        const total = width * root.windowCount;
        // The focused column is the newest one, and the row scrolls just far enough to show it.
        const shift = Math.min(0, 1 - total);
        const out = [];
        for (let index = 0; index < root.windowCount; index++) {
            const x = shift + width * index;
            out.push({
                "x": root.scrollDirection === "left" ? 1 - x - width : x,
                "y": 0, "w": width, "h": 1,
                "label": String(index + 1),
                "isNew": index === root.windowCount - 1
            });
        }
        return out;
    }

    readonly property var windows: {
        if (root.engine === "dwindle") return root.dwindleWindows();
        if (root.engine === "master") return root.masterWindows();
        if (root.engine === "scrolling") return root.scrollingWindows();
        // Monocle stacks every window full-screen with only the focused one showing, so the
        // single rect needs a label - an unlabelled full-bleed block with a border barely
        // distinguishable from its own fill (colPrimary on colPrimaryContainer) just reads as a
        // blank rectangle. The count says what is actually stacked behind the visible one.
        const label = root.windowCount > 1 ? Translation.tr("1 of %1").arg(root.windowCount) : "1";
        return [{ "x": 0, "y": 0, "w": 1, "h": 1, "label": label, "isNew": true }];
    }

    readonly property var captionLines: {
        const out = [];
        if (root.engine === "dwindle") {
            out.push(Translation.tr("Every new window splits the focused one. A window splits side by side while it is wider than it is tall, and top to bottom once it is not."));
            if (Math.abs(root.widthMultiplier - 1) > 0.001)
                out.push(Translation.tr("A width multiplier of %1× moves where that changeover happens.")
                    .arg(root.widthMultiplier.toFixed(2)));
            if (root.forceSplit === 1)
                out.push(Translation.tr("New windows always take the left or top half."));
            else if (root.forceSplit === 2)
                out.push(Translation.tr("New windows always take the right or bottom half."));
            else
                out.push(Translation.tr("The new window takes whichever half the pointer is in. The diagram shows the right or bottom one."));
            if (Math.abs(root.splitRatio - 1) > 0.001) {
                const share = Math.round(Math.max(0.08, Math.min(0.92, root.splitRatio / 2)) * 100);
                out.push(root.splitBias === 1
                    ? Translation.tr("The window that was already there keeps %1% of the space.").arg(share)
                    : Translation.tr("The left or top side of each split takes %1% of the space.").arg(share));
            }
            if (root.smartSplit)
                out.push(Translation.tr("Smart split is on, so the quarter of the window the pointer sits in decides the direction. The diagram cannot show that."));
            if (root.preserveSplit)
                out.push(Translation.tr("Splits keep their direction when a window closes."));
            return out;
        }
        if (root.engine === "master") {
            const percent = Math.round(Math.max(0.1, Math.min(0.9, root.masterFactor)) * 100);
            const slaves = Math.max(0, root.windowCount - 1);
            const centred = root.orientation === "center" && slaves >= root.slavesForCenter;
            out.push(centred
                ? Translation.tr("The master window sits in the middle and takes %1% of the width.").arg(percent)
                : Translation.tr("The master area takes %1% of the screen, on the %2.")
                    .arg(percent).arg(root.sideName(root.orientation === "center"
                        ? root.centerFallback : root.orientation)));
            if (root.orientation === "center" && !centred)
                out.push(Translation.tr("Centring only starts at %1 windows in the stack, so this many falls back to the %2.")
                    .arg(root.slavesForCenter).arg(root.sideName(root.centerFallback)));
            if (root.newStatus === "master")
                out.push(Translation.tr("A new window becomes the master and pushes the old one into the stack."));
            else if (root.newStatus === "inherit")
                out.push(Translation.tr("A new window takes the role of the one that was focused."));
            else
                out.push(root.newOnTop
                    ? Translation.tr("New windows join the top of the stack.")
                    : Translation.tr("New windows join the end of the stack."));
            return out;
        }
        if (root.engine === "scrolling") {
            out.push(Translation.tr("Windows form a row of columns %1% of the screen wide, and the row scrolls sideways to keep the focused column in view.")
                .arg(Math.round(Math.max(0.1, Math.min(1, root.columnWidth)) * 100)));
            out.push(root.scrollDirection === "left"
                ? Translation.tr("New columns appear on the left.")
                : Translation.tr("New columns appear on the right."));
            if (root.fullscreenOnOneColumn)
                out.push(Translation.tr("A single column on its own fills the whole screen."));
            return out;
        }
        out.push(Translation.tr("Every window fills the screen and only the focused one is visible. There is nothing to tune."));
        return out;
    }

    function sideName(side: string): string {
        if (side === "right") return Translation.tr("right");
        if (side === "top") return Translation.tr("top");
        if (side === "bottom") return Translation.tr("bottom");
        return Translation.tr("left");
    }

    Layout.fillWidth: true
    spacing: 10

    Component.onCompleted: HyprlandGui.watch(root.optionKeys)

    /// Scrolling is the one layout whose row runs off the screen, so its diagram keeps a margin
    /// on both sides and dims what falls outside. Without it a four-column row would draw as two
    /// windows side by side, which is exactly what it does not look like in use.
    readonly property real overhang: root.engine === "scrolling" ? 0.25 : 0

    Item {
        id: stage

        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        Layout.maximumWidth: 380 * (1 + 2 * root.overhang)
        implicitHeight: screenRect.height
        clip: true

        Rectangle {
            id: screenRect

            x: Math.round(stage.width * root.overhang / (1 + 2 * root.overhang))
            width: Math.round(stage.width / (1 + 2 * root.overhang))
            height: Math.round(width / Math.max(0.2, root.screenAspect))
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer3
            border.width: root.overhang > 0 ? 1 : 0
            border.color: Appearance.colors.colOutlineVariant

            Behavior on x { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(screenRect) }
            Behavior on width { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(screenRect) }
        }

        Repeater {
            // The count as the model: a value change then moves the rectangles that already
            // exist - which is what lets the Behaviors below actually animate - instead of
            // tearing every delegate down because the array is a fresh one.
            model: root.windows.length

            delegate: Rectangle {
                id: windowRect
                required property int index

                readonly property var slot: root.windows[windowRect.index]
                    ?? ({ "x": 0, "y": 0, "w": 1, "h": 1, "label": "", "isNew": false })
                readonly property bool offScreen:
                    windowRect.slot.x < -0.001 || windowRect.slot.x + windowRect.slot.w > 1.001

                x: screenRect.x + Math.round(windowRect.slot.x * screenRect.width) + 3
                y: screenRect.y + Math.round(windowRect.slot.y * screenRect.height) + 3
                width: Math.max(6, Math.round(windowRect.slot.w * screenRect.width) - 6)
                height: Math.max(6, Math.round(windowRect.slot.h * screenRect.height) - 6)
                radius: Appearance.rounding.verysmall
                opacity: windowRect.offScreen ? 0.35 : 1
                color: windowRect.slot.isNew
                    ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                border.width: 1
                border.color: windowRect.slot.isNew
                    ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                Behavior on x { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(windowRect) }
                Behavior on y { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(windowRect) }
                Behavior on width { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(windowRect) }
                Behavior on height { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(windowRect) }
                Behavior on opacity { animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(windowRect) }

                StyledText {
                    anchors.centerIn: parent
                    visible: windowRect.slot.label !== "" && windowRect.width > 22
                        && windowRect.height > 18
                    text: windowRect.slot.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: windowRect.slot.isNew
                        ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                }
            }
        }
    }

    Repeater {
        // Count-modelled for the same reason as the windows above: the sentences change in
        // place instead of the whole footer being rebuilt on every slider release.
        model: root.captionLines.length

        delegate: StyledText {
            required property int index

            Layout.fillWidth: true
            text: root.captionLines[index] ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }
}
