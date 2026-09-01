pragma Singleton
import Quickshell
import qs

/**
 * How the bar is *operated*, as opposed to where it sits (see BarPlacement).
 *
 * The bar's default behaviour assumes a pointer: popups follow hover intent and the
 * bar can hide until the cursor reaches the screen edge. Neither survives contact
 * with a finger — there is no hover to read, and a bar that is off-screen until you
 * touch where it used to be is unusable. A touch-first family therefore pins these
 * regardless of what the user's stored bar preferences say, exactly as BarPlacement
 * pins the position, and Settings keeps showing the stored preference untouched.
 */
Singleton {
    id: root

    // Popups open on tap and stay until dismissed, instead of tracking the pointer.
    readonly property bool clickToShow: PanelFamily.touchFirst
        || (Config.options?.bar?.tooltips?.clickToShow ?? false)

    // The bar's buttons reach their panels through these popups. Turning them off on a
    // touch-first family would leave inert buttons and no other way in, so the preference
    // only applies where a pointer can also right-click, hover or use a keybind.
    readonly property bool enablePopups: PanelFamily.touchFirst
        || (Config.options?.bar?.tooltips?.enablePopups ?? true)

    // Hover-to-reveal auto-hide. A touch-first bar is always seated.
    readonly property bool autoHide: !PanelFamily.touchFirst
        && (Config.options?.bar?.autoHide?.enable ?? false)
}
