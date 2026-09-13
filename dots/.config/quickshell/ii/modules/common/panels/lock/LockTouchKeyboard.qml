pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/**
 * The keyboard the lock screen draws for itself.
 *
 * A tablet has no other way in. The regular on-screen keyboard cannot help here: it is a
 * layer-shell surface, and the session lock protocol puts the lock surface above every
 * layer — that is the entire point of the protocol, not an oversight to work around. So a
 * touch-first family that locks its screen has no keyboard at all unless the lock surface
 * carries one, which is what this is.
 *
 * It types by assigning to `LockContext.currentText` rather than by synthesising key events
 * through ydotool, and that is deliberate. This is the unlock path: if it does not work the
 * device is a brick until a physical keyboard is found. ydotool needs a running daemon, a
 * writable uinput node and permissions that a locked session is exactly the wrong place to
 * discover are missing. Assigning a string needs none of those. It also means nothing this
 * keyboard types can escape the lock surface, because it never becomes an input event at
 * all.
 *
 * Three layers, the same three Android offers: letters, symbols, and a numeric pad for
 * people whose password is a PIN.
 */
Item {
    id: root

    required property LockContext context
    /// Whether the sheet is on screen. The host animates around this.
    property bool shown: false
    /// "text" (qwerty + symbols) or "pin" (numeric pad).
    property string mode: "text"

    /// The host unlocks; this only ever collects characters.
    signal submitRequested
    /// Asks the host to put the keyboard away. The lock screen's toolbar can bring it back,
    /// but a control on the far side of the screen is not where anyone looks for it — the
    /// way out of a keyboard is on the keyboard.
    signal collapseRequested

    // 0 = off, 1 = next character only, 2 = locked. Android's three states, on one key.
    property int shiftState: 0
    property bool symbolLayer: false

    readonly property bool numeric: root.mode === "pin"

    implicitHeight: handleStrip.height + root.keySpacing + keyGrid.implicitHeight
        + root.verticalPadding * 2

    // ── Metrics ─────────────────────────────────────────────────────────────
    // Keys are sized from the surface, so one layout serves a 10" tablet and a scaled 27"
    // panel. The floor is the touch target; nothing here may be smaller than a fingertip.
    readonly property real verticalPadding: Math.round(root.keySpacing * 1.5)
    readonly property real keySpacing: Math.max(5, Math.round(root.width * 0.004))
    readonly property real maxRowWidth: Math.min(root.width - root.keySpacing * 2,
                                                 root.numeric ? 520 : 1180)
    readonly property real unitWidth: {
        const columns = root.numeric ? 3 : 10;
        return (root.maxRowWidth - root.keySpacing * (columns - 1)) / columns;
    }
    readonly property real keyHeight: Math.max(Appearance.sizes.minimumTouchTarget,
                                               Math.min(root.numeric ? 84 : 68,
                                                        Math.round(root.unitWidth * (root.numeric ? 0.72 : 0.86))))

    // ── Layers ──────────────────────────────────────────────────────────────
    // `k` is what the key types. `act` marks a key that does something instead. `w` is the
    // key's width in units, defaulting to one.
    readonly property var letterRows: [
        [{ k: "q" }, { k: "w" }, { k: "e" }, { k: "r" }, { k: "t" }, { k: "y" }, { k: "u" }, { k: "i" }, { k: "o" }, { k: "p" }],
        [{ k: "a" }, { k: "s" }, { k: "d" }, { k: "f" }, { k: "g" }, { k: "h" }, { k: "j" }, { k: "k" }, { k: "l" }],
        [{ act: "shift", icon: "shift", w: 1.5 }, { k: "z" }, { k: "x" }, { k: "c" }, { k: "v" }, { k: "b" }, { k: "n" }, { k: "m" }, { act: "backspace", icon: "backspace", w: 1.5 }],
        [{ act: "layer", label: "?123", w: 1.5 }, { k: "," }, { act: "space", w: 4 }, { k: "." }, { act: "submit", icon: "keyboard_return", w: 1.5, accent: true }]
    ]

    readonly property var symbolRows: [
        [{ k: "1" }, { k: "2" }, { k: "3" }, { k: "4" }, { k: "5" }, { k: "6" }, { k: "7" }, { k: "8" }, { k: "9" }, { k: "0" }],
        [{ k: "@" }, { k: "#" }, { k: "$" }, { k: "%" }, { k: "&" }, { k: "-" }, { k: "_" }, { k: "+" }, { k: "(" }, { k: ")" }],
        [{ k: "*" }, { k: "\"" }, { k: "'" }, { k: ":" }, { k: ";" }, { k: "!" }, { k: "?" }, { k: "/" }, { k: "\\" }, { act: "backspace", icon: "backspace" }],
        [{ act: "layer", label: "ABC", w: 1.5 }, { k: "=" }, { act: "space", w: 4 }, { k: "~" }, { act: "submit", icon: "keyboard_return", w: 1.5, accent: true }]
    ]

    readonly property var pinRows: [
        [{ k: "1" }, { k: "2" }, { k: "3" }],
        [{ k: "4" }, { k: "5" }, { k: "6" }],
        [{ k: "7" }, { k: "8" }, { k: "9" }],
        [{ act: "backspace", icon: "backspace" }, { k: "0" }, { act: "submit", icon: "keyboard_return", accent: true }]
    ]

    readonly property var rows: root.numeric ? root.pinRows
        : (root.symbolLayer ? root.symbolRows : root.letterRows)

    // ── Typing ──────────────────────────────────────────────────────────────
    function type(character) {
        const shifted = root.shiftState > 0 && !root.symbolLayer && !root.numeric;
        root.context.currentText += shifted ? character.toUpperCase() : character;
        root.context.resetClearTimer();
        // A one-shot shift is spent by the character it capitalised; a locked one is not.
        if (root.shiftState === 1)
            root.shiftState = 0;
    }

    function backspace() {
        root.context.currentText = root.context.currentText.slice(0, -1);
        root.context.resetClearTimer();
    }

    function press(key) {
        switch (key.act ?? "") {
        case "":
            root.type(key.k);
            break;
        case "space":
            root.type(" ");
            break;
        case "backspace":
            root.backspace();
            break;
        case "shift":
            // Off → one shot → locked → off, which is the same key doing all three the way
            // Android does it. A separate caps key would cost a slot on a row that has none.
            root.shiftState = (root.shiftState + 1) % 3;
            break;
        case "layer":
            root.symbolLayer = !root.symbolLayer;
            root.shiftState = 0;
            break;
        case "submit":
            root.submitRequested();
            break;
        }
    }

    /// Reset the transient layer state so a reopened keyboard never starts mid-word.
    onShownChanged: {
        if (!root.shown) {
            root.shiftState = 0;
            root.symbolLayer = false;
        }
    }

    // A grab bar, in the place every sheet on a touch device puts one. Tapping it hides the
    // keyboard; it is also the only affordance saying the keyboard can be hidden at all.
    Item {
        id: handleStrip
        anchors.top: parent.top
        anchors.topMargin: root.verticalPadding
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.maxRowWidth
        height: 34

        RippleButton {
            id: collapseButton
            anchors.centerIn: parent
            implicitWidth: 96
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active

            onClicked: root.collapseRequested()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "keyboard_hide"
                iconSize: 18
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    ColumnLayout {
        id: keyGrid
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: handleStrip.bottom
        anchors.topMargin: root.keySpacing
        width: root.maxRowWidth
        spacing: root.keySpacing

        Repeater {
            model: root.rows

            delegate: RowLayout {
                id: keyRow
                required property var modelData
                Layout.alignment: Qt.AlignHCenter
                spacing: root.keySpacing

                Repeater {
                    model: keyRow.modelData

                    delegate: RippleButton {
                        id: key
                        required property var modelData

                        readonly property string keyAction: key.modelData.act ?? ""
                        readonly property bool isAccent: key.modelData.accent === true
                        readonly property bool isShiftKey: key.keyAction === "shift"
                        readonly property bool shiftEngaged: key.isShiftKey && root.shiftState > 0

                        Layout.preferredWidth: root.unitWidth * (key.modelData.w ?? 1)
                            + root.keySpacing * ((key.modelData.w ?? 1) - 1)
                        Layout.preferredHeight: root.keyHeight

                        buttonRadius: Appearance.rounding.small
                        toggled: key.isAccent || key.shiftEngaged

                        colBackground: key.keyAction === "" || key.keyAction === "space"
                            ? Appearance.colors.colLayer2
                            : Appearance.colors.colLayer1
                        colBackgroundToggled: key.isAccent
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSecondaryContainer

                        onClicked: root.press(key.modelData)

                        contentItem: Item {
                            // A glyph key and a symbol key are the same button with different
                            // insides, so both live here rather than in two delegates.
                            StyledText {
                                anchors.centerIn: parent
                                visible: key.modelData.icon === undefined
                                text: {
                                    const label = key.modelData.label ?? key.modelData.k ?? "";
                                    if (key.modelData.k === undefined)
                                        return label;
                                    return root.shiftState > 0 && !root.symbolLayer && !root.numeric
                                        ? label.toUpperCase() : label;
                                }
                                font.pixelSize: (key.modelData.label !== undefined)
                                    ? Appearance.font.pixelSize.small
                                    : Appearance.font.pixelSize.larger
                                color: key.toggled
                                    ? (key.isAccent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer)
                                    : Appearance.colors.colOnLayer1
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: key.modelData.icon !== undefined
                                text: {
                                    if (!key.isShiftKey)
                                        return key.modelData.icon ?? "";
                                    // The locked state has to look different from the one-shot
                                    // one, or the key that changes what the next tap types
                                    // gives no sign of which of its three states it is in.
                                    return root.shiftState === 2 ? "keyboard_capslock" : "shift";
                                }
                                iconSize: 22
                                fill: key.shiftEngaged ? 1 : 0
                                color: key.toggled
                                    ? (key.isAccent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer)
                                    : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }
}
