pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.modules.common
import qs.services

Singleton {
    id: root

    readonly property var options: Config.options.background.widgets.at_a_glance
    property int refreshVersion: 0

    // ── 1. Weather ────────────────────────────────────────────────────────────
    readonly property var weatherData: Weather.data
    readonly property bool weatherAvailable: (options.enableWeather ?? true) && Weather.data && Weather.data.temp !== ""
    readonly property string weatherTemperature: weatherAvailable ? String(Weather.data.temp).replace("°C", "°C").replace("°F", "°F") : ""
    readonly property string weatherDescription: weatherAvailable ? (Weather.data.wDesc || "") : ""
    readonly property string weatherCity: weatherAvailable ? (Weather.data.city || "") : ""
    readonly property int weatherCode: weatherAvailable ? (Weather.data.wCode || 113) : 113

    // ── 2. Media ──────────────────────────────────────────────────────────────
    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool mediaAvailable: (options.enableMedia ?? true) && player !== null && String(player.trackTitle || "") !== ""
    readonly property bool mediaPlaying: mediaAvailable && player.playbackState === MprisPlaybackState.Playing
    readonly property string mediaTitle: mediaAvailable ? String(player.trackTitle || Translation.tr("Unknown Title")) : ""
    readonly property string mediaArtist: mediaAvailable ? String(player.trackArtist || Translation.tr("Unknown Artist")) : ""
    readonly property string mediaArtUrl: mediaAvailable ? String(MprisController.artUrl || "") : ""

    // ── 3. Calendar ───────────────────────────────────────────────────────────
    readonly property date now: DateTime.clock.date
    readonly property var todayEvents: {
        refreshVersion;
        if (!(options.enableCalendar ?? true) || !CalendarService.khalAvailable || !CalendarService.events)
            return [];
        return CalendarService.events.filter(event => {
            const date = new Date(event.startDate);
            const today = root.now || new Date();
            return date.getFullYear() === today.getFullYear()
                && date.getMonth() === today.getMonth()
                && date.getDate() === today.getDate();
        }).sort((a, b) => new Date(a.startDate) - new Date(b.startDate));
    }

    readonly property var nextEvent: {
        const events = todayEvents;
        const timestamp = (now || new Date()).getTime();
        for (let i = 0; i < events.length; i++) {
            if (new Date(events[i].endDate).getTime() > timestamp)
                return events[i];
        }
        return null;
    }

    readonly property bool calendarAvailable: nextEvent !== null
    readonly property bool calendarActive: calendarAvailable && ((new Date(nextEvent.startDate).getTime() - (now || new Date()).getTime()) <= (options.calendarWindowMinutes || 60) * 60000)
    readonly property string calendarTitle: calendarAvailable ? String(nextEvent.content || Translation.tr("Calendar event")) : ""
    readonly property string calendarMeta: {
        if (!calendarAvailable)
            return "";
        const start = new Date(nextEvent.startDate);
        const end = new Date(nextEvent.endDate);
        if (start.getTime() <= (now || new Date()).getTime() && end.getTime() > (now || new Date()).getTime())
            return Translation.tr("Now");
        return Qt.formatDateTime(start, Config.options.time.format.includes("ap") || Config.options.time.format.includes("AP") ? "h:mm ap" : "hh:mm");
    }

    // ── 4. Sports ─────────────────────────────────────────────────────────────
    readonly property var game: {
        refreshVersion;
        if (!(options.enableSports ?? true) || !SportsService.enabled)
            return null;
        return SportsService.currentGame || (SportsService.allGames && SportsService.allGames.length > 0 ? SportsService.allGames[0] : null);
    }
    readonly property bool sportsAvailable: game !== null
    readonly property bool sportsActive: sportsAvailable && game.state === "in"
    readonly property string sportsTitle: sportsAvailable ? String(game.home.name + " · " + game.away.name) : ""
    readonly property string sportsMeta: sportsAvailable ? String(game.state === "in" ? (game.home.score + " – " + game.away.score) : game.status) : ""
    readonly property string sportsLeague: sportsAvailable ? String(game.league || "") : ""

    // ── 5. To-Do Tasks ────────────────────────────────────────────────────────
    readonly property int todoPendingCount: {
        refreshVersion;
        if (!(options.enableTodo ?? true) || !Todo.list) return 0;
        return Todo.list.filter(item => !(item.done || item.status === 2)).length;
    }
    readonly property bool todoAvailable: todoPendingCount > 0
    readonly property string todoTopTitle: {
        if (!todoAvailable) return "";
        const top = Todo.list.find(item => !(item.done || item.status === 2));
        return top ? String(top.content || top.title || Translation.tr("To-Do Item")) : Translation.tr("To-Do Task");
    }

    // ── 6. Email Unread ───────────────────────────────────────────────────────
    readonly property int emailUnreadCount: {
        refreshVersion;
        if (!(options.enableEmail ?? true) || !EmailService.authenticated) return 0;
        return EmailService.inboxUnreadCount || 0;
    }
    readonly property bool emailAvailable: emailUnreadCount > 0

    // ── 7. LocalSend Transfers ────────────────────────────────────────────────
    readonly property bool localSendActive: (options.enableLocalSend ?? true) && LocalSend.available && (LocalSend.currentTransfer !== null || LocalSend.sending)
    readonly property string localSendTitle: localSendActive ? (LocalSend.sending ? Translation.tr("Sending file...") : Translation.tr("Receiving file...")) : ""

    // ── 8. KDE Connect Device ─────────────────────────────────────────────────
    readonly property bool kdeConnectActive: (options.enableKdeConnect ?? true) && KdeConnectService.available && KdeConnectService.activeDevice !== null && ((KdeConnectService.activeDevice.isReachable ?? KdeConnectService.activeDevice.reachable) ?? false)
    readonly property string kdeConnectDeviceName: kdeConnectActive ? KdeConnectService.activeDeviceDisplayName : ""
    readonly property int kdeConnectBattery: kdeConnectActive ? (KdeConnectService.activeDevice.batteryCharge ?? -1) : -1

    // ── 9. Active Targets & Helper Functions ──────────────────────────────────
    readonly property var activeTargetsList: {
        refreshVersion;
        const targets = [];
        if (mediaAvailable && mediaPlaying) targets.push("media");
        if (calendarAvailable && calendarActive) targets.push("calendar");
        if (sportsAvailable && sportsActive) targets.push("sports");
        if (todoAvailable) targets.push("todo");
        if (emailAvailable) targets.push("email");
        if (localSendActive) targets.push("localsend");
        if (kdeConnectActive && kdeConnectBattery >= 0 && kdeConnectBattery < 20) targets.push("kdeconnect");
        // Fallback Date & Weather is always available as default
        targets.push("fallback");
        return targets;
    }

    readonly property string activeService: chooseService()

    function chooseService() {
        refreshVersion;
        const priority = (options && options.servicePriority) ? options.servicePriority : ["media", "calendar", "sports", "todo", "email", "localsend", "kdeconnect", "fallback"];
        for (let i = 0; i < priority.length; i++) {
            const service = priority[i];
            if (service === "media" && mediaAvailable && (mediaPlaying || (options && (options.enableMedia ?? true))))
                return service;
            if (service === "calendar" && calendarAvailable && calendarActive)
                return service;
            if (service === "sports" && sportsAvailable && sportsActive)
                return service;
            if (service === "todo" && todoAvailable)
                return service;
            if (service === "email" && emailAvailable)
                return service;
            if (service === "localsend" && localSendActive)
                return service;
            if (service === "kdeconnect" && kdeConnectActive)
                return service;
        }
        return "fallback";
    }

    function getTargetData(serviceName) {
        if (serviceName === "media") {
            return {
                service: "media",
                title: mediaTitle,
                subtitle: mediaArtist,
                meta: mediaPlaying ? Translation.tr("Playing") : Translation.tr("Paused"),
                icon: mediaPlaying ? "play_arrow" : "pause",
                artUrl: mediaArtUrl
            };
        }
        if (serviceName === "calendar") {
            return {
                service: "calendar",
                title: calendarTitle,
                subtitle: calendarMeta,
                meta: "",
                icon: "event",
                artUrl: ""
            };
        }
        if (serviceName === "sports") {
            return {
                service: "sports",
                title: sportsTitle,
                subtitle: sportsLeague,
                meta: sportsMeta,
                icon: "sports_soccer",
                artUrl: ""
            };
        }
        if (serviceName === "todo") {
            return {
                service: "todo",
                title: todoTopTitle,
                subtitle: String(todoPendingCount) + " " + Translation.tr("items on list"),
                meta: "",
                icon: "task_alt",
                artUrl: ""
            };
        }
        if (serviceName === "email") {
            return {
                service: "email",
                title: String(emailUnreadCount) + " " + Translation.tr("unread emails"),
                subtitle: EmailService.userEmail || Translation.tr("Inbox"),
                meta: "",
                icon: "mail",
                artUrl: ""
            };
        }
        if (serviceName === "localsend") {
            return {
                service: "localsend",
                title: localSendTitle,
                subtitle: Translation.tr("LocalSend Active"),
                meta: "",
                icon: "share",
                artUrl: ""
            };
        }
        if (serviceName === "kdeconnect") {
            return {
                service: "kdeconnect",
                title: kdeConnectDeviceName,
                subtitle: kdeConnectBattery >= 0 ? (Translation.tr("Battery: ") + kdeConnectBattery + "%") : Translation.tr("Connected"),
                meta: "",
                icon: "smartphone",
                artUrl: ""
            };
        }
        // Fallback: Date & Weather
        return {
            service: "fallback",
            title: Qt.formatDateTime(now || new Date(), "ddd, MMM d"),
            subtitle: weatherAvailable ? (weatherTemperature + " " + weatherDescription) : Qt.formatDateTime(now || new Date(), Config.options.time.format.includes("ap") || Config.options.time.format.includes("AP") ? "h:mm ap" : "hh:mm"),
            meta: "",
            icon: "today",
            artUrl: ""
        };
    }

    readonly property var currentTargetData: getTargetData(activeService)
    readonly property string activeTitle: currentTargetData.title
    readonly property string activeSubtitle: currentTargetData.subtitle
    readonly property string activeMeta: currentTargetData.meta
    readonly property string activeIcon: currentTargetData.icon

    function refresh() {
        refreshVersion++;
    }

    Connections {
        target: MprisController
        function onActivePlayerChanged() { root.refresh(); }
        function onActiveTrackChanged() { root.refresh(); }
        function onTrackChanged() { root.refresh(); }
    }

    Connections {
        target: CalendarService
        function onEventsChanged() { root.refresh(); }
        function onKhalAvailableChanged() { root.refresh(); }
    }

    Connections {
        target: SportsService
        function onCurrentGameChanged() { root.refresh(); }
        function onAllGamesChanged() { root.refresh(); }
        function onEnabledChanged() { root.refresh(); }
    }

    Connections {
        target: Todo
        function onListChanged() { root.refresh(); }
    }

    Connections {
        target: EmailService
        function onInboxUnreadCountChanged() { root.refresh(); }
    }

    Connections {
        target: LocalSend
        function onCurrentTransferChanged() { root.refresh(); }
        function onSendingChanged() { root.refresh(); }
    }

    Connections {
        target: KdeConnectService
        function onDevicesChanged() { root.refresh(); }
    }

    Connections {
        target: Weather
        function onDataChanged() { root.refresh(); }
    }
}
