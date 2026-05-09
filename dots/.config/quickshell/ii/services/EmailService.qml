pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import QtCore

Singleton {
    id: root

    signal attachmentDownloadFinished(string attachmentId, bool success, string path)
    signal emailSent(bool success, string errorMsg)

    // public state
    property bool authenticated: false
    property bool loading: false
    property bool sendingEmail: false
    property string userEmail: ""
    property string userAvatar: ""
    property string currentEmailBody: ""
    property string currentEmailHtmlPath: ""
    property bool loadingEmailBody: false
    property ListModel currentEmailAttachments: ListModel {}

    property int maxEmails: 20
    property string historyId: ""
    property bool enableUpdates: false
    property bool enablePromotions: false
    property bool enableSocials: false
    property int refreshIntervalMinutes: 1
    property bool compactMode: false
    property bool stackingEnabled: true
    property bool authenticating: false
    property var enabledLabels: []
    property bool enableStarred: false
    property bool enableImportant: false
    property bool enablePurchases: false
    property bool enableSpam: true
    property bool enableSent: true
    property bool enableTrash: false
    property bool enableUnreadBadges: false
    property bool showSnippets: true
    property bool showAvatars: true
    property bool confirmDelete: true
    property int bodyFontSize: 14
    property bool semanticTimestampsEnabled: true
    property bool autoMarkAsRead: true
    property var navOrder: [
        {
            tab: "inbox",
            icon: "inbox",
            label: "Inbox"
        },
        {
            tab: "starred",
            icon: "star",
            label: "Starred"
        },
        {
            tab: "sent",
            icon: "send",
            label: "Sent"
        },
        {
            tab: "trash",
            icon: "delete",
            label: "Trash"
        },
        {
            tab: "spam",
            icon: "report",
            label: "Spam"
        },
        {
            tab: "important",
            icon: "label_important",
            label: "Important"
        },
        {
            tab: "purchases",
            icon: "shopping_cart",
            label: "Purchases"
        }
    ]

    // Compose draft state
    property string composeDraftTo: ""
    property string composeDraftSubject: ""
    property string composeDraftBody: ""
    property var composeDraftAttachments: []
    property bool credentialsConfigured: false

    function checkCredentials() {
        credentialsChecker.running = true;
    }

    function formatRelativeDate(timestamp) {
        if (!timestamp)
            return "";

        let date = new Date(timestamp * 1000);
        let today = new Date();

        if (!root.semanticTimestampsEnabled) {
            if (date.toDateString() === today.toDateString()) {
                return date.toLocaleTimeString(Qt.locale(), "HH:mm");
            }
            return date.toLocaleDateString(Qt.locale(), "MMM d");
        }

        let now = Math.floor(Date.now() / 1000);
        let diff = now - timestamp;

        if (diff < 0)
            return "Just now"; // Clock skew
        if (diff < 60)
            return "Just now";
        if (diff < 3600)
            return Math.floor(diff / 60) + "m ago";
        if (diff < 86400)
            return Math.floor(diff / 3600) + "h ago";
        if (diff < 172800)
            return "Yesterday";

        if (date.getFullYear() === today.getFullYear()) {
            return date.toLocaleDateString(Qt.locale(), "MMM d");
        }
        return date.toLocaleDateString(Qt.locale(), "MMM d, yyyy");
    }
    Process {
        id: credentialsChecker
        command: ["python3", Directories.scriptPath + "/email/check_credentials.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.credentialsConfigured = data.configured;
                    root.credentialsCheckFailed = !data.configured;
                } catch (e) {
                    root.credentialsConfigured = false;
                    root.credentialsCheckFailed = true;
                }
            }
        }
    }

    property bool checkingCredentials: credentialsChecker.running
    property bool credentialsCheckFailed: false

    onMaxEmailsChanged: _startDebouncedSync()
    onEnableUpdatesChanged: _startDebouncedSync()
    onEnablePromotionsChanged: _startDebouncedSync()
    onEnableSocialsChanged: _startDebouncedSync()
    onEnableStarredChanged: _startDebouncedSync()
    onEnableImportantChanged: _startDebouncedSync()
    onEnablePurchasesChanged: _startDebouncedSync()
    onEnableSpamChanged: _startDebouncedSync()
    onEnableSentChanged: _startDebouncedSync()
    onEnableTrashChanged: _startDebouncedSync()
    onRefreshIntervalMinutesChanged: {
        _startDebouncedSync();
        if (autoRefreshTimer.running) {
            autoRefreshTimer.restart();
        }
    }

    Timer {
        id: debounceSyncTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.authenticated)
                root.syncAll();
        }
    }

    Timer {
        id: autoRefreshTimer
        interval: root.refreshIntervalMinutes * 60 * 1000
        running: root.authenticated && root.refreshIntervalMinutes > 0
        repeat: true
        onTriggered: {
            console.log("[Gmail] Auto-refresh Timer Triggered! Interval:", interval, "ms");
            root.syncAll();
        }
    }

    Timer {
        id: retryRefreshTimer
        interval: 15000 // 15 seconds
        repeat: false
        onTriggered: {
            if (!root.authenticated && root._refreshToken !== "") {
                console.log("[Gmail] Retrying token refresh...");
                root._refreshAndFetch();
            }
        }
    }

    Connections {
        target: Network
        function onWifiStatusChanged() {
            if (Network.wifiStatus === "connected" && !root.authenticated && root._refreshToken !== "") {
                console.log("[Gmail] Network connected, retrying refresh...");
                root._refreshAndFetch();
            }
        }
    }

    Settings {
        id: emailSettings
        category: "EmailService"
        property alias maxEmails: root.maxEmails
        property alias enableUpdates: root.enableUpdates
        property alias enablePromotions: root.enablePromotions
        property alias enableSocials: root.enableSocials
        property alias refreshIntervalMinutes: root.refreshIntervalMinutes
        property alias enabledLabels: root.enabledLabels
        property alias enableStarred: root.enableStarred
        property alias enableImportant: root.enableImportant
        property alias enablePurchases: root.enablePurchases
        property alias enableSpam: root.enableSpam
        property alias enableSent: root.enableSent
        property alias enableTrash: root.enableTrash
        property alias enableUnreadBadges: root.enableUnreadBadges
        property alias compactMode: root.compactMode
        property alias stackingEnabled: root.stackingEnabled
        property alias historyId: root.historyId
        property alias showSnippets: root.showSnippets
        property alias showAvatars: root.showAvatars
        property alias confirmDelete: root.confirmDelete
        property alias bodyFontSize: root.bodyFontSize
        property alias autoMarkAsRead: root.autoMarkAsRead
        property alias navOrder: root.navOrder
        property alias credentialsConfigured: root.credentialsConfigured

        // Draft persistence
        property alias composeDraftTo: root.composeDraftTo
        property alias composeDraftSubject: root.composeDraftSubject
        property alias composeDraftBody: root.composeDraftBody
        property alias composeDraftAttachments: root.composeDraftAttachments
    }

    function _startDebouncedSync() {
        if (!authenticated)
            return;
        debounceSyncTimer.restart();
    }

    property ListModel inboxMessages: ListModel {}
    property ListModel sentMessages: ListModel {}
    property ListModel spamMessages: ListModel {}
    property ListModel starredMessages: ListModel {}
    property ListModel importantMessages: ListModel {}
    property ListModel purchasesMessages: ListModel {}
    property ListModel trashMessages: ListModel {}
    property ListModel searchMessagesModel: ListModel {}
    property ListModel labels: ListModel {}
    property ListModel currentThreadMessages: ListModel {}

    property int inboxUnreadCount: 0
    property int spamUnreadCount: 0
    property int sentUnreadCount: 0
    property int trashUnreadCount: 0
    property int starredUnreadCount: 0
    property int importantUnreadCount: 0
    property int purchasesUnreadCount: 0
    property var syncingLabels: ({})

    function _getBestToken() {
        let now = Math.floor(Date.now() / 1000);
        if (_accessToken !== "" && now < (_tokenExpiry - 30)) {
            return _accessToken;
        }
        return _refreshToken;
    }

    function decrementUnreadForModel(targetModel) {
        if (targetModel === inboxMessages)
            inboxUnreadCount = Math.max(0, inboxUnreadCount - 1);
        else if (targetModel === spamMessages)
            spamUnreadCount = Math.max(0, spamUnreadCount - 1);
        else if (targetModel === sentMessages)
            sentUnreadCount = Math.max(0, sentUnreadCount - 1);
        else if (targetModel === trashMessages)
            trashUnreadCount = Math.max(0, trashUnreadCount - 1);
        else if (targetModel === starredMessages)
            starredUnreadCount = Math.max(0, starredUnreadCount - 1);
        else if (targetModel === importantMessages)
            importantUnreadCount = Math.max(0, importantUnreadCount - 1);
        else if (targetModel === purchasesMessages)
            purchasesUnreadCount = Math.max(0, purchasesUnreadCount - 1);
    }

    // internal tokens
    property string _accessToken: ""
    property int _tokenExpiry: 0   // epoch seconds
    property string _refreshToken: ""

    // IPC
    IpcHandler {
        target: "gmail"
        function onAuthComplete(refreshToken: string, email: string, picture: string) {
            KeyringStorage.setNestedField(["gmail_refresh_token"], refreshToken);
            KeyringStorage.setNestedField(["gmail_user_email"], email);
            KeyringStorage.setNestedField(["gmail_user_avatar"], picture);
            root.userEmail = email;
            root.userAvatar = picture;
            root._refreshToken = refreshToken;
            root._refreshAndFetch();
        }
        function onTokenRefreshed(accessToken: string, expiresIn: int) {
            root._accessToken = accessToken;
            root._tokenExpiry = Math.floor(Date.now() / 1000) + expiresIn - 60;
            root.authenticated = true;
            root.syncAll();
        }
    }

    // initialization — keyring might not have loaded yet
    Component.onCompleted: {
        root.checkCredentials();
        if (KeyringStorage.loaded) {
            _tryInit();
        }
    }

    Connections {
        target: KeyringStorage
        function onLoadedChanged() {
            if (KeyringStorage.loaded && !root.authenticated)
                root._tryInit();
        }
    }

    function _tryInit() {
        const storedToken = KeyringStorage.keyringData["gmail_refresh_token"];
        const storedEmail = KeyringStorage.keyringData["gmail_user_email"];
        const storedAvatar = KeyringStorage.keyringData["gmail_user_avatar"];

        if (storedEmail) {
            root.userEmail = storedEmail;
        }

        if (storedAvatar) {
            root.userAvatar = storedAvatar;
        }

        if (storedToken && storedToken !== "") {
            _refreshToken = storedToken;
            _refreshAndFetch();
        }
    }

    // public functions
    function startOAuth() {
        if (!credentialsConfigured)
            return;
        authProcess.running = false;
        root.authenticating = true;
        authProcess.running = true;
    }

    function removeAccount() {
        KeyringStorage.setNestedField(["gmail_refresh_token"], "");
        KeyringStorage.setNestedField(["gmail_user_email"], "");
        KeyringStorage.setNestedField(["gmail_user_avatar"], "");
        _accessToken = "";
        _refreshToken = "";
        userEmail = "";
        userAvatar = "";
        authenticated = false;
        inboxMessages.clear();
        sentMessages.clear();
        spamMessages.clear();
        labels.clear();
    }

    function syncAll() {
        const stored = KeyringStorage.keyringData["gmail_refresh_token"];
        if (stored && stored !== "") {
            _refreshToken = stored;
            _refreshAndFetch();
        }
    }

    function _refreshAndFetch() {
        if (_refreshToken === "")
            return;
        loading = true;
        // First refresh the token, then fetch all labels in parallel
        tokenRefresher.command = ["python3", Directories.scriptPath + "/email/token_refresh.py", _refreshToken];
        tokenRefresher.running = true;
    }

    // Token refresh process
    Process {
        id: tokenRefresher
        command: ["echo", ""]
        stdout: StdioCollector {
            id: tokenOutput
            onStreamFinished: {
                if (text.length === 0) {
                    // Don't immediately de-authenticate on empty response, could be network glitch
                    root.loading = false;
                    return;
                }
                try {
                    const data = JSON.parse(text);
                    root._accessToken = data.access_token;
                    root._tokenExpiry = Math.floor(Date.now() / 1000) + data.expires_in - 60;
                    root.authenticated = true;
                    // Now fetch all mailboxes
                    root._startFetchAll();
                } catch (e) {
                    root.authenticated = false;
                    root.loading = false;
                    console.warn("[Gmail] Token parse error:", e);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // Keep authenticated true if we have a refresh token, just stop loading
                root.loading = false;
                if (!root.authenticated) {
                    retryRefreshTimer.start();
                }
            }
        }
    }

    // Fetch processes — one per label
    Process {
        id: authProcess
        command: ["python3", Directories.scriptPath + "/email/oauth_server.py"]
        onRunningChanged: {
            if (!running)
                root.authenticating = false;
        }
    }

    property string _fetchScript: Directories.scriptPath + "/email/fetch_emails.py"

    property var _pageTokens: ({})

    function _getToken(tab, pageIndex) {
        if (!_pageTokens[tab])
            _pageTokens[tab] = [""];
        if (pageIndex < _pageTokens[tab].length)
            return _pageTokens[tab][pageIndex];
        return "";
    }

    function _setNextToken(tab, pageIndex, token) {
        if (!_pageTokens[tab])
            _pageTokens[tab] = [""];
        if (token) {
            _pageTokens[tab][pageIndex + 1] = token;
        } else {
            // If no token returned, remove any future tokens to prevent going forward
            _pageTokens[tab].length = pageIndex + 1;
        }
    }

    function hasNextPage(tab, pageIndex) {
        let t = tab.toLowerCase();
        if (!_pageTokens[t])
            return false;
        return _pageTokens[t].length > pageIndex + 1;
    }

    function syncLabel(label, pageIndex = 0, force = false) {
        if (!authenticated || _refreshToken === "")
            return;

        let tab = label.toLowerCase();
        let targetModel = tab === "inbox" ? inboxMessages : tab === "sent" ? sentMessages : tab === "spam" ? spamMessages : tab === "starred" ? starredMessages : tab === "important" ? importantMessages : tab === "purchases" ? purchasesMessages : tab === "trash" ? trashMessages : searchMessagesModel;

        // Clear model immediately if forcing or changing page to show loading state
        if (force || pageIndex !== 0) {
            targetModel.clear();
        }

        // Always set loading to true to provide UI feedback (progress bar)
        // The global overlay in CheatsheetEmail.qml will only show if model.count === 0
        loading = true;
        let hId = (force || targetModel.count === 0) ? "" : historyId;
        let token = _getToken(tab, pageIndex);
        let bestToken = _getBestToken();
        if (tab === "inbox") {
            let catFlags = (enableUpdates ? "1" : "0") + "," + (enablePromotions ? "1" : "0") + "," + (enableSocials ? "1" : "0");
            inboxFetcher.command = ["python3", _fetchScript, bestToken, "INBOX", maxEmails.toString(), catFlags, token, hId];
            inboxFetcher._currentTab = tab;
            inboxFetcher._currentPage = pageIndex;
            inboxFetcher.running = true;
        } else if (tab === "sent") {
            sentFetcher.command = ["python3", _fetchScript, bestToken, "SENT", maxEmails.toString(), token, hId];
            sentFetcher._currentTab = tab;
            sentFetcher._currentPage = pageIndex;
            sentFetcher.running = true;
        } else if (tab === "trash") {
            trashFetcher.command = ["python3", _fetchScript, bestToken, "TRASH", maxEmails.toString(), token, hId];
            trashFetcher._currentTab = tab;
            trashFetcher._currentPage = pageIndex;
            trashFetcher.running = true;
        } else if (tab === "spam") {
            spamFetcher.command = ["python3", _fetchScript, bestToken, "SPAM", maxEmails.toString(), token, hId];
            spamFetcher._currentTab = tab;
            spamFetcher._currentPage = pageIndex;
            spamFetcher.running = true;
        } else if (tab === "starred") {
            starredFetcher.command = ["python3", _fetchScript, bestToken, "STARRED", maxEmails.toString(), token, hId];
            starredFetcher._currentTab = tab;
            starredFetcher._currentPage = pageIndex;
            starredFetcher.running = true;
        } else if (tab === "important") {
            importantFetcher.command = ["python3", _fetchScript, bestToken, "IMPORTANT", maxEmails.toString(), token, hId];
            importantFetcher._currentTab = tab;
            importantFetcher._currentPage = pageIndex;
            importantFetcher.running = true;
        } else if (tab === "purchases") {
            purchasesFetcher.command = ["python3", _fetchScript, bestToken, "CATEGORY_PURCHASES", maxEmails.toString(), token, hId];
            purchasesFetcher._currentTab = tab;
            purchasesFetcher._currentPage = pageIndex;
            purchasesFetcher.running = true;
        } else if (tab.indexOf("label_") === 0) {
            for (let i = 0; i < labels.count; i++) {
                let lbl = labels.get(i);
                if ("label_" + lbl.id === label) {
                    searchMessages("label:" + lbl.name.replace(/ /g, '-'), pageIndex);
                    break;
                }
            }
        }
    }

    function _startFetchAll() {
        syncLabel("inbox");
        labelFetcher.command = ["python3", Directories.scriptPath + "/email/fetch_labels.py", _getBestToken(), enabledLabels.join(",")];
        labelFetcher.running = true;
    }

    property int _pendingFetches: 0

    function _onFetchDone() {
        _pendingFetches--;
        if (_pendingFetches <= 0) {
            loading = false;
        }
    }

    Process {
        id: inboxFetcher
        property string _currentTab: "inbox"
        property int _currentPage: 0
        command: ["echo", "[]"]
        onRunningChanged: {
            if (running) {
                root._pendingFetches++;
                root.syncingLabels["fetcher"] = true;
                root.syncingLabelsChanged();
            } else {
                delete root.syncingLabels["fetcher"];
                root.syncingLabelsChanged();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._populateModel(root.inboxMessages, text, inboxFetcher._currentTab, inboxFetcher._currentPage);
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    Process {
        id: sentFetcher
        property string _currentTab: "sent"
        property int _currentPage: 0
        command: ["echo", "[]"]
        onRunningChanged: {
            if (running) {
                root._pendingFetches++;
                root.syncingLabels["fetcher"] = true;
                root.syncingLabelsChanged();
            } else {
                delete root.syncingLabels["fetcher"];
                root.syncingLabelsChanged();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._populateModel(root.sentMessages, text, sentFetcher._currentTab, sentFetcher._currentPage);
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    Process {
        id: trashFetcher
        property string _currentTab: "trash"
        property int _currentPage: 0
        command: ["echo", "[]"]
        onRunningChanged: {
            if (running) {
                root._pendingFetches++;
                root.syncingLabels["fetcher"] = true;
                root.syncingLabelsChanged();
            } else {
                delete root.syncingLabels["fetcher"];
                root.syncingLabelsChanged();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._populateModel(root.trashMessages, text, trashFetcher._currentTab, trashFetcher._currentPage);
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    Process {
        id: spamFetcher
        property string _currentTab: "spam"
        property int _currentPage: 0
        command: ["echo", "[]"]
        onRunningChanged: {
            if (running) {
                root._pendingFetches++;
                root.syncingLabels["fetcher"] = true;
                root.syncingLabelsChanged();
            } else {
                delete root.syncingLabels["fetcher"];
                root.syncingLabelsChanged();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._populateModel(root.spamMessages, text, spamFetcher._currentTab, spamFetcher._currentPage);
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    Process {
        id: starredFetcher
        property string _currentTab: "starred"
        property int _currentPage: 0
        command: ["echo", "[]"]
        onRunningChanged: {
            if (running) {
                root._pendingFetches++;
                root.syncingLabels["fetcher"] = true;
                root.syncingLabelsChanged();
            } else {
                delete root.syncingLabels["fetcher"];
                root.syncingLabelsChanged();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._populateModel(root.starredMessages, text, starredFetcher._currentTab, starredFetcher._currentPage);
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    Process {
        id: importantFetcher
        property string _currentTab: "important"
        property int _currentPage: 0
        command: ["echo", "[]"]
        onRunningChanged: {
            if (running) {
                root._pendingFetches++;
                root.syncingLabels["fetcher"] = true;
                root.syncingLabelsChanged();
            } else {
                delete root.syncingLabels["fetcher"];
                root.syncingLabelsChanged();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._populateModel(root.importantMessages, text, importantFetcher._currentTab, importantFetcher._currentPage);
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    Process {
        id: purchasesFetcher
        property string _currentTab: "purchases"
        property int _currentPage: 0
        command: ["echo", "[]"]
        onRunningChanged: {
            if (running) {
                root._pendingFetches++;
                root.syncingLabels["fetcher"] = true;
                root.syncingLabelsChanged();
            } else {
                delete root.syncingLabels["fetcher"];
                root.syncingLabelsChanged();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._populateModel(root.purchasesMessages, text, purchasesFetcher._currentTab, purchasesFetcher._currentPage);
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    Process {
        id: searchFetcher
        property string _currentTab: "search"
        property int _currentPage: 0
        command: ["echo", "[]"]
        onRunningChanged: {
            if (running)
                root._pendingFetches++;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                root._populateModel(root.searchMessagesModel, text, searchFetcher._currentTab, searchFetcher._currentPage);
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    Process {
        id: labelFetcher
        command: ["echo", "{}"]
        onRunningChanged: {
            if (running)
                root._pendingFetches++;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.labels.clear();
                    if (data.labels) {
                        data.labels.forEach(l => {
                            if (l.type === "user") {
                                root.labels.append({
                                    id: l.id,
                                    name: l.name,
                                    messagesUnread: l.messagesUnread || 0
                                });
                            } else if (l.type === "system") {
                                if (l.id === "INBOX")
                                    root.inboxUnreadCount = l.messagesUnread || 0;
                                else if (l.id === "SPAM")
                                    root.spamUnreadCount = l.messagesUnread || 0;
                                else if (l.id === "SENT")
                                    root.sentUnreadCount = l.messagesUnread || 0;
                                else if (l.id === "TRASH")
                                    root.trashUnreadCount = l.messagesUnread || 0;
                                else if (l.id === "STARRED")
                                    root.starredUnreadCount = l.messagesUnread || 0;
                                else if (l.id === "IMPORTANT")
                                    root.importantUnreadCount = l.messagesUnread || 0;
                                else if (l.id === "CATEGORY_PURCHASES")
                                    root.purchasesUnreadCount = l.messagesUnread || 0;
                            }
                        });
                    }
                } catch (e) {
                    console.warn("[Gmail] Labels parse error:", e);
                }
                root._onFetchDone();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._onFetchDone();
        }
    }

    function _populateModel(targetModel, jsonText, tab, pageIndex) {
        if (!jsonText || jsonText.trim().length === 0) {
            targetModel.clear();
            return;
        }
        try {
            const res = JSON.parse(jsonText);

            if (res.noChange) {
                return;
            }

            const msgs = res.messages || [];

            if (res.historyId) {
                root.historyId = res.historyId;
            }

            const newIds = new Set(msgs.map(m => m.id));
            const npt = res.nextPageToken || "";

            if (tab !== undefined && pageIndex !== undefined) {
                root._setNextToken(tab, pageIndex, npt);
            }

            // Deep comparison to avoid unnecessary updates and flickering
            if (targetModel.count === msgs.length) {
                let identical = true;
                for (let i = 0; i < msgs.length; i++) {
                    let oldItem = targetModel.get(i);
                    let newItem = msgs[i];

                    if (oldItem.id !== newItem.id || oldItem.unread !== (newItem.unread || false) || oldItem.starred !== (newItem.starred || false) || oldItem.subject !== (newItem.subject || "(sem assunto)") || oldItem.snippet !== (newItem.snippet || "")) {
                        identical = false;
                        break;
                    }
                }
                if (identical)
                    return;
            }

            // Only clear and refill if data actually changed
            targetModel.clear();

            var seenThreads = {};
            var threadCounts = {};
            var threadUnreadCounts = {};
            if (root.stackingEnabled) {
                for (var k = 0; k < msgs.length; k++) {
                    var mThread = msgs[k].threadId;
                    if (mThread) {
                        threadCounts[mThread] = (threadCounts[mThread] || 0) + 1;
                        if (msgs[k].unread) {
                            threadUnreadCounts[mThread] = (threadUnreadCounts[mThread] || 0) + 1;
                        }
                    }
                }
            }

            msgs.forEach(function (msg, index) {
                if (root.stackingEnabled && msg.threadId) {
                    if (seenThreads[msg.threadId])
                        return;
                    seenThreads[msg.threadId] = true;
                }

                var msgData = {
                    id: msg.id,
                    threadId: msg.threadId || "",
                    subject: msg.subject || "(no subject)",
                    from: msg.from || "",
                    date: msg.date || "",
                    snippet: msg.snippet || "",
                    unread: msg.unread || false,
                    starred: msg.starred || false,
                    timestamp: msg.timestamp || 0,
                    labelsString: (msg.labels || []).join(","),
                    icon: msg.icon || "person",
                    isStack: root.stackingEnabled && threadCounts[msg.threadId] > 1,
                    stackCount: root.stackingEnabled ? (threadCounts[msg.threadId] || 1) : 1,
                    threadUnreadCount: root.stackingEnabled ? (threadUnreadCounts[msg.threadId] || 0) : 0
                };
                targetModel.append(msgData);
            });
        } catch (e) {
            console.warn("[Gmail] Sync error:", e);
        }
    }

    // Actions that use fire-and-forget (execDetached is fine for these)

    Process {
        id: emailSender
        command: ["echo", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.success) {
                        root.emailSent(true, "");
                    } else {
                        root.emailSent(false, data.error || "Unknown error");
                    }
                } catch (e) {
                    root.emailSent(false, "Parse error: " + e);
                }
                root.sendingEmail = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.emailSent(false, "Process exited with code " + exitCode);
                root.sendingEmail = false;
            }
        }
    }

    function sendEmail(to, subject, bodyHtml, attachments, threadId = "", inReplyTo = "", references = "") {
        if (!authenticated || _refreshToken === "") {
            root.emailSent(false, "Not authenticated");
            return;
        }
        sendingEmail = true;
        let cmd = ["python3", Directories.scriptPath + "/email/send_email.py", _refreshToken, to, subject, bodyHtml];
        if (threadId)
            cmd.push("--thread-id", threadId);
        if (inReplyTo)
            cmd.push("--in-reply-to", inReplyTo);
        if (references)
            cmd.push("--references", references);

        if (attachments && attachments.length > 0) {
            cmd.push("--attachments");
            cmd = cmd.concat(attachments);
        }
        emailSender.command = cmd;
        emailSender.running = true;
    }

    function _ensureValidToken(callback) {
        let now = Math.floor(Date.now() / 1000);
        if (_accessToken !== "" && now < _tokenExpiry) {
            callback(_accessToken);
            return;
        }

        if (_refreshToken === "")
            return;

        // One-time connection to wait for the next token refresh
        let connection = null;
        connection = root.onAuthenticatedChanged.connect(() => {
            if (root.authenticated && root._accessToken !== "") {
                if (connection)
                    root.onAuthenticatedChanged.disconnect(connection);
                callback(root._accessToken);
            }
        });

        _refreshAndFetch();
    }

    function markAsRead(messageId) {
        _ensureValidToken(token => {
            const bodyStr = JSON.stringify({
                removeLabelIds: ["UNREAD"]
            });
            Quickshell.execDetached(["curl", "-s", "-X", "POST", "-H", "Authorization: Bearer " + token, "-H", "Content-Type: application/json", "-d", bodyStr, `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}/modify`]);
        });
    }

    function markThreadAsRead(threadId) {
        _ensureValidToken(token => {
            const bodyStr = JSON.stringify({
                removeLabelIds: ["UNREAD"]
            });
            Quickshell.execDetached(["curl", "-s", "-X", "POST", "-H", "Authorization: Bearer " + token, "-H", "Content-Type: application/json", "-d", bodyStr, `https://gmail.googleapis.com/gmail/v1/users/me/threads/${threadId}/modify`]);
        });

        // Update local models
        var models = [inboxMessages, sentMessages, spamMessages, starredMessages, importantMessages, purchasesMessages, searchMessagesModel, currentThreadMessages];
        for (var i = 0; i < models.length; i++) {
            var m = models[i];
            for (var j = 0; j < m.count; j++) {
                var item = m.get(j);
                if (item.threadId === threadId && item.unread) {
                    m.setProperty(j, "unread", false);
                    m.setProperty(j, "threadUnreadCount", 0);
                    root.decrementUnreadForModel(m);
                }
            }
        }
    }

    function toggleStarMessage(messageId, currentState) {
        _ensureValidToken(token => {
            const bodyStr = JSON.stringify(currentState ? {
                removeLabelIds: ["STARRED"]
            } : {
                addLabelIds: ["STARRED"]
            });
            Quickshell.execDetached(["curl", "-s", "-X", "POST", "-H", "Authorization: Bearer " + token, "-H", "Content-Type: application/json", "-d", bodyStr, `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}/modify`]);
        });

        var models = [inboxMessages, sentMessages, spamMessages, starredMessages, importantMessages, purchasesMessages, searchMessagesModel, currentThreadMessages];
        for (var i = 0; i < models.length; i++) {
            var m = models[i];
            for (var j = 0; j < m.count; j++) {
                if (m.get(j).id === messageId) {
                    if (m === starredMessages && currentState) {
                        if (m.get(j).unread) {
                            root.decrementUnreadForModel(m);
                        }
                        m.remove(j);
                    } else {
                        m.setProperty(j, "starred", !currentState);
                    }
                    break;
                }
            }
        }
    }

    function trashMessage(messageId) {
        console.log("[EmailService] Trashing message:", messageId);
        _ensureValidToken(token => {
            Quickshell.execDetached(["python3", Directories.scriptPath + "/email/delete_email.py", token, messageId, "trash"]);
        });
        _removeFromModels(messageId);
    }

    function deleteMessagePermanent(messageId) {
        console.log("[EmailService] Permanently deleting message:", messageId);
        _ensureValidToken(token => {
            Quickshell.execDetached(["python3", Directories.scriptPath + "/email/delete_email.py", token, messageId, "permanent"]);
        });
        _removeFromModels(messageId);
    }

    function restoreMessage(messageId) {
        console.log("[EmailService] Restoring message from trash:", messageId);
        _ensureValidToken(token => {
            Quickshell.execDetached(["python3", Directories.scriptPath + "/email/delete_email.py", token, messageId, "untrash"]);
        });
        _removeFromModels(messageId);
    }

    function _removeFromModels(messageId) {
        let models = [inboxMessages, sentMessages, spamMessages, starredMessages, importantMessages, purchasesMessages, trashMessages, searchMessagesModel, currentThreadMessages];
        for (let m of models) {
            for (let i = 0; i < m.count; i++) {
                let item = m.get(i);
                if (item && item.id == messageId) {
                    if (item.unread) {
                        root.decrementUnreadForModel(m);
                    }
                    m.remove(i);
                    console.log("[EmailService] Removed from model:", messageId);
                    break;
                }
            }
        }
    }

    function searchMessages(query, pageIndex = 0) {
        if (_refreshToken === "")
            return;
        loading = true;

        let token = _getToken("search", pageIndex);
        let bestToken = _getBestToken();

        searchFetcher.command = ["python3", _fetchScript, bestToken, "SEARCH:" + query, maxEmails.toString(), token];
        searchFetcher._currentTab = "search";
        searchFetcher._currentPage = pageIndex;
        searchFetcher.running = true;
    }

    Process {
        id: emailBodyFetcher
        command: ["echo", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                console.log("[Gmail] Received body data:", text.substring(0, 500), "...");
                try {
                    const data = JSON.parse(text);
                    root.currentEmailBody = data.body || "";
                    root.currentEmailHtmlPath = data.htmlPath || "";
                    root.currentEmailAttachments.clear();
                    const atts = data.attachments || [];
                    atts.forEach(a => {
                        console.log("[Gmail] Processing attachment:", a.name, "| hasEventInfo:", !!a.eventInfo);
                        root.currentEmailAttachments.append({
                            name: a.name || "",
                            mimeType: a.mimeType || "",
                            attachmentId: a.attachmentId || "",
                            icon: a.icon || "attach_file",
                            sizeLabel: a.sizeLabel || "",
                            eventInfo: a.eventInfo || null
                        });
                    });
                } catch (e) {
                    root.currentEmailBody = "";
                    root.currentEmailHtmlPath = "";
                    root.currentEmailAttachments.clear();
                    console.warn("[Gmail] Body parse error:", e);
                }
                root.loadingEmailBody = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.loadingEmailBody = false;
        }
    }

    function fetchEmailBody(messageId) {
        currentEmailBody = "";
        loadingEmailBody = true;
        let bestToken = _getBestToken();
        emailBodyFetcher.command = ["python3", Directories.scriptPath + "/email/fetch_email_body.py", bestToken, messageId];
        emailBodyFetcher.running = true;
    }

    Process {
        id: emailAttachmentDownloader
        command: ["echo", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.success) {
                        console.log("[Gmail] Downloaded attachment to: ", data.path);
                        root.attachmentDownloadFinished(data.attachmentId || "", true, data.path);
                    } else {
                        console.warn("[Gmail] Download error: ", data.error);
                        root.attachmentDownloadFinished(data.attachmentId || "", false, "");
                    }
                } catch (e) {
                    console.warn("[Gmail] Download parse error:", e);
                }
            }
        }
    }

    function downloadAttachment(messageId, attachmentId, filename, targetDir) {
        if (_refreshToken === "")
            return;
        var bestToken = _getBestToken();
        var cmd = ["python3", Directories.scriptPath + "/email/download_email_attachment.py", bestToken, messageId, attachmentId, filename];
        if (targetDir) {
            cmd.push(targetDir);
        }
        emailAttachmentDownloader.command = cmd;
        emailAttachmentDownloader.running = true;
    }

    Process {
        id: threadFetcher
        command: ["echo", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (data && data.length > 0) {
                        root.currentThreadMessages.clear();
                        data.reverse();
                        for (var i = 0; i < data.length; i++) {
                            var msg = data[i];
                            root.currentThreadMessages.append({
                                id: msg.id,
                                threadId: msg.threadId,
                                from: msg.from,
                                subject: msg.subject,
                                date: msg.date,
                                snippet: msg.snippet,
                                body: msg.body,
                                attachments: msg.attachments || [],
                                unread: msg.unread,
                                starred: msg.starred,
                                timestamp: msg.timestamp,
                                labelsString: (msg.labels || []).join(",")
                            });
                        }
                    }
                } catch (e) {
                    root.currentThreadMessages.clear();
                    console.warn("[Gmail] Thread parse error:", e);
                }
                root.loadingEmailBody = false;
            }
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0)
                root.loadingEmailBody = false;
        }
    }

    function fetchThread(threadId) {
        currentThreadMessages.clear();
        loadingEmailBody = true;
        var bestToken = _getBestToken();
        threadFetcher.command = ["python3", Directories.scriptPath + "/email/fetch_thread.py", bestToken, threadId];
        threadFetcher.running = true;
    }
}
