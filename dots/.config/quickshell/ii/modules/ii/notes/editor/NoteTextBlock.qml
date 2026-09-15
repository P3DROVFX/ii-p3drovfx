import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * Every block you can type in: paragraph, heading, list item, quote, callout.
 *
 * One delegate for all five because they differ in what is drawn *beside* the text — a
 * bullet, a number, a checkbox, a bar, an icon — and in its size and weight, not in how it
 * behaves. Five nearly identical files would drift apart on the first change to key
 * handling, and key handling is the part that has to be identical.
 *
 * The text belongs to this item while it is being typed in. It is reported upwards on a
 * debounce and the editor writes it, but the editor never writes it back: a model that
 * updated per keystroke would rebuild this delegate and drop the caret to the start of the
 * line on every character.
 */
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    readonly property string blockType: root.block ? root.block.type : "text"
    readonly property int indent: root.block && root.block.indent !== undefined ? root.block.indent : 0
    readonly property bool isList: root.blockType === "list"
    readonly property bool isChecked: root.isList && root.block.checked === true
    property bool isPromoted: false

    HoverHandler {
        id: blockHover
    }

    /// Rhythm unit from NotesMetrics (28px).
    readonly property int paperLineHeight: NotesMetrics.paperLineHeight
    readonly property bool isMajorHeading: root.blockType === "heading" && root.block && (root.block.level === 1 || root.block.level === 2)
    readonly property int targetLines: root.blockType === "callout" ? 2 : (root.isMajorHeading ? 2 : 1)
    readonly property int minHeight: root.targetLines * root.paperLineHeight

    implicitHeight: {
        const raw = Math.max(row.implicitHeight, editText.implicitHeight) + (root.blockType === "callout" ? 24 : root.isMajorHeading ? 20 : 6);
        return Math.max(root.minHeight, Math.ceil(raw / root.paperLineHeight) * root.paperLineHeight);
    }

    /// A callout carries a container, and a container needs room to sit in.
    readonly property int verticalPadding: root.blockType === "heading" ? 10
        : root.blockType === "callout" ? 12
        : 4
    readonly property int indentStep: 26

    readonly property int textSize: {
        if (root.blockType !== "heading")
            return Appearance.font.pixelSize.normal;
        if (root.block.level === 1)
            return Appearance.font.pixelSize.huge;
        return root.block.level === 2 ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.large;
    }

    /**
     * Whether this line has markdown in it worth drawing.
     *
     * Only these blocks get the rendered twin below; everything else stays on exactly the
     * path it was on, which keeps the common case — a plain sentence — pixel for pixel
     * what it was.
     */
    readonly property bool hasMarkup: {
        const text = root.block ? String(root.block.text ?? "") : "";
        if (text.length === 0)
            return false;
        return /(\*\*|__|[*_`~]|\[[^\]]*\]\()/.test(text);
    }

    /// Source while the caret is in it, drawn when it is not.
    readonly property bool rendered: root.hasMarkup && !editText.activeFocus

    /**
     * The four tones, as Material container pairs.
     *
     * They used to differ only in the colour of the sentence, which on this palette meant
     * three barely distinguishable pinks and one red: an "information" callout and a
     * "warning" callout looked like the same thing said twice. A tinted container is what
     * the tone is *for*.
     */
    readonly property color toneColor: {
        if (root.blockType !== "callout")
            return Appearance.colors.colOnLayer0;
        switch (root.block.tone) {
        case "success": return Appearance.m3colors.m3onPrimaryContainer;
        case "warning": return Appearance.m3colors.m3onTertiaryContainer;
        case "error": return Appearance.m3colors.m3onErrorContainer;
        default: return Appearance.m3colors.m3onSecondaryContainer;
        }
    }

    readonly property color toneBackground: {
        switch (root.block && root.blockType === "callout" ? root.block.tone : "") {
        case "success": return Appearance.colors.colPrimaryContainer;
        case "warning": return Appearance.colors.colTertiaryContainer;
        case "error": return Appearance.colors.colErrorContainer;
        default: return Appearance.colors.colSecondaryContainer;
        }
    }

    /// Which number this item shows. Counted from the items above it at the same level,
    /// because the document stores a list style rather than a running number — renumbering
    /// stored values on every insert is how numbered lists get out of step with themselves.
    readonly property int ordinal: {
        if (!root.isList || root.block.style !== "number" || !root.editor)
            return 1;
        let n = 1;
        for (let i = root.blockIndex - 1; i >= 0; i--) {
            const above = root.editor.blockAt(i);
            if (!above || above.type !== "list" || above.indent !== root.indent)
                break;
            if (above.style !== "number")
                break;
            n++;
        }
        return n;
    }

    // ── Focus ─────────────────────────────────────────────────────────────

    function takeFocus(caret): void {
        if (!root.editor || !root.block)
            return;
        editText.forceActiveFocus();
        editText.cursorPosition = caret < 0 ? editText.length : Math.min(caret, editText.length);
        // Only now is the request spent. Clearing it before the caret was actually here
        // let a delegate that was about to be rebuilt swallow it.
        if (editText.activeFocus)
            root.editor.clearFocusRequest(root.block.id);
    }

    function checkFocusRequest(): void {
        if (!root.editor || !root.block)
            return;
        const caret = root.editor.peekFocus(root.block.id);
        if (caret === -2)
            return;
        // Deferred, and this delegate may not live long enough to answer: a list that
        // rebuilds while a focus request is in flight destroys the row it was meant for,
        // and a destroyed QML object reads as `null` from the closure that captured it —
        // which is what "cannot read property 'takeFocus' of null" was, once per rebuild.
        Qt.callLater(() => {
            if (root)
                root.takeFocus(caret);
        });
    }

    Connections {
        target: root.editor
        function onFocusRequestChanged() {
            root.checkFocusRequest();
        }
        function onFocusTickChanged() {
            root.checkFocusRequest();
        }
    }

    Component.onCompleted: root.checkFocusRequest()

    /// The container behind a callout, and nothing at all behind everything else.
    Rectangle {
        anchors.fill: row
        anchors.margins: -8
        anchors.leftMargin: -12
        anchors.rightMargin: -12
        visible: root.blockType === "callout"
        radius: Appearance.rounding.normal
        color: root.toneBackground
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: (root.blockType === "callout" || root.isMajorHeading)
            ? undefined
            : parent.top
        anchors.verticalCenter: root.blockType === "callout"
            ? parent.verticalCenter
            : undefined
        anchors.bottom: root.isMajorHeading
            ? parent.bottom
            : undefined
        anchors.bottomMargin: root.isMajorHeading ? 1 : 0
        anchors.topMargin: (root.blockType === "callout" || root.isMajorHeading) ? 0 : 4
        anchors.leftMargin: NotesMetrics.readingPadding + root.indent * root.indentStep
        anchors.rightMargin: NotesMetrics.readingPadding
        spacing: 10

        // ── What sits beside the text ─────────────────────────────────────

        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: root.isList || root.blockType === "callout" ? 24 : 0
            Layout.preferredHeight: 21
            visible: Layout.preferredWidth > 0

            // Bullet
            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: Appearance.colors.colOnLayer1
                visible: root.isList && root.block.style === "bullet"
            }

            // Number
            StyledText {
                anchors.centerIn: parent
                text: root.ordinal + "."
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                visible: root.isList && root.block.style === "number"
            }

            // Checkbox
            Rectangle {
                anchors.centerIn: parent
                width: 19
                height: 19
                radius: Appearance.rounding.verysmall
                visible: root.isList && root.block.style === "checkbox"
                color: root.isChecked ? Appearance.colors.colPrimary : "transparent"
                border.width: root.isChecked ? 0 : 2
                border.color: Appearance.colors.colOnLayer1Inactive

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "check"
                    iconSize: 15
                    color: Appearance.colors.colOnPrimary
                    opacity: root.isChecked ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editor.toggleChecked(root.block.id)
                }
            }

            // Callout icon
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.blockType === "callout"
                text: {
                    switch (root.block.tone) {
                    case "success": return "check_circle";
                    case "warning": return "warning";
                    case "error": return "error";
                    default: return "info";
                    }
                }
                iconSize: 20
                color: root.toneColor
            }
        }

        // The quote's bar. A shape rather than an icon: a quotation is a run of text set
        // aside, and the bar is what says how far it runs.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: root.blockType === "quote" ? 3 : 0
            Layout.preferredHeight: textCell.implicitHeight
            radius: 2
            color: Appearance.colors.colPrimary
            visible: root.blockType === "quote"
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.maximumWidth: NotesMetrics.readingWidth
            spacing: 6

            /**
             * The line, twice: the editor you type in, and the markdown it means.
             *
             * Two items rather than flipping `textFormat` on the one. A `TextEdit` told to
             * change format re-parses its document, and the plain serialisation of a
             * parsed markdown document has lost its markers — one careless commit after
             * that and `**bold**` is gone from the file. Nothing here ever re-parses: the
             * editor keeps the source, the label draws it, and the editor is still the
             * item under the pointer, so a click lands where it always did.
             */
            Item {
                id: textCell
                Layout.fillWidth: true
                implicitHeight: root.rendered
                    ? Math.max(renderedText.implicitHeight, 1)
                    : editText.implicitHeight

            TextEdit {
                id: editText
                width: textCell.width

                text: root.block ? root.block.text : ""
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.PlainText
                renderType: Text.NativeRendering

                color: root.blockType === "callout" ? root.toneColor
                    : root.blockType === "quote" ? Appearance.colors.colOnLayer1
                    : Appearance.colors.colOnLayer0
                // Invisible while the twin below is drawing, but still the item under the
                // pointer: opacity does not take an item out of the input chain, so a
                // click on rendered markdown still lands in the editor and shows the
                // source it came from.
                opacity: root.rendered ? 0 : (root.isChecked ? 0.55 : 1)
                font {
                    family: Appearance.font.family.main
                    pixelSize: root.textSize
                    weight: root.blockType === "heading" ? Font.DemiBold : Font.Normal
                    italic: root.blockType === "quote"
                    strikeout: root.isChecked
                }
                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer

                // The placeholder only ever appears on the block the caret is in: a page of
                // "Write something…" under every empty line would be noise.
                StyledText {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: root.blockType === "heading"
                        ? Translation.tr("Heading")
                        : Translation.tr("Write something…")
                    font: editText.font
                    color: Appearance.colors.colOnLayer1Inactive
                    visible: editText.length === 0 && editText.activeFocus
                }

                onActiveFocusChanged: {
                    if (activeFocus) {
                        root.editor.activeBlockId = root.block.id;
                        root.editor.activeTextEdit = editText;
                        root.checkUrlAndWikilink();
                    } else {
                        if (root.editor && root.editor.activeTextEdit === editText)
                            root.editor.activeTextEdit = null;
                        // Leaving the block commits whatever the debounce was still holding.
                        saveDebounce.stop();
                        root.commit();
                        root.wikilinkActive = false;
                    }
                }

                onCursorPositionChanged: {
                    if (activeFocus && !root.applying)
                        root.checkUrlAndWikilink();
                }

                onTextChanged: {
                    // Only what was typed. A change while the caret is elsewhere is the
                    // model syncing in, and committing that writes a round-trip back over
                    // the source.
                    if (root.applying || !editText.activeFocus)
                        return;
                    root.checkUrlAndWikilink();
                    root.applying = true;
                    const converted = root.editor.tryShortcut(root.block.id, editText.text);
                    if (converted !== null && converted !== undefined) {
                        saveDebounce.stop();
                        editText.text = converted;
                        editText.cursorPosition = editText.length;
                        root.endApplying();
                        return;
                    }
                    root.applying = false;
                    saveDebounce.restart();
                }

                Keys.onPressed: event => root.handleKey(event)
            }

                StyledText {
                    id: renderedText
                    width: textCell.width
                    visible: root.rendered
                    text: root.block ? root.block.text : ""
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    color: editText.color
                    opacity: root.isChecked ? 0.55 : 1
                    font: editText.font
                    lineHeight: root.paperLineHeight
                    lineHeightMode: Text.FixedHeight
                    // Set, and ignored: `linkColor` applies to the StyledText format and
                    // markdown becomes rich text, which takes its link colour from Qt.
                    // Measured — a link here draws in Qt's blue, not the theme's primary.
                    // Left in place because it costs nothing the day that changes.
                    linkColor: Appearance.colors.colPrimary
                }
            }

            // ── Discrete URL preview conversion chip ──────────────────────────
            RowLayout {
                visible: root.detectedUrl.length > 0 && editText.activeFocus
                spacing: 8

                RippleButton {
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    leftPadding: 10
                    rightPadding: 10
                    contentItem: RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            text: "web"
                            iconSize: 15
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                        StyledText {
                            text: Translation.tr("Convert to preview card")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                    }
                    onClicked: {
                        const targetUrl = root.detectedUrl;
                        root.detectedUrl = "";
                        root.editor.setType(root.block.id, "linkPreview", { url: targetUrl });
                    }
                }

                RippleButton {
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    leftPadding: 8
                    rightPadding: 8
                    contentItem: StyledText {
                        text: Translation.tr("Keep as link")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    onClicked: root.detectedUrl = ""
                }
            }

            // ── Active Wikilink under cursor affordance ────────────────────────
            RowLayout {
                visible: root.activeWikilinkTarget.length > 0 && editText.activeFocus
                spacing: 6

                RippleButton {
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    leftPadding: 8
                    rightPadding: 8
                    contentItem: RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            text: "open_in_new"
                            iconSize: 14
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Open: %1").arg(root.activeWikilinkTarget)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colPrimary
                        }
                    }
                    onClicked: root.openWikilink(root.activeWikilinkTarget)
                }
            }

            // ── Wikilink Autocompletion popup ─────────────────────────────────
            Rectangle {
                Layout.preferredWidth: Math.min(320, parent.width)
                Layout.preferredHeight: wikilinkList.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surfaceContainerHigh
                visible: root.wikilinkActive && root.wikilinkSuggestions.length > 0
                clip: true

                ColumnLayout {
                    id: wikilinkList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 4
                    spacing: 2

                    Repeater {
                        model: root.wikilinkSuggestions

                        RippleButton {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            leftPadding: 8
                            rightPadding: 8

                            contentItem: RowLayout {
                                spacing: 6
                                MaterialSymbol {
                                    text: "article"
                                    iconSize: 15
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.title.length > 0 ? modelData.title : Translation.tr("Untitled note")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer0
                                    elide: Text.ElideRight
                                }
                            }
                            onClicked: root.insertWikilink(modelData.title)
                        }
                    }
                }
            }
        }

        NotesIconButton {
            Layout.alignment: Qt.AlignTop
            visible: root.isList && root.block.style === "checkbox" && editText.text.trim().length > 0 && (blockHover.hovered || root.isPromoted)
            symbol: root.isPromoted ? "check_circle" : "assignment_turned_in"
            size: 26
            iconSize: 15
            colIcon: root.isPromoted ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            tooltipText: root.isPromoted ? Translation.tr("Added to tasks") : Translation.tr("Promote to Todo task")
            onTriggered: {
                Todo.addItem({ content: editText.text.trim(), done: root.isChecked });
                root.isPromoted = true;
            }
        }
    }

    property string detectedUrl: ""
    property string wikilinkQuery: ""
    property bool wikilinkActive: false

    function checkUrlAndWikilink(): void {
        const txt = editText.text.trim();
        // Standalone URL check: only if the block is solely a URL
        if (/^https?:\/\/[^\s]+$/i.test(txt)) {
            root.detectedUrl = txt;
        } else {
            root.detectedUrl = "";
        }

        // Wikilink check
        const before = editText.text.slice(0, editText.cursorPosition);
        const openIdx = before.lastIndexOf("[[");
        if (openIdx !== -1) {
            const afterOpen = before.slice(openIdx + 2);
            if (afterOpen.indexOf("]") === -1 && afterOpen.indexOf("\n") === -1) {
                root.wikilinkQuery = afterOpen.toLowerCase();
                root.wikilinkActive = true;
                return;
            }
        }
        root.wikilinkActive = false;
    }

    readonly property var wikilinkSuggestions: {
        if (!root.wikilinkActive || !root.editor)
            return [];
        const currentId = root.editor.noteId;
        const q = root.wikilinkQuery;
        return NotesService.notes.filter(n => n.id !== currentId && (q.length === 0 || n.title.toLowerCase().includes(q))).slice(0, 5);
    }

    readonly property string activeWikilinkTarget: {
        if (!editText.activeFocus)
            return "";
        const txt = editText.text;
        const pos = editText.cursorPosition;
        const openIdx = txt.lastIndexOf("[[", Math.max(0, pos - 1));
        if (openIdx === -1)
            return "";
        const closeIdx = txt.indexOf("]]", openIdx);
        if (closeIdx === -1 || pos > closeIdx + 2)
            return "";
        return txt.slice(openIdx + 2, closeIdx).split("|")[0].trim();
    }

    function insertWikilink(targetTitle): void {
        const before = editText.text.slice(0, editText.cursorPosition);
        const openIdx = before.lastIndexOf("[[");
        if (openIdx === -1)
            return;
        const after = editText.text.slice(editText.cursorPosition);
        const replacement = `[[${targetTitle}]] `;
        root.applying = true;
        editText.text = before.slice(0, openIdx) + replacement + after;
        editText.cursorPosition = openIdx + replacement.length;
        root.wikilinkActive = false;
        root.endApplying();
        saveDebounce.restart();
    }

    function openWikilink(target): void {
        const norm = String(target).toLowerCase();
        const found = NotesService.notes.find(n => n.title.toLowerCase() === norm || n.id === target);
        if (found) {
            Persistent.states.notes.noteId = found.id;
        }
    }

    /**
     * True while this delegate is writing its own text, and for a moment afterwards.
     *
     * Two things depend on it. The assignment must not come back through `onTextChanged`
     * as if somebody had typed it. And nothing may *commit* during that window — which is
     * the subtler one: a markdown conversion replaces the block, the delegate loses focus
     * as it is rebuilt, and the focus-out handler would then save the text as it was
     * before the conversion. That is how "- " ended up stored as the content of a bullet
     * whose prefix had already been taken away.
     */
    property bool applying: false

    /// True while this block is the one waiting to hear what the clipboard held.
    property bool pasteTarget: false

    Connections {
        target: root.editor
        enabled: root.pasteTarget
        function onPasteFellThrough() {
            root.pasteTarget = false;
            // No image in the clipboard, so this is an ordinary paste after all — done
            // here rather than by the key handler, which could not have known yet.
            if (editText.activeFocus)
                editText.paste();
        }
    }

    function endApplying(): void {
        // Same guard as the focus request above: the delegate can be gone by the time this
        // runs, and writing a property on a destroyed object throws.
        Qt.callLater(() => {
            if (root)
                root.applying = false;
        });
    }

    function commit(): void {
        if (root.applying || !root.block || !root.editor)
            return;
        if (editText.text === root.block.text)
            return;
        root.editor.commitText(root.block.id, editText.text);
    }

    Timer {
        id: saveDebounce
        // Short. The store debounces the disk write of its own; this one only decides how
        // often the document in memory is told, which is also how coarse undo is.
        interval: 400
        onTriggered: root.commit()
    }

    function handleKey(event): void {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        if (ctrl && event.key === Qt.Key_Z) {
            saveDebounce.stop();
            root.commit();
            if (shift)
                root.editor.redo();
            else
                root.editor.undo();
            event.accepted = true;
            return;
        }

        if (ctrl && event.key === Qt.Key_V && !shift) {
            // Handed over rather than decided here: what the clipboard holds can only be
            // learned from a subprocess. If it turns out not to be an image the editor
            // says so and the text paste happens then.
            root.pasteTarget = true;
            root.editor.pasteFromClipboard();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (shift)
                return; // A soft break inside the block.
            saveDebounce.stop();
            root.editor.splitAt(root.block.id, editText.cursorPosition, editText.text);
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            saveDebounce.stop();
            root.commit();
            root.editor.indent(root.block.id, (shift || event.key === Qt.Key_Backtab) ? -1 : 1);
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Backspace
            && editText.cursorPosition === 0
            && editText.selectionStart === editText.selectionEnd) {
            saveDebounce.stop();
            root.editor.mergeInto(root.block.id, editText.text);
            event.accepted = true;
            return;
        }

        // Up on the first line and down on the last walk to the next block, so the whole
        // note is reachable without touching the mouse.
        if (event.key === Qt.Key_Up && editText.cursorPosition <= editText.text.indexOf("\n") + 1
            && !editText.text.slice(0, editText.cursorPosition).includes("\n")) {
            saveDebounce.stop();
            root.commit();
            root.editor.moveFocus(root.block.id, -1);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Down
            && !editText.text.slice(editText.cursorPosition).includes("\n")) {
            saveDebounce.stop();
            root.commit();
            root.editor.moveFocus(root.block.id, 1);
            event.accepted = true;
        }
    }
}
