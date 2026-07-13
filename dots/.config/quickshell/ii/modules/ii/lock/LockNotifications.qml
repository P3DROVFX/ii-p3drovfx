pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Read-only notification list for the lock screen.
 * Strictly display-only: no actions, no dismissal, no mouse handling,
 * so the lock surface keeps forcing focus on the password box.
 */
ColumnLayout {
    id: root

    readonly property var conf: Config.options.lock.notifications
    readonly property string criticalUrgency: NotificationUrgency.Critical.toString()
    readonly property bool onTop: conf.position.startsWith("top")
    readonly property bool onLeft: conf.position.endsWith("left")
    readonly property real zoom: conf.zoomPercent / 100

    property double lockTime: 0
    // The Loader in LockSurface activates when the session gets locked
    Component.onCompleted: lockTime = Date.now()

    readonly property var filtered: Notifications.list.filter(notif => {
        if (conf.onlySinceLock && notif.time < root.lockTime)
            return false;
        if (conf.filters.skipTransient && notif.isTransient)
            return false;
        if (conf.filters.skipLowUrgency && notif.urgency === NotificationUrgency.Low.toString())
            return false;
        const appName = notif.appName.toLowerCase();
        if (conf.neverShowApps.some(app => app.toLowerCase() === appName))
            return false;
        if (conf.defaultPolicy === "hide" && !conf.alwaysShowApps.some(app => app.toLowerCase() === appName))
            return false;
        return true;
    }).sort((a, b) => b.time - a.time)

    // Notifications rendered with full content: everything in "full" mode,
    // otherwise only critical ones when the override allows them through
    readonly property var fullyShown: {
        if (conf.privacy === "full")
            return filtered.slice(0, conf.maxShown);
        if (conf.filters.criticalOverride === "full")
            return filtered.filter(n => n.urgency === root.criticalUrgency).slice(0, conf.maxShown);
        return [];
    }
    readonly property var redactedRest: filtered.filter(n => !fullyShown.includes(n))
    readonly property var redactedGroups: {
        if (conf.privacy !== "redacted")
            return [];
        const groups = [];
        redactedRest.forEach(notif => {
            let group = groups.find(g => g.appName === notif.appName);
            if (!group) {
                group = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    count: 0
                };
                groups.push(group);
            }
            group.count += 1;
        });
        return groups.slice(0, Math.max(0, conf.maxShown - fullyShown.length));
    }
    readonly property int overflowCount: {
        if (conf.privacy === "full")
            return filtered.length - fullyShown.length;
        if (conf.privacy === "redacted")
            return redactedRest.filter(n => !redactedGroups.some(g => g.appName === n.appName)).length;
        return 0; // The count pill already covers every remaining notification
    }

    // Flat, ordered list of everything to render. Newest sits closest to the
    // screen edge: stacking is newest-first on top, flipped when on the bottom
    readonly property var displayItems: {
        const items = fullyShown.map(notif => ({
            kind: "full",
            notif: notif
        }));
        redactedGroups.forEach(group => items.push({
            kind: "redacted",
            group: group
        }));
        if (conf.privacy === "countOnly" && redactedRest.length > 0)
            items.push({
                kind: "countPill"
            });
        if (overflowCount > 0)
            items.push({
                kind: "overflow"
            });
        return onTop ? items : items.reverse();
    }

    width: 380 * zoom
    spacing: 8
    visible: filtered.length > 0

    Repeater {
        model: root.displayItems
        delegate: Loader {
            id: itemLoader
            required property var modelData
            readonly property bool isCard: modelData.kind === "full" || modelData.kind === "redacted"

            Layout.fillWidth: isCard
            Layout.alignment: root.onLeft ? Qt.AlignLeft : Qt.AlignRight
            Layout.leftMargin: (!isCard && root.onLeft) ? 10 : 0
            Layout.rightMargin: (!isCard && !root.onLeft) ? 10 : 0
            sourceComponent: {
                switch (itemLoader.modelData.kind) {
                case "full":
                    return fullComponent;
                case "redacted":
                    return redactedComponent;
                case "countPill":
                    return pillComponent;
                default:
                    return overflowComponent;
                }
            }

            Component {
                id: fullComponent
                FullCard {
                    notif: itemLoader.modelData.notif
                }
            }
            Component {
                id: redactedComponent
                RedactedCard {
                    group: itemLoader.modelData.group
                }
            }
            Component {
                id: pillComponent
                CountPill {}
            }
            Component {
                id: overflowComponent
                StyledText {
                    text: Translation.tr("+%1 more").arg(root.overflowCount)
                    font.pixelSize: Appearance.font.pixelSize.small * root.zoom
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    component Card: Rectangle {
        radius: Appearance.rounding.normal * root.zoom
        color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.08)
    }

    component FullCard: Card {
        id: fullCard
        required property var notif

        implicitHeight: fullCardRow.implicitHeight + 20 * root.zoom

        RowLayout {
            id: fullCardRow
            anchors {
                fill: parent
                margins: 10 * root.zoom
            }
            spacing: 10 * root.zoom

            NotificationAppIcon {
                Layout.alignment: Qt.AlignTop
                implicitSize: 38 * root.zoom
                appIcon: fullCard.notif.appIcon
                summary: fullCard.notif.summary
                image: fullCard.notif.image
                urgency: fullCard.notif.urgency === root.criticalUrgency ? NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2 * root.zoom

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6 * root.zoom

                    StyledText {
                        Layout.fillWidth: true
                        text: fullCard.notif.appName
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller * root.zoom
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        text: NotificationUtils.getFriendlyNotifTimeString(fullCard.notif.time)
                        font.pixelSize: Appearance.font.pixelSize.smaller * root.zoom
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: fullCard.notif.summary
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.weight: Font.Medium
                    font.pixelSize: Appearance.font.pixelSize.small * root.zoom
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: fullCard.notif.body
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    font.pixelSize: Appearance.font.pixelSize.smaller * root.zoom
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    component RedactedCard: Card {
        id: redactedCard
        required property var group

        implicitHeight: redactedCardRow.implicitHeight + 20 * root.zoom

        RowLayout {
            id: redactedCardRow
            anchors {
                fill: parent
                margins: 10 * root.zoom
            }
            spacing: 10 * root.zoom

            NotificationAppIcon {
                implicitSize: 38 * root.zoom
                appIcon: redactedCard.group.appIcon
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2 * root.zoom

                StyledText {
                    Layout.fillWidth: true
                    text: redactedCard.group.appName
                    elide: Text.ElideRight
                    font.weight: Font.Medium
                    font.pixelSize: Appearance.font.pixelSize.small * root.zoom
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: redactedCard.group.count === 1 ? Translation.tr("1 new notification") : Translation.tr("%1 new notifications").arg(redactedCard.group.count)
                    font.pixelSize: Appearance.font.pixelSize.smaller * root.zoom
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    component CountPill: Card {
        implicitWidth: pillRow.implicitWidth + 28 * root.zoom
        implicitHeight: pillRow.implicitHeight + 14 * root.zoom
        radius: Appearance.rounding.full

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6 * root.zoom

            MaterialSymbol {
                fill: 1
                text: "notifications"
                iconSize: Appearance.font.pixelSize.huge * root.zoom
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: root.redactedRest.length
                font.weight: Font.Medium
                font.pixelSize: Appearance.font.pixelSize.small * root.zoom
                color: Appearance.colors.colOnLayer1
            }
        }
    }
}
