pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * What the Reminders tab draws for each list, level and category: icons, names and the
 * category palette. Colours come from the theme except a category's own, which is the
 * user's pick from `palette` (Samsung Reminder's category colours, toned for both modes).
 */
Singleton {
    id: root

    /// Category colours, Samsung's twelve in order.
    readonly property list<string> palette: ["#e8574f", "#f08a3c", "#f2b33d", "#7cb342", "#3cae7a", "#2fa9a5",
        "#3d9be9", "#5c6bc0", "#8e63ce", "#c45bb4", "#8d6e63", "#78909c"]

    readonly property list<string> categoryIcons: ["checklist", "list", "home", "work", "school", "shopping_cart",
        "fitness_center", "favorite", "flight", "restaurant", "payments", "pets", "local_hospital", "celebration",
        "directions_car", "book_2"]

    /// The smart lists, in Samsung's order (Place is left out: a PC has no location).
    readonly property var smartLists: [
        { id: "today", icon: "today", label: Translation.tr("Today"), shape: "Cookie7Sided", shapeKind: MaterialShape.Shape.Cookie7Sided },
        { id: "scheduled", icon: "event_upcoming", label: Translation.tr("Scheduled"), shape: "Cookie9Sided", shapeKind: MaterialShape.Shape.Cookie9Sided },
        { id: "important", icon: "star", label: Translation.tr("Important"), shape: "Sunny", shapeKind: MaterialShape.Shape.Sunny },
        { id: "noAlert", icon: "notifications_off", label: Translation.tr("No alert"), shape: "Cookie6Sided", shapeKind: MaterialShape.Shape.Cookie6Sided },
        { id: "completed", icon: "check_circle", label: Translation.tr("Completed"), shape: "Cookie12Sided", shapeKind: MaterialShape.Shape.Cookie12Sided }
    ]

    readonly property var alertLevels: [
        { id: "light", icon: "notifications", label: Translation.tr("Light"),
            description: Translation.tr("A notification and a short sound") },
        { id: "medium", icon: "notifications_active", label: Translation.tr("Medium"),
            description: Translation.tr("A full-screen alert and a short sound") },
        { id: "strong", icon: "alarm", label: Translation.tr("Strong"),
            description: Translation.tr("A full-screen alert that keeps ringing") }
    ]

    function smartList(id) {
        return root.smartLists.find(list => list.id === id) ?? null;
    }

    function alertLevel(id) {
        return root.alertLevels.find(level => level.id === id) ?? root.alertLevels[0];
    }

    /// Each smart tile's own container/content pair, so the five read apart at a glance.
    function smartColors(id) {
        switch (id) {
        case "today":
            return [ClockStyle.colPrimary, ClockStyle.colOnPrimary];
        case "scheduled":
            return [ClockStyle.colTertiary, ClockStyle.colOnTertiary];
        case "important":
            return ["#f2b33d", "#3d2a00"];
        case "noAlert":
            return [ClockStyle.colSecondaryContainer, ClockStyle.colOnSecondaryContainer];
        default:
            return [ClockStyle.colSurfaceHighest, ClockStyle.colOnSurfaceVariant];
        }
    }

    /// A category's colour: its own pick, or the theme's primary for an uncoloured one.
    function categoryColor(id): color {
        const category = RemindersService.category(id);
        return category && category.color.length > 0 ? category.color : ClockStyle.colPrimary;
    }

    function categoryIcon(id): string {
        return RemindersService.category(id)?.icon ?? "checklist";
    }

    function countText(count: int): string {
        return count === 1 ? Translation.tr("1 reminder") : Translation.tr("%1 reminders").arg(String(count));
    }

    /// Readable text on a category colour.
    function onColor(col): color {
        const c = Qt.color(col);
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.6 ? "#1d1b16" : "#ffffff";
    }
}
