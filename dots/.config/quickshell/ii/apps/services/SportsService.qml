pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Slim SportsService stand-in for standalone apps (zero ESPN polling in app process).
 */
Singleton {
    id: root

    property var timetableGames: []

    function acquireTimetableSubscriber() {}
    function releaseTimetableSubscriber() {}
    function requestTimetableRange(startIso, endIso, force = false) {}
    function gamesForDate(date) { return []; }
    function gameById(id) { return null; }
    function focusGame(game) {}
    function clearFocusedGame() {}
    function detailsForGame(gameId) { return null; }
    function detailsLoadingForGame(gameId) { return false; }
    function detailsErrorForGame(gameId) { return ""; }
}
