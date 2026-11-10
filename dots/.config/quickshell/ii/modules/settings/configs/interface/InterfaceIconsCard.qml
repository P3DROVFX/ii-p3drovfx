pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The themed icon pack as a full-width card: the feature tile's states (primary container
 * and a morphing shape while on), and while it is on a strip of real application icons
 * unfolds under the header, drawn through the shell's own icon lookup so they are the icons
 * the dock and launcher show. `configureRequested` opens the pack's sub-page.
 */
Rectangle {
    id: root

    readonly property real padding: 20
    readonly property real headerSpacing: 14
    readonly property real iconSize: 24
    readonly property real iconPadding: 12
    readonly property real compactBreak: 520
    readonly property real buttonHeight: 36
    readonly property real stripGap: 10
    readonly property real stripTop: 16
    readonly property real tileSize: 60
    readonly property real glyphSize: 40
    readonly property real tileTint: 0.08
    readonly property int maxIcons: 8
    readonly property var candidates: ["firefox", "kitty", "org.gnome.Nautilus", "code", "steam", "spotify", "discord", "telegram-desktop", "vlc", "gimp", "obsidian", "thunderbird"]

    property string symbol: ""
    property var shapeOn: MaterialShape.Shape.Cookie12Sided
    property var shapeOff: MaterialShape.Shape.Circle
    property string title: ""
    property string summary: ""
    property bool checked: false

    signal toggled(bool value)
    signal configureRequested()

    readonly property bool engaged: cardHover.hovered
    readonly property bool compact: root.width < root.compactBreak
    readonly property color colContent: root.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
    readonly property var previewIcons: root.candidates
        .map(name => AppSearch.guessIcon(name))
        .filter((icon, index, all) => AppSearch.iconExists(icon) && all.indexOf(icon) === index)
        .slice(0, root.maxIcons)
    readonly property real stripHeight: root.previewIcons.length > 0 ? root.tileSize : 0
    readonly property real revealed: root.checked ? root.stripHeight : 0

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: root.checked
        ? (root.engaged ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }
    // Under the content, so the switch and the button keep their own clicks. It owns the
    // cursor: a MouseArea without one would put the arrow back over the whole card.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.configureRequested()
    }

    Component {
        id: configureComponent

        RippleButton {
            implicitHeight: root.buttonHeight
            implicitWidth: configureRow.implicitWidth + 28
            buttonRadius: height / 2
            buttonRadiusPressed: Appearance.rounding.small
            colBackground: ColorUtils.applyAlpha(root.colContent, 0.1)
            colBackgroundHover: ColorUtils.applyAlpha(root.colContent, 0.18)
            colBackgroundActive: ColorUtils.applyAlpha(root.colContent, 0.26)
            colRipple: ColorUtils.applyAlpha(root.colContent, 0.26)
            onClicked: root.configureRequested()

            contentItem: Item {
                RowLayout {
                    id: configureRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "tune"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.colContent
                    }
                    StyledText {
                        text: Translation.tr("Configure")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: root.colContent
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: root.headerSpacing

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: root.iconSize
                padding: root.iconPadding
                fill: root.checked ? 1 : 0
                shape: root.checked ? root.shapeOn : root.shapeOff
                color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: root.colContent
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.summary
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.colContent
                    opacity: 0.8
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: !root.compact
                visible: active
                sourceComponent: configureComponent
            }

            StyledSwitch {
                Layout.alignment: Qt.AlignVCenter
                sizeScale: 0.85
                checked: root.checked
                activeColor: Appearance.colors.colPrimary
                activeThumbColor: Appearance.colors.colOnPrimary
                inactiveColor: Appearance.colors.colSurfaceContainerHighest
                onToggled: root.toggled(checked)
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.topMargin: root.revealed > 0 ? root.stripTop : 0
            Layout.preferredHeight: root.revealed
            clip: true
            opacity: root.stripHeight > 0 ? root.revealed / root.stripHeight : 0

            Behavior on Layout.preferredHeight {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            Flow {
                width: parent.width
                height: root.stripHeight
                spacing: root.stripGap

                Repeater {
                    model: root.previewIcons

                    delegate: Rectangle {
                        id: slot

                        required property string modelData

                        width: root.tileSize
                        height: root.tileSize
                        radius: Appearance.rounding.normal
                        color: ColorUtils.applyAlpha(Appearance.colors.colOnPrimaryContainer, root.tileTint)

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: root.glyphSize
                            source: Quickshell.iconPath(slot.modelData, "image-missing")
                        }
                    }
                }
            }
        }

        Loader {
            Layout.topMargin: root.stripTop
            active: root.compact
            visible: active
            sourceComponent: configureComponent
        }
    }
}
