pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

// Lyrics provider picker shared by Lyrics Studio and the Immersive options sheet.
Row {
    id: root
    property color accentColor: Appearance.colors.colPrimary
    property color surfaceColor: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
    property color surfaceHoverColor: Appearance.colors.colLayer2Hover
    property color surfaceActiveColor: Appearance.colors.colLayer2Active
    property color onSurfaceColor: Appearance.colors.colOnLayer2
    /// Icon on the selected provider; defaults to the accent over its tinted fill.
    property color activeIconColor: accentColor
    property real activeFillOpacity: 0.75
    property real buttonSize: 28
    spacing: 4

    Repeater {
        model: [
            {
                key: "auto",
                icon: "auto_awesome",
                tip: Translation.tr("Auto (LRC → YTMusic → Genius)")
            },
            {
                key: "lrclib",
                icon: "timer",
                tip: Translation.tr("LRCLib synced/plain")
            },
            {
                key: "ytmusic",
                icon: "smart_display",
                tip: Translation.tr("YouTube Music")
            },
            {
                key: "genius",
                icon: "music_note",
                tip: Translation.tr("Genius (plain)")
            }
        ]

        delegate: RippleButton {
            id: providerButton
            required property var modelData
            implicitWidth: root.buttonSize
            implicitHeight: root.buttonSize
            buttonRadius: Appearance.rounding.full
            readonly property bool isActive: Config.options.lyricsService.lyricsProvider === modelData.key
            colBackground: isActive ? ColorUtils.applyAlpha(root.accentColor, root.activeFillOpacity) : root.surfaceColor
            colBackgroundHover: isActive ? ColorUtils.applyAlpha(root.accentColor, Math.min(1, root.activeFillOpacity + 0.1))
                                      : root.surfaceHoverColor
            colBackgroundActive: root.surfaceActiveColor

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: root.buttonSize / 2
                color: providerButton.isActive ? root.activeIconColor : root.onSurfaceColor
                text: providerButton.modelData.icon
            }
            onClicked: {
                Config.options.lyricsService.lyricsProvider = modelData.key;
                LyricsService.initiliazeLyrics();
            }
            PopupToolTip {
                text: providerButton.modelData.tip
            }
        }
    }
}
