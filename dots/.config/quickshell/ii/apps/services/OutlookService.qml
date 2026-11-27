pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Slim OutlookService stand-in for standalone apps.
 */
Singleton {
    id: root

    property bool authenticated: false
    property bool authenticating: false
    property string clientId: ""
    property bool deviceFlowActive: false
    property string deviceMessage: ""
    property string lastError: ""
    property string userCode: ""
    property string verificationUri: ""

    function beginAuthorization(clientId) {}
    function disconnect() {}
}
