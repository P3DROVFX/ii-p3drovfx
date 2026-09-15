pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root

    readonly property bool bouncy: Config?.options.lunae.bouncyAnimations ?? false

    readonly property list<real> drawerOpenCurve: bouncy
        ? Appearance.animationCurves.expressiveDefaultSpatial
        : Appearance.animationCurves.emphasized

    readonly property list<real> popupCurve: bouncy
        ? Appearance.animationCurves.expressiveDefaultSpatial
        : Appearance.animationCurves.emphasized

    readonly property list<real> notifExpansionCurve: bouncy
        ? Appearance.animationCurves.expressiveFastSpatial
        : Appearance.animationCurves.emphasized
    readonly property int notifExpansionDuration: bouncy ? 350 : 300

    readonly property list<real> closeCurve: Appearance.animationCurves.emphasized

    readonly property int drawerOpenDuration: Appearance.animationCurves.expressiveDefaultSpatialDuration
    readonly property int drawerCloseDuration: 400
    readonly property int popupDuration: Appearance.animationCurves.expressiveDefaultSpatialDuration

    readonly property list<real> morphCurve: bouncy
        ? Appearance.animationCurves.expressiveFastSpatial
        : Appearance.animationCurves.emphasized
    readonly property int morphDuration: bouncy ? 350 : 200

    readonly property QtObject osd: QtObject {
        readonly property int duration: bouncy ? 350 : 200
        readonly property int easingType: bouncy ? Easing.BezierSpline : Easing.OutCubic
        readonly property list<real> curve: Appearance.animationCurves.expressiveFastSpatial
    }

    readonly property QtObject rounding: QtObject {
        readonly property real armpit: Appearance.rounding.medlarge
        readonly property real panelLarge: Appearance.rounding.medlarge
        readonly property real panelNested: 20
        readonly property real panelSmall: Appearance.rounding.normal
    }
}
