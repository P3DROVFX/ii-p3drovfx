pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "android_search_bar"

    visibleWhenLocked: root.lockBehavior === "keep"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "android_search_bar")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property real contentScale: (Config.options.background.widgets.android_search_bar.widgetSize ?? 100) / 100.0
    readonly property string aspectRatio: Config.options.background.widgets.android_search_bar.aspectRatio ?? "0.5x2"

    implicitWidth: {
        if (root.aspectRatio === "4x1") return 960 * root.contentScale;
        if (root.aspectRatio === "3x1") return 720 * root.contentScale;
        if (root.aspectRatio === "2x1") return 480 * root.contentScale;
        return 340 * root.contentScale; // "0.5x2" default
    }
    implicitHeight: 60 * root.contentScale

    readonly property var options: Config.options.background.widgets.android_search_bar
    readonly property string action1Key: options.action1 ?? "music_rec"
    readonly property string action2Key: options.action2 ?? "ai_chat"
    readonly property string action3Key: options.action3 ?? "search"

    readonly property color colOuterBg: WidgetColorScheme.cardBgColor
    readonly property color colInnerBg: WidgetColorScheme.innerShapeColor
    readonly property color colIconText: WidgetColorScheme.textColorOnPillTrack

    function getActionDetails(key) {
        if (key === "ai_chat") return { defaultIcon: "neurology", label: Translation.tr("AI Chat") };
        if (key === "music_rec") return { defaultIcon: "music_note", label: Translation.tr("Music Recognition") };
        if (key === "translator") return { defaultIcon: "translate", label: Translation.tr("Translator") };
        if (key === "wallpapers") return { defaultIcon: "wallpaper", label: Translation.tr("Wallpapers") };
        if (key === "phone") return { defaultIcon: "smartphone", label: Translation.tr("Phone / KDE Connect") };
        if (key === "cheatsheet") return { defaultIcon: "help", label: Translation.tr("Cheatsheet") };
        if (key === "clipboard") return { defaultIcon: "content_paste", label: Translation.tr("Clipboard") };
        if (key === "color_picker") return { defaultIcon: "colorize", label: Translation.tr("Color Picker") };
        if (key === "screenshot") return { defaultIcon: "crop", label: Translation.tr("Screenshot") };
        return { defaultIcon: "search", label: Translation.tr("Search") };
    }

    function runAction(key) {
        if (key === "search") {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        } else if (key === "music_rec") {
            SongRec.toggleRunning();
        } else if (key === "ai_chat") {
            Ai.surfaceRouter.open({
                surface: "sidebar",
                focusIntent: "composer"
            });
        } else if (key === "translator") {
            Persistent.states.sidebar.policies.tab = 1;
            GlobalStates.sidebarLeftOpen = true;
        } else if (key === "wallpapers") {
            Persistent.states.sidebar.policies.tab = 3;
            GlobalStates.sidebarLeftOpen = true;
        } else if (key === "phone") {
            Persistent.states.sidebar.policies.tab = 5;
            GlobalStates.sidebarLeftOpen = true;
        } else if (key === "cheatsheet") {
            cheatsheetIpc.running = true;
        } else if (key === "clipboard") {
            GlobalStates.overviewOpen = true;
        } else if (key === "color_picker") {
            Quickshell.execDetached(["hyprpicker", "-a"]);
        } else if (key === "screenshot") {
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
        } else {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }

    Process {
        id: cheatsheetIpc
        command: ["qs", "ipc", "-c", "ii", "call", "cheatsheet", "toggle"]
    }

    StyledDropShadow {
        target: outerCapsule
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    // ── Outer Capsule Container (Dynamic Theme Colors) ───────────────────────
    Rectangle {
        id: outerCapsule
        anchors.fill: parent
        radius: height / 2
        color: root.colOuterBg

        RowLayout {
            anchors.fill: parent
            anchors.margins: 4 * root.contentScale
            spacing: 6 * root.contentScale

            // ── Inner Search Bar Pill Container ─────────────────────────────────
            Rectangle {
                id: innerPill
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: height / 2
                color: root.colInnerBg

                // Click area for opening Search overlay on inner bar
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14 * root.contentScale
                    anchors.rightMargin: 6 * root.contentScale
                    spacing: 6 * root.contentScale

                    // ── Dynamic Google "G" SVG Icon from assets/icons ─────────
                    CustomIcon {
                        implicitWidth:  24 * root.contentScale
                        implicitHeight: 24 * root.contentScale
                        Layout.alignment: Qt.AlignVCenter
                        source: "google.svg"
                        colorize: true
                        color: root.colIconText
                    }

                    Item { Layout.fillWidth: true } // Spacer

                    // ── Inner Button 1 (Action 1) ────────────────────────────
                    RippleButton {
                        implicitWidth:  40 * root.contentScale
                        implicitHeight: 40 * root.contentScale
                        topLeftRadius:    Appearance.rounding.full
                        topRightRadius:   Appearance.rounding.full
                        bottomLeftRadius: Appearance.rounding.full
                        bottomRightRadius:Appearance.rounding.full
                        colBackground:      "transparent"
                        colBackgroundHover: ColorUtils.applyAlpha(root.colIconText, 0.12)
                        colRipple:          ColorUtils.applyAlpha(root.colIconText, 0.24)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.options.icon1 || root.getActionDetails(root.action1Key).defaultIcon
                            fill: 1
                            iconSize: Math.round(28 * root.contentScale)
                            color: root.colIconText
                        }

                        onClicked: root.runAction(root.action1Key)
                    }

                    // ── Inner Button 2 (Action 2) ────────────────────────────
                    RippleButton {
                        implicitWidth:  40 * root.contentScale
                        implicitHeight: 40 * root.contentScale
                        topLeftRadius:    Appearance.rounding.full
                        topRightRadius:   Appearance.rounding.full
                        bottomLeftRadius: Appearance.rounding.full
                        bottomRightRadius:Appearance.rounding.full
                        colBackground:      "transparent"
                        colBackgroundHover: ColorUtils.applyAlpha(root.colIconText, 0.12)
                        colRipple:          ColorUtils.applyAlpha(root.colIconText, 0.24)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.options.icon2 || root.getActionDetails(root.action2Key).defaultIcon
                            fill: 1
                            iconSize: Math.round(28 * root.contentScale)
                            color: root.colIconText
                        }

                        onClicked: root.runAction(root.action2Key)
                    }
                }
            }

            // ── Outer Right Circle Button (Action 3) ─────────────────────────
            RippleButton {
                implicitWidth:  parent.height
                implicitHeight: parent.height
                topLeftRadius:    Appearance.rounding.full
                topRightRadius:   Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius:Appearance.rounding.full
                colBackground:      root.colInnerBg
                colBackgroundHover: ColorUtils.applyAlpha(root.colIconText, 0.15)
                colRipple:          ColorUtils.applyAlpha(root.colIconText, 0.30)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.options.icon3 || root.getActionDetails(root.action3Key).defaultIcon
                    fill: 1
                    iconSize: Math.round(28 * root.contentScale)
                    color: root.colIconText
                }

                onClicked: root.runAction(root.action3Key)
            }
        }
    }
}
