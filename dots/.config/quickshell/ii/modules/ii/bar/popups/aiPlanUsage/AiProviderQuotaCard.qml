pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../../shared/cards"

SectionCard {
    id: root

    required property var providerData
    property bool startAnim: false
    property int animDelay: 0
    property color accentColor: Appearance.colors.colSecondary
    property color accentContainer: Appearance.colors.colSecondaryContainer
    property color onAccentContainer: Appearance.colors.colOnSecondaryContainer

    Layout.fillWidth: true
    title: String(root.providerData.name ?? AiPlanUsage.providerName(String(root.providerData.id ?? "")))
    subtitle: root.providerData.stale === true || root.providerData.available !== true
        ? String(root.providerData.error ?? Translation.tr("Quota unavailable"))
        : ""
    icon: root.providerData.available === true ? "auto_awesome" : "cloud_off"
    shapeString: {
        const providerId = String(root.providerData.providerId ?? root.providerData.id ?? "");
        const groupId = String(root.providerData.groupId ?? "");
        if (providerId === "antigravity")
            return groupId === "gemini" ? "Sunny" : "SoftBurst";
        switch (providerId) {
        case "chatgpt": return "Cookie9Sided";
        case "claude": return "Clover4Leaf";
        case "zai": return "Sunny";
        case "kimi": return "SoftBurst";
        case "opencode": return "Cookie9Sided";
        case "openrouter": return "Circle";
        default: return "SoftBurst";
        }
    }
    shapeColor: root.accentContainer
    symbolColor: root.onAccentContainer
    headerExtraText: {
        const plan = String(root.providerData.plan ?? "");
        const planLabel = plan.length > 0 ? plan.charAt(0).toUpperCase() + plan.slice(1) : "";
        if (root.providerData.stale === true)
            return planLabel.length > 0
                ? planLabel + " · " + Translation.tr("cached")
                : Translation.tr("Cached");
        return planLabel;
    }
    showDivider: false
    opacity: 0.0

    transform: Translate {
        id: cardTranslate
        y: 18
    }

    onStartAnimChanged: {
        cardAnim.stop();
        root.opacity = 0.0;
        cardTranslate.y = 18;
        if (root.startAnim)
            Qt.callLater(function() { cardAnim.start(); });
    }

    SequentialAnimation {
        id: cardAnim

        PauseAnimation {
            duration: root.animDelay
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 1.0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            NumberAnimation {
                target: cardTranslate
                property: "y"
                to: 0
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
    }

    Repeater {
        id: quotaRepeater
        model: root.providerData.items ?? []

        delegate: AiQuotaRow {
            required property var modelData
            required property int index

            quota: modelData
            showGroupName: String(root.providerData.groupId ?? "").length === 0
            startAnim: root.startAnim
            animDelay: root.animDelay + Appearance.animation.elementMoveFast.duration
                + Math.min(index, 4) * Math.round(Appearance.animation.elementMoveFast.duration / 5)
            accentColor: root.accentColor
            accentContainer: root.accentContainer
            onAccentContainer: root.onAccentContainer
        }
    }
}
