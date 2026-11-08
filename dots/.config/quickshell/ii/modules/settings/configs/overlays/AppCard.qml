import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One of the shell's own apps. The card is mostly a coloured plate — the app's accent
 * container while it is loaded, the pane colour while it is not — that holds the app:
 * its icon in its own shape, the name in the big title face, the live state and the app's
 * secondary options as chips, with the load switch top-right. A slim footer under the
 * plate carries the shortcut as keycaps and the filled Open button.
 */
Rectangle {
    id: root

    property string symbol: ""
    property var shape: MaterialShape.Shape.Cookie9Sided
    property string title: ""
    property string summary: ""
    property var keys: []
    property bool checked: false
    property bool canOpen: true
    property string warning: ""
    // "primary" | "secondary" | "tertiary": spread over the shelf so neighbours differ
    property string accent: "primary"
    default property alias chips: chipRow.data

    signal toggled(bool value)
    signal openRequested()

    readonly property color colPlate: !root.checked ? Appearance.colors.colLayer2
        : root.accent === "tertiary" ? Appearance.colors.colTertiaryContainer
        : root.accent === "secondary" ? Appearance.colors.colSecondaryContainer
        : Appearance.colors.colPrimaryContainer
    readonly property color colOnPlate: !root.checked ? Appearance.colors.colOnLayer2
        : root.accent === "tertiary" ? Appearance.colors.colOnTertiaryContainer
        : root.accent === "secondary" ? Appearance.colors.colOnSecondaryContainer
        : Appearance.colors.colOnPrimaryContainer
    readonly property color colStrong: root.accent === "tertiary" ? Appearance.colors.colTertiary
        : root.accent === "secondary" ? Appearance.colors.colSecondary
        : Appearance.colors.colPrimary
    readonly property color colOnStrong: root.accent === "tertiary" ? Appearance.colors.colOnTertiary
        : root.accent === "secondary" ? Appearance.colors.colOnSecondary
        : Appearance.colors.colOnPrimary

    readonly property bool engaged: cardHover.hovered
    readonly property int footerHeight: 60

    radius: Appearance.rounding.verylarge
    color: root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    HoverHandler { id: cardHover }

    // ── plate: the app ──
    Rectangle {
        id: plate
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            margins: 6
            bottomMargin: root.footerHeight
        }
        radius: Appearance.rounding.verylarge - 6
        color: root.colPlate
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

        ColumnLayout {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.symbol
                    iconSize: 28
                    padding: 14
                    fill: root.checked ? 1 : 0
                    shape: root.checked ? root.shape : MaterialShape.Shape.Circle
                    color: root.checked ? root.colStrong : Appearance.colors.colSurfaceContainerHighest
                    colSymbol: root.checked ? root.colOnStrong : Appearance.colors.colOnSurface
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.title
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: root.colOnPlate
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: root.checked ? Translation.tr("Loaded") : Translation.tr("Off")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: root.colOnPlate
                        opacity: 0.75
                    }
                }

                StyledSwitch {
                    Layout.alignment: Qt.AlignTop
                    sizeScale: 0.85
                    checked: root.checked
                    activeColor: root.colStrong
                    activeThumbColor: root.colOnStrong
                    inactiveColor: Appearance.colors.colSurfaceContainerHighest
                    onToggled: root.toggled(checked)
                }
            }

            StyledText {
                id: summaryText
                Layout.fillWidth: true
                Layout.preferredHeight: summaryMetrics.height * 2
                text: root.warning.length > 0 ? root.warning : root.summary
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.warning.length > 0 ? Appearance.colors.colError : root.colOnPlate
                opacity: root.warning.length > 0 ? 1 : 0.85
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
                FontMetrics {
                    id: summaryMetrics
                    font: summaryText.font
                }
            }
        }

        RowLayout {
            id: chipRow
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 12
            spacing: 6
        }
    }

    // ── footer: shortcut + open ──
    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 18
            rightMargin: 10
            bottomMargin: 10
        }
        height: root.footerHeight - 16
        spacing: 4

        Repeater {
            model: root.keys
            delegate: Rectangle {
                required property string modelData
                implicitHeight: 26
                implicitWidth: Math.max(26, keyText.implicitWidth + 14)
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colSurfaceContainerHighest
                StyledText {
                    id: keyText
                    anchors.centerIn: parent
                    text: parent.modelData
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        RippleButton {
            implicitHeight: 40
            implicitWidth: openRow.implicitWidth + 30
            buttonRadius: height / 2
            buttonRadiusPressed: Appearance.rounding.small
            enabled: root.checked && root.canOpen
            opacity: enabled ? 1 : 0.4
            colBackground: root.colStrong
            colBackgroundHover: ColorUtils.mix(root.colStrong, root.colOnStrong, 0.9)
            colRipple: ColorUtils.mix(root.colStrong, root.colOnStrong, 0.8)
            onClicked: root.openRequested()
            contentItem: Item {
                RowLayout {
                    id: openRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.colOnStrong
                    }
                    StyledText {
                        text: Translation.tr("Open")
                        font.weight: Font.DemiBold
                        color: root.colOnStrong
                    }
                }
            }
        }
    }
}
