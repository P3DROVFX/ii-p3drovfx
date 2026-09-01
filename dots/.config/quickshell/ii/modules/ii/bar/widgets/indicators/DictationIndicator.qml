pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../shared/cards"

/**
 * One pill in the bar for as long as dictation is running: a microphone, the
 * elapsed time, and the language being transcribed. Everything worth knowing
 * mid-sentence, in about the width of a clock.
 *
 * Its popup is the control surface. Dictation is one of the few shell states
 * where stopping and abandoning are genuinely different actions — one types
 * everything said so far into the focused window, the other throws it away — so
 * both get a real button instead of the destructive one hiding behind the
 * absence of the other. The focused window is named on the card, because
 * "insert text" only means something if you can see where it will land.
 */
MouseArea {
    id: indicator
    property bool vertical: false

    readonly property bool recording: DictationService.recording
    readonly property bool transcribing: DictationService.transcribing
    readonly property bool busy: DictationService.busy
    /** Idle and still shown: a button to start dictation with, rather than a status. */
    readonly property bool idleButton: !busy && (Config.options?.dictation?.alwaysShowIndicator ?? false)
    readonly property bool active: (busy || idleButton) && (Config.options?.dictation?.showIndicator ?? true)
    readonly property int elapsedSeconds: Math.floor(DictationService.elapsedMs / 1000)

    readonly property Toplevel targetWindow: ToplevelManager.activeToplevel
    readonly property string targetTitle: {
        const title = indicator.targetWindow?.title ?? "";
        return title.length > 0 ? title : Translation.tr("No focused window");
    }

    Layout.fillHeight: vertical
    readonly property bool clickToShowPopup: Config.options.bar.tooltips.clickToShow
    readonly property bool showHoverState: containsMouse && !clickToShowPopup
    hoverEnabled: !clickToShowPopup
    cursorShape: Qt.PointingHandCursor

    implicitWidth: active ? (vertical ? Appearance.sizes.verticalBarWidth : layoutHoriz.implicitWidth) : 0
    implicitHeight: active ? (vertical ? layoutVert.implicitHeight : Appearance.sizes.baseBarHeight) : 0
    visible: active

    Component.onCompleted: indicator.reconcile()
    onActiveChanged: indicator.reconcile()
    onRecordingChanged: indicator.reconcile()
    onIdleButtonChanged: indicator.reconcile()

    function reconcile() {
        rootItem.toggleVisible(indicator.active);
        rootItem.toggleHighlight(indicator.recording);
    }

    function formatTime(seconds) {
        const minutes = Math.floor(seconds / 60);
        return String(minutes).padStart(2, '0') + ":" + String(seconds % 60).padStart(2, '0');
    }

    readonly property color colContainer: {
        if (indicator.idleButton)
            return indicator.showHoverState ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1;
        if (indicator.transcribing)
            return indicator.showHoverState ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer;
        return indicator.showHoverState ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer;
    }
    readonly property color colOnContainer: {
        if (indicator.idleButton)
            return Appearance.colors.colOnLayer1;
        if (indicator.transcribing)
            return Appearance.colors.colOnSecondaryContainer;
        return Appearance.colors.colOnPrimaryContainer;
    }
    readonly property string glyph: {
        if (indicator.transcribing)
            return "graphic_eq";
        if (indicator.idleButton)
            return "mic";
        return indicator.showHoverState ? "stop" : "mic";
    }

    component PulsingMic: MaterialSymbol {
        text: indicator.glyph
        iconSize: 16
        color: indicator.colOnContainer

        // The only thing saying the microphone is open right now, so it must
        // not keep running once it is not.
        SequentialAnimation on opacity {
            running: indicator.recording
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.45; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
        }
        onTextChanged: if (!indicator.recording) opacity = 1.0
    }

    // ── Horizontal: one pill — mic · time · language ─────────────────────────
    Item {
        id: layoutHoriz
        visible: !indicator.vertical
        anchors.centerIn: parent
        implicitWidth: pillHoriz.implicitWidth
        implicitHeight: 32

        Rectangle {
            id: pillHoriz
            anchors.centerIn: parent
            height: 32
            implicitWidth: contentHoriz.implicitWidth + 20
            radius: height / 2
            color: indicator.colContainer

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            RowLayout {
                id: contentHoriz
                anchors.centerIn: parent
                spacing: 6

                PulsingMic {}

                StyledText {
                    visible: indicator.busy
                    text: indicator.transcribing ? "···" : indicator.formatTime(indicator.elapsedSeconds)
                    color: indicator.colOnContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.features: ({ "tnum": 1 })
                    font.weight: Font.Bold
                }

                StyledText {
                    text: DictationService.languageBadge
                    color: indicator.colOnContainer
                    opacity: 0.7
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // ── Vertical bar: the same pill, stacked ─────────────────────────────────
    ColumnLayout {
        id: layoutVert
        visible: indicator.vertical
        anchors.centerIn: parent
        spacing: 4

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 32
            implicitHeight: contentVert.implicitHeight + 12
            radius: width / 2
            color: indicator.colContainer

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            ColumnLayout {
                id: contentVert
                anchors.centerIn: parent
                spacing: 2

                PulsingMic {
                    Layout.alignment: Qt.AlignHCenter
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: indicator.busy && !indicator.transcribing
                    text: indicator.formatTime(indicator.elapsedSeconds).substring(0, 2)
                    color: indicator.colOnContainer
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: indicator.busy && !indicator.transcribing
                    text: indicator.formatTime(indicator.elapsedSeconds).substring(3, 5)
                    color: indicator.colOnContainer
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: DictationService.languageBadge
                    color: indicator.colOnContainer
                    opacity: 0.7
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    onClicked: mouse => {
        if (mouse.button !== Qt.LeftButton)
            return;
        if (indicator.clickToShowPopup)
            return;
        // Idle: start. Busy: finish now, which types what has been heard so far.
        if (indicator.idleButton)
            DictationService.toggle();
        else
            DictationService.stop();
        detailsPopup.close();
    }

    StyledPopup {
        id: detailsPopup
        hoverTarget: indicator
        stickyHover: true
        popupRadius: Appearance.rounding.large

        contentItem: ColumnLayout {
            id: popupLayout
            spacing: 10
            // HeroCard elides rather than wraps, and its mic takes 64px off the
            // left before the text column starts, so the width has to come from
            // the longest subtitle rather than from the card's own default.
            implicitWidth: 360

            // The cards fly in once the surface itself has mostly unfolded, the
            // same staggered entrance every other bar popup uses.
            readonly property bool startAnim: detailsPopup.opened && detailsPopup.popupOpenProgress > 0.6

            function resetCards() {
                heroCard.opacity = 0.0;
                heroCard.scale = 0.85;
                heroCardTransform.y = 25;

                targetCard.opacity = 0.0;
                targetCard.scale = 0.85;
                targetCardTransform.y = 25;

                actionsRow.opacity = 0.0;
                actionsRow.scale = 0.85;
                actionsRowTransform.y = 25;
            }

            onStartAnimChanged: {
                if (!popupLayout.startAnim)
                    return;
                popupLayout.resetCards();
                Qt.callLater(function () {
                    heroCardAnim.start();
                    targetCardAnim.start();
                    actionsRowAnim.start();
                });
            }

            Connections {
                target: detailsPopup
                // Only once the surface has fully collapsed. Resetting at the
                // start of the close would empty the popup before it shrinks.
                function onPopupOpenProgressChanged() {
                    if (detailsPopup.popupOpenProgress !== 0.0)
                        return;
                    heroCardAnim.stop();
                    targetCardAnim.stop();
                    actionsRowAnim.stop();
                    popupLayout.resetCards();
                }
            }

            HeroCard {
                id: heroCard
                Layout.fillWidth: true
                startAnim: popupLayout.startAnim

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: heroCardTransform
                    y: 25
                }

                SequentialAnimation {
                    id: heroCardAnim
                    PauseAnimation { duration: 40 }
                    ParallelAnimation {
                        NumberAnimation { target: heroCard; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: heroCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: heroCardTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                compactMode: true
                implicitWidth: 360
                implicitHeight: 125
                titleSize: Appearance.font.pixelSize.larger
                subtitleSize: Appearance.font.pixelSize.smaller

                icon: indicator.transcribing ? "graphic_eq" : "mic"
                title: {
                    if (indicator.transcribing)
                        return Translation.tr("Transcribing…");
                    if (indicator.idleButton)
                        return Translation.tr("Dictate");
                    return Translation.tr("Dictating…");
                }
                subtitle: {
                    if (indicator.transcribing)
                        return Translation.tr("Turning speech into text");
                    if (indicator.idleButton)
                        return DictationService.available
                            ? Translation.tr("Click to start dictating")
                            : Translation.tr("Not ready — see Settings");
                    return Config.options.dictation.outputMode === "clipboard"
                        ? Translation.tr("Click to stop and copy text")
                        : Translation.tr("Click to stop and insert text");
                }

                // Only the clock earns the pill. The model's name is far longer
                // than the corner can hold and comes back elided to "Whisper —
                // Acc…", which tells the reader nothing.
                pillText: indicator.busy ? indicator.formatTime(indicator.elapsedSeconds) : ""
                pillIcon: indicator.busy ? "timer" : ""
                pillColor: indicator.transcribing ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
                pillTextColor: Appearance.colors.colOnPrimary
                pillIconColor: Appearance.colors.colOnPrimary
            }

            // Where the text is about to land. Dictation aims at another window
            // by definition, and the wrong one being focused is the mistake
            // worth catching before pressing stop rather than after.
            Rectangle {
                id: targetCard
                Layout.fillWidth: true
                implicitHeight: targetRow.implicitHeight + 18
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: targetCardTransform
                    y: 25
                }

                SequentialAnimation {
                    id: targetCardAnim
                    PauseAnimation { duration: 100 }
                    ParallelAnimation {
                        NumberAnimation { target: targetCard; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: targetCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: targetCardTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                RowLayout {
                    id: targetRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    MaterialSymbol {
                        text: "web_asset"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: indicator.targetTitle
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: DictationService.languageBadge
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            RowLayout {
                id: actionsRow
                Layout.fillWidth: true
                spacing: 8

                opacity: 0.0
                scale: 0.85
                transform: Translate {
                    id: actionsRowTransform
                    y: 25
                }

                SequentialAnimation {
                    id: actionsRowAnim
                    PauseAnimation { duration: 160 }
                    ParallelAnimation {
                        NumberAnimation { target: actionsRow; property: "opacity"; to: 1.0; duration: 300 }
                        NumberAnimation { target: actionsRow; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        NumberAnimation { target: actionsRowTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    visible: indicator.idleButton
                    buttonRadius: Appearance.rounding.full
                    materialIcon: "mic"
                    mainText: Translation.tr("Start dictating")
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    colText: Appearance.colors.colOnPrimary
                    onClicked: {
                        DictationService.toggle();
                        detailsPopup.close();
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    visible: indicator.busy
                    buttonRadius: Appearance.rounding.full
                    materialIcon: "keyboard_tab"
                    mainText: Config.options.dictation.outputMode === "clipboard"
                        ? Translation.tr("Stop & copy")
                        : Translation.tr("Stop & insert")
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    colText: Appearance.colors.colOnPrimary
                    onClicked: {
                        DictationService.stop();
                        detailsPopup.close();
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    visible: indicator.busy
                    buttonRadius: Appearance.rounding.full
                    materialIcon: "delete"
                    mainText: Translation.tr("Discard")
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    colRipple: Appearance.colors.colErrorContainerActive
                    colText: Appearance.colors.colOnErrorContainer
                    onClicked: {
                        DictationService.discard();
                        detailsPopup.close();
                    }
                }
            }
        }
    }
}
