pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/dock"
import "../../../ii/dock/utilities"

/**
 * One dock item ({ type, … } as DockContent's model holds it) drawn by the dock's
 * own component, centred in this item's box — DockContent's delegates, wired to
 * an inert `context` (DockPreviewContext) instead of the dock.
 */
Loader {
    id: root

    property var itemData: ({})
    property int itemIndex: -1
    property var context: null
    readonly property bool vertical: root.context?.isVertical ?? false

    sourceComponent: {
        switch (root.itemData?.type) {
        case "app": return appComponent;
        case "appGroup": return appGroupComponent;
        case "action": return actionComponent;
        case "file": return fileComponent;
        case "media": return mediaComponent;
        case "weather": return weatherComponent;
        case "sports": return sportsComponent;
        case "tasks": return tasksComponent;
        case "phone": return phoneComponent;
        case "livePreview": return livePreviewComponent;
        case "widgetStack": return stackComponent;
        case "utility": return utilityComponent;
        default: return null;
        }
    }

    Component {
        id: appComponent
        Item {
            DockAppButton {
                id: appButton
                anchors.centerIn: parent
                appToplevel: root.itemData.appData
                dockContent: root.context
                delegateIndex: root.itemIndex
            }
            Connections {
                target: root.context
                function onAttentionRequested(kind) {
                    if (kind === "launch")
                        appButton.playLaunchAnimation();
                    else
                        appButton.playNotificationAnimation();
                }
            }
        }
    }
    Component {
        id: appGroupComponent
        Item {
            DockAppGroupButton {
                anchors.centerIn: parent
                apps: root.itemData.apps ?? []
                groupId: root.itemData.groupId ?? ""
                dockContent: root.context
                delegateIndex: root.itemIndex
            }
        }
    }
    Component {
        id: actionComponent
        Item {
            id: actionRoot
            readonly property string actionId: root.itemData.actionId ?? ""
            readonly property var overviewCfg: Config.options.dock.overviewButton ?? null
            readonly property bool isOverview: actionRoot.actionId === "overview"
            DockActionButton {
                anchors.centerIn: parent
                actionId: actionRoot.actionId
                symbolName: actionRoot.actionId === "pin" ? "keep"
                    : actionRoot.actionId === "trash" ? "delete"
                    : actionRoot.isOverview ? (String(actionRoot.overviewCfg?.symbol ?? "").trim() || "apps")
                    : "drag_indicator"
                toggledSymbolName: actionRoot.actionId === "pin" ? "bookmark" : ""
                toggled: actionRoot.actionId === "pin" && (Config.options.dock.pinnedOnStartup ?? false)
                normalShape: actionRoot.isOverview ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Pill
                activeShape: actionRoot.isOverview ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie9Sided
                symbolSize: Math.round(Appearance.sizes.dockButtonSize * 0.5)
                dockContent: root.context
                delegateIndex: root.itemIndex
                customImageSource: actionRoot.actionId === "trash"
                    ? ("file://" + Directories.assetsPath + "/icons/" + (Appearance.m3colors.darkmode ? "macos-trash-dark.png" : "macos-trash.png")) : ""
                customIconSource: actionRoot.isOverview && String(actionRoot.overviewCfg?.iconFile ?? "").length > 0
                    ? ("file://" + Directories.assetsPath + "/icons/" + actionRoot.overviewCfg.iconFile) : ""
                tintCustomIcon: actionRoot.overviewCfg?.iconTint ?? true
                shapeName: actionRoot.isOverview ? String(actionRoot.overviewCfg?.shape ?? "SoftBurst") : ""
                alwaysShowShape: actionRoot.isOverview && (actionRoot.overviewCfg?.alwaysShowShape ?? false)
                dragActive: false
                dragOver: false
                dragSymbol: ""
            }
        }
    }
    Component {
        id: fileComponent
        Item {
            DockFileButton {
                anchors.centerIn: parent
                filePath: root.itemData.path ?? ""
                dockContent: root.context
                delegateIndex: root.itemIndex
            }
        }
    }
    Component {
        id: mediaComponent
        Item {
            DockMediaWidget {
                anchors.centerIn: parent
                isVertical: root.vertical
                dockContent: root.context
                delegateIndex: root.itemIndex
            }
        }
    }
    Component {
        id: weatherComponent
        Item {
            DockWeatherWidget {
                anchors.centerIn: parent
                isVertical: root.vertical
                dockContent: root.context
                delegateIndex: root.itemIndex
            }
        }
    }
    Component {
        id: sportsComponent
        Item {
            DockSportsWidget {
                anchors.centerIn: parent
                isVertical: root.vertical
                dockContent: root.context
                delegateIndex: root.itemIndex
            }
        }
    }
    Component {
        id: tasksComponent
        Item {
            DockTasksWidget {
                anchors.centerIn: parent
                isVertical: root.vertical
                dockContent: root.context
                delegateIndex: root.itemIndex
            }
        }
    }
    Component {
        id: phoneComponent
        Item {
            DockPhoneWidget {
                anchors.centerIn: parent
                isVertical: root.vertical
                dockContent: root.context
                delegateIndex: root.itemIndex
            }
        }
    }
    Component {
        id: livePreviewComponent
        Item {
            // Never captures here: the dock's capture lease needs a revealed dock.
            DockLivePreviewWidget {
                anchors.centerIn: parent
                isVertical: root.vertical
                dockContent: root.context
                dockRevealed: false
                dockWindowVisible: true
                delegateIndex: root.itemIndex
            }
        }
    }
    Component {
        id: stackComponent
        DockWidgetStack {
            isVertical: root.vertical
            dockContent: root.context
            delegateIndex: root.itemIndex
            members: root.context?.live?.widgetStackMembers ?? []
            currentType: root.context?.live?.widgetStackCurrentType ?? ""
        }
    }
    Component {
        id: utilityComponent
        Item {
            UtilityPreview {
                anchors.centerIn: parent
                kind: root.itemData.kind ?? ""
                // A side dock stacks every tile square.
                wide: (root.itemData.wide ?? false) && !root.vertical
                width: implicitWidth
                height: implicitHeight
            }
        }
    }
}
