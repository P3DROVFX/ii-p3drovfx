pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Inline editor action bar: the selection size as the hero number, Copy as the
// one filled call to action, Save tonal, and the rarer actions as icons. The
// owner places it (x/y/visible) and wires the *Requested signals.
Toolbar {
    id: actionBar

    padding: 6
    spacing: 4
    implicitHeight: 56
    width: implicitWidth
    height: implicitHeight

    // Selection size in capture pixels.
    property int physW: 0
    property int physH: 0
    readonly property bool sharp: Appearance.rounding.scale === 0
    property bool exportMenuOpen: false

    signal copyRequested()
    signal saveRequested()
    signal saveAsRequested()
    signal extractTextRequested()
    signal openWithRequested()
    signal searchRequested()
    signal copyPathRequested()
    signal cancelRequested()

    opacity: visible ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Labelled action. `primary` is the bar's one filled call to
    // action; the rest are tonal.
    component ActionButton: RippleButton {
        id: ab
        property string symbolName: ""
        property string labelText: ""
        property bool primary: false
        readonly property color colText: primary ? Appearance.colors.colOnPrimary : (toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface)
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 44
        implicitWidth: abRow.implicitWidth + 32
        buttonRadius: (Appearance.rounding.scale === 0) ? 0 : height / 2

        colBackground: primary ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighest
        colRipple: primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        contentItem: Item {
            Row {
                id: abRow
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    iconSize: 20
                    text: ab.symbolName
                    fill: ab.primary || ab.toggled ? 1 : 0
                    color: ab.colText
                    animateChange: true
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ab.labelText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: ab.colText
                }
            }
        }
    }

    // Icon-only action; the label lives in the tooltip. Pressed or
    // toggled it squares off, like the editor's tools.
    component IconAction: RippleButton {
        id: ia
        property string symbolName: ""
        property string tip: ""
        property bool danger: false
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 44
        implicitWidth: 44
        buttonRadius: (Appearance.rounding.scale === 0) ? 0 : (toggled ? Math.min(height * 0.3, Appearance.rounding.normal) : height / 2)
        colBackground: "transparent"
        colBackgroundHover: danger ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHighest
        colRipple: danger ? Appearance.colors.colErrorContainerActive : Appearance.colors.colSurfaceContainerHighestActive
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 22
                text: ia.symbolName
                fill: ia.toggled ? 1 : 0
                color: ia.toggled ? Appearance.colors.colOnSecondaryContainer : (ia.danger && ia.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurfaceVariant)
                animateChange: true
            }
        }

        StyledToolTip {
            z: 9999
            text: ia.tip
        }
    }

    // Size: the one number this bar is about, on its own tonal slab.
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: 4
        implicitWidth: sizeLabel.implicitWidth + 28
        implicitHeight: 44
        radius: actionBar.sharp ? 0 : height / 2
        color: Appearance.colors.colPrimaryContainer

        RegionSizeLabel {
            id: sizeLabel
            anchors.centerIn: parent
            sizeW: actionBar.physW
            sizeH: actionBar.physH
            digitSize: 24
            colDigits: Appearance.colors.colOnPrimaryContainer
        }
    }

    ActionButton {
        primary: true
        symbolName: "content_copy"
        labelText: Translation.tr("Copy")
        onClicked: actionBar.copyRequested()
    }
    ActionButton {
        symbolName: "save"
        labelText: Translation.tr("Save")
        onClicked: actionBar.saveRequested()
    }
    IconAction {
        Layout.leftMargin: 2
        symbolName: "save_as"
        tip: Translation.tr("Save As...")
        onClicked: actionBar.saveAsRequested()
    }
    IconAction {
        symbolName: "document_scanner"
        tip: Translation.tr("Extract Text")
        onClicked: actionBar.extractTextRequested()
    }

    Item {
        id: exportContainer
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: exportBtn.implicitWidth
        implicitHeight: exportBtn.implicitHeight

        IconAction {
            id: exportBtn
            anchors.fill: parent
            symbolName: "ios_share"
            tip: Translation.tr("Export")
            toggled: actionBar.exportMenuOpen
            onClicked: actionBar.exportMenuOpen = !actionBar.exportMenuOpen
        }

        Item {
            id: exportMenu
            readonly property bool openBelow: actionBar.y < height + 16
            readonly property real restY: openBelow ? (parent.height + 10) : (-height - 10)
            width: exportCol.implicitWidth + 12
            height: exportCol.implicitHeight + 12
            anchors.horizontalCenter: parent.horizontalCenter
            visible: opacity > 0
            opacity: actionBar.exportMenuOpen ? 1 : 0
            y: restY + (actionBar.exportMenuOpen ? 0 : (openBelow ? -8 : 8))

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on y {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            StyledRectangularShadow {
                target: exportMenuSurface
            }

            Rectangle {
                id: exportMenuSurface
                anchors.fill: parent
                radius: actionBar.sharp ? 0 : Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainer
            }

            component MenuItem: RippleButton {
                id: mi
                property string symbolName: ""
                property string labelText: ""
                implicitWidth: Math.max(224, miRow.implicitWidth + 28)
                implicitHeight: 44
                buttonRadius: (Appearance.rounding.scale === 0) ? 0 : (mi.hovered ? height / 2 : Appearance.rounding.small)
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                colRipple: Appearance.colors.colSurfaceContainerHighestActive

                contentItem: Item {
                    Row {
                        id: miRow
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            iconSize: 20
                            text: mi.symbolName
                            fill: mi.hovered ? 1 : 0
                            color: mi.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: mi.labelText
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }
            }

            Column {
                id: exportCol
                anchors.centerIn: parent
                spacing: 2

                MenuItem {
                    symbolName: "open_in_new"
                    labelText: Translation.tr("Open with default app")
                    onClicked: {
                        actionBar.exportMenuOpen = false;
                        actionBar.openWithRequested();
                    }
                }
                MenuItem {
                    symbolName: "image_search"
                    labelText: Translation.tr("Reverse image search")
                    onClicked: {
                        actionBar.exportMenuOpen = false;
                        actionBar.searchRequested();
                    }
                }
                MenuItem {
                    symbolName: "link"
                    labelText: Translation.tr("Copy file path")
                    onClicked: {
                        actionBar.exportMenuOpen = false;
                        actionBar.copyPathRequested();
                    }
                }
            }
        }
    }

    IconAction {
        danger: true
        symbolName: "close"
        tip: Translation.tr("Cancel")
        onClicked: actionBar.cancelRequested()
    }
}
