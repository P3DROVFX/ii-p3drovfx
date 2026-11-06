pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Passwords popup content: type, pick, gone.
 *
 * Hover opens it with the login for the window behind it already selected;
 * click in (or open it from the keybind) and the search has the keyboard. Enter copies its password and closes;
 * the bar widget then shows the clipboard draining. Nothing else is on screen
 * unless asked for: usernames and actions appear only on the selected row,
 * and the list never shows more than a handful of logins.
 */
ColumnLayout {
    id: root

    property bool opened: false
    readonly property int contentWidth: 384
    readonly property int maxRows: 5
    readonly property int rowSpacing: 3
    // PasswordItemRow.rowHeight; every row is the same height.
    readonly property int stageHeight: root.maxRows * 54 + (root.maxRows - 1) * root.rowSpacing

    signal requestClose()

    // Holds the popup open only while the user is actually typing: a key in
    // the last moment. Focus alone is not enough — the search is focused on
    // every open, so "focused" held the popup open forever.
    readonly property bool typing: typingRecently.running
    Timer {
        id: typingRecently
        interval: 1500
    }
    function noteTyping(): void {
        typingRecently.restart();
    }

    property string query: ""
    property int selectedIndex: 0
    readonly property var rows: (PasswordManager.unlocked && root.opened)
        ? PasswordManager.results(root.query, root.maxRows)
        : []
    readonly property var selectedItem: root.rows.length > 0
        ? root.rows[Math.min(root.selectedIndex, root.rows.length - 1)]
        : null

    spacing: 0

    // The layout overrides a ColumnLayout's own implicitWidth; a child's
    // preferred width is what actually holds the popup open.
    Item {
        Layout.preferredWidth: root.contentWidth
        Layout.preferredHeight: 0
    }

    onQueryChanged: root.selectedIndex = 0
    onRowsChanged: if (root.selectedIndex >= root.rows.length) root.selectedIndex = 0
    onOpenedChanged: {
        if (root.opened) {
            root.query = "";
            searchInput.text = "";
            root.selectedIndex = 0;
            PasswordManager.clearError();
            PasswordManager.refresh();
            Qt.callLater(root.focusInput);
        }
    }

    function focusInput(): void {
        if (PasswordManager.unlocked)
            searchInput.forceActiveFocus();
        else
            gate.focusField();
    }

    Connections {
        target: PasswordManager
        function onStateChanged() {
            if (root.opened)
                Qt.callLater(root.focusInput);
        }
    }

    function run(kind: string, item): void {
        if (!item)
            return;
        if (kind === "type") {
            // Close first: the keyboard has to be back on the window by the time
            // wtype starts (the helper waits a quarter second for it).
            root.requestClose();
            PasswordManager.autoType(item, "login");
            return;
        }
        PasswordManager.copy(item, kind);
        root.requestClose();
    }

    function move(delta: int): void {
        if (root.rows.length === 0)
            return;
        root.selectedIndex = (root.selectedIndex + delta + root.rows.length) % root.rows.length;
    }

    component FieldAction: RippleButton {
        id: fieldAction
        required property string symbol
        required property string hint
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0)
        colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.08)
        colRipple: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.16)

        MaterialSymbol {
            anchors.centerIn: parent
            text: fieldAction.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledToolTip {
            text: fieldAction.hint
            requireOverlay: false
        }
    }

    component Hint: Row {
        id: hint
        required property var keys
        required property string label
        spacing: 5
        KeyHint {
            anchors.verticalCenter: parent.verticalCenter
            keys: hint.keys
            surface: Appearance.colors.colSurfaceContainer
            onSurface: Appearance.colors.colOnSurface
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    // ── Locked / signed out / missing ────────────────────────────────────────
    PasswordVaultGate {
        id: gate
        // Not fillWidth: a nested layout's maximum is its children's, and
        // without the password field nothing inside would stretch it.
        Layout.preferredWidth: root.contentWidth
        visible: !PasswordManager.unlocked
        contentWidth: root.contentWidth

        Keys.onEscapePressed: root.requestClose()
        onTypedKey: root.noteTyping()
    }

    // ── Search field ─────────────────────────────────────────────────────────
    Rectangle {
        id: searchField
        visible: PasswordManager.unlocked
        Layout.fillWidth: true
        implicitHeight: 56
        radius: height / 2
        color: Appearance.colors.colSurfaceContainerHighest

        MaterialShape {
            id: searchShape
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 40
            // Morph, never spin: idle circle, a burst once the user types.
            shapeString: root.query.length > 0 ? "Cookie9Sided" : "Circle"
            color: Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !PasswordManager.loadingItems && !PasswordManager.busy
                text: "key"
                iconSize: Appearance.font.pixelSize.larger
                fill: 1
                color: Appearance.colors.colOnPrimary
            }
            MaterialLoadingIndicator {
                anchors.centerIn: parent
                visible: PasswordManager.loadingItems || PasswordManager.busy
                loading: visible
                implicitSize: 30
                shapeColor: Appearance.colors.colOnPrimary
            }
        }

        StyledTextInput {
            id: searchInput
            anchors.left: searchShape.right
            anchors.leftMargin: 12
            anchors.right: fieldActions.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.normal
            clip: true
            onTextChanged: root.query = searchInput.text
            onTextEdited: root.noteTyping()

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: searchInput.text.length === 0
                text: Translation.tr("Search %1").arg(PasswordManager.providerName)
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }

            Keys.onPressed: event => {
                const ctrl = event.modifiers & Qt.ControlModifier;
                const shift = event.modifiers & Qt.ShiftModifier;
                switch (event.key) {
                case Qt.Key_Down:
                    root.move(1);
                    event.accepted = true;
                    return;
                case Qt.Key_Up:
                    root.move(-1);
                    event.accepted = true;
                    return;
                case Qt.Key_Tab:
                    root.move(shift ? -1 : 1);
                    event.accepted = true;
                    return;
                case Qt.Key_Backtab:
                    root.move(-1);
                    event.accepted = true;
                    return;
                case Qt.Key_Escape:
                    if (searchInput.text.length > 0)
                        searchInput.text = "";
                    else
                        root.requestClose();
                    event.accepted = true;
                    return;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (ctrl && PasswordManager.wtypeAvailable)
                        root.run("type", root.selectedItem);
                    else
                        root.run(shift ? "username" : "password", root.selectedItem);
                    event.accepted = true;
                    return;
                }
                if (ctrl && event.key === Qt.Key_T) {
                    root.run("totp", root.selectedItem);
                    event.accepted = true;
                } else if (ctrl && event.key === Qt.Key_L) {
                    PasswordManager.lock();
                    event.accepted = true;
                } else if (ctrl && event.key === Qt.Key_R) {
                    PasswordManager.sync();
                    event.accepted = true;
                }
            }
        }

        Row {
            id: fieldActions
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            FieldAction {
                symbol: "sync"
                hint: Translation.tr("Sync vault (Ctrl+R)")
                enabled: !PasswordManager.busy
                onClicked: PasswordManager.sync()
            }
            FieldAction {
                symbol: "lock"
                hint: Translation.tr("Lock (Ctrl+L)")
                visible: PasswordManager.provider !== "pass"
                onClicked: PasswordManager.lock()
            }
        }
    }

    // ── Results ──────────────────────────────────────────────────────────────
    // A stage of fixed height: what is listed changes as you type, the popup
    // does not. A popup that resized per keystroke shook (its own height
    // animation on top of the rows'), and shrank out from under the pointer,
    // which closed it. One selected row + the rest at rest always fit.
    Item {
        id: stage
        visible: PasswordManager.unlocked
        Layout.fillWidth: true
        Layout.topMargin: 10
        implicitHeight: root.stageHeight

        Column {
            id: list
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: root.rowSpacing

            // A fixed set of rows written by position: typing changes what each
            // row shows instead of rebuilding rows (and their shape canvases).
            Repeater {
                model: root.maxRows
                delegate: PasswordItemRow {
                    required property int index
                    readonly property var entry: index < root.rows.length ? root.rows[index] : null
                    width: list.width
                    visible: entry !== null
                    item: entry
                    selected: index === root.selectedIndex
                    isFirst: index === 0
                    isLast: index === Math.min(root.rows.length, root.maxRows) - 1
                    prevSelected: index - 1 === root.selectedIndex
                    nextSelected: index + 1 === root.selectedIndex
                    suggested: entry !== null && PasswordManager.suggestion !== null && PasswordManager.suggestion.id === entry.id
                    canType: PasswordManager.wtypeAvailable
                    onHoveredRow: root.selectedIndex = index
                    onActivated: root.run("password", entry)
                    onAction: kind => root.run(kind, entry)
                }
            }
        }

        // Nothing to list: the vault's size, big and condensed, and a nudge.
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width
            visible: root.rows.length === 0
            spacing: 0

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.query.length === 0 && !PasswordManager.loadingItems
                text: String(PasswordManager.items.length)
                font.family: Appearance.font.family.main
                font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                font.pixelSize: 64
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: root.contentWidth - 32
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: PasswordManager.loadingItems
                    ? Translation.tr("Opening vault…")
                    : root.query.length > 0
                        ? Translation.tr("Nothing matches “%1”").arg(root.query)
                        : (PasswordManager.items.length === 1 ? Translation.tr("login — type to find it") : Translation.tr("logins — type to find one"))
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ── Keys, said once and quietly ──────────────────────────────────────────
    Row {
        // Faded, never removed: removing it would change the popup's height.
        visible: PasswordManager.unlocked
        opacity: root.rows.length > 0 ? 1 : 0
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 10
        spacing: 14

        Hint { keys: ["↵"]; label: Translation.tr("Password") }
        Hint { keys: ["⇧", "↵"]; label: Translation.tr("User") }
        Hint { keys: ["Ctrl", "T"]; label: Translation.tr("2FA") }
        Hint {
            visible: PasswordManager.wtypeAvailable
            keys: ["Ctrl", "↵"]
            label: Translation.tr("Type")
        }
    }
}
