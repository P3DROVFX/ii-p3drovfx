pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The windows a rule's match catches right now.
 *
 * A window rule is the one setting in Hyprland with no feedback loop: you write a pattern, reload,
 * open the app, and find out. This row closes that loop while you type - the regex mistake people
 * actually make shows up as an empty list instead of as a rule that silently never fires.
 *
 * It is honest about its limits. This is JavaScript's regex engine reading `hyprctl clients`, not
 * Hyprland matching a window, so it can say "this pattern catches these three windows" and it
 * cannot say "Hyprland will therefore apply the rule".
 */
Rectangle {
    id: root

    /// The rule's match table.
    property var match: ({})
    property bool showEmptyHint: true

    readonly property var report: HyprlandRules.matchReport(root.match)
    readonly property int total: HyprlandData.windowList?.length ?? 0

    property var _memo: ({})

    /// The matched windows as plain rows, kept by identity: the report is a fresh object on
    /// every window event the compositor sends, and this list is what the Repeater runs on.
    readonly property var matched: ObjectUtils.keep(root._memo, "matched",
        root.report.windows.map(window => ({
            "class": String(window.class ?? ""),
            "title": String(window.title ?? "")
        })))

    readonly property string headline: {
        if (root.report.broken.length > 0)
            return Translation.tr("That pattern is not valid, so nothing can be matched against it.");
        if (root.report.empty)
            return Translation.tr("Nothing to match on yet.");
        if (root.report.usable === 0)
            return Translation.tr("Nothing here can be checked against your open windows.");
        if (root.report.windows.length === 0)
            return Translation.tr("No window open right now matches this.");
        return Translation.tr("Matches %1 of your %2 open windows.")
            .arg(root.report.windows.length).arg(root.total);
    }

    visible: root.showEmptyHint || !root.report.empty
    Layout.fillWidth: true
    implicitHeight: visible ? layout.implicitHeight + 20 : 0
    color: root.report.broken.length > 0
        ? Appearance.colors.colSurfaceContainerHigh : Appearance.colors.colLayer2

    // Same rule as the section footer: this row is never the first of a group, so only its
    // bottom corners depend on what follows it.
    readonly property bool isLast: {
        const owner = root.parent;
        if (!owner) return true;
        const siblings = owner.children;
        let seen = false;
        for (let i = 0; i < siblings.length; i++) {
            if (siblings[i] === root) {
                seen = true;
                continue;
            }
            if (!seen || !siblings[i].visible) continue;
            return typeof siblings[i].topLeftRadius === "undefined";
        }
        return true;
    }

    topLeftRadius: Appearance.rounding.verysmall
    topRightRadius: Appearance.rounding.verysmall
    bottomLeftRadius: root.isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
    bottomRightRadius: root.isLast ? Appearance.rounding.large : Appearance.rounding.verysmall

    ColumnLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 16
            rightMargin: 16
            topMargin: 10
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: root.report.broken.length > 0 ? "error" : "search"
                iconSize: Appearance.font.pixelSize.normal
                color: root.report.broken.length > 0
                    ? Appearance.colors.colError : Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: root.headline
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.report.broken.length > 0
                    ? Appearance.colors.colError : Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        Repeater {
            model: root.matched

            delegate: RowLayout {
                required property var modelData

                Layout.fillWidth: true
                Layout.leftMargin: 24
                spacing: 8

                MaterialSymbol {
                    text: "check"
                    iconSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: String(modelData.class ?? "")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(modelData.title ?? "")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.report.unknown.length > 0
            text: Translation.tr("This page cannot check %1 against your open windows, so the list above ignores it. Hyprland still applies it.")
                .arg(root.report.unknown.join(", "))
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }
}
