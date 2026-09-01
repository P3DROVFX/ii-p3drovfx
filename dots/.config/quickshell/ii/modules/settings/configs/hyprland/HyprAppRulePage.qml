pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Rules -> one app.
 *
 * Everything this page can do to one application's windows, on a page of its own.
 *
 * The card used to be inline in the list, so a machine with five app rules was five copies of
 * sixteen controls stacked down one scroll - and the list of which apps have rules, which is the
 * thing you came to the tab to see, was buried among them. The list is a list now; this is what
 * one of its rows opens.
 */
HyprSubPage {
    id: page

    /// Set by the Rules tab before it opens this, the same way the full rule editor is.
    readonly property string ruleId: HyprlandRules.editId
    readonly property var spec: HyprlandRules.find("windowrule", page.ruleId) ?? ({})
    readonly property string windowClass: HyprlandRules.patternLabel(String((page.spec.match ?? {}).class ?? ""))

    title: HyprlandRules.appEntry(page.windowClass)?.name
        ?? (page.windowClass === "" ? Translation.tr("New rule") : page.windowClass)
    subtitle: HyprlandRules.effectSummary("windowrule", page.spec)

    ContentSection {
        title: Translation.tr("Rules for this app")
        icon: "widgets"

        HyprAppRuleCard {
            ruleId: page.ruleId
            showHeader: false
            onEditRequested: {
                HyprlandRules.beginEdit("windowrule", page.ruleId);
                page.activeSubPage = Qt.resolvedUrl("HyprRuleEditorPage.qml");
            }
            onRemoveRequested: {
                HyprlandRules.remove("windowrule", page.ruleId);
                page.goBack();
            }
        }
    }
}
