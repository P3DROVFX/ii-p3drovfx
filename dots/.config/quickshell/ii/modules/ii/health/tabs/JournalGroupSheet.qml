pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.health.components

/**
 * One journal error group: the message, where and how often it shows up, the latest
 * lines it wrote, and the two ways to quiet it — known (it stays visible under Known
 * and counts as noise) or muted (it goes away entirely).
 */
ClockSheet {
    id: root

    property string fp: ""
    property HealthAssistant assistant: null

    readonly property var group: Array.from(HealthService.journal.groups ?? []).find(g => g.fp === root.fp) ?? null
    readonly property string key: `journal:${root.fp}`
    property var lines: []
    property bool loading: true

    title: Translation.tr("From %1").arg(HealthText.sourceLabel(root.group?.source))
    subtitle: root.group?.state === "new" ? Translation.tr("New") : root.group?.state === "muted" ? Translation.tr("Muted") : Translation.tr("Known noise")

    Component.onCompleted: {
        HealthService.query("journalGroup", { fp: root.fp, lines: 20 }, (ok, data) => {
            root.loading = false;
            root.lines = ok ? Array.from(data?.lines ?? []) : [];
        });
    }

    headerActions: [
        HealthAssistantButton {
            assistant: root.assistant ?? placeholderAssistant
            key: root.key
            visible: root.assistant !== null && root.assistant.allowed
            provider: () => ({ group: root.group, recentLines: root.lines.slice(-15) })
        }
    ]

    HealthAssistant {
        id: placeholderAssistant
    }

    HealthAssistantPanel {
        Layout.fillWidth: true
        visible: root.assistant !== null && (root.assistant.isOpenOn(root.key) || root.assistant.hasAnswerFor(root.key))
        assistant: root.assistant ?? placeholderAssistant
        key: root.key
        placeholder: Translation.tr("Ask about this message — “is it harmful?”")
        provider: () => ({ group: root.group, recentLines: root.lines.slice(-15) })
    }

    HealthExplainCard {
        Layout.fillWidth: true
        explanation: root.group ? HealthText.explainJournal(root.group) : null
    }

    StyledText {
        Layout.fillWidth: true
        text: root.group?.sample ?? ""
        wrapMode: Text.WrapAnywhere
        font.family: Appearance.font.family.monospace
        font.pixelSize: ClockStyle.textSmall + 1
        color: ClockStyle.colOnSurface
    }

    ClockFormPicker {
        Layout.fillWidth: true
        symbol: "event_repeat"
        shapeKind: MaterialShape.Shape.Cookie7Sided
        caption: Translation.tr("Shows up")
        value: HealthText.journalSeen(root.group)
        showChevron: false
    }
    ClockFormPicker {
        Layout.fillWidth: true
        symbol: "numbers"
        shapeKind: MaterialShape.Shape.Clover4Leaf
        caption: Translation.tr("This boot")
        value: Translation.tr("%1 lines").arg(root.group?.countBoot ?? 0)
        showChevron: false
    }
    ClockFormPicker {
        Layout.fillWidth: true
        symbol: "schedule"
        shapeKind: MaterialShape.Shape.Sunny
        caption: Translation.tr("First seen")
        value: root.group?.firstSeen ? Qt.formatDateTime(new Date(Number(root.group.firstSeen)), "d MMM yyyy, hh:mm") : "—"
        showChevron: false
    }

    HealthLogBox {
        lines: root.lines
        loading: root.loading
    }

    actions: [
        ClockSheetAction {
            visible: root.group?.state !== "muted"
            label: Translation.tr("Mute this message")
            symbol: "notifications_off"
            onClicked: {
                HealthService.mute(root.fp);
                root.close();
            }
        },
        ClockSheetAction {
            visible: root.group?.state === "muted"
            label: Translation.tr("Unmute")
            symbol: "notifications_active"
            onClicked: {
                HealthService.unmute(root.fp);
                root.close();
            }
        },
        ClockSheetAction {
            visible: root.group?.state === "new"
            primary: true
            label: Translation.tr("Mark as known")
            symbol: "done"
            onClicked: {
                HealthService.markKnown(root.fp);
                root.close();
            }
        }
    ]
}
