import QtQuick
import Quickshell

/**
 * The home screen's non-visual half: the gesture that moves between workspaces.
 *
 * The icons themselves are not here. They are injected into the desktop widget canvas by
 * the composition root — see TabletHomeIconsLayer for why they cannot be a surface of
 * their own.
 */
Scope {
    TabletWorkspaceDragHandler {}
}
