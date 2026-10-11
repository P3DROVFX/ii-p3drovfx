// ii-p3drovfx login screen: the shell's lock screen, rebuilt for SDDM.
// Colours, wallpaper, fonts and lock-look settings come from theme.conf.user,
// which the shell keeps in sync (see sddm/README.md in the shell's config).
import QtQuick
import "components"

Item {
    id: root

    // One instance per screen; SDDM sizes the root to its screen.
    width: 1920
    height: 1080

    Binding {
        target: Theme
        property: "cfg"
        value: config
    }

    Backdrop {
        id: backdrop
        anchors.fill: parent
        Component.onCompleted: active = true
    }

    LoginSurface {
        id: surface
        anchors.fill: parent
        focus: true
        opacity: 1
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.ms(200)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveEffects
            }
        }
        onLoginSucceeded: {
            surface.opacity = 0;
            backdrop.active = false;
        }
    }
}
