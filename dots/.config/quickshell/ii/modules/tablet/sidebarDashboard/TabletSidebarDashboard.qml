import QtQuick
import Quickshell

import qs.modules.common

Scope {
    id: root

    Variants {
        id: screenVariants
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            // Held back until Config is readable: the shade decides between a blurred backdrop
            // and a plain opaque surface from the transparency setting, and Config loads async.
            Loader {
                active: Config.ready
                sourceComponent: shadeWindowComponent
            }

            Component {
                id: shadeWindowComponent
                TabletShadeWindow {
                    screen: screenScope.modelData
                }
            }
        }
    }
}
