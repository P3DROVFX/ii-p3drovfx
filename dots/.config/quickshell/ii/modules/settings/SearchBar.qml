pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings v2 – Search Bar
 *
 * Layout (horizontal, fills parent width, height 56):
 *   [MaterialShape 56x56: search icon / clear button]
 *   [ToolbarTextField 56 height: main input pill field containing internal 40x40 enter button]
 *   [RippleButton 56x56: close window button]
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

    // Shake animation targets search input
    SequentialAnimation {
        id: noMoreResultsAnim
        NumberAnimation {
            target: searchInput
            property: "Layout.leftMargin"
            to: -12
            duration: 50
        }
        NumberAnimation {
            target: searchInput
            property: "Layout.leftMargin"
            to: 12
            duration: 50
        }
        NumberAnimation {
            target: searchInput
            property: "Layout.leftMargin"
            to: -8
            duration: 40
        }
        NumberAnimation {
            target: searchInput
            property: "Layout.leftMargin"
            to: 8
            duration: 40
        }
        NumberAnimation {
            target: searchInput
            property: "Layout.leftMargin"
            to: 0
            duration: 30
        }
    }

    // 1. Left: Search icon & Clear button (56x56 1:1 shape)
    MaterialShapeWrappedMaterialSymbol {
        id: searchIconShape
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 56
        Layout.preferredHeight: 56
        iconSize: 22

        readonly property bool hasText: searchInput.text.length > 0

        color: {
            if (hasText) {
                return searchIconMouseArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary;
            } else {
                return searchIconMouseArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2;
            }
        }
        colSymbol: hasText ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2

        Behavior on color {
            ColorAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        animateChange: true

        // Rounded silhouettes keep enough quiet space for the result counter.
        // The previous sequence mixed flowers and sunbursts into the 56px
        // badge, making the count look cramped and retargeting the morph before
        // its 350ms animation had finished.
        readonly property var indicatorShapes: [
            MaterialShape.Shape.Circle,
            MaterialShape.Shape.Cookie4Sided,
            MaterialShape.Shape.Cookie6Sided,
            MaterialShape.Shape.Cookie7Sided,
            MaterialShape.Shape.Cookie9Sided,
            MaterialShape.Shape.Cookie12Sided,
            MaterialShape.Shape.Clover4Leaf,
            MaterialShape.Shape.Clover8Leaf,
            MaterialShape.Shape.Puffy,
            MaterialShape.Shape.Bun
        ]

        property int currentShapeIndex: 0
        property bool shapePending: false

        readonly property bool isHoveredAndHasText: searchIconMouseArea.containsMouse && hasText

        shape: isHoveredAndHasText ? MaterialShape.Shape.SoftBurst : indicatorShapes[currentShapeIndex]

        function advanceShape() {
            if (searchInput.text.length === 0) {
                currentShapeIndex = 0;
                searchIconShape.rotation = 0;
                shapePending = false;
                return;
            }

            if (shapeAnimTimer.running) {
                shapePending = true;
                return;
            }

            shapePending = false;
            currentShapeIndex = (currentShapeIndex + 1) % indicatorShapes.length;
            searchIconShape.rotation += 360 / indicatorShapes.length;
            shapeAnimTimer.start();
        }

        Timer {
            id: shapeAnimTimer
            // Never retarget ShapeCanvas while its current morph is running.
            interval: searchIconShape.animation?.duration
                ?? Appearance.animation.elementMove.duration
            repeat: false
            onTriggered: {
                if (searchIconShape.shapePending && searchInput.text.length > 0) {
                    searchIconShape.advanceShape();
                }
            }
        }

        // Show "n/total" text when there are results
        readonly property bool _showCount: root.lastSearchIndex !== -1 && root.resultsCount > 0
        text: isHoveredAndHasText ? "close" : (_showCount ? "" : "search")

        StyledText {
            id: resultCountText
            visible: searchIconShape._showCount && !searchIconShape.isHoveredAndHasText
            animateChange: true
            anchors.centerIn: parent
            text: (root.lastSearchIndex % Math.max(root.resultsCount, 1) + 1) + "/" + root.resultsCount
            color: searchIconShape.hasText ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            rotation: 360 - searchIconShape.rotation
        }

        MouseArea {
            id: searchIconMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: (searchInput.text.length > 0) ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (searchInput.text.length > 0) {
                    searchInput.text = "";
                    root.textChanged("");
                    searchIconShape.advanceShape();
                    searchInput.forceActiveFocus();
                }
            }
        }
    }

    // 2. Middle: Input text field (fills remaining width, height 56)
    ToolbarTextField {
        id: searchInput
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        Layout.fillHeight: true
        colBackground: Appearance.colors.colLayer1
        font.pixelSize: Appearance.font.pixelSize.normal
        placeholderText: Translation.tr("Search all settings..")
        rightPadding: (searchActionBtn.hasText || searchActionBtn.width > 0.5) ? (searchActionBtn.width + 16) : 16

        Behavior on rightPadding {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        Component.onCompleted: {
            searchInput.forceActiveFocus();
        }

        onTextChanged: {
            searchIconShape.advanceShape();
            root.textChanged(text);
        }
        onAccepted: root.accepted(text)

        // Action button (arrow_forward) appearing inside search input on the right (40x40 circle)
        Rectangle {
            id: searchActionBtn
            property bool hasText: searchInput.text.length > 0
            visible: hasText || width > 0.5
            clip: true

            anchors {
                right: parent.right
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }

            width: hasText ? 40 : 0
            height: 40
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary
            opacity: hasText ? 1.0 : 0.0

            scale: {
                if (!hasText)
                    return 0.0;
                return mouseAreaSearch.pressed ? 0.9 : mouseAreaSearch.containsMouse ? 1.05 : 1.0;
            }

            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_forward"
                iconSize: 18
                color: Appearance.colors.colOnPrimary
            }

            MouseArea {
                id: mouseAreaSearch
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (searchInput.text.trim().length > 0) {
                        root.accepted(searchInput.text);
                    }
                }
            }
        }
    }

    // 3. Rightmost: Close button circle (56x56 1:1 circle)
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
