pragma ComponentBehavior: Bound

import qs.modules.common

// Taskbar-sized brand glyph. The overlay taskbar renders this through the
// generic `iconComponent` hook on an OverlayContext registry entry and binds
// `toggled`; keeping the Discord-specific colours here means the shared
// taskbar never has to know which widget it is drawing.
DiscordGlyph {
    id: root

    property bool toggled: false

    implicitSize: 28
    iconSize: 16
    color: root.toggled ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    iconColor: root.toggled
        ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
}
