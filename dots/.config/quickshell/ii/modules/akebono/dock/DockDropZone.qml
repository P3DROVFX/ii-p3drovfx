pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: zone
    anchors.fill: parent

    required property var dock
    required property var surface
    required property var dropTarget
    property real edgeSlack: 0
    property bool topMode: false
    signal rippleRequested(real localX, real amp, real dur)

    property string dropCloneAppId: ""
    property real dropCloneFall: 0
    property real dropCloneOpacity: 1
    property real dropTargetX: 0
    property real dropTargetY: 0
    property real pendingDropLeftX: 0
    property real nopeProgress: 0
    property real nopeX: 0
    property real nopeBarY: 0

    function dropOnDock(leftX, appIds, winX, dockTopY) {
        if (!zone.dock)
            return;
        if (appIds.length === 0) {
            zone.nopeX = winX;
            zone.nopeBarY = dockTopY;
            nopeAnim.restart();
            return;
        }
        for (let i = 1; i < appIds.length; i++)
            zone.dock.pinAt(leftX, appIds[i]);
        const appId = appIds[0];
        const center = zone.dock.slotCenterFor(leftX, appId);
        const w = zone.dock.mapToItem(null, center, zone.dock.height / 2);
        zone.pendingDropLeftX = leftX;
        zone.dropTargetX = w.x;
        zone.dropTargetY = w.y;
        zone.dropCloneOpacity = 1;
        zone.dropCloneAppId = appId;
        dropFallAnim.restart();
    }

    DropArea {
        parent: zone.dropTarget
        anchors.fill: parent
        onDropped: drop => {
            if (drop.formats.indexOf("application/x-desktop-icon") < 0 || !zone.dock)
                return;
            let m;
            try {
                m = JSON.parse(drop.getDataAsString("application/x-desktop-icon"));
            } catch (e) {
                return;
            }
            const local = mapToItem(zone.dock, drop.x, drop.y);
            if (local.x < -zone.edgeSlack || local.x > zone.dock.width + zone.edgeSlack)
                return;
            drop.accept();
            const winPt = mapToItem(null, drop.x, drop.y);
            const dockTop = zone.dock.mapToItem(null, 0, 0).y;
            zone.dropOnDock(local.x, m.appIds ?? [], winPt.x, dockTop);
        }
    }

    NumberAnimation {
        id: dropFallAnim
        target: zone
        property: "dropCloneFall"
        from: 0
        to: 1
        duration: 340
        easing.type: Easing.InQuad
        onFinished: {
            if (!zone.dock) {
                zone.dropCloneAppId = "";
                return;
            }
            const center = zone.dock.pinAt(zone.pendingDropLeftX, zone.dropCloneAppId);
            zone.rippleRequested(zone.surface.mapFromItem(zone.dock, center, 0).x, 34, 950);
            cloneFadeAnim.restart();
        }
    }
    NumberAnimation {
        id: cloneFadeAnim
        target: zone
        property: "dropCloneOpacity"
        from: 1
        to: 0
        duration: 150
        onFinished: zone.dropCloneAppId = ""
    }
    NumberAnimation {
        id: nopeAnim
        target: zone
        property: "nopeProgress"
        from: 0
        to: 1
        duration: 1100
    }

    Item {
        id: dropClone
        visible: zone.dropCloneAppId !== ""
        width: zone.dock?.iconSize ?? 40
        height: zone.dock?.iconSize ?? 40
        x: zone.dropTargetX - width / 2
        y: zone.dropTargetY - height / 2 + (zone.topMode ? 1 : -1) * (1 - zone.dropCloneFall) * 130
        opacity: zone.dropCloneOpacity
        z: 10

        IconImage {
            anchors.fill: parent
            source: Quickshell.iconPath(AppSearch.guessIcon(zone.dropCloneAppId), "image-missing")
        }
    }

    Item {
        id: nope
        readonly property real p: zone.nopeProgress
        visible: p > 0 && p < 1
        width: nopeRow.implicitWidth
        height: nopeRow.implicitHeight
        transformOrigin: Item.Center
        x: zone.nopeX - width / 2 + p * 80
        y: zone.topMode ? (zone.nopeBarY + (zone.dock?.height ?? 0) + p * 120) : (zone.nopeBarY - height - p * 120)
        opacity: Math.sin(p * Math.PI)
        scale: 0.7 + p * 0.7
        rotation: -10
        z: 11

        Row {
            id: nopeRow
            spacing: -8
            NopeText { prog: nope.p; text: "Nope"; color: Appearance.m3colors.m3background }
            NopeText { prog: nope.p; text: "!"; color: Appearance.colors.colError }
        }
    }

    component NopeText: StyledText {
        id: nt
        property real prog: 0
        font.family: Appearance.font.family.main
        font.styleName: ""
        font.variableAxes: ({ "ROND": 100, "wght": 800 })
        font.pixelSize: 42
        padding: 4
        layer.enabled: true
        layer.smooth: true
        layer.effect: ShaderEffect {
            property real phase: nt.prog * 8.0
            property real amp: 0.4
            property real freq: 10.0
            property vector2d invSize: Qt.vector2d(1.0 / Math.max(1, width), 1.0 / Math.max(1, height))
            fragmentShader: Quickshell.shellPath("assets/shaders/akebono/textripple.frag.qsb")
        }
    }
}
