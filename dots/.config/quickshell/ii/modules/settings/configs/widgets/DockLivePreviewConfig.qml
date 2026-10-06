import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.dock
import qs.services

/**
 * Dock → Live Preview. The hero is the dock's own widget on a tray at the bottom
 * of the wallpaper, at the width chosen below; it never captures here (the
 * capture belongs to the dock, while it is shown). Options stay original.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Live Preview")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Hero: the widget, at its width ───────────────────────────────
        ClippingRectangle {
            id: hero
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(190, Math.min(240, width / 4))
            // The screen's own corners: a larger radius cut the ends of attached docks.
            radius: Appearance.rounding.windowRounding
            color: Appearance.colors.colLayer2
            readonly property bool on: Config.options.dock.enableLivePreviewWidget ?? false
            readonly property int slots: Math.max(2, Math.min(6, Config.options.dock.livePreviewSlots ?? 2))
            readonly property string appName: {
                const id = Config.options.dock.livePreviewAppId ?? "";
                if (id.length === 0)
                    return "";
                const entry = TaskbarApps.getCachedDesktopEntry(id);
                return entry?.name ?? id;
            }

            DockPreviewContext {
                id: heroContext
                live: GlobalStates.dockContents.length > 0 ? GlobalStates.dockContents[0] : null
            }

            Item {
                width: parent.width
                height: Math.max(parent.height, parent.width * 9 / 16)
                y: parent.height - height
                ColorsWallpaperImage {
                    anchors.fill: parent
                    targetMode: "desktop"
                    visible: hero.visible
                }
            }
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                opacity: hero.on ? 0.16 : 0.42
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: heroTray
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(Appearance.sizes.elevationMargin * 1.2)
                width: heroContext.buttonSlotSize * hero.slots
                height: heroContext.buttonSlotHeight
                radius: (Config.options.dock.dockRadius ?? -1) >= 0 ? Config.options.dock.dockRadius : Appearance.rounding.windowRounding + 12
                color: Appearance.colors.colLayer0
                opacity: hero.on ? 1 : 0.6
                scale: Math.min(1, (hero.width - 40) / Math.max(1, width))
                transformOrigin: Item.Bottom
                Behavior on width {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                DockItemView {
                    anchors.fill: parent
                    itemData: ({ "type": "livePreview" })
                    context: heroContext
                }
            }
            DockInputShield {}

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 11
                height: heroTagColumn.implicitHeight + 12
                width: Math.min(hero.width - 22, heroTagColumn.implicitWidth + 36)
                radius: Math.min(height / 2, Appearance.rounding.large)
                color: Appearance.colors.colSurfaceContainerHigh
                ColumnLayout {
                    id: heroTagColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Live Preview")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: !hero.on ? Translation.tr("Off")
                            : (hero.appName.length > 0 ? hero.appName : Translation.tr("No app chosen")) + " · " + Translation.tr("%1 slots wide").arg(hero.slots)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }
        }

        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("Live Preview Widget")
            icon: "live_tv"

            ConfigSwitch {
                buttonIcon: "live_tv"
                text: Translation.tr("Enable Live Preview widget")
                checked: Config.options.dock.enableLivePreviewWidget ?? false
                onCheckedChanged: {
                    Config.options.dock.enableLivePreviewWidget = checked;
                }
            }

            ContentSubsection {
                visible: Config.options.dock.enableLivePreviewWidget ?? false
                title: Translation.tr("Target application")
                icon: "apps"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.dock.livePreviewAppId ?? ""
                    onSelected: newValue => {
                        DockLivePreviewService.selectApp(newValue);
                    }
                    options: {
                        const options = [{
                            displayName: Translation.tr("No application selected"),
                            icon: "block",
                            value: ""
                        }];
                        const selected = Config.options.dock.livePreviewAppId || "";
                        if (selected !== "") {
                            const entry = TaskbarApps.getCachedDesktopEntry(selected);
                            const name = (entry && entry.name) ? entry.name : selected;
                            options.push({
                                displayName: name,
                                icon: "live_tv",
                                value: selected
                            });
                        }
                        const appList = TaskbarApps.apps || [];
                        for (let i = 0; i < appList.length; ++i) {
                            const app = appList[i];
                            const appId = (app && app.appId) ? app.appId : "";
                            if (!appId || options.some(option => TaskbarApps.normalizeAppId(option.value) === TaskbarApps.normalizeAppId(appId)))
                                continue;
                            const appEntry = TaskbarApps.getCachedDesktopEntry(appId);
                            const appName = (appEntry && appEntry.name) ? appEntry.name : appId;
                            options.push({
                                displayName: appName,
                                icon: "apps",
                                value: appId
                            });
                        }
                        return options;
                    }
                }
            }

            ConfigSpinBox {
                visible: Config.options.dock.enableLivePreviewWidget ?? false
                Layout.fillWidth: true
                icon: "width"
                text: Translation.tr("Preview width (slots)")
                value: Config.options.dock.livePreviewSlots ?? 2
                from: 2
                to: 6
                stepSize: 1
                onValueChanged: Config.options.dock.livePreviewSlots = value
            }

            ContentSubsection {
                visible: Config.options.dock.enableLivePreviewWidget ?? false
                title: Translation.tr("Capture mode")
                icon: "videocam"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.dock.livePreviewCaptureMode ?? "visible"
                    onSelected: newValue => Config.options.dock.livePreviewCaptureMode = newValue
                    options: [
                        {
                            displayName: Translation.tr("While visible"),
                            icon: "visibility",
                            value: "visible"
                        },
                        {
                            displayName: Translation.tr("While hovered"),
                            icon: "touch_app",
                            value: "hover"
                        }
                    ]
                }
            }

            ConfigSwitch {
                visible: Config.options.dock.enableLivePreviewWidget ?? false
                buttonIcon: "mouse"
                text: Translation.tr("Show captured cursor")
                checked: Config.options.dock.livePreviewPaintCursor ?? false
                onCheckedChanged: Config.options.dock.livePreviewPaintCursor = checked
            }

            ConfigSwitch {
                visible: Config.options.dock.enableLivePreviewWidget ?? false
                buttonIcon: "sync"
                text: Translation.tr("Follow active window")
                checked: Config.options.dock.livePreviewFollowActiveWindow ?? true
                onCheckedChanged: Config.options.dock.livePreviewFollowActiveWindow = checked
            }
        }
    }
}
