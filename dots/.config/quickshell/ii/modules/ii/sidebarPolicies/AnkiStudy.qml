import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.sidebarPolicies.anki
import QtQuick

/**
 * Anki tab: study your Anki collection from the sidebar, on Anki's own engine
 * (services/Anki.qml → scripts/anki/anki_daemon.py), no Anki app needed.
 *
 * Pages: setup (install / starting / error) → home (due today + decks) → review.
 * Login, add-card and account open as sheets over the tab. The daemon is held while the
 * tab exists and stops a minute after it goes.
 */
Item {
    id: root

    property real padding: Appearance.rounding.small
    /// "", "login", "add", "account"
    property string sheet: ""

    readonly property string page: Anki.installed !== true || !Anki.ready ? "setup"
        : Anki.studying ? "review" : "home"

    function triggerContentEntrance() {
        root.focusPage();
    }

    function focusPage() {
        if (root.sheet.length > 0)
            return;
        if (pageLoader.item)
            pageLoader.item.forceActiveFocus();
    }

    Component.onCompleted: Anki.hold()
    Component.onDestruction: Anki.release()

    // Images and formulas are sized by the daemon for the card's text column.
    onWidthChanged: Anki.themeMaxWidth = Math.max(160, root.width - root.padding * 2 - ClockStyle.cardPadding * 2)

    onSheetChanged: {
        if (root.sheet.length === 0)
            Qt.callLater(root.focusPage);
    }

    Loader {
        id: pageLoader
        anchors {
            fill: parent
            margins: root.padding
        }
        focus: root.sheet.length === 0
        sourceComponent: root.page === "setup" ? setupPage : root.page === "review" ? reviewPage : homePage
        onLoaded: Qt.callLater(root.focusPage)
    }

    Component {
        id: setupPage
        AnkiSetupPage {}
    }

    Component {
        id: homePage
        AnkiHomePage {
            onSheetRequested: name => root.sheet = name
        }
    }

    Component {
        id: reviewPage
        AnkiReviewPage {
            onBackRequested: Anki.endStudy()
        }
    }

    // ── Sheets ───────────────────────────────────────────────────────────
    Loader {
        anchors {
            fill: parent
            margins: root.padding
        }
        z: 10
        active: root.sheet.length > 0 && Anki.ready
        focus: active
        sourceComponent: root.sheet === "login" ? loginSheet : root.sheet === "add" ? addSheet : accountSheet
        onLoaded: item.forceActiveFocus()
    }

    Component {
        id: loginSheet
        AnkiLoginSheet {
            onDismissed: root.sheet = ""
        }
    }

    Component {
        id: addSheet
        AnkiAddSheet {
            onDismissed: root.sheet = ""
        }
    }

    Component {
        id: accountSheet
        AnkiAccountSheet {
            onDismissed: root.sheet = ""
        }
    }

    // ── Toast ────────────────────────────────────────────────────────────
    Rectangle {
        id: toast
        property string message: ""
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: root.padding + ClockStyle.gapLarge
        }
        z: 20
        width: Math.min(root.width - ClockStyle.gapHuge * 2, toastText.implicitWidth + ClockStyle.gapHuge * 2)
        height: 44
        radius: Appearance.rounding.full
        color: Appearance.m3colors.m3inverseSurface
        opacity: toastTimer.running ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        StyledText {
            id: toastText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, toast.width - ClockStyle.gapHuge * 2)
            elide: Text.ElideRight
            text: toast.message
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.m3colors.m3inverseOnSurface
        }

        Timer {
            id: toastTimer
            interval: 2600
        }

        Connections {
            target: Anki
            function onToast(message) {
                toast.message = message;
                toastTimer.restart();
            }
        }
    }
}
