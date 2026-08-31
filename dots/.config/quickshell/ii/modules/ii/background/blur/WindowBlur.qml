import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF

Item {
    id: windowBlurRoot

    required property var sourceItem
    // False until the wallpaper plane has its final size and the image has decoded. The capture
    // below is taken once and never retaken, so activating before then bakes in a texture that no
    // longer matches the plane - the wallpaper then shows a hard-edged sharp band next to the
    // blurred one for the rest of the effect's life.
    required property bool sourceReady
    required property bool hasWindowsInActiveWorkspace

    readonly property real sourceWidth: sourceItem ? sourceItem.width : 0
    readonly property real sourceHeight: sourceItem ? sourceItem.height : 0

    // Overview (and the plain search bar behind Super) deliberately does NOT clear the blur: the
    // wallpaper stays blurred underneath. This item sits below the overview dim layer, so the
    // overview's own dim/scale still composes on top of the blurred wallpaper.
    readonly property bool shouldBlur: Config.options.background.blurWhenWindowsOpen
        && hasWindowsInActiveWorkspace && !GlobalStates.screenLocked
        && sourceReady && sourceWidth > 0 && sourceHeight > 0

    // Keep the Loader binding intact while still allowing a fresh grab once the plane's geometry
    // settles.
    property bool reloadRequested: false
    readonly property bool desiredBlurActive: shouldBlur && !reloadRequested

    function refreshBlur() {
        if (!desiredBlurActive)
            return;
        reloadRequested = true;
        Qt.callLater(function() {
            windowBlurRoot.reloadRequested = false;
        });
    }

    // The Loader below activates the instant shouldBlur flips true, which can be before
    // sourceItem's layout has settled (e.g. right as a window opens). MultiEffect's implicit
    // ShaderEffectSource grabs sourceItem at whatever size it has *at that moment*, then
    // stretches that texture to fill the final geometry once layout catches up — producing a
    // squashed/stretched wallpaper. Force a rebuild shortly after activation so it re-grabs
    // once layout has settled.
    onShouldBlurChanged: if (shouldBlur) refreshBlur();

    // The plane itself resizes whenever the wallpaper's real dimensions, the screen geometry or
    // the zoom scale land - all of which happen after startup, and none of which reach the
    // capture on their own. Debounced, so a burst of them costs one rebuild.
    onSourceWidthChanged: blurRefreshTimer.restart();
    onSourceHeightChanged: blurRefreshTimer.restart();

    // The fade tracks shouldBlur, never the one-frame rebuild: a rebuild that restarted the fade
    // read as the blur falling away and creeping back every time it ran (once per workspace
    // switch, which is what made switching workspaces flash the sharp wallpaper).
    visible: windowBlurRoot.desiredBlurActive
    opacity: windowBlurRoot.shouldBlur ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    // GPU: Loader only instantiates the expensive MultiEffect when blur is actually needed.
    // Previously the MultiEffect (blurMax:64 shader + texture allocation) was always resident
    // in the scene graph even when source was null at idle.
    Loader {
        id: blurEffectLoader
        anchors.fill: parent
        active: windowBlurRoot.desiredBlurActive
        sourceComponent: MultiEffect {
            anchors.fill: parent
            source: windowBlurRoot.sourceItem
            blurEnabled: true
            blurMax: 64
            blur: Config.options.background.blurWhenWindowsOpenRadius / 100.0

            Rectangle {
                anchors.fill: parent
                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
            }
        }
    }

    Timer {
        id: blurRefreshTimer
        interval: 100
        repeat: false
        onTriggered: {
            windowBlurRoot.refreshBlur();
        }
    }
}
