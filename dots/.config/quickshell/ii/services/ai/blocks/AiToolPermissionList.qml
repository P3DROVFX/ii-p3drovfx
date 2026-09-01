import QtQuick
import QtQuick.Layouts
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets

/**
 * The one presentation of standing tool permissions shared by Settings and
 * the chat popover.  The registry decides the domain order; this component
 * only groups that declarative data and writes the user's choice through the
 * chat-scoped permissions API.
 */
ColumnLayout {
    id: root

    property var definitions: Array.from(Ai.toolbox.definitions)
    property string density: "comfortable" // compact | comfortable
    property var expandedDomains: ({})

    Layout.fillWidth: true
    // Domain accordions belong to one permission list. A normal section gap
    // makes them read as unrelated cards; keep a compact token gap instead.
    spacing: root.density === "compact"
        ? Appearance.rounding.unsharpenmore / 2
        : Appearance.rounding.unsharpenmore

    readonly property var visibleDomains: AiToolRegistry.domains.filter(domain => root.toolsForDomain(domain).length > 0)

    function toolsForDomain(domain: string): var {
        return Array.from(root.definitions).filter(definition => definition.domain === domain);
    }

    function expandedFor(domain: string): bool {
        return root.expandedDomains[domain] === true;
    }

    function setExpanded(domain: string, expanded: bool) {
        if (root.expandedFor(domain) === expanded)
            return;
        const next = Object.assign({}, root.expandedDomains);
        next[domain] = expanded;
        root.expandedDomains = next;
    }

    function domainPermission(domain: string): string {
        const tools = root.toolsForDomain(domain);
        if (tools.length === 0)
            return "ask";
        const first = Ai.toolbox.permission(tools[0].id);
        for (let i = 1; i < tools.length; i++) {
            if (Ai.toolbox.permission(tools[i].id) !== first)
                return "mixed";
        }
        return first;
    }

    function setDomainPermission(domain: string, value: string) {
        const tools = root.toolsForDomain(domain);
        for (let i = 0; i < tools.length; i++) {
            if (Ai.toolbox.permissionValuesFor(tools[i].id).indexOf(value) >= 0)
                Ai.toolbox.setPermission(tools[i].id, value);
        }
    }

    function domainTitle(domain: string): string {
        switch (domain) {
        case "settings": return Translation.tr("Shell settings");
        case "system": return Translation.tr("System");
        case "tasks": return Translation.tr("Tasks");
        case "windows": return Translation.tr("Windows");
        case "time": return Translation.tr("Time & reminders");
        case "media": return Translation.tr("Media");
        case "gmail": return Translation.tr("Gmail");
        case "files": return Translation.tr("Files");
        case "web": return Translation.tr("Web");
        case "theme": return Translation.tr("Theme");
        case "notes": return Translation.tr("Notes");
        case "sports": return Translation.tr("Sports");
        case "vision": return Translation.tr("Vision");
        case "shell": return Translation.tr("Terminal");
        case "rag": return Translation.tr("Local retrieval");
        case "memory": return Translation.tr("Memory");
        default: return Translation.tr("Other");
        }
    }

    function permissionSummary(domain: string): string {
        const permission = root.domainPermission(domain);
        if (permission === "mixed")
            return Translation.tr("Mixed permissions");
        return Ai.toolbox.permissionLabels[permission] ?? permission;
    }

    Repeater {
        model: root.visibleDomains

        delegate: ContentSubsection {
            id: domainSection
            required property string modelData

            readonly property string domain: modelData
            readonly property var tools: root.toolsForDomain(domain)

            title: root.domainTitle(domain) + " · " + String(tools.length) + " · " + root.permissionSummary(domain)
            tooltip: Translation.tr("Choose a default for every available tool in this domain, or open it to set them one by one.")
            collapsible: true
            expanded: root.expandedFor(domain)
            onExpandedChanged: root.setExpanded(domain, expanded)

            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: root.domainPermission(domainSection.domain)
                options: [
                    {
                        displayName: Translation.tr("Always"),
                        icon: "check_circle",
                        value: "allow"
                    },
                    {
                        displayName: Translation.tr("Ask first"),
                        icon: "help",
                        value: "ask"
                    },
                    {
                        displayName: Translation.tr("Never"),
                        icon: "block",
                        value: "deny"
                    }
                ]
                onSelected: value => root.setDomainPermission(domainSection.domain, value)
            }

            Repeater {
                model: domainSection.tools

                delegate: ColumnLayout {
                    id: toolEntry
                    required property var modelData

                    readonly property string permission: Ai.toolbox.permission(modelData.id)
                    readonly property bool dangerous: modelData.risk === "danger"
                    readonly property string unavailableReason: permission === "deny" ? "" : Ai.toolbox.unavailableReason(modelData.id)

                    Layout.fillWidth: true
                    Layout.topMargin: root.density === "compact" ? 0 : 4
                    spacing: root.density === "compact" ? 4 : 8
                    opacity: permission === "deny" || unavailableReason.length > 0 ? 0.64 : 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            text: toolEntry.modelData.icon
                            iconSize: root.density === "compact" ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.huge
                            color: toolEntry.danger ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: toolEntry.modelData.title
                                wrapMode: Text.Wrap
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: toolEntry.modelData.summary
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: toolEntry.unavailableReason.length > 0
                                spacing: 4

                                MaterialSymbol {
                                    text: "info"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: toolEntry.unavailableReason
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }

                    ConfigSelectionArray {
                        Layout.fillWidth: true
                        currentValue: toolEntry.permission
                        options: [
                            {
                                displayName: Translation.tr("Always"),
                                icon: "check_circle",
                                value: "allow"
                            },
                            {
                                displayName: Translation.tr("Ask first"),
                                icon: "help",
                                value: "ask"
                            },
                            {
                                displayName: Translation.tr("Never"),
                                icon: "block",
                                value: "deny"
                            }
                        ].filter(option => Ai.toolbox.permissionValuesFor(toolEntry.modelData.id).indexOf(option.value) >= 0)
                        onSelected: value => Ai.toolbox.setPermission(toolEntry.modelData.id, value)
                    }
                }
            }
        }
    }
}
