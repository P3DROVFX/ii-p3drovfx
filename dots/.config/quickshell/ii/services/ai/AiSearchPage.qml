pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.services.ai
import qs.services.ai.blocks
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Full-surface destinations for Search AI controls.
 *
 * These pages replace the chat body through AiSearchNavigator. They are
 * intentionally ordinary children of the launcher surface: no popup window,
 * focus trap, or second layer is created for an extensive collection.
 */
Item {
    id: root

    required property string pageId
    signal requestBack
    property string pendingTrashId: ""

    readonly property var pageMeta: ({
        "models": { title: Translation.tr("Models"), subtitle: Translation.tr("Choose the model and inspect its capabilities."), icon: "auto_awesome" },
        "history": { title: Translation.tr("History"), subtitle: Translation.tr("Return to a conversation or manage its lifecycle."), icon: "history" },
        "tools": { title: Translation.tr("Tools & web"), subtitle: Translation.tr("Control exposure, web mode, and per-tool approval."), icon: "construction" },
        "keys": { title: Translation.tr("Provider keys"), subtitle: Translation.tr("Keys stay masked and are tested without sending a chat."), icon: "key" },
        "actions": { title: Translation.tr("Actions"), subtitle: Translation.tr("Keyboard actions available from Search AI."), icon: "bolt" }
    })

    readonly property var meta: root.pageMeta[root.pageId] ?? ({ title: "", subtitle: "", icon: "info" })
    implicitHeight: pageCard.implicitHeight

    function cycleResponseMode() {
        const modes = ["fast", "balanced", "deep"];
        const index = modes.indexOf(Ai.responseMode);
        Ai.setResponseMode(modes[(index + 1 + modes.length) % modes.length], false);
    }

    function cycleWebMode() {
        const modes = ["off", "auto", "on"];
        const index = modes.indexOf(Ai.webMode);
        Ai.setWebMode(modes[(index + 1 + modes.length) % modes.length], false);
    }

    function cycleFunctionExposure() {
        const modes = ["none", "safe", "all"];
        const index = modes.indexOf(Ai.functionExposure);
        Ai.setFunctionExposure(modes[(index + 1 + modes.length) % modes.length], false);
    }

    Rectangle {
        id: pageCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: pageColumn.implicitHeight + 36
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.large

        ColumnLayout {
            id: pageColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.requestBack()

                    Accessible.name: Translation.tr("Back")

                    contentItem: MaterialSymbol {
                        text: "arrow_back"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledToolTip { text: Translation.tr("Back (Esc)") }
                }

                MaterialShapeWrappedMaterialSymbol {
                    implicitWidth: 42
                    implicitHeight: 42
                    shape: MaterialShape.Shape.SoftBurst
                    text: root.meta.icon
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.m3colors.m3onPrimaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: root.meta.title
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.meta.subtitle
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Loader {
                id: pageLoader
                Layout.fillWidth: true
                sourceComponent: root.pageId === "models" ? modelsPage
                    : root.pageId === "history" ? historyPage
                    : root.pageId === "tools" ? toolsPage
                    : root.pageId === "keys" ? keysPage
                    : root.pageId === "actions" ? actionsPage
                    : null
            }
        }
    }

    Component {
        id: modelsPage

        AiModelPickerPopover {
            id: modelPicker
            Layout.fillWidth: true
            maxListHeight: 360
            onPicked: modelId => {
                Ai.setModel(modelId, false);
                root.requestBack();
            }
        }
    }

    Component {
        id: historyPage

        ColumnLayout {
            id: historyColumn
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 conversations").arg(String(Ai.sessions?.index?.length ?? 0))
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: Translation.tr("Permanently remove trashed chats after %1 days").arg(String(Ai.sessions?.retentionDays ?? 30))
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: Ai.sessions.setRetentionDays((Ai.sessions.retentionDays ?? 30) >= 365 ? 30 : (Ai.sessions.retentionDays ?? 30) + 30)

                    Accessible.name: Translation.tr("Change retention period")

                    contentItem: MaterialSymbol {
                        text: "schedule"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledToolTip { text: Translation.tr("Cycle trash retention") }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(360, Math.max(64, sessionList.contentHeight))

                ListView {
                    id: sessionList
                    anchors.fill: parent
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel {
                        values: {
                            const entries = Array.from(Ai.sessions?.index ?? []);
                            entries.sort((a, b) => {
                                if ((b.pinned ?? false) !== (a.pinned ?? false))
                                    return (b.pinned ?? false) ? 1 : -1;
                                return String(b.updatedAt ?? "").localeCompare(String(a.updatedAt ?? ""));
                            });
                            return entries;
                        }
                    }

                    delegate: RowLayout {
                        id: sessionRow
                        required property var modelData
                        width: sessionList.width
                        spacing: 6

                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 58
                            buttonRadius: Appearance.rounding.small
                            colBackground: Ai.sessions.currentId === sessionRow.modelData.id
                                ? Appearance.colors.colSecondaryContainer
                                : Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: {
                                Ai.openSession(sessionRow.modelData.id);
                                root.requestBack();
                            }

                            contentItem: RowLayout {
                                spacing: 8

                                MaterialSymbol {
                                    text: sessionRow.modelData.pinned ? "push_pin" : "chat_bubble"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer2
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: sessionRow.modelData.title || Translation.tr("Untitled chat")
                                        elide: Text.ElideRight
                                        color: Appearance.colors.colOnLayer2
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: sessionRow.modelData.preview || Translation.tr("No messages yet")
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: Ai.sessions.setPinned(sessionRow.modelData.id, !sessionRow.modelData.pinned)

                            contentItem: MaterialSymbol {
                                text: sessionRow.modelData.pinned ? "push_pin" : "push_pin"
                                iconSize: Appearance.font.pixelSize.smallie
                                color: sessionRow.modelData.pinned ? Appearance.m3colors.m3primary : Appearance.colors.colSubtext
                            }

                            StyledToolTip { text: Translation.tr("Pin or unpin") }
                        }

                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: root.pendingTrashId = root.pendingTrashId === sessionRow.modelData.id ? "" : sessionRow.modelData.id

                            Accessible.name: Translation.tr("Move chat to trash")

                            contentItem: MaterialSymbol {
                                text: "delete"
                                iconSize: Appearance.font.pixelSize.smallie
                                color: Appearance.m3colors.m3error
                            }

                            StyledToolTip { text: Translation.tr("Move to trash") }
                        }

                        RippleButton {
                            visible: root.pendingTrashId === sessionRow.modelData.id
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.m3colors.m3error
                            colBackgroundHover: Appearance.m3colors.m3error
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: {
                                Ai.sessions.trash(sessionRow.modelData.id);
                                root.pendingTrashId = "";
                            }

                            Accessible.name: Translation.tr("Confirm moving chat to trash")

                            contentItem: MaterialSymbol {
                                text: "check"
                                iconSize: Appearance.font.pixelSize.smallie
                                color: Appearance.m3colors.m3onError
                            }

                            StyledToolTip { text: Translation.tr("Confirm trash") }
                        }
                    }
                }
            }

            RowLayout {
                visible: !!Ai.sessions.deletedEntry
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 moved to trash").arg(Ai.sessions.deletedEntry?.title ?? Translation.tr("Chat"))
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }

                RippleButton {
                    implicitWidth: 76
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: Ai.sessions.undoDelete()

                    Accessible.name: Translation.tr("Undo trash")

                    contentItem: StyledText {
                        text: Translation.tr("Undo")
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }

                RippleButton {
                    implicitWidth: 76
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: {
                        Ai.sessions.purge(Ai.sessions.deletedEntry?.id ?? "");
                        Ai.sessions.deletedEntry = null;
                    }

                    Accessible.name: Translation.tr("Permanently purge chat")

                    contentItem: StyledText {
                        text: Translation.tr("Purge")
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.m3colors.m3error
                    }
                }
            }
        }
    }

    Component {
        id: toolsPage

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: ScriptModel {
                        values: [
                            { id: "response", icon: "speed", label: Translation.tr("Response: %1").arg(Ai.responseMode) },
                            { id: "web", icon: "travel_explore", label: Translation.tr("Web: %1").arg(Ai.webMode) },
                            { id: "functions", icon: "construction", label: Translation.tr("Tools: %1").arg(Ai.functionExposure) }
                        ]
                    }

                    RippleButton {
                        id: toolProfileButton
                        required property var modelData
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: {
                            if (toolProfileButton.modelData.id === "response")
                                root.cycleResponseMode();
                            else if (toolProfileButton.modelData.id === "web")
                                root.cycleWebMode();
                            else
                                root.cycleFunctionExposure();
                        }

                        contentItem: RowLayout {
                            spacing: 5

                            MaterialSymbol {
                                text: toolProfileButton.modelData.icon
                                iconSize: Appearance.font.pixelSize.smallie
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }

                            StyledText {
                                text: toolProfileButton.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }
                        }
                    }
                }
            }

            AiToolsPopover {
                Layout.fillWidth: true
                onClosed: root.requestBack()
            }
        }
    }

    Component {
        id: keysPage

        AiApiKeyManager {
            Layout.fillWidth: true
            onClosed: root.requestBack()
        }
    }

    Component {
        id: actionsPage

        ListView {
            id: actionList
            Layout.fillWidth: true
            implicitHeight: Math.min(360, Math.max(64, contentHeight))
            clip: true
            spacing: 5
            model: ScriptModel { values: Array.from(AiActionRegistry.actions) }

            delegate: RowLayout {
                id: actionRow
                required property var modelData
                width: actionList.width
                spacing: 8

                MaterialShapeWrappedMaterialSymbol {
                    implicitWidth: 36
                    implicitHeight: 36
                    shape: MaterialShape.Shape.SoftBurst
                    text: actionRow.modelData.icon
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colLayer2
                    colSymbol: Appearance.colors.colOnLayer2
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: actionRow.modelData.label
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: actionRow.modelData.shortcut || Translation.tr("Available from the action rail")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
