pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings v2 – Search Bar
 *
 * Layout (horizontal, fills parent width):
 *   [ Rectangle (colLayer1, rounding.full, height 56) containing:
 *       [MaterialShape circle: search icon (40x40, centered/8px margins)]
 *       [ToolbarTextField (colLayer2 background, height 40, centered/8px margins)]
 *   ]
 *   [RippleButton circle: close, same height as rectangle (56x56)]
 *
 * Signals:
 *   - accepted()          → user pressed Enter to cycle through results
 *   - closeRequested()    → user clicked the close/X button
 *
 * Bindable properties:
 *   - lastSearchIndex / resultsCount → used to show "n/total" inside the icon
 */
RowLayout {
    id: root

    spacing: 8
    implicitHeight: 56

    // ── Public state (bind from parent) ────────────────────────────────────
    property int lastSearchIndex: -1
    property int resultsCount: 0

    // ── Signals ────────────────────────────────────────────────────────────
    signal accepted(string text)
    signal closeRequested
    signal textChanged(string text)

    // ── Shake animation (called on "no more results") ──────────────────────
    function shakeNoResults() {
        noMoreResultsAnim.restart();
    }

    // ── Force focus ────────────────────────────────────────────────────────
    function forceFocus() {
        searchInput.forceActiveFocus();
    }

    // ── Left: Main input area rectangle (fills full height 56) ─────────────
    Rectangle {
        id: searchInputContainer
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.full

        border.color: searchInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        border.width: searchInput.activeFocus ? 2 : 1

        Behavior on border.color {
            ColorAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        Behavior on border.width {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        // Shake animation targets the whole search container
        SequentialAnimation {
            id: noMoreResultsAnim
            NumberAnimation {
                target: searchInputContainer
                property: "Layout.leftMargin"
                to: -12
                duration: 50
            }
            NumberAnimation {
                target: searchInputContainer
                property: "Layout.leftMargin"
                to: 12
                duration: 50
            }
            NumberAnimation {
                target: searchInputContainer
                property: "Layout.leftMargin"
                to: -8
                duration: 40
            }
            NumberAnimation {
                target: searchInputContainer
                property: "Layout.leftMargin"
                to: 8
                duration: 40
            }
            NumberAnimation {
                target: searchInputContainer
                property: "Layout.leftMargin"
                to: 0
                duration: 30
            }
        }

        RowLayout {
            anchors {
                fill: parent
                margins: 8
            }
            spacing: 8

            // Left inside rectangle: search icon circle (40x40, centered with 8px margins)
            MaterialShapeWrappedMaterialSymbol {
                id: searchIconShape
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 40
                Layout.fillHeight: true
                iconSize: 18
                shape: MaterialShape.Shape.Circle
                animateChange: true

                // Show "n/total" text when there are results
                readonly property bool _showCount: root.lastSearchIndex !== -1 && root.resultsCount > 0
                text: _showCount ? "" : "search"

                StyledText {
                    id: resultCountText
                    visible: false
                    animateChange: true
                    anchors.centerIn: parent
                    text: (root.lastSearchIndex % Math.max(root.resultsCount, 1) + 1) + "/" + root.resultsCount
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                }

                // Delay show so icon fade-out has time
                Connections {
                    target: searchIconShape
                    function on_ShowCountChanged() {
                        if (!searchIconShape._showCount) {
                            resultCountText.visible = false;
                        } else {
                            showCountTimer.restart();
                        }
                    }
                }
                Timer {
                    id: showCountTimer
                    interval: 100
                    repeat: false
                    onTriggered: resultCountText.visible = true
                }
            }

            // Right inside rectangle: visible text field (40x40, centered with 8px margins)
            ToolbarTextField {
                id: searchInput
                Layout.fillWidth: true
                Layout.fillHeight: true
                colBackground: Appearance.colors.colLayer2Base
                font.pixelSize: Appearance.font.pixelSize.small
                placeholderText: Translation.tr("Search all settings..")

                Component.onCompleted: {
                    searchInput.forceActiveFocus();
                }

                onTextChanged: root.textChanged(text)
                onAccepted: root.accepted(text)
            }
        }
    }

    // ── Right: close button circle (same height as outer rectangle, i.e., 56x56) ──
    RippleButton {
        id: closeBtn
        Layout.alignment: Qt.AlignVCenter
        buttonRadius: Appearance.rounding.full
        Layout.preferredWidth: 56
        Layout.preferredHeight: 56
        Layout.fillHeight: true

        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        scale: closeBtn.down ? 0.92 : (closeBtn.hovered ? 1.06 : 1.0)
        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutBack
            }
        }

        onClicked: root.closeRequested()

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: "close"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }
}
