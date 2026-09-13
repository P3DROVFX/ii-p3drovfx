import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * One key of the deck keyboard.
 *
 * The classic OskKey stays as it is; this is its counterpart for the deck layout data in
 * layouts.js. It differs in three ways: its width comes from the layout's unit grid rather than
 * a shape name, it shows the glyph of whichever level the latched modifiers select, and it never
 * holds a key down - every tap goes through Ydotool.tapKey as a single atomic event burst.
 */
RippleButton {
    id: root

    property var keyData
    property real unitWidth: 40 // Pixels per layout unit, handed down by the row
    property bool active: false // Lets the parent light up an action key (Pin, ...)

    readonly property string role: keyData?.role ?? "key"
    readonly property int keycode: keyData?.code ?? -1
    readonly property bool isModifier: root.role === "mod"

    readonly property int shiftKeycode: 42
    readonly property int altGrKeycode: 100

    // Which glyph level the latched modifiers select. AltGr wins over Shift: the layouts carry no
    // fourth level, so there is nothing to show for the two of them together.
    readonly property int level: {
        const latched = Ydotool.latched;
        if ((latched[root.altGrKeycode] ?? Ydotool.latchOff) !== Ydotool.latchOff) return 2;
        if ((latched[root.shiftKeycode] ?? Ydotool.latchOff) !== Ydotool.latchOff) return 1;
        return 0;
    }

    readonly property string baseGlyph: keyData?.base ?? ""
    readonly property string shiftGlyph: keyData?.shift ?? ""
    readonly property string altGrGlyph: keyData?.altgr ?? ""

    readonly property string mainLabel: {
        // The space bar wears the layout code instead of the word "Space"; tapping it still types a space.
        if (root.role === "space") return keyData?.badge ?? keyData?.label ?? "";
        if (root.role !== "key") return keyData?.label ?? "";
        if (root.level === 2) return root.altGrGlyph || root.baseGlyph;
        if (root.level === 1) return root.shiftGlyph || root.baseGlyph;
        return root.baseGlyph;
    }

    // A letter's shift glyph is just its capital, so printing it in the corner says nothing. Only
    // keys whose second level is a different character earn a corner legend - and only if the user
    // wants the corners at all, since a plain deck reads more easily on a small screen.
    readonly property bool showsSecondaryGlyphs: Config.options?.osk.secondaryGlyphs ?? true
    readonly property bool showsShiftLegend: root.showsSecondaryGlyphs && root.role === "key" && root.shiftGlyph !== ""
        && root.shiftGlyph !== root.baseGlyph.toUpperCase() && root.level === 0
    readonly property bool showsAltGrLegend: root.showsSecondaryGlyphs && root.role === "key"
        && root.altGrGlyph !== "" && root.level !== 2

    readonly property int latchState: root.isModifier ? (Ydotool.latched[root.keycode] ?? Ydotool.latchOff) : Ydotool.latchOff
    readonly property bool locked: root.latchState === Ydotool.latchLocked

    signal actionTriggered(string action)

    // The unit grid decides the width outright, so the layout must not fall back to the implicit
    // one. Everything the key draws lives inside contentItem, hence no padding of its own.
    Layout.preferredWidth: (keyData?.u ?? 1) * root.unitWidth
    Layout.fillHeight: true
    Layout.minimumWidth: 0
    Layout.minimumHeight: 0
    padding: 0

    toggled: root.isModifier ? (root.latchState !== Ydotool.latchOff) : root.active
    buttonRadius: Appearance.rounding.small
    colBackground: root.role === "key" ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    colBackgroundToggled: root.locked ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
    colBackgroundToggledHover: root.locked ? Appearance.colors.colTertiaryHover : Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: root.locked ? Appearance.colors.colTertiaryActive : Appearance.colors.colPrimaryActive

    readonly property color colForeground: {
        if (!root.toggled) return root.role === "key" ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnLayer1;
        return root.locked ? Appearance.colors.colOnTertiary : Appearance.colors.colOnPrimary;
    }

    downAction: () => {
        if (root.role === "action") {
            root.actionTriggered(root.keyData.action);
            return;
        }
        if (root.isModifier) {
            Ydotool.toggleLatch(root.keycode);
            return;
        }
        Ydotool.tapKey(root.keycode);
    }

    contentItem: Item {
        StyledText {
            id: mainText
            anchors.centerIn: parent
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            color: root.colForeground
            elide: Text.ElideRight
            font.pixelSize: root.role === "key" ? Math.max(11, Math.round(root.unitWidth * 0.40)) : Math.max(9, Math.round(root.unitWidth * 0.27))
            text: root.mainLabel

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            id: shiftLegend
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Math.round(root.unitWidth * 0.08)
            visible: root.showsShiftLegend
            color: ColorUtils.transparentize(root.colForeground, 0.4)
            font.pixelSize: Math.max(8, Math.round(root.unitWidth * 0.22))
            text: root.shiftGlyph
        }

        StyledText {
            id: altGrLegend
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: Math.round(root.unitWidth * 0.08)
            visible: root.showsAltGrLegend
            color: ColorUtils.transparentize(root.colForeground, 0.55)
            font.pixelSize: Math.max(8, Math.round(root.unitWidth * 0.22))
            text: root.altGrGlyph
        }

        // A locked modifier is already tinted; the bar tells it apart from a one-shot at a glance.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.locked
            width: Math.round(root.width * 0.4)
            height: 2
            radius: height / 2
            color: root.colForeground
        }
    }
}
