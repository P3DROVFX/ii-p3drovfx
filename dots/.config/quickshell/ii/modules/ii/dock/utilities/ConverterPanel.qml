import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "UnitConverter.js" as Units

/**
 * Two fields, one per unit: typing in either converts into the other. The
 * category chips sit on top, each side picks its unit from chips, and the
 * swap button turns the pair around.
 */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property string categoryId: panel.tile?.categoryId ?? "length"
    readonly property var units: Units.category(panel.categoryId).units

    spacing: 8

    // Rewrites the other field without echoing back into this one.
    property bool _syncing: false
    function fromEdited(text) {
        if (panel._syncing || !panel.tile)
            return;
        const value = Units.parse(text);
        if (!isFinite(value))
            return;
        panel.tile.input = value;
        panel._syncing = true;
        toField.text = Units.format(panel.tile.output);
        panel._syncing = false;
    }
    function toEdited(text) {
        if (panel._syncing || !panel.tile)
            return;
        const value = Units.parse(text);
        if (!isFinite(value))
            return;
        panel.tile.input = Units.convert(value, panel.categoryId, panel.tile.toId, panel.tile.fromId);
        panel._syncing = true;
        fromField.text = Units.format(panel.tile.input);
        panel._syncing = false;
    }
    function refresh() {
        if (!panel.tile)
            return;
        panel._syncing = true;
        fromField.text = Units.format(panel.tile.input);
        toField.text = Units.format(panel.tile.output);
        panel._syncing = false;
    }
    onTileChanged: panel.refresh()
    Component.onCompleted: {
        panel.refresh();
        fromField.focusInput();
    }
    Connections {
        target: panel.tile
        function onFromIdChanged() { panel.refresh(); }
        function onToIdChanged() { panel.refresh(); }
        function onCategoryIdChanged() { panel.refresh(); }
    }

    // ── Category: icon segments; the chosen one widens to show its name ──
    RowLayout {
        Layout.fillWidth: true
        spacing: 3
        Repeater {
            model: Units.categories
            delegate: RippleButton {
                id: segment
                required property var modelData
                required property int index
                readonly property bool chosen: panel.categoryId === segment.modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: segment.chosen ? 3 : 1
                implicitHeight: 44
                // A connected group: outer ends pill, inner joins tight; the
                // chosen segment rounds into a pill of its own.
                topLeftRadius: segment.chosen || segment.index === 0 ? 22 : Appearance.rounding.verysmall
                bottomLeftRadius: segment.chosen || segment.index === 0 ? 22 : Appearance.rounding.verysmall
                topRightRadius: segment.chosen || segment.index === Units.categories.length - 1 ? 22 : Appearance.rounding.verysmall
                bottomRightRadius: segment.chosen || segment.index === Units.categories.length - 1 ? 22 : Appearance.rounding.verysmall
                colBackground: segment.chosen ? ClockStyle.colPrimary : ClockStyle.colField
                colBackgroundHover: segment.chosen ? ClockStyle.colPrimaryHover : ClockStyle.colFieldHover
                colRipple: segment.chosen ? ClockStyle.colPrimaryActive : ClockStyle.colSurfaceActive
                onClicked: panel.tile?.setCategory(segment.modelData.id)
                Behavior on Layout.preferredWidth {
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }
                contentItem: Item {
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: segment.modelData.symbol
                            iconSize: 20
                            fill: segment.chosen ? 1 : 0
                            color: segment.chosen ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant
                        }
                        StyledText {
                            visible: segment.chosen
                            text: Translation.tr(segment.modelData.title)
                            color: ClockStyle.colOnPrimary
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                        }
                    }
                }
                StyledToolTip {
                    text: Translation.tr(segment.modelData.title)
                    extraVisibleCondition: !segment.chosen
                }
            }
        }
    }

    component UnitField: Rectangle {
        id: field
        property alias text: input.text
        property string unitId
        property bool result: false
        signal edited(string text)
        signal unitPicked(string unitId)
        function focusInput() {
            input.forceActiveFocus();
            input.selectAll();
        }
        Layout.fillWidth: true
        implicitHeight: column.implicitHeight + 24
        radius: ClockStyle.radiusLarge
        color: input.activeFocus ? ClockStyle.colPrimaryContainer : ClockStyle.colField
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            id: column
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                TextInput {
                    id: input
                    Layout.fillWidth: true
                    color: input.activeFocus ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                    selectionColor: ClockStyle.colPrimary
                    selectedTextColor: ClockStyle.colOnPrimary
                    font.family: ClockStyle.fontMain
                    font.variableAxes: field.result ? ClockStyle.axesDigitsBold : ClockStyle.axesDigits
                    font.pixelSize: 40
                    clip: true
                    selectByMouse: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onTextEdited: field.edited(input.text)
                }
                StyledText {
                    text: Units.unit(panel.categoryId, field.unitId)?.label ?? ""
                    color: input.activeFocus ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: panel.units
                    delegate: RippleButton {
                        id: unitChip
                        required property var modelData
                        readonly property bool chosen: field.unitId === unitChip.modelData.id
                        implicitHeight: 28
                        implicitWidth: unitLabel.implicitWidth + 18
                        buttonRadius: unitChip.chosen ? ClockStyle.radiusSmall : 14
                        colBackground: unitChip.chosen ? ClockStyle.colPrimary : ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.06)
                        colBackgroundHover: unitChip.chosen ? ClockStyle.colPrimaryHover : ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.12)
                        colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.2)
                        onClicked: field.unitPicked(unitChip.modelData.id)
                        contentItem: StyledText {
                            id: unitLabel
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: unitChip.modelData.label
                            color: unitChip.chosen ? ClockStyle.colOnPrimary : ClockStyle.colOnSurface
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }

    UnitField {
        id: fromField
        unitId: panel.tile?.fromId ?? ""
        onEdited: text => panel.fromEdited(text)
        onUnitPicked: id => panel.tile?.setUnits(id, panel.tile.toId)
    }

    ClockIconButton {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: -16
        Layout.bottomMargin: -16
        z: 2
        symbol: "swap_vert"
        tooltip: Translation.tr("Swap units")
        colBackground: ClockStyle.colPrimary
        colIcon: ClockStyle.colOnPrimary
        onClicked: panel.tile?.swap()
    }

    UnitField {
        id: toField
        unitId: panel.tile?.toId ?? ""
        result: true
        onEdited: text => panel.toEdited(text)
        onUnitPicked: id => panel.tile?.setUnits(panel.tile.fromId, id)
    }
}
