pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * The "Add condition" / "Add action" catalogue, as a side sheet: a search field and a
 * grouped list of kinds. Rows that cannot be added here stay visible but greyed, with
 * the reason — hiding them would make the catalogue look smaller than it is.
 *
 * Built by a ClockSidePanel (`show(component, { title, choices })`); `picked(key)` fires
 * once and the sheet closes. Enter in the search takes the first row that can be added.
 *
 * `choices`: [{ key, label, icon, group, enabled, hint }]
 */
ClockSheet {
    id: root

    property var choices: []
    property string query: ""

    signal picked(string key)

    readonly property var filtered: {
        const q = root.query.trim().toLowerCase();
        const list = q.length
            ? root.choices.filter(c => c.label.toLowerCase().indexOf(q) !== -1
                || (c.group ?? "").toLowerCase().indexOf(q) !== -1)
            : root.choices;
        // Flatten into rows with group headers where the group changes; each row knows
        // whether it starts or ends its group, for the grouped corners.
        const out = [];
        let last = null;
        for (const c of list) {
            if ((c.group ?? "") !== last && (c.group ?? "").length) {
                if (out.length && !out[out.length - 1].header)
                    out[out.length - 1].last = true;
                out.push({ header: true, label: c.group });
                last = c.group;
            }
            const first = out.length === 0 || out[out.length - 1].header;
            out.push(Object.assign({ header: false, first: first, last: false }, c));
        }
        if (out.length && !out[out.length - 1].header)
            out[out.length - 1].last = true;
        return out;
    }

    function choose(key: string): void {
        root.picked(key);
        root.close();
    }

    scrollable: false

    Component.onCompleted: Qt.callLater(search.focusInput)

    ClockFormField {
        id: search
        symbol: "search"
        shapeKind: MaterialShape.Shape.Cookie12Sided
        caption: Translation.tr("Search")
        placeholder: Translation.tr("Filter by name or group")
        onTextChanged: root.query = text
        onAccepted: {
            const first = root.filtered.find(c => !c.header && c.enabled !== false);
            if (first)
                root.choose(first.key);
        }
    }

    StyledListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        popin: false
        animateAppearance: false
        animatePopulate: false
        model: root.filtered

        delegate: Item {
            id: row
            required property var modelData
            required property int index

            width: list.width
            implicitHeight: row.modelData.header ? (row.index === 0 ? 26 : 38) : 54

            StyledText {
                visible: row.modelData.header
                anchors {
                    left: parent.left
                    leftMargin: ClockStyle.gapSmall
                    bottom: parent.bottom
                    bottomMargin: ClockStyle.gapTiny + 2
                }
                text: row.modelData.label ?? ""
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.Bold
                color: ClockStyle.colPrimary
            }

            RippleButton {
                id: choice
                visible: !row.modelData.header
                anchors.fill: parent
                enabled: row.modelData.enabled !== false
                opacity: enabled ? 1 : 0.5
                // One grouped shape per group: outer corners small, the joins tighter.
                buttonRadius: Appearance.rounding.verysmall
                topLeftRadius: row.modelData.first ? ClockStyle.radiusSmall : Appearance.rounding.verysmall / 2
                topRightRadius: topLeftRadius
                bottomLeftRadius: row.modelData.last ? ClockStyle.radiusSmall : Appearance.rounding.verysmall / 2
                bottomRightRadius: bottomLeftRadius
                colBackground: ClockStyle.colField
                colBackgroundHover: ClockStyle.colFieldHover
                colRipple: ClockStyle.colSurfaceActive
                onClicked: root.choose(row.modelData.key)

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: ClockStyle.gapSmall + 2
                        rightMargin: ClockStyle.gap
                    }
                    spacing: ClockStyle.gap - 2

                    MaterialShapeWrappedMaterialSymbol {
                        text: row.modelData.icon ?? "bolt"
                        iconSize: 18
                        padding: 8
                        shape: MaterialShape.Shape.Cookie7Sided
                        color: ClockStyle.colPrimaryContainer
                        colSymbol: ClockStyle.colOnPrimaryContainer
                        rotation: choice.hovered ? 20 : 0
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.label ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: (row.modelData.hint ?? "").length > 0
                            text: row.modelData.hint ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textSmall
                            color: ClockStyle.colOnSurfaceVariant
                        }
                    }

                    MaterialSymbol {
                        visible: choice.enabled
                        text: "add"
                        iconSize: ClockStyle.iconSmall
                        color: ClockStyle.colPrimary
                    }
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: list.count === 0
            text: Translation.tr("Nothing matches")
            font.pixelSize: ClockStyle.textNormal
            color: ClockStyle.colSubtext
        }
    }
}
