pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Slim Weather stand-in for standalone apps: reads cached forecast data if
 * present, with zero network polling or notifications.
 */
Singleton {
    id: root

    readonly property bool useUSCS: Config.options?.weather?.useUSCS ?? false
    property var forecastData: []
}
