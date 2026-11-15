import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * M3E 3-segment mutually-exclusive phone service switcher (ii tools | KDE Connect | Off).
 */
Rectangle {
    id: root

    property string currentService: "off"
    property bool interactive: true
    // false once KDE Connect is known to be missing: its segment stays, greyed.
    property bool kdeAvailable: true

    signal selected(string service)

    implicitHeight: 50
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer1
    opacity: root.interactive ? 1.0 : 0.55

    readonly property var _segments: [
        { id: "iiTools", label: Translation.tr("ii tools"), icon: "phonelink" },
        { id: "kdeconnect", label: Translation.tr("KDE Connect"), icon: "smartphone" },
        { id: "off", label: Translation.tr("Off"), icon: "sync_disabled" }
    ]

    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        Repeater {
            model: root._segments

            delegate: Rectangle {
                id: seg
                required property var modelData
                readonly property bool chosen: root.currentService === modelData.id
                readonly property bool offVariant: modelData.id === "off"
                readonly property bool unavailable: modelData.id === "kdeconnect" && !root.kdeAvailable && !seg.chosen
                opacity: seg.unavailable ? 0.45 : 1

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.full
                color: seg.chosen
                    ? (seg.offVariant ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary)
                    : (segHover.hovered ? ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.06) : "transparent")

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: seg.modelData.icon
                        iconSize: 18
                        fill: seg.chosen ? 1 : 0
                        color: seg.chosen
                            ? (seg.offVariant ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnPrimary)
                            : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: seg.unavailable ? Translation.tr("%1 · Not found").arg(seg.modelData.label) : seg.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.variableAxes: seg.chosen ? Appearance.font.variableAxes.title : Appearance.font.variableAxes.main
                        font.weight: seg.chosen ? Font.DemiBold : Font.Medium
                        color: seg.chosen
                            ? (seg.offVariant ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnPrimary)
                            : Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    anchors.fill: parent
                    buttonRadius: parent.radius
                    colBackground: "transparent"
                    colBackgroundHover: "transparent"
                    colRipple: ColorUtils.applyAlpha(
                        seg.chosen && !seg.offVariant ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary,
                        0.14
                    )
                    enabled: root.interactive && !seg.unavailable
                    onClicked: root.selected(seg.modelData.id)
                }

                HoverHandler {
                    id: segHover
                    cursorShape: root.interactive && !seg.unavailable ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }
    }
}
