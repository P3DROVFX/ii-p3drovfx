pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Pick the app a new window rule is about.
 *
 * Open windows come first, because the class an app actually maps with is frequently not the one
 * its desktop file advertises - picking the running window is the only way to be certain, and it
 * is also the only way to write a rule for something with no desktop file at all. The installed
 * list is underneath for the app that is not running right now.
 *
 * Choosing either writes an anchored pattern, `^(class)$`, which is what stops a rule meant for
 * "code" from also catching "codium".
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

    /// One row per class, not per window: three terminals are one rule.
    readonly property var openWindows: {
        const seen = {};
        const out = [];
        for (const window of Array.from(HyprlandData.windowList ?? [])) {
            const cls = String(window.class ?? "");
            if (cls === "" || seen[cls]) continue;
            if (!subPageRoot.matches(cls) && !subPageRoot.matches(window.title)) continue;
            seen[cls] = true;
            out.push({
                "cls": cls,
                "name": HyprlandRules.appLabel(cls),
                "detail": String(window.title ?? ""),
                "icon": AppSearch.guessIcon(cls)
            });
        }
        return out;
    }

    readonly property var installed: {
        const seen = {};
        for (const row of subPageRoot.openWindows) seen[row.cls] = true;
        const out = [];
        for (const entry of Array.from(AppSearch.list ?? [])) {
            const cls = String(entry.startupClass ?? "") !== ""
                ? String(entry.startupClass) : String(entry.id ?? "").replace(/\.desktop$/, "");
            if (cls === "" || seen[cls]) continue;
            if (!subPageRoot.matches(entry.name) && !subPageRoot.matches(cls)) continue;
            seen[cls] = true;
            out.push({ "cls": cls, "name": String(entry.name ?? cls), "detail": cls,
                "icon": String(entry.icon ?? "") });
        }
        return out.sort((left, right) => left.name.localeCompare(right.name));
    }

    readonly property var rows: {
        let out = [];
        if (subPageRoot.openWindows.length > 0)
            out = out.concat([{ "header": Translation.tr("Open now") }], subPageRoot.openWindows);
        if (subPageRoot.installed.length > 0)
            out = out.concat([{ "header": Translation.tr("Installed") }], subPageRoot.installed);
        return out;
    }

    function pick(cls: string) {
        const id = HyprlandRules.appId(cls);
        if (HyprlandRules.find("windowrule", id) === null)
            HyprlandRules.save("windowrule", id, { "match": { "class": HyprlandRules.exactPattern(cls) } });
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
                    text: Translation.tr("Which app?")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Picking a window that is open uses the class it really has.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search apps and open windows")
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
                readonly property bool taken: !entryRow.isHeader
                    && HyprlandRules.find("windowrule", HyprlandRules.appId(entryRow.modelData.cls)) !== null

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
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: subPageRoot.pick(entryRow.modelData.cls)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        IconImage {
                            Layout.alignment: Qt.AlignVCenter
                            implicitSize: 26
                            source: entryRow.isHeader ? ""
                                : Quickshell.iconPath(entryRow.modelData.icon, "application-x-executable")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: entryRow.isHeader ? "" : entryRow.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: entryRow.isHeader ? "" : entryRow.modelData.detail
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        StyledText {
                            visible: entryRow.taken
                            text: Translation.tr("Already has rules")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }
}
