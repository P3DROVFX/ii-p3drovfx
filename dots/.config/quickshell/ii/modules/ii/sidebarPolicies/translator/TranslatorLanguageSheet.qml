pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The language list, as a page that rises over the translator tab: the sidebar has no
 * room beside the panes for a side sheet, so it covers them the way a sheet takes the
 * full width of a compact Clock window.
 *
 * Search as you type (accents ignored), arrows move through the matches, Enter picks,
 * Esc goes back. The current language is the selected row; each row carries its
 * initial in a shape badge.
 */
Rectangle {
    id: root

    property var languages: []
    property string current: ""
    /// Picking the language to translate into: "Detect language" makes no sense there.
    property bool forTarget: false

    signal picked(string language)
    signal dismissed()

    function displayName(lang: string): string {
        return lang === "auto" ? Translation.tr("Detect language") : lang;
    }

    function fold(text: string): string {
        return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    }

    readonly property var matches: {
        const query = root.fold(searchField.text.trim());
        return root.languages.filter(lang => {
            if (root.forTarget && lang === "auto")
                return false;
            if (query.length === 0)
                return true;
            return root.fold(root.displayName(lang)).includes(query) || (lang === "auto" && "auto".includes(query));
        });
    }

    readonly property int selectedIndex: root.matches.indexOf(root.current)

    function pickCurrent() {
        if (list.currentIndex >= 0 && list.currentIndex < root.matches.length)
            root.picked(root.matches[list.currentIndex]);
    }

    color: Appearance.colors.colLayer0

    // Entrance: a fade and a short rise, once.
    opacity: 0
    transform: Translate {
        id: rise
        y: ClockStyle.enterOffset
    }
    ParallelAnimation {
        id: entrance
        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: ClockStyle.motionEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        NumberAnimation {
            target: rise
            property: "y"
            to: 0
            duration: ClockStyle.motionEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    Component.onCompleted: {
        if (ClockStyle.reducedMotion) {
            root.opacity = 1;
            rise.y = 0;
        } else {
            entrance.start();
        }
        searchField.forceActiveFocus();
        list.currentIndex = Math.max(0, root.matches.indexOf(root.current));
    }

    // The page swallows the clicks that land between its controls.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Appearance.rounding.small
        }
        spacing: ClockStyle.gapSmall

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: ClockStyle.gapTiny
            spacing: ClockStyle.gapSmall

            ClockIconButton {
                symbol: "arrow_back"
                tooltip: Translation.tr("Back")
                onClicked: root.dismissed()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.forTarget ? Translation.tr("Translate into") : Translation.tr("Translate from")
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textTitle
                    color: ClockStyle.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 languages").arg(root.languages.length - 1)
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // ── Search ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: ClockStyle.rowHeight
            radius: ClockStyle.pill(ClockStyle.rowHeight)
            color: searchField.activeFocus ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh
            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: ClockStyle.gapLarge + 2
                    rightMargin: ClockStyle.gapSmall
                }
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: "search"
                    iconSize: ClockStyle.iconNormal - 2
                    color: ClockStyle.colOnSurfaceVariant
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    padding: 0
                    verticalAlignment: TextInput.AlignVCenter
                    background: null
                    placeholderText: Translation.tr("Search languages")
                    placeholderTextColor: ClockStyle.colSubtext
                    color: ClockStyle.colOnSurface
                    selectedTextColor: ClockStyle.colOnSecondaryContainer
                    selectionColor: ClockStyle.colSecondaryContainer
                    font.family: ClockStyle.fontMain
                    font.pixelSize: ClockStyle.textLarge
                    onTextChanged: list.currentIndex = root.matches.length > 0 ? 0 : -1

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.dismissed();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            list.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            list.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.pickCurrent();
                            event.accepted = true;
                        }
                    }
                }

                ClockIconButton {
                    size: 36
                    iconSize: ClockStyle.iconSmall + 2
                    symbol: "close"
                    tooltip: Translation.tr("Clear")
                    visible: searchField.text.length > 0
                    onClicked: {
                        searchField.text = "";
                        searchField.forceActiveFocus();
                    }
                }
            }
        }

        // ── List ────────────────────────────────────────────────────────
        // The settings sidebar's scheme: rows scroll under rounded corners — painted
        // corner pieces over an opaque page, a layer mask only when it is translucent.
        Rectangle {
            id: listContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.large
            color: Appearance.colors.colLayer0
            readonly property bool opaqueBackground: Appearance.colors.colLayer0.a >= 1

            layer.enabled: !listContainer.opaqueBackground
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: listMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Rectangle {
                id: listMask
                width: listContainer.width
                height: listContainer.height
                radius: listContainer.radius
                visible: false
                layer.enabled: true
            }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 4

                /// The row being pressed: its neighbours round the corners facing it.
                property int pressedIndex: -1
                model: root.matches
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                keyNavigationWraps: false

                TouchpadScrollHandler {
                    flickable: list
                }

                // Centre the current language once the list has its real height;
                // positioning at creation lands against a zero-height view.
                property bool centred: false
                onHeightChanged: {
                    if (list.centred || list.height <= 0)
                        return;
                    list.centred = true;
                    Qt.callLater(() => list.positionViewAtIndex(list.currentIndex, ListView.Center));
                }

                delegate: RippleButton {
                    id: row
                    required property string modelData
                    required property int index

                    readonly property bool selected: row.modelData === root.current
                    readonly property bool keyboardCurrent: ListView.isCurrentItem && searchField.activeFocus

                    width: list.width
                    implicitHeight: ClockStyle.rowHeight

                    // Smart radius, as in the settings sidebar: the list is one group
                    // (large outer corners, tight joins); the selected and the pressed row
                    // become pills and the rows facing them round those corners too.
                    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(ClockStyle.rowHeight / 2, Appearance.rounding.large)
                    readonly property real rLarge: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.large
                    readonly property real rSmall: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.verysmall
                    readonly property bool topPill: row.selected || row.down
                        || row.index - 1 === root.selectedIndex || row.index - 1 === list.pressedIndex
                    readonly property bool bottomPill: row.selected || row.down
                        || row.index + 1 === root.selectedIndex || row.index + 1 === list.pressedIndex
                    property real rTop: row.topPill ? row.rFull : (row.index === 0 ? row.rLarge : row.rSmall)
                    property real rBottom: row.bottomPill ? row.rFull : (row.index === list.count - 1 ? row.rLarge : row.rSmall)
                    Behavior on rTop {
                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                    }
                    Behavior on rBottom {
                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                    }

                    topLeftRadius: row.rTop
                    topRightRadius: row.rTop
                    bottomLeftRadius: row.rBottom
                    bottomRightRadius: row.rBottom
                    colBackground: row.selected ? ClockStyle.colPrimary
                        : row.keyboardCurrent ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                    colBackgroundHover: row.selected ? ClockStyle.colPrimaryHover : Appearance.colors.colLayer2Hover
                    colRipple: row.selected ? ClockStyle.colPrimaryActive : Appearance.colors.colLayer2Active
                    onDownChanged: {
                        if (row.down)
                            list.pressedIndex = row.index;
                        else if (list.pressedIndex === row.index)
                            list.pressedIndex = -1;
                    }
                    onClicked: root.picked(row.modelData)

                    contentItem: Item {
                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: ClockStyle.gapSmall
                                rightMargin: ClockStyle.gapLarge
                            }
                            spacing: ClockStyle.gap

                            // The language's initial in a badge; "detect" gets its own glyph.
                            Item {
                                implicitWidth: 36
                                implicitHeight: 36

                                MaterialShape {
                                    anchors.fill: parent
                                    shape: row.modelData === "auto" ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie4Sided
                                    color: row.selected ? ClockStyle.colOnPrimary : ClockStyle.colSecondaryContainer
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: row.modelData === "auto"
                                    text: "auto_awesome"
                                    iconSize: ClockStyle.iconSmall + 2
                                    fill: 1
                                    color: row.selected ? ClockStyle.colPrimary : ClockStyle.colOnSecondaryContainer
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: row.modelData !== "auto"
                                    text: Array.from(row.modelData)[0]?.toUpperCase() ?? ""
                                    font.pixelSize: ClockStyle.textNormal
                                    font.weight: Font.Bold
                                    color: row.selected ? ClockStyle.colPrimary : ClockStyle.colOnSecondaryContainer
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.displayName(row.modelData)
                                font.pixelSize: ClockStyle.textLarge - 1
                                font.weight: row.selected ? Font.DemiBold : Font.Normal
                                color: row.selected ? ClockStyle.colOnPrimary : Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }

                            MaterialSymbol {
                                visible: row.selected
                                text: "check"
                                iconSize: ClockStyle.iconNormal - 2
                                color: ClockStyle.colOnPrimary
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - ClockStyle.gapHuge * 2
                visible: root.matches.length === 0
                spacing: ClockStyle.gapSmall

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "search_off"
                    iconSize: 28
                    padding: 16
                    shape: MaterialShape.Shape.Cookie7Sided
                    color: ClockStyle.colSecondaryContainer
                    colSymbol: ClockStyle.colOnSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("No language matches “%1”").arg(searchField.text.trim())
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colOnSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }

            CornerCutouts {
                anchors.fill: parent
                visible: listContainer.opaqueBackground
                radius: listContainer.radius
                color: Appearance.colors.colLayer0
            }
        }
    }
}
