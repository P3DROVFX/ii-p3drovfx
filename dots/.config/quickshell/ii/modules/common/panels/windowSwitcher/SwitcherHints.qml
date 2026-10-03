import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/windowSwitcher/WindowSwitcherLogic.js" as Logic

/**
 * The quiet line under the switcher: where the selection is in a list too long to see at once
 * ("4 / 17", `showPosition`), and - unless turned off (windowSwitcher.showKeyHints) - the keys
 * that do something right now. Shared by the island and the panel.
 */
StyledText {
    id: hints

    property bool showPosition: false

    readonly property var keys: {
        if (WindowSwitcher.released)
            return [["Enter", Translation.tr("switch")], ["Tab", Translation.tr("next")], ["Esc", Translation.tr("cancel")]];
        if (WindowSwitcher.query.length > 0)
            return [["Enter", Translation.tr("switch")], [Translation.tr("Let go of Alt"), Translation.tr("keep typing")],
                ["Esc", Translation.tr("clear")]];
        return [["Tab", Translation.tr("next")], ["1–9", Translation.tr("pick")], ["Del", Translation.tr("close")],
            [Translation.tr("Type"), Translation.tr("search")]];
    }
    readonly property var parts: {
        const out = [];
        if (hints.showPosition)
            out.push(Logic.positionText(WindowSwitcher.selectedIndex, WindowSwitcher.count));
        if (WindowSwitcher.showKeyHints)
            for (const [key, what] of hints.keys)
                out.push(`<b>${Logic.escapeHtml(key)}</b> ${Logic.escapeHtml(what)}`);
        return out.filter(part => part.length > 0);
    }

    visible: hints.parts.length > 0
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    textFormat: Text.StyledText
    text: hints.parts.join("   ·   ")
    font.pixelSize: Appearance.font.pixelSize.smaller
    color: Appearance.colors.colSubtext
}
