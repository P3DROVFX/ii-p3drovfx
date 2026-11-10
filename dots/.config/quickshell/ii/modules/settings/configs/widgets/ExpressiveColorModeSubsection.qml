pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSubsection {
    id: root

    title: Translation.tr("Colour treatment")
    icon: "palette"

    property string currentValue: "primary"
    signal selected(string newValue)

    readonly property string normalizedCurrentValue: {
        const raw = String(root.currentValue ?? "primary").trim().toLowerCase().replace(/[\s_-]/g, "");
        if (raw === "vibrant") return "primary";
        if (raw === "tonal") return "tertiaryContainer";
        if (raw === "primary") return "primary";
        if (raw === "primarycontainer") return "primaryContainer";
        if (raw === "secondary") return "secondary";
        if (raw === "secondarycontainer") return "secondaryContainer";
        if (raw === "tertiary" || raw === "teritiary") return "tertiary";
        if (raw === "tertiarycontainer" || raw === "teritiarycontainer") return "tertiaryContainer";
        if (raw === "neutral") return "neutral";
        if (raw === "neutralcontainer") return "neutralContainer";
        return "primary";
    }

    ConfigSelectionArray {
        id: selectionArray
        currentValue: root.normalizedCurrentValue
        onSelected: newValue => root.selected(String(newValue))
        options: [
            { displayName: Translation.tr("Primary"), icon: "circle", value: "primary" },
            { displayName: Translation.tr("Primary container"), icon: "format_color_fill", value: "primaryContainer" },
            { displayName: Translation.tr("Secondary"), icon: "palette", value: "secondary" },
            { displayName: Translation.tr("Secondary container"), icon: "layers", value: "secondaryContainer" },
            { displayName: Translation.tr("Tertiary"), icon: "auto_awesome", value: "tertiary" },
            { displayName: Translation.tr("Tertiary container"), icon: "auto_awesome_motion", value: "tertiaryContainer" },
            { displayName: Translation.tr("Neutral"), icon: "contrast", value: "neutral" },
            { displayName: Translation.tr("Neutral container"), icon: "texture", value: "neutralContainer" }
        ]
    }
}
