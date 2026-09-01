pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * What a shortcut should do.
 *
 * Two lists in one: things the compositor does, and things this shell does. The shell half is
 * read from `hyprctl globalshortcuts`, so it is whatever is really registered right now rather
 * than a list in this file that goes stale the first time a panel is renamed.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false

    property string rawQuery: ""
    readonly property string query: subPageRoot.rawQuery.trim().toLowerCase()

    function matches(text: string): bool {
        return subPageRoot.query === "" || String(text ?? "").toLowerCase().indexOf(subPageRoot.query) >= 0;
    }

    readonly property var compositorRows: HyprlandBinds.actionCatalogue
        .filter(entry => entry.id !== "global")
        .filter(entry => subPageRoot.matches(entry.label) || subPageRoot.matches(entry.id))
        .map(entry => ({ "kind": "catalogue", "id": entry.id, "icon": entry.icon,
            "name": entry.label, "detail": entry.hint ?? "" }))

    readonly property var shellRows: Array.from(HyprlandBinds.globals ?? [])
        .filter(shortcut => subPageRoot.matches(shortcut.name) || subPageRoot.matches(shortcut.description))
        .map(shortcut => ({ "kind": "global", "id": shortcut.name, "icon": "widgets",
            "name": shortcut.description !== "" ? shortcut.description : shortcut.name,
            "detail": shortcut.name }))
        .sort((left, right) => left.name.localeCompare(right.name))

    readonly property var rows: {
        let out = [];
        if (subPageRoot.shellRows.length > 0)
            out = out.concat([{ "header": Translation.tr("This shell") }], subPageRoot.shellRows);
        if (subPageRoot.compositorRows.length > 0)
            out = out.concat([{ "header": Translation.tr("Windows and workspaces") }],
                subPageRoot.compositorRows);
        return out;
    }

    function pick(row: var) {
        if (row.kind === "global") {
            HyprlandBinds.putDraft("actionId", "global");
            HyprlandBinds.putDraft("actionValue", row.id);
        } else {
            HyprlandBinds.putDraft("actionId", row.id);
            // A different action rarely wants the previous one's parameter, and a stale
            // direction silently produces a bind that points the wrong way.
            const entry = HyprlandBinds.catalogueEntry(row.id);
            if (entry === null || entry.param === undefined) HyprlandBinds.putDraft("actionValue", "");
            else if (entry.param === "direction") HyprlandBinds.putDraft("actionValue", "l");
            else HyprlandBinds.putDraft("actionValue", "");
        }
        subPageRoot.goBack();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("What should it do?")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Or choose \"Run a command\" and write your own.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search actions")
            onTextChanged: subPageRoot.rawQuery = text
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2
            clip: true
            // Filtered per keystroke; replaying the entry animation on every letter reads as
            // a stutter, not an animation.
            animateAppearance: false
            model: subPageRoot.rows

            delegate: Item {
                id: entryRow

                required property var modelData

                readonly property bool isHeader: modelData.header !== undefined
                readonly property bool current: !entryRow.isHeader
                    && (entryRow.modelData.kind === "global"
                        ? (HyprlandBinds.draft.actionId === "global"
                            && HyprlandBinds.draft.actionValue === entryRow.modelData.id)
                        : HyprlandBinds.draft.actionId === entryRow.modelData.id)

                width: list.width
                implicitHeight: entryRow.isHeader ? 34 : 48

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    visible: entryRow.isHeader
                    text: entryRow.isHeader ? entryRow.modelData.header : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                RippleButton {
                    anchors.fill: parent
                    visible: !entryRow.isHeader
                    buttonRadius: Appearance.rounding.normal
                    colBackground: entryRow.current ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer1
                    colBackgroundHover: entryRow.current ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colLayer1Hover
                    colRipple: entryRow.current ? Appearance.colors.colPrimaryContainerActive
                        : Appearance.colors.colLayer1Active
                    onClicked: subPageRoot.pick(entryRow.modelData)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: entryRow.isHeader ? "" : entryRow.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: entryRow.current ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: entryRow.isHeader ? "" : entryRow.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: entryRow.current ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: entryRow.isHeader ? "" : entryRow.modelData.detail
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: entryRow.current ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext
                            }
                        }

                        MaterialSymbol {
                            visible: entryRow.current
                            text: "check"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }
        }
    }
}
