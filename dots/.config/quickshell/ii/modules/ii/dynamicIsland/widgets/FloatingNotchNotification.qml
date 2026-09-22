import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import qs.modules.ii.dynamicIsland.core

/**
 * A notification on the island, contracted and expanded.
 *
 * One face for both, drawn in the growing island (the registry's `expandsInPlace`), so
 * expanding is these same items moving rather than a second layout crossfading over the
 * first. Contracted, it is the title over one line of body - or, with
 * `dynamicIsland.widgets.notification.oneLine`, a slim single line. Expanded, it is a
 * card: the icon beside the app and time, the title and up to six lines of body, Copy and
 * Close at the top right, and the notification's own actions as pills along the bottom.
 *
 * Every position is interpolated between the two layouts on `morph`, which runs on the
 * island's own clock (500 ms, expressive spatial), so the content arrives with the body.
 * The title and body are drawn at the card's type size for the whole move and scaled
 * down to the contracted size, never animated through font sizes: a pixel size is an
 * integer, and stepping 12, 13, 14 reads as a jitter.
 */
Item {
    id: root
    anchors.fill: parent

    /** Set by the island while the pointer holds it open. */
    property bool isExpanded: false

    readonly property var liveNotif: Notifications.popupList.length > 0 ? Notifications.popupList[Notifications.popupList.length - 1] : null
    /**
     * The notification on screen, held after the popup list lets go of it.
     *
     * Opening search (or anything that clears popups) emptied the list while this face
     * was still fading out, so its text and icon swapped to the empty state in a single
     * frame in the middle of the transition. The island decides when the face leaves;
     * until then it keeps showing what it showed.
     */
    property var heldNotif: null
    onLiveNotifChanged: {
        if (root.liveNotif)
            root.heldNotif = root.liveNotif;
    }
    Component.onCompleted: root.heldNotif = root.liveNotif
    readonly property var latestNotif: root.liveNotif ?? root.heldNotif
    readonly property bool isUrgent: latestNotif && latestNotif.urgency === NotificationUrgency.Critical.toString()
    /** The enum, for the components that take one; the service stores a string. */
    readonly property var urgencyEnum: (root.latestNotif && root.latestNotif.notification)
        ? root.latestNotif.notification.urgency : NotificationUrgency.Normal

    readonly property color accentColor: isUrgent ? Appearance.colors.colPrimary : Appearance.colors.colSecondary

    property real pulseOpacity: 0.0

    SequentialAnimation {
        id: pulseAnimation
        running: root.isUrgent
        loops: Animation.Infinite
        NumberAnimation {
            target: root
            property: "pulseOpacity"
            from: 0.0
            to: 0.35
            duration: 800
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "pulseOpacity"
            from: 0.35
            to: 0.0
            duration: 800
            easing.type: Easing.InQuad
        }
    }

    // ── Content ──────────────────────────────────────────────────────────────
    /** The body, as the notification list draws it. */
    readonly property string bodyContent: root.latestNotif
        ? NotificationUtils.processNotificationBody(root.latestNotif.body ?? "",
            root.latestNotif.appName || root.latestNotif.summary || "")
        : ""
    readonly property bool hasBody: root.bodyContent !== ""
    readonly property bool hasActions: actionRepeater.count > 0

    function close() {
        if (root.latestNotif)
            Notifications.discardNotification(root.latestNotif.notificationId);
    }

    // ── The morph ────────────────────────────────────────────────────────────
    /** 0 contracted, 1 expanded; overshoots a little with the island's own bounce. */
    property real morph: root.isExpanded ? 1 : 0
    Behavior on morph {
        NumberAnimation {
            duration: Math.round(500 * Appearance.animMultiplier)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }
    /** Anything off the contracted rest draws at the card's type size. */
    readonly property bool cardType: root.isExpanded || root.morph > 0.001
    /** The card's own parts come in once the island has mostly grown. */
    readonly property real fade: Math.max(0, Math.min(1, (root.morph - 0.35) / 0.65))

    function mix(from, to) {
        return from + (to - from) * root.morph;
    }

    // ── Geometry ─────────────────────────────────────────────────────────────
    readonly property bool oneLine: Config.options.dynamicIsland?.widgets?.notification?.oneLine === true

    // Type sizes: the contracted ones, and the card's.
    readonly property int titleSize: Appearance.font.pixelSize.small             // 15
    readonly property int titleCardSize: Appearance.font.pixelSize.large         // 17
    readonly property int bodySize: root.oneLine ? Appearance.font.pixelSize.smallie : Appearance.font.pixelSize.smaller
    readonly property int bodyCardSize: 14

    // The card, from the registry's expanded box.
    readonly property real cardWidth: IslandRegistry.widthFor("notification", "expanded")
    readonly property real cardPadding: 16
    readonly property real cardIconY: root.cardPadding
    readonly property real cardIconSize: 48
    readonly property real cardTextX: root.cardPadding + root.cardIconSize + 12
    /** Copy and Close, top right: the app line and the title stop short of them. */
    readonly property real cardButtonsWidth: 2 * 32 + 4
    readonly property real cardTitleWidth: root.cardWidth - root.cardTextX - root.cardPadding
        - root.cardButtonsWidth - 8
    // The app and time sit over the title, in the text column beside the icon.
    readonly property real cardMetaY: root.cardPadding
    readonly property real cardTitleY: root.cardMetaY + metaMetrics.height + 2
    readonly property real cardBodyY: root.cardTitleY + titleCardMetrics.height + 4
    readonly property real cardBodyWidth: root.cardWidth - root.cardTextX - root.cardPadding - 2
    readonly property real cardContentBottom: Math.max(root.cardIconY + root.cardIconSize,
        root.cardBodyY + (root.hasBody ? bodyText.implicitHeight : 0))
    readonly property real cardActionsY: root.cardContentBottom + 14
    /** What the island grows to: read by NotchContent while the island is expanded. */
    readonly property real expandedHeight: root.cardContentBottom
        + (root.hasActions ? 14 + actionRow.implicitHeight : 0) + root.cardPadding

    // The contracted face, two lines or one.
    readonly property real restHeight: IslandRegistry.heightFor("notification", "compact")
    readonly property real restPadding: root.oneLine ? 6 : 10
    readonly property real restIconSize: root.restHeight - 2 * root.restPadding
    readonly property real restTextX: root.restPadding * 2 + root.restIconSize
    /** Two lines: title and body centred together. One line: the title centred. */
    readonly property real restTitleY: root.oneLine
        ? Math.round((root.restHeight - titleMetrics.height) / 2)
        : Math.round((root.restHeight - titleMetrics.height
            - (root.hasBody ? 2 + bodyMetrics.height : 0)) / 2)
    readonly property real restTitleWidth: root.oneLine
        ? Math.min(summaryText.contentWidthAtRest, (root.width - root.restTextX - 16) * 0.55)
        : root.width - root.restTextX - 14
    readonly property real restBodyX: root.oneLine ? root.restTextX + root.restTitleWidth + 8 : root.restTextX
    readonly property real restBodyY: root.oneLine
        ? root.restTitleY + titleMetrics.ascent - bodyMetrics.ascent
        : root.restTitleY + titleMetrics.height + 2
    readonly property real restBodyWidth: root.width - root.restBodyX - (root.oneLine ? 16 : 14)

    FontMetrics { id: titleMetrics; font.family: summaryText.font.family; font.pixelSize: root.titleSize; font.bold: true }
    FontMetrics { id: titleCardMetrics; font.family: summaryText.font.family; font.pixelSize: root.titleCardSize; font.bold: true }
    FontMetrics { id: bodyMetrics; font.family: bodyText.font.family; font.pixelSize: root.bodySize }
    FontMetrics { id: metaMetrics; font.family: bodyText.font.family; font.pixelSize: Appearance.font.pixelSize.smaller }

    // ── App and time (card only) ─────────────────────────────────────────────
    // The card's parts stay built and only fade, so none is created mid-morph.
    Row {
        x: root.cardTextX
        y: root.cardMetaY
        spacing: 6
        opacity: root.fade

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.cardTitleWidth - 60)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: root.accentColor
            text: root.latestNotif ? (root.latestNotif.appName || "") : ""
            elide: Text.ElideRight
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: "·"
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: root.latestNotif ? NotificationUtils.getFriendlyNotifTimeString(root.latestNotif.time) : ""
        }
    }

    /** Quiet round icon buttons for the card's corner. */
    component HeaderButton: IconToolbarButton {
        Layout.fillHeight: false
        implicitHeight: 32
        iconSize: Appearance.font.pixelSize.larger
    }

    // Copy and Close, top right, riding the edge as it moves out.
    Row {
        x: root.width - 12 - width
        y: root.cardPadding - 4
        spacing: 4
        opacity: root.fade
        enabled: root.isExpanded

        HeaderButton {
            id: copyButton
            text: "content_copy"
            onClicked: {
                Quickshell.clipboardText = root.latestNotif ? root.latestNotif.body : "";
                copyButton.text = "inventory";
                copyIconTimer.restart();
            }

            Timer {
                id: copyIconTimer
                interval: 1500
                repeat: false
                onTriggered: copyButton.text = "content_copy"
            }
        }

        HeaderButton {
            text: "close"
            onClicked: root.close()
        }
    }

    // ── Icon, title, body: shared by both layouts ────────────────────────────
    NotificationAppIcon {
        x: root.mix(root.restPadding, root.cardPadding)
        y: root.mix(root.restPadding, root.cardIconY)
        appIcon: root.latestNotif ? root.latestNotif.appIcon : ""
        summary: root.latestNotif ? root.latestNotif.summary : ""
        urgency: root.urgencyEnum
        image: root.latestNotif ? root.latestNotif.image : ""
        implicitSize: root.mix(root.restIconSize, root.cardIconSize)

        scale: root.isUrgent ? 1.0 + root.pulseOpacity * 0.08 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }
    }

    StyledText {
        id: summaryText
        /** The title's width at the contracted size, which the one-line face packs the body after. */
        readonly property real contentWidthAtRest: implicitWidth * root.titleSize / font.pixelSize

        x: root.mix(root.restTextX, root.cardTextX)
        y: root.mix(root.restTitleY, root.cardTitleY)
        width: root.cardType
            ? root.cardTitleWidth / scale
            : root.restTitleWidth
        transformOrigin: Item.TopLeft
        scale: root.cardType ? root.mix(root.titleSize / root.titleCardSize, 1) : 1
        font.pixelSize: root.cardType ? root.titleCardSize : root.titleSize
        font.bold: true
        color: Appearance.colors.colOnSurface
        text: root.latestNotif ? root.latestNotif.summary : ""
        maximumLineCount: 1
        elide: Text.ElideRight
    }

    StyledText {
        id: bodyText
        x: root.mix(root.restBodyX, root.cardTextX)
        y: root.mix(root.restBodyY, root.cardBodyY)
        // The card's width from the first frame, so it wraps once rather than every
        // frame of the growth; the island's shape clips what it has not reached yet.
        width: root.cardType ? root.cardBodyWidth : root.restBodyWidth
        visible: root.hasBody
        transformOrigin: Item.TopLeft
        scale: root.cardType ? root.mix(root.bodySize / root.bodyCardSize, 1) : 1
        font.pixelSize: root.cardType ? root.bodyCardSize : root.bodySize
        lineHeight: root.cardType ? 20 : 1
        lineHeightMode: root.cardType ? Text.FixedHeight : Text.ProportionalHeight
        color: ColorUtils.mix(Appearance.colors.colSubtext, Appearance.colors.colOnSurfaceVariant,
            1 - Math.max(0, Math.min(1, root.morph)))
        textFormat: Text.StyledText
        text: root.bodyContent.replace(/\n/g, root.cardType ? "<br/>" : " ")
        wrapMode: Text.Wrap // elide only works with a wrap mode set
        maximumLineCount: root.cardType ? 6 : 1
        elide: Text.ElideRight
        onLinkActivated: link => {
            Qt.openUrlExternally(link);
            GlobalStates.sidebarRightOpen = false;
        }

        PointingHandLinkHover {}
    }

    // ── Actions (card only) ──────────────────────────────────────────────────
    /** A flat pill, as wide as its share of the row. */
    component ActionPill: RippleButton {
        Layout.fillWidth: true
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
    }

    RowLayout {
        id: actionRow
        x: root.cardTextX
        y: root.cardActionsY
        width: root.cardWidth - root.cardTextX - root.cardPadding
        spacing: 8
        opacity: root.fade
        visible: root.hasActions
        enabled: root.isExpanded

        Repeater {
            id: actionRepeater
            model: root.latestNotif ? root.latestNotif.actions : []

            ActionPill {
                id: actionPill
                required property var modelData
                onClicked: {
                    const identifier = actionPill.modelData.identifier;
                    if (identifier.startsWith("__qs_")) {
                        Notifications.executeShellAction(root.latestNotif, identifier);
                        root.close();
                    } else {
                        Notifications.attemptInvokeAction(root.latestNotif.notificationId, identifier);
                    }
                }

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small - 1
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurface
                    text: actionPill.modelData.text
                    elide: Text.ElideRight
                }
            }
        }
    }
}
