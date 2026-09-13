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

    signal aiRequested()

    readonly property bool hasActiveSelection: root.editor !== null && root.editor.hasSelection && root.editor.activeTextEdit !== null && root.editor.activeTextEdit.activeFocus
    readonly property rect selRect: root.editor ? root.editor.selectionGeometry : Qt.rect(0, 0, 0, 0)
    readonly property int policy: Number(Config.options?.policies?.ai ?? 1)

    visible: root.hasActiveSelection && root.selRect.width > 0
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

    function toggleWrap(prefix, suffix): void {
        if (!root.editor || !root.editor.activeTextEdit)
            return;
        const te = root.editor.activeTextEdit;
        const start = te.selectionStart;
        const end = te.selectionEnd;
        if (start === end)
            return;
        const sMin = Math.min(start, end);
        const sMax = Math.max(start, end);
        const full = te.text;
        const sel = te.selectedText;

        const before = full.slice(Math.max(0, sMin - prefix.length), sMin);
        const after = full.slice(sMax, sMax + suffix.length);

        if (before === prefix && after === suffix) {
            // Unwrap
            const newText = full.slice(0, sMin - prefix.length) + sel + full.slice(sMax + suffix.length);
            te.text = newText;
            te.select(sMin - prefix.length, sMax - prefix.length);
            if (root.editor.activeBlockId)
                root.editor.commitText(root.editor.activeBlockId, newText);
        } else {
            // Wrap
            const wrapped = prefix + sel + suffix;
            const newText = full.slice(0, sMin) + wrapped + full.slice(sMax);
            te.text = newText;
            te.select(sMin + prefix.length, sMax + prefix.length);
            if (root.editor.activeBlockId)
                root.editor.commitText(root.editor.activeBlockId, newText);
        }
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
            colIcon: Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("**", "**")
        }

        NotesIconButton {
            symbol: "format_italic"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Italic (*text*)")
            colIcon: Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("*", "*")
        }

        NotesIconButton {
            symbol: "format_strikethrough"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Strikethrough (~~text~~)")
            colIcon: Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("~~", "~~")
        }

        NotesIconButton {
            symbol: "code"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Code, inline")
            colIcon: Appearance.colors.colOnLayer1
            onTriggered: root.toggleWrap("`", "`")
        }

        NotesIconButton {
            symbol: "link"
            size: 32
            iconSize: 18
            tooltipText: Translation.tr("Link ([text](url))")
            colIcon: Appearance.colors.colOnLayer1
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
            tooltipText: Translation.tr("Ask AI on selection")
            colIcon: Appearance.colors.colTertiary
            onTriggered: root.aiRequested()
        }
    }
}
