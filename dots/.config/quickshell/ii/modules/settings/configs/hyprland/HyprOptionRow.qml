pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One line of the option browser: the key, what it is set to, and - once opened - the editor.
 *
 * The editor is chosen by the type Hyprland declares for the key rather than by anything written
 * here, so a key added by a future release gets a working control the day it appears. That does
 * mean the controls are deliberately plain: nothing here knows that `input:follow_mouse` takes
 * 0 to 3, so it offers a number rather than four buttons pretending to know better. Where a key
 * does have a control that understands it, the row says which tab that is on instead of guessing.
 *
 * Only the switch sits in the closed row. Everything else needs a value typed and confirmed, and
 * every write costs a file write and a config reload, so it waits behind the disclosure.
 */
Item {
    id: root

    required property var entry
    property bool expanded: false
    /// True in a search, where a bare `size` would not say which of five sections it belongs to.
    property bool showSection: false

    signal toggled

    /**
     * Everything below reads the key through these two rather than through `entry`.
     *
     * A row can outlive its entry, or arrive before the catalogue has been read, and a key that
     * was set by an older Hyprland is not in the list at all - so `entry` being null is a normal
     * state and not a bug to be crashed on. One null reference here otherwise takes out every
     * binding on the row and both of the notes underneath it.
     */
    readonly property string optionKey: root.entry?.key ?? ""
    readonly property string kind: root.entry?.kind ?? "text"

    property var _memo: ({})

    /// One property per layer rather than resolve()'s bundle: the bundle was a fresh object on
    /// every change anywhere, and with the browser open that re-made every binding on three
    /// hundred rows per edit. Ownership never changes, "known" changes once; only the value moves.
    readonly property bool locked: HyprlandGui.shellOwned(root.optionKey) !== ""
    readonly property bool known: HyprlandGui.effective[root.optionKey] !== undefined
    readonly property bool isManaged: HyprlandGui.managedConfig.hasOwnProperty(root.optionKey)
    readonly property bool isShadowed: HyprlandGui.shadowed[root.optionKey] !== undefined
    readonly property string inheritedFile: String(HyprlandGui.inheritedConfig[root.optionKey]?.file ?? "")
    readonly property var current: HyprlandGui.displayValue(root.optionKey, undefined)
    readonly property string curatedTab: HyprlandCatalog.curatedIn(root.optionKey)

    /// The one-line summary on the right of the closed row.
    readonly property string valueText: {
        if (root.kind === "bool") return "";
        if (root.current !== undefined) return HyprlandCatalog.format(root.kind, root.current);
        return root.known ? "" : Translation.tr("not reported");
    }

    /// What the row says under the key, when there is anything worth saying.
    readonly property string badge: {
        if (root.locked) return Translation.tr("owned by the shell");
        if (root.isShadowed) return Translation.tr("overridden after load");
        if (root.isManaged) return Translation.tr("set from here");
        if (root.inheritedFile !== "")
            return Translation.tr("set in %1").arg(root.inheritedFile);
        return "";
    }

    readonly property string kindIcon: {
        const kind = root.kind;
        if (kind === "bool") return "toggle_on";
        if (kind === "int" || kind === "float") return "tag";
        if (kind === "color") return "palette";
        if (kind === "gradient") return "gradient";
        if (kind === "vec2") return "open_with";
        if (kind === "gaps") return "space_bar";
        return "text_fields";
    }

    /// The colours this key holds, if it holds any. A gradient has several. Kept by identity,
    /// or the row of swatches was torn down and rebuilt on every unrelated edit.
    readonly property var swatches: {
        let out = [];
        if (root.current !== undefined) {
            if (root.kind === "color") out = [HyprlandCatalog.colorParts(root.current).rgb];
            else if (root.kind === "gradient")
                out = HyprlandCatalog.gradientParts(root.current).colors.map(item => `#${item.slice(2)}`);
        }
        return ObjectUtils.keep(root._memo, "swatches", out);
    }

    implicitHeight: column.implicitHeight

    function write(value: var) {
        if (root.locked || root.optionKey === "" || value === undefined) return;
        HyprlandGui.setKey(root.optionKey, value);
    }

    /// Two numbers written together, because half a coordinate is not a value.
    function writePair(x: string, y: string) {
        const first = parseFloat(x);
        const second = parseFloat(y);
        if (isNaN(first) || isNaN(second)) return;
        const pair = Array.from(root.current ?? []);
        if (pair.length === 2 && pair[0] === first && pair[1] === second) return;
        root.write([first, second]);
    }

    /// Typed text as the value its key takes, or undefined when it is not one.
    function parse(text: string): var {
        const trimmed = String(text ?? "").trim();
        const kind = root.kind;
        if (kind === "int") {
            const number = parseInt(trimmed, 10);
            return isNaN(number) ? undefined : number;
        }
        if (kind === "float") {
            const number = parseFloat(trimmed);
            return isNaN(number) ? undefined : number;
        }
        if (kind === "gaps") return HyprlandCatalog.gapsValue(trimmed);
        if (kind === "color") {
            const hex = trimmed.replace(/^#/, "").replace(/^0x/i, "");
            if (/^[0-9a-fA-F]{8}$/.test(hex)) return `rgba(${hex})`;
            if (!/^[0-9a-fA-F]{6}$/.test(hex)) return trimmed === "" ? undefined : trimmed;
            // Only the six digits were typed, so the alpha that is already there is kept.
            return HyprlandCatalog.colorValue(hex, HyprlandCatalog.colorParts(root.current).alpha);
        }
        if (kind === "gradient") {
            const parsed = HyprlandCatalog.gradientParts(trimmed);
            const value = HyprlandCatalog.gradientValue(parsed.colors, parsed.angle);
            return value === "" ? undefined : value;
        }
        return trimmed;
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: 2

        RippleButton {
            id: header
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + 18
            buttonRadius: root.expanded ? Appearance.rounding.large : Appearance.rounding.small
            colBackground: root.expanded ? Appearance.colors.colSecondaryContainer
                : Appearance.colors.colLayer2
            colBackgroundHover: root.expanded ? Appearance.colors.colSecondaryContainerHover
                : Appearance.colors.colLayer2Hover
            colRipple: root.expanded ? Appearance.colors.colSecondaryContainerActive
                : Appearance.colors.colLayer2Active
            onClicked: root.toggled()

            contentItem: RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.kindIcon
                    iconSize: Appearance.font.pixelSize.large
                    color: root.locked ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                    opacity: root.locked ? 0.5 : 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.showSection ? root.optionKey : (root.entry?.path ?? "")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.monospace
                        color: root.expanded ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.badge !== ""
                        text: root.badge
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.locked ? Appearance.colors.colSubtext
                            : Appearance.colors.colPrimary
                    }
                }

                Row {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.swatches.length > 0
                    spacing: 3

                    Repeater {
                        model: root.swatches

                        delegate: Rectangle {
                            required property var modelData

                            width: 18
                            height: 18
                            radius: Appearance.rounding.verysmall
                            color: modelData
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.maximumWidth: 180
                    visible: root.valueText !== "" && root.swatches.length === 0
                    text: root.valueText
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                }

                StyledSwitch {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.kind === "bool"
                    enabled: !root.locked
                    // Not checkable on purpose. Left to itself a switch flips its own `checked`,
                    // which throws away the binding below, and it would then keep showing what it
                    // assumed even where the write was refused or the value came back different.
                    checkable: false
                    checked: root.current === true || root.current === 1
                    onClicked: root.write(!checked)
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "expand_more"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                    rotation: root.expanded ? 180 : 0

                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
                    }
                }
            }
        }

        // ── Opened ────────────────────────────────────────────────────────────
        Rectangle {
            id: editorCard
            Layout.fillWidth: true
            visible: root.expanded
            implicitHeight: visible ? editorColumn.implicitHeight + 26 : 0
            topLeftRadius: Appearance.rounding.verysmall
            topRightRadius: Appearance.rounding.verysmall
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: editorColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: 16
                    rightMargin: 16
                    topMargin: 13
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: root.optionKey
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: HyprlandCatalog.kindLabel(root.kind)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colPrimary
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: root.expanded && root.optionKey !== "" && root.kind !== "bool"
                        && !root.locked
                    visible: active
                    sourceComponent: root.kind === "vec2" ? pairEditor : singleEditor
                }
            }
        }

        HyprOptionNote {
            visible: root.expanded && (implicitHeight > 0)
            keys: root.expanded && root.optionKey !== "" ? [root.optionKey] : []
            notes: {
                if (!root.expanded) return [];
                const out = [];
                if (!root.known)
                    out.push({ "icon": "help", "text": Translation.tr("Hyprland will not report this one, so the value shown is only what has been written for it. Setting it still works.") });
                if (root.curatedTab === "input")
                    out.push({ "icon": "widgets", "text": Translation.tr("The Input tab has a control for this that knows what its values mean.") });
                if (root.curatedTab === "layout")
                    out.push({ "icon": "widgets", "text": Translation.tr("The Layout tab has a control for this that knows what its values mean.") });
                if (root.kind === "gradient")
                    out.push({ "icon": "info", "text": Translation.tr("Colours are written AARRGGBB, several of them make a gradient, and a trailing angle such as 45deg turns it. Hyprland prints them one way and reads them back another; the translation happens here.") });
                if (root.kind === "gaps")
                    out.push({ "icon": "info", "text": Translation.tr("One number for all four sides, or four in the order top, right, bottom, left.") });
                return out;
            }
        }
    }

    // ── Fields ────────────────────────────────────────────────────────────────
    /// Everything except a switch and a pair of numbers. Confirmed with Enter or by leaving the
    /// field, never per keystroke: each write reloads the compositor's config.
    Component {
        id: singleEditor

        MaterialTextField {
            id: field

            readonly property string incoming: {
                if (root.current === undefined) return "";
                if (root.kind === "color") return HyprlandCatalog.colorText(root.current);
                return String(root.current);
            }

            // MaterialTextField wraps by default, and a long value then fights its own width.
            wrapMode: TextInput.NoWrap
            placeholderText: HyprlandCatalog.kindLabel(root.kind)
            // Typing in a field that is being rewritten underneath is maddening, so an edit in
            // progress always wins over an incoming value.
            onIncomingChanged: {
                if (field.activeFocus) return;
                field.text = field.incoming;
            }
            onEditingFinished: {
                if (field.text === field.incoming) return;
                root.write(root.parse(field.text));
            }
            Component.onCompleted: field.text = field.incoming
        }
    }

    Component {
        id: pairEditor

        RowLayout {
            id: pairRow
            spacing: 8

            readonly property var pair: Array.from(root.current ?? [0, 0])

            MaterialTextField {
                id: xField
                Layout.fillWidth: true
                wrapMode: TextInput.NoWrap
                placeholderText: "x"
                validator: DoubleValidator {}
                onEditingFinished: root.writePair(xField.text, yField.text)
                Component.onCompleted: xField.text = String(pairRow.pair[0] ?? 0)
            }

            MaterialTextField {
                id: yField
                Layout.fillWidth: true
                wrapMode: TextInput.NoWrap
                placeholderText: "y"
                validator: DoubleValidator {}
                onEditingFinished: root.writePair(xField.text, yField.text)
                Component.onCompleted: yField.text = String(pairRow.pair[1] ?? 0)
            }
        }
    }
}
