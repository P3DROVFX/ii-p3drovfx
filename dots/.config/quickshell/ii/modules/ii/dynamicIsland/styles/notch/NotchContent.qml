pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.overview

/**
 * Draws whichever activity the notch is showing.
 *
 * Two things are deliberate here.
 *
 * The loader's `source` follows the *activity*, not the presentation: the legacy widgets
 * each render both states from an `isExpanded` property, and reloading them on expand
 * would restart their internal state - the album art state machine being the expensive
 * one. So expanding rebinds a property and never rebuilds anything.
 *
 * And the resting face is drawn here rather than loaded: a clock needs no file, and the
 * old panel's "home" widget was three lines of layout that cost a Loader.
 */
Item {
    id: content

    required property string activityId
    required property bool expanded
    required property var controller

    readonly property string sourcePath: IslandRegistry.legacyContentFor(content.activityId)
    readonly property bool hasWidget: content.sourcePath !== ""

    readonly property bool isSearch: content.activityId === "search"
    readonly property bool isOsd: content.activityId === "osd"

    /** The live search widget, so the surface can size itself to its results. */
    readonly property Item searchItem: searchLoader.item
    readonly property real searchImplicitWidth: searchLoader.item ? searchLoader.item.implicitWidth : 0
    readonly property real searchImplicitHeight: searchLoader.item ? searchLoader.item.implicitHeight : 0

    function focusSearch() {
        if (searchLoader.item)
            searchLoader.item.focusSearchInput();
    }

    function cancelSearch() {
        if (searchLoader.item)
            searchLoader.item.cancelSearch();
    }

    // Content changing is a morph, not a cut: the outgoing state fades and shrinks
    // slightly while the incoming one arrives, which is what makes the island read as
    // one object changing rather than two widgets swapping.
    opacity: 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(content)
    }

    Loader {
        id: widgetLoader

        anchors.centerIn: parent
        width: parent.width
        height: parent.height

        active: content.hasWidget && !content.isSearch && !content.isOsd
        source: content.sourcePath

        // Rebinding rather than reloading; see above.
        Binding {
            target: widgetLoader.item && widgetLoader.item.hasOwnProperty("isExpanded") ? widgetLoader.item : null
            property: "isExpanded"
            value: content.expanded
        }

        // Some widgets lay themselves out differently when they are one of several.
        // With a single slot there is always exactly one.
        Binding {
            target: widgetLoader.item && widgetLoader.item.hasOwnProperty("panelWidgetsCount") ? widgetLoader.item : null
            property: "panelWidgetsCount"
            value: 1
        }

        Binding {
            target: widgetLoader.item && widgetLoader.item.hasOwnProperty("isDragOverNotch") ? widgetLoader.item : null
            property: "isDragOverNotch"
            value: content.controller.sources.localSend.dragHovering
        }

        opacity: 0
        scale: 0.96
        onLoaded: {
            widgetLoader.opacity = 1;
            widgetLoader.scale = 1;
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(widgetLoader)
        }
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMoveSmall.duration
                easing.type: Easing.OutBack
                easing.overshoot: 0.5
            }
        }
    }

    // ── Search ───────────────────────────────────────────────────────────────
    // Kept loaded across a close so the query and the result list survive being
    // dismissed and reopened, which is what the launcher has always done.
    Loader {
        id: searchLoader
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: searchLoader.item ? searchLoader.item.implicitWidth : parent.width

        active: Config.ready
        visible: content.isSearch
        opacity: content.isSearch ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(searchLoader)
        }

        sourceComponent: SearchWidget {
            inNotchMode: true
        }

        onVisibleChanged: {
            if (!searchLoader.visible || !searchLoader.item)
                return;
            // A query handed over by another surface (a keybind, the bar) opens with that
            // text already in place instead of an empty field.
            if (GlobalStates.activeSearchQuery) {
                searchLoader.item.setSearchingText(GlobalStates.activeSearchQuery);
                GlobalStates.activeSearchQuery = "";
            } else {
                searchLoader.item.cancelSearch();
            }
            Qt.callLater(() => searchLoader.item.focusSearchInput());
        }
    }

    // ── OSD ──────────────────────────────────────────────────────────────────
    Loader {
        id: osdLoader
        anchors.fill: parent
        active: content.isOsd
        source: {
            if (!content.isOsd)
                return "";
            const indicators = {
                "volume": "VolumeIndicator.qml",
                "brightness": "BrightnessIndicator.qml",
                "playerVolume": "PlayerVolumeIndicator.qml",
                "gamma": "GammaIndicator.qml",
                "keyboardBrightness": "KeyboardBrightnessIndicator.qml"
            };
            const file = indicators[GlobalStates.osdCurrentIndicator];
            if (!file)
                return "";
            return Quickshell.shellPath("modules/ii/topLayer/osd/indicators/" + file);
        }
    }

    // The resting face.
    RowLayout {
        anchors.centerIn: parent
        spacing: 6
        visible: !content.hasWidget && !content.isSearch && !content.isOsd

        MaterialSymbol {
            text: "water_drop"
            iconSize: 14
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            text: "ii"
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.bold: true
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
