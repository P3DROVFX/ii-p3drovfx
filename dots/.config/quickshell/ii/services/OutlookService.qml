pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Microsoft Entra authentication shared by Outlook calendar and mail bridges.
 *
 * This is deliberately a public-client device flow: the user supplies an app
 * id, while refresh tokens stay in the existing Secret Service keyring. A
 * desktop configuration cannot keep an application client secret private.
 */
Singleton {
    id: root

    readonly property list<string> scopes: ["offline_access", "User.Read", "Calendars.Read", "Mail.Read"]
    readonly property string helperPath: Directories.scriptPath + "/outlook/auth.py"
    readonly property bool configured: root.clientId.length > 0
    readonly property bool authenticated: root.refreshToken.length > 0 && !root.reauthorizationRequired
    readonly property bool deviceFlowActive: root.deviceCode.length > 0
    readonly property bool authenticating: deviceCodeProcess.running || deviceTokenProcess.running || root.deviceFlowActive
    readonly property bool refreshing: tokenRefreshProcess.running

    property string clientId: ""
    property string refreshToken: ""
    property string accessToken: ""
    property int accessTokenExpiry: 0
    property string activeAccountEmail: ""
    property bool reauthorizationRequired: false
    property string lastError: ""
    property string deviceCode: ""
    property string userCode: ""
    property string verificationUri: ""
    property string deviceMessage: ""
    property int devicePollIntervalSeconds: 5
    property var tokenCallbacks: []

    function _loadStoredAccount() {
        if (!KeyringStorage.loaded || !KeyringStorage.keyringData)
            return;
        const stored = KeyringStorage.keyringData.outlook_timetable ?? ({});
        root.clientId = String(stored.clientId ?? "").trim();
        root.refreshToken = String(stored.refreshToken ?? "");
        root.activeAccountEmail = String(stored.email ?? "").trim().toLowerCase();
    }

    function _storeAccount() {
        KeyringStorage.setNestedField(["outlook_timetable"], {
            clientId: root.clientId,
            refreshToken: root.refreshToken,
            email: root.activeAccountEmail
        });
    }

    function setClientId(value) {
        const next = String(value ?? "").trim();
        if (!next || next.length > 200 || /\s/.test(next)) {
            root.lastError = Translation.tr("Enter a valid Microsoft application (client) ID.");
            return false;
        }
        if (root.clientId !== next) {
            root.clientId = next;
            root.refreshToken = "";
            root.accessToken = "";
            root.accessTokenExpiry = 0;
            root.activeAccountEmail = "";
            root.reauthorizationRequired = false;
        }
        root.lastError = "";
        root._storeAccount();
        return true;
    }

    function disconnect() {
        root.cancelDeviceFlow();
        root.refreshToken = "";
        root.accessToken = "";
        root.accessTokenExpiry = 0;
        root.activeAccountEmail = "";
        root.reauthorizationRequired = false;
        root.lastError = "";
        root._storeAccount();
    }

    function beginAuthorization(value = root.clientId) {
        if (root.authenticating)
            return false;
        if (!root.setClientId(value))
            return false;
        root.lastError = "";
        deviceCodeProcess.responseText = "";
        deviceCodeProcess.stdinEnabled = true;
        deviceCodeProcess.running = true;
        return true;
    }

    function cancelDeviceFlow() {
        devicePollTimer.stop();
        root.deviceCode = "";
        root.userCode = "";
        root.verificationUri = "";
        root.deviceMessage = "";
    }

    function hasValidAccessToken() {
        return root.accessToken.length > 0 && Math.floor(Date.now() / 1000) < root.accessTokenExpiry - 30;
    }

    /** Invoke callback with a fresh Graph token, or an empty string on failure. */
    function withAccessToken(callback) {
        if (typeof callback !== "function")
            return false;
        if (root.hasValidAccessToken()) {
            callback(root.accessToken);
            return true;
        }
        if (!root.authenticated || !root.configured) {
            callback("");
            return false;
        }
        root.tokenCallbacks = root.tokenCallbacks.concat([callback]);
        if (!tokenRefreshProcess.running) {
            tokenRefreshProcess.responseText = "";
            tokenRefreshProcess.stdinEnabled = true;
            tokenRefreshProcess.running = true;
        }
        return true;
    }

    function updateAccountEmail(email) {
        const normalized = String(email ?? "").trim().toLowerCase();
        if (!normalized || normalized === root.activeAccountEmail)
            return;
        root.activeAccountEmail = normalized;
        root._storeAccount();
    }

    function _consumeTokenReply(text, pendingAllowed = false) {
        let reply;
        try {
            reply = JSON.parse(String(text ?? "").trim());
        } catch (error) {
            root.lastError = Translation.tr("Microsoft authorization returned an unreadable response.");
            return { ok: false };
        }
        if (!reply?.ok) {
            const code = String(reply?.code ?? "");
            if (pendingAllowed && (code === "authorization_pending" || code === "slow_down")) {
                if (code === "slow_down")
                    root.devicePollIntervalSeconds = Math.min(30, root.devicePollIntervalSeconds + 5);
                return { ok: false, pending: true };
            }
            root.lastError = String(reply?.message ?? Translation.tr("Microsoft authorization failed."));
            if (code === "invalid_grant" || code === "expired_token" || code === "authorization_declined") {
                root.reauthorizationRequired = true;
                root.cancelDeviceFlow();
            }
            return { ok: false };
        }
        root.accessToken = String(reply.accessToken ?? "");
        root.accessTokenExpiry = Math.floor(Date.now() / 1000) + Number(reply.expiresIn ?? 3600);
        const nextRefresh = String(reply.refreshToken ?? "");
        if (nextRefresh.length > 0)
            root.refreshToken = nextRefresh;
        root.reauthorizationRequired = false;
        root.lastError = "";
        root._storeAccount();
        return { ok: root.accessToken.length > 0 };
    }

    function _finishRefresh() {
        const callbacks = root.tokenCallbacks;
        root.tokenCallbacks = [];
        const token = root.hasValidAccessToken() ? root.accessToken : "";
        for (let index = 0; index < callbacks.length; ++index)
            callbacks[index](token);
    }

    Component.onCompleted: root._loadStoredAccount()

    Connections {
        target: KeyringStorage

        function onLoadedChanged() {
            if (KeyringStorage.loaded)
                root._loadStoredAccount();
        }
    }

    Process {
        id: deviceCodeProcess

        command: ["python3", root.helperPath, "device-code"]
        stdinEnabled: true
        property string responseText: ""

        onRunningChanged: {
            if (!running)
                return;
            write(JSON.stringify({ clientId: root.clientId, scopes: root.scopes }) + "\n");
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: deviceCodeProcess.responseText = text.trim()
        }

        onExited: exitCode => {
            let reply;
            try {
                reply = JSON.parse(deviceCodeProcess.responseText);
            } catch (error) {
                reply = { ok: false, message: Translation.tr("Microsoft sign-in could not start.") };
            }
            if (exitCode !== 0 || !reply?.ok) {
                root.lastError = String(reply?.message ?? Translation.tr("Microsoft sign-in could not start."));
                return;
            }
            root.deviceCode = String(reply.deviceCode ?? "");
            root.userCode = String(reply.userCode ?? "");
            root.verificationUri = String(reply.verificationUri ?? "");
            root.deviceMessage = String(reply.message ?? "");
            root.devicePollIntervalSeconds = Math.max(2, Number(reply.interval ?? 5));
            if (!root.deviceCode || !root.verificationUri) {
                root.lastError = Translation.tr("Microsoft sign-in returned incomplete instructions.");
                root.cancelDeviceFlow();
                return;
            }
            devicePollTimer.restart();
        }
    }

    Timer {
        id: devicePollTimer

        interval: root.devicePollIntervalSeconds * 1000
        repeat: true
        running: root.deviceFlowActive
        onTriggered: {
            if (deviceTokenProcess.running || !root.deviceFlowActive)
                return;
            deviceTokenProcess.responseText = "";
            deviceTokenProcess.stdinEnabled = true;
            deviceTokenProcess.running = true;
        }
    }

    Process {
        id: deviceTokenProcess

        command: ["python3", root.helperPath, "poll"]
        stdinEnabled: true
        property string responseText: ""

        onRunningChanged: {
            if (!running)
                return;
            write(JSON.stringify({ clientId: root.clientId, deviceCode: root.deviceCode }) + "\n");
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: deviceTokenProcess.responseText = text.trim()
        }

        onExited: exitCode => {
            const result = root._consumeTokenReply(deviceTokenProcess.responseText, true);
            if (result.ok)
                root.cancelDeviceFlow();
            else if (!result.pending && exitCode !== 0 && !root.lastError)
                root.lastError = Translation.tr("Microsoft sign-in could not finish.");
        }
    }

    Process {
        id: tokenRefreshProcess

        command: ["python3", root.helperPath, "refresh"]
        stdinEnabled: true
        property string responseText: ""

        onRunningChanged: {
            if (!running)
                return;
            write(JSON.stringify({ clientId: root.clientId, refreshToken: root.refreshToken, scopes: root.scopes }) + "\n");
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: tokenRefreshProcess.responseText = text.trim()
        }

        onExited: exitCode => {
            root._consumeTokenReply(tokenRefreshProcess.responseText);
            if (exitCode !== 0 && !root.lastError)
                root.lastError = Translation.tr("Microsoft token refresh failed.");
            root._finishRefresh();
        }
    }
}
