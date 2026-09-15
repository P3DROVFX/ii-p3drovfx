pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.presets

/**
 * The community preset store, inside the Welcome flow.
 *
 * A preset is a WHOLE look - wallpaper, palette, bar layout, dock, widgets,
 * the settings behind them - so for someone who installed the shell an hour
 * ago it is the shortest path from "a fresh install" to "my desktop". The
 * store already existed in Settings, but only as a place you go once you know
 * Settings exists, with a browse-then-install-then-apply route through a
 * detail page. Nobody on their first day knows to look.
 *
 * Here a card is one click and one meaning: WEAR THIS. The install is a step
 * on the way rather than a thing to decide about, so the card downloads the
 * preset if it has to and applies it the moment it lands.
 *
 * Everything this pane does is walked back by one button. `presets.sh` snapshots
 * config.json before every apply and `revert` pops the newest snapshot, so
 * going back N applies means reverting N times - the pane counts its own and
 * no one else's, which is what keeps a preset the user already had from before
 * the Welcome out of it. The presets it downloaded are removed in the same
 * breath; ones that were already on disk are left alone.
 */
ColumnLayout {
    id: root

    // The tab that owns this pane. The first search costs a GitHub request,
    // so it waits until someone actually looks at the store.
    property bool active: false
    signal pickYourOwnRequested()

    spacing: Appearance.rounding.small

    // ── One-click "wear this look" ───────────────────────────────────────────
    // The repo whose install we are waiting on, and the preset whose apply we
    // are waiting on. The store runs one job at a time, so one of each is all
    // there can ever be.
    property string pendingRepo: ""
    property string pendingName: ""
    property string failure: ""

    // What THIS pane did, so the way back is exactly as long as the way in.
    property int appliedHere: 0
    property var installedHere: []
    property int revertsLeft: 0
    property bool cleaning: false

    // Sorted by stars: on a page that asks someone to pick a look in a minute,
    // the order that needs no explanation is "what other people kept".
    readonly property var results: {
        let rows = PresetStore.discoverResults.slice();
        rows.sort((a, b) => (b.stars || 0) - (a.stars || 0));
        return rows;
    }

    readonly property bool working: PresetStore.busy || root.cleaning
        || root.pendingRepo !== "" || root.pendingName !== ""

    // Whether there is anything to walk back. `appliedHere` alone was not it:
    // it is per-instance, so a look applied before this page was built - in an
    // earlier Welcome, from Settings, or simply before a hot reload - left the
    // shell wearing a preset with no way out of it on the page that put it
    // there. The marker on disk is what actually answers "am I wearing one".
    readonly property bool wearingPreset: PresetStore.activePreset !== ""
    readonly property bool canGoBack: root.wearingPreset
        || root.appliedHere > 0 || root.installedHere.length > 0

    // One revert per apply this pane made, or one for a look that was already
    // on when the page opened - `presets.sh revert` pops one snapshot per call.
    readonly property int revertsNeeded: Math.max(root.appliedHere, root.wearingPreset ? 1 : 0)

    function useLook(entry) {
        if (!entry || root.working)
            return;
        root.failure = "";
        const installedAs = String(entry.installedAs ?? "");
        if (installedAs.length > 0) {
            root.applyNamed(installedAs);
            return;
        }
        const repo = String(entry.repo ?? "");
        if (repo === "")
            return;
        root.pendingRepo = repo;
        PresetStore.install(repo, "", false);
    }

    function applyNamed(name) {
        if (!name || PresetStore.activePreset === name)
            return;
        root.pendingName = name;
        PresetStore.applyPreset(name);
    }

    function backToDefault() {
        if (root.working)
            return;
        root.failure = "";
        root.revertsLeft = root.revertsNeeded;
        if (root.revertsLeft <= 0) {
            root.dropDownloads();
            return;
        }
        root.cleaning = true;
        PresetStore.revert();
    }

    // Only what this pane downloaded. A preset the user already had is theirs.
    function dropDownloads() {
        const names = root.installedHere.slice();
        root.installedHere = [];
        root.revertsLeft = 0;
        root.cleaning = false;
        for (const name of names)
            PresetStore.uninstall(name);
    }

    Component.onCompleted: PresetStore.ensureLoaded()

    onActiveChanged: {
        if (!root.active)
            return;
        PresetStore.discover("", 30);
    }

    Connections {
        target: PresetStore

        function onInstallFinished(name, ok, error) {
            if (root.pendingRepo === "")
                return;
            root.pendingRepo = "";
            if (!ok) {
                root.failure = error;
                return;
            }
            root.installedHere = root.installedHere.concat([name]);
            root.applyNamed(name);
        }

        function onApplyFinished(name, ok) {
            if (root.pendingName !== name)
                return;
            root.pendingName = "";
            if (ok)
                root.appliedHere += 1;
            else
                root.failure = Translation.tr("“%1” could not be applied.").arg(name);
        }

        function onRevertFinished(ok) {
            if (!root.cleaning)
                return;
            root.revertsLeft = Math.max(0, root.revertsLeft - 1);
            root.appliedHere = Math.max(0, root.appliedHere - 1);
            if (ok && root.revertsLeft > 0) {
                PresetStore.revert();
                return;
            }
            root.dropDownloads();
        }
    }

    // ── Search ───────────────────────────────────────────────────────────────
    // GitHub answers ten searches a minute to a signed-out shell, and this is
    // a live search rather than an index, so a keystroke cannot be one.
    Timer {
        id: searchDebounce
        interval: 700
        repeat: false
        onTriggered: PresetStore.discover(searchField.text, 30)
    }

    RowLayout {
        Layout.fillWidth: true
        // A RowLayout is itself a Layout, and for those Layout.fillHeight
        // defaults to TRUE - so without this the search row takes whatever
        // vertical space is going and the grid below it is squeezed to a
        // sliver. Same rule bites every nested layout on this page.
        Layout.fillHeight: false
        Layout.preferredHeight: 44
        Layout.maximumHeight: 44
        spacing: Appearance.rounding.verysmall

        ToolbarTextField {
            id: searchField
            Layout.fillWidth: true
            Layout.fillHeight: true
            colBackground: Appearance.colors.colLayer2
            placeholderText: Translation.tr("Search looks made by other people…")
            font.pixelSize: Appearance.font.pixelSize.normal
            onTextChanged: searchDebounce.restart()
            onAccepted: {
                searchDebounce.stop();
                PresetStore.discover(searchField.text, 30, true);
            }
        }

        RippleButtonWithIcon {
            Layout.fillHeight: true
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh")
            buttonRadius: Appearance.rounding.full
            enabled: !PresetStore.discovering
            onClicked: {
                searchDebounce.stop();
                PresetStore.discover(searchField.text, 30, true);
            }
        }
    }

    StyledIndeterminateProgressBar {
        Layout.fillWidth: true
        visible: PresetStore.discovering || root.working
    }

    // ── What went wrong, when something did ──────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: root.failure.length > 0
        implicitHeight: failureRow.implicitHeight + 20
        radius: Appearance.rounding.small
        color: Appearance.colors.colErrorContainer

        RowLayout {
            id: failureRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 12
            spacing: 8

            MaterialSymbol {
                text: "error"
                iconSize: 18
                color: Appearance.colors.colOnErrorContainer
            }

            StyledText {
                Layout.fillWidth: true
                text: root.failure
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnErrorContainer
            }
        }
    }

    // ── The looks ────────────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // The store could not be reached, or has nothing to show. Either way
        // the page still has a way forward, so it points at it rather than
        // leaving a dead grid.
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 460)
            spacing: Appearance.rounding.small
            visible: !PresetStore.discovering && root.results.length === 0

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: PresetStore.discoverError.length > 0 ? "cloud_off" : "travel_explore"
                iconSize: 44
                color: Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer0
                text: PresetStore.discoverError.length > 0
                    ? Translation.tr("The store could not be reached.")
                    : (searchField.text.length > 0
                        ? Translation.tr("Nothing published under that name yet.")
                        : Translation.tr("No looks have been published yet."))
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: PresetStore.discoverError.length > 0
                text: PresetStore.discoverError
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Appearance.rounding.verysmall
                materialIcon: "palette"
                mainText: Translation.tr("Pick your own instead")
                buttonRadius: Appearance.rounding.full
                onClicked: root.pickYourOwnRequested()
            }
        }

        StyledFlickable {
            id: resultsFlickable
            anchors.fill: parent
            visible: root.results.length > 0
            contentWidth: width
            contentHeight: resultFlow.implicitHeight
            clip: true

            Flow {
                id: resultFlow
                width: resultsFlickable.width
                spacing: 12

                // Narrower than the Settings store's cards: this pane is a
                // picker inside a 1080px window with a tab row and a footer
                // over it, so it wants two rows of looks visible, not one.
                readonly property int minWidth: 180
                readonly property int columns: Math.max(1,
                    Math.floor((width + spacing) / (minWidth + spacing)))
                readonly property real itemWidth: Math.floor(
                    (width - (columns - 1) * spacing) / columns)

                move: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                Repeater {
                    model: root.results

                    delegate: StoreResultCard {
                        required property var modelData
                        entry: modelData
                        applyMode: true
                        width: resultFlow.itemWidth
                        onActivated: root.useLook(modelData)
                    }
                }
            }
        }
    }

    // ── What a look costs, and the way back out of one ───────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: footerRow.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: root.canGoBack
            ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            id: footerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 12
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: root.canGoBack ? "check_circle" : "info"
                iconSize: 20
                color: root.canGoBack
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.canGoBack
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurfaceVariant
                text: root.wearingPreset
                    ? Translation.tr("Wearing “%1”. Keep browsing to try another one.").arg(PresetStore.activePreset)
                    : root.canGoBack
                        ? Translation.tr("Your settings were changed by a look from the store.")
                        : Translation.tr("These looks are published by other people and are not reviewed by this project. Applying one replaces your settings and can hand it whatever those settings are allowed to run.")
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignVCenter
                visible: root.canGoBack
                enabled: !root.working
                materialIcon: "restart_alt"
                mainText: Translation.tr("Remove and go back to default")
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                colText: Appearance.colors.colOnLayer2
                onClicked: root.backToDefault()
            }
        }
    }
}
