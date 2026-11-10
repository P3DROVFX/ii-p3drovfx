pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * Floating mini-toolbar appearing above active text selection (Apple Notes / Notion style).
 *
 * Provides quick inline formatting (Bold, Italic, Strikethrough, Code, Link)
 * and direct one-click access to the AI Assistant for the selected text.
 */
Rectangle {
    id: root

    property var editor: null
    property bool formattingInProgress: false

    signal aiRequested()

    readonly property bool hasActiveSelection: root.formattingInProgress || (root.editor !== null && root.editor.hasSelection && root.editor.activeTextEdit !== null && root.editor.activeTextEdit.activeFocus)
    readonly property rect selRect: root.editor ? root.editor.selectionGeometry : Qt.rect(0, 0, 0, 0)
    readonly property int policy: Number(Config.options?.policies?.ai ?? 1)

    visible: root.hasActiveSelection && (root.formattingInProgress || root.selRect.width > 0)
    opacity: root.visible ? 1.0 : 0.0

    implicitHeight: 38
    implicitWidth: barRow.implicitWidth + 16
    radius: NotesMetrics.pillRadius(root.implicitHeight)
    color: Appearance.m3colors.m3surfaceContainerHighest
    z: 25

    StyledRectangularShadow {
        target: root
    }

    // Position dynamically above the selection rectangle
    x: {
        if (!root.editor)
            return 16;
        const targetX = root.selRect.x + (root.selRect.width / 2) - (root.width / 2);
        return Math.max(16, Math.min(root.editor.width - root.width - 16, targetX));
    }

    y: {
        if (!root.editor)
            return 16;
        if (root.selRect.y > root.height + 14)
            return root.selRect.y - root.height - 8;
        return root.selRect.y + root.selRect.height + 8;
    }

    Behavior on opacity {
        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        preventStealing: true
    }

    function _hasExactMarkerAround(full, sMin, sMax, prefix, suffix): bool {
        if (prefix === "[") {
            const before = full.slice(Math.max(0, sMin - 1), sMin);
            const afterRest = full.slice(sMax);
            return before === "[" && /^\]\([^)]*\)/.test(afterRest);
        }
        const before = full.slice(Math.max(0, sMin - prefix.length), sMin);
        const after = full.slice(sMax, sMax + suffix.length);
        if (before !== prefix || after !== suffix)
            return false;
        if (prefix === "*" && suffix === "*") {
            const before2 = full.slice(Math.max(0, sMin - 2), sMin);
            const after2 = full.slice(sMax, sMax + 2);
            const before3 = full.slice(Math.max(0, sMin - 3), sMin);
            const after3 = full.slice(sMax, sMax + 3);
            if (before2 === "**" && after2 === "**" && !(before3 === "***" && after3 === "***"))
                return false;
        }
        return true;
    }

    function _hasExactMarkerInside(sel, prefix, suffix): bool {
        if (prefix === "[")
            return /^\[[^\]]+\]\([^)]*\)$/.test(sel);
        if (sel.length < prefix.length + suffix.length)
            return false;
        if (!sel.startsWith(prefix) || !sel.endsWith(suffix))
            return false;
        if (prefix === "*" && suffix === "*") {
            if (sel.startsWith("**") && sel.endsWith("**") && !(sel.startsWith("***") && sel.endsWith("***")))
                return false;
        }
        return true;
    }

    function isWrapped(prefix, suffix): bool {
        if (!root.editor)
            return false;
        const te = root.editor.activeTextEdit;
        const full = te ? String(te.text ?? "") : "";
        const start = te ? te.selectionStart : root.editor.selectedStart;
        const end = te ? te.selectionEnd : root.editor.selectedEnd;
        if (start === end || full.length === 0)
            return false;
        const sMin = Math.min(start, end);
        const sMax = Math.max(start, end);
        const sel = full.slice(sMin, sMax);
        return root._hasExactMarkerAround(full, sMin, sMax, prefix, suffix)
            || root._hasExactMarkerInside(sel, prefix, suffix);
    }

    function toggleWrap(prefix, suffix): void {
        if (!root.editor)
            return;
        const te = root.editor.activeTextEdit;
        if (!te)
            return;
        const start = te.selectionStart !== te.selectionEnd ? te.selectionStart : root.editor.selectedStart;
        const end = te.selectionStart !== te.selectionEnd ? te.selectionEnd : root.editor.selectedEnd;
        if (start === end)
            return;
        const sMin = Math.min(start, end);
        const sMax = Math.max(start, end);
        const full = String(te.text ?? "");
        const sel = full.slice(sMin, sMax);
        if (sel.length === 0)
            return;

        root.formattingInProgress = true;
        let newText = full;
        let newStart = sMin;
        let newEnd = sMax;

        if (root._hasExactMarkerAround(full, sMin, sMax, prefix, suffix)) {
            if (prefix === "[") {
                const afterRest = full.slice(sMax);
                const match = afterRest.match(/^\]\([^)]*\)/);
                const suffixLen = match ? match[0].length : suffix.length;
                newText = full.slice(0, sMin - 1) + sel + full.slice(sMax + suffixLen);
                newStart = sMin - 1;
                newEnd = sMax - 1;
            } else {
                newText = full.slice(0, sMin - prefix.length) + sel + full.slice(sMax + suffix.length);
                newStart = sMin - prefix.length;
                newEnd = sMax - prefix.length;
            }
        } else if (root._hasExactMarkerInside(sel, prefix, suffix)) {
            if (prefix === "[") {
                const match = sel.match(/^\[([^\]]+)\]\([^)]*\)$/);
                const inner = match ? match[1] : sel;
                newText = full.slice(0, sMin) + inner + full.slice(sMax);
                newStart = sMin;
                newEnd = sMin + inner.length;
            } else {
                const inner = sel.slice(prefix.length, sel.length - suffix.length);
                newText = full.slice(0, sMin) + inner + full.slice(sMax);
                newStart = sMin;
                newEnd = sMin + inner.length;
            }
        } else {
            const wrapped = prefix + sel + suffix;
            newText = full.slice(0, sMin) + wrapped + full.slice(sMax);
            newStart = sMin + prefix.length;
            newEnd = sMax + prefix.length;
        }

        te.text = newText;
        te.forceActiveFocus();
        te.select(newStart, newEnd);
        if (root.editor.activeBlockId)
            root.editor.commitText(root.editor.activeBlockId, newText);
        root.editor.rememberSelection(te, root.editor.activeBlockId);
        root.formattingInProgress = false;
    }

    RowLayout {
        id: barRow
        anchors.centerIn: parent
        spacing: 2

        NotesIconButton {
            symbol: "format_bold"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Bold (**text**)")
            colIcon: root.isWrapped("**", "**") ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("**", "**")
        }

        NotesIconButton {
            symbol: "format_italic"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Italic (*text*)")
            colIcon: root.isWrapped("*", "*") ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("*", "*")
        }

        NotesIconButton {
            symbol: "format_strikethrough"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Strikethrough (~~text~~)")
            colIcon: root.isWrapped("~~", "~~") ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("~~", "~~")
        }

        NotesIconButton {
            symbol: "code"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Code, inline")
            colIcon: root.isWrapped("`", "`") ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("`", "`")
        }

        NotesIconButton {
            symbol: "link"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Link ([text](url))")
            colIcon: root.isWrapped("[", "](https://)") ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("[", "](https://)")
        }

        // Air, not a rule — the same decision as the formatting bar below it.
        Item {
            visible: root.policy !== 0
            Layout.preferredWidth: 10
        }

        // AI Assistant Action Button
        NotesIconButton {
            visible: root.policy !== 0
            symbol: "auto_awesome"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Ask AI about this")
            colIcon: Appearance.colors.colTertiary
            onTriggered: root.aiRequested()
        }
    }
}
