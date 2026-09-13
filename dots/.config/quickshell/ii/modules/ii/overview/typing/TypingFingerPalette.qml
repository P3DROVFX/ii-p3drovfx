pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root
    // Functional categories keep their hue across theme changes; the existing
    // category helper derives the container tone from Material You. Numbers
    // and full finger names also carry the meaning when hues are hard to tell.
    readonly property var fills: [
        Appearance.m3colors.m3surfaceContainerHigh,
        Appearance.colors.colSecondaryContainer,
        ColorUtils.categoryContainer(325, Appearance.colors.colPrimaryContainer, 0.28),
        ColorUtils.categoryContainer(205, Appearance.colors.colPrimaryContainer, 0.32),
        ColorUtils.categoryContainer(65, Appearance.colors.colPrimaryContainer, 0.38),
        ColorUtils.categoryContainer(140, Appearance.colors.colPrimaryContainer, 0.28)
    ]
    readonly property var inks: root.fills.map(fill => ColorUtils.mostReadable(fill,
        [Appearance.colors.colOnSurface, Appearance.colors.colOnPrimaryContainer, Appearance.colors.colOnPrimary]))

    function kind(finger: int): int { return finger === 6 ? 1 : Math.abs(finger); }
    function fill(finger: int): color { return root.fills[root.kind(finger)] ?? root.fills[0]; }
    function ink(finger: int): color { return root.inks[root.kind(finger)] ?? root.inks[0]; }
    function name(finger: int): string {
        switch (finger) {
        case -5: return Translation.tr("Left little finger");
        case -4: return Translation.tr("Left ring finger");
        case -3: return Translation.tr("Left middle finger");
        case -2: return Translation.tr("Left index finger");
        case -1: return Translation.tr("Left thumb");
        case 1: return Translation.tr("Right thumb");
        case 2: return Translation.tr("Right index finger");
        case 3: return Translation.tr("Right middle finger");
        case 4: return Translation.tr("Right ring finger");
        case 5: return Translation.tr("Right little finger");
        case 6: return Translation.tr("Either thumb");
        default: return Translation.tr("Unassigned finger");
        }
    }
}
