import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root

    Layout.fillWidth: true
    Layout.preferredHeight: 200
    implicitHeight: 200

    radius: Appearance.rounding.large
    color: Appearance.colors.colPrimaryContainer

    // Internal animation control
    property bool startAnim: false
    
    onStartAnimChanged: {
        if (startAnim) {
            // Reset all elements to initial state
            clockCircle.opacity = 0.0;
            clockCircleTranslate.x = -50;
            clockHand.opacity = 0.0;
            timeText.opacity = 0.0;
            timeText.scale = 0.9;
            ampmText.opacity = 0.0;
            ampmText.scale = 0.9;
            dayText.opacity = 0.0;
            dayText.translateX = 20;
            dateText.opacity = 0.0;
            dateText.translateX = 20;
            
            // Start animations after reset
            Qt.callLater(function() {
                clockCircleAnim.start();
                clockHandAnim.start();
                timeAnim.start();
                ampmAnim.start();
                dayAnim.start();
                dateAnim.start();
            });
        }
    }

    Connections {
        target: root
        function onPopupOpenProgressChanged() {
            if (root && root.popupOpenProgress === 0.0) {
                clockCircleAnim.stop();
                clockHandAnim.stop();
                timeAnim.stop();
                ampmAnim.stop();
                dayAnim.stop();
                dateAnim.stop();

                clockCircle.opacity = 0.0;
                clockCircleTranslate.x = -50;
                clockHand.opacity = 0.0;
                timeText.opacity = 0.0;
                timeText.scale = 0.9;
                ampmText.opacity = 0.0;
                ampmText.scale = 0.9;
                dayText.opacity = 0.0;
                dayText.translateX = 20;
                dateText.opacity = 0.0;
                dateText.translateX = 20;
            }
        }
    }

    // Clip content to card's rounded borders using OpacityMask
    layer.enabled: true
    layer.smooth: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
            antialiasing: true
        }
    }

    // Left-side clock circle container (approx 306px, centered on screen layout)
    Item {
        id: clockCircle
        width: parent.height * 1.53
        height: width
        opacity: 0.0
        anchors {
            left: parent.left
            leftMargin: -width * 0.52
            verticalCenter: parent.verticalCenter
        }
        
        transform: Translate {
            id: clockCircleTranslate
            x: -50
        }
        
        SequentialAnimation {
            id: clockCircleAnim
            PauseAnimation { duration: 80 }
            ParallelAnimation {
                NumberAnimation { target: clockCircle; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                NumberAnimation { target: clockCircleTranslate; property: "x"; from: -50; to: 0; duration: 450; easing.type: Easing.OutCubic }
            }
        }

        readonly property real blurPadding: 80

        // 1. The original, sharp clock face source (solid circle + native ticks).
        // Positioned offscreen at x: 1000, y: 1200 (visible: true) with padded size to allow
        // the blur to expand without clipping.
        Item {
            id: clockFace
            width: parent.width + clockCircle.blurPadding * 2
            height: parent.height + clockCircle.blurPadding * 2
            x: 1000
            y: 1200

            // Solid background circle centered inside padding
            Rectangle {
                width: clockCircle.width
                height: clockCircle.height
                anchors.centerIn: parent
                radius: width / 2
                color: Appearance.colors.colPrimary
            }

            // Native Scene Graph ticks centered inside padding
            Item {
                id: ticksContainer
                width: clockCircle.width
                height: clockCircle.height
                anchors.centerIn: parent
                z: 1

                Repeater {
                    model: 90
                    delegate: Rectangle {
                        width: 2.5
                        height: parent.width / 2 * 0.17 // r * 0.17 (equivalent to r2 - r1)
                        color: Qt.rgba(1, 1, 1, 0.45) // Semi-transparent white
                        antialiasing: true

                        x: parent.width / 2 - width / 2
                        y: parent.height / 2 - parent.height / 2 * 0.95 // top of the tick is at cy - r2

                        transform: Rotation {
                            origin.x: width / 2
                            origin.y: parent.height / 2 * 0.95 // r2
                            angle: index * 4 // 360 / 90 = 4 degrees per tick
                        }
                    }
                }

                // Continuous rotation animation
                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 60000 // 60 seconds per full turn
                    loops: Animation.Infinite
                }
            }
        }

        // 2. Blur mask gradient: white at the top-left (blurred), transparent elsewhere.
        // Restricted to radius 130 so it only affects the top-left corner.
        RadialGradient {
            id: maskGradient
            width: clockCircle.width + clockCircle.blurPadding * 2
            height: clockCircle.height + clockCircle.blurPadding * 2
            x: 1000
            y: 1000
            visible: true

            // Center dynamically at the card's top-left corner, adjusting for the padding
            horizontalOffset: -clockCircle.x + clockCircle.blurPadding - width / 2
            verticalOffset: -clockCircle.y + clockCircle.blurPadding - height / 2

            horizontalRadius: 130
            verticalRadius: 130

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: "white"
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }
        }

        // 3. Sharp mask gradient: transparent at the top-left (hidden), white elsewhere (visible).
        // Restricted to radius 130 so it only affects the top-left corner.
        RadialGradient {
            id: maskGradientInverted
            width: clockCircle.width + clockCircle.blurPadding * 2
            height: clockCircle.height + clockCircle.blurPadding * 2
            x: 1000
            y: 1100
            visible: true

            // Center dynamically at the card's top-left corner, adjusting for the padding
            horizontalOffset: -clockCircle.x + clockCircle.blurPadding - width / 2
            verticalOffset: -clockCircle.y + clockCircle.blurPadding - height / 2

            horizontalRadius: 130
            verticalRadius: 130

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: "transparent"
                }
                GradientStop {
                    position: 1.0
                    color: "white"
                }
            }
        }

        // 4. Sharp layer containing the sharp parts of the face, masked out in the top-left corner.
        OpacityMask {
            id: sharpLayer
            width: clockCircle.width + clockCircle.blurPadding * 2
            height: clockCircle.height + clockCircle.blurPadding * 2
            anchors.centerIn: parent
            source: clockFace
            maskSource: maskGradientInverted
        }

        // 5. Blurred layer containing the blurred parts of the face, masked in the top-left corner.
        // Uses full-resolution source and a moderate radius of 24 to keep the blur rich, distinct,
        // and clearly visible as a soft frosted glow on the ticks and circle edge.
        MaskedBlur {
            id: blurLayer
            width: clockCircle.width + clockCircle.blurPadding * 2
            height: clockCircle.height + clockCircle.blurPadding * 2
            anchors.centerIn: parent
            source: clockFace
            maskSource: maskGradient
            radius: 24
            samples: 24
        }

        // 4. Fixed horizontal tertiary hand pointing right, positioned on top of the blur effect
        Rectangle {
            id: clockHand
            width: parent.width * 0.183
            height: 4
            color: Appearance.colors.colTertiary
            radius: 2
            z: 10 // Force rendering on top of everything
            opacity: 0.0

            // Positioned relative to clockCircle center using simple local coordinates:
            // Proportional and extends slightly outside the circle
            x: parent.width - width + (parent.width * 0.06)
            y: parent.height / 2 - height / 2
            
            SequentialAnimation {
                id: clockHandAnim
                PauseAnimation { duration: 200 }
                NumberAnimation { target: clockHand; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
            }
        }
    }

    // Inner shadow mask canvas to create a solid frame with a rounded rectangle cutout matching the card
    Canvas {
        id: shadowMaskCanvas
        x: -80
        y: -80
        // Expand the canvas bounds significantly to prevent the drop shadow blur from being clipped
        width: root.width + 160
        height: root.height + 160
        visible: false

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = "black";
            ctx.beginPath();
            
            // Outer rectangle covering the expanded canvas size
            ctx.rect(0, 0, width, height);
            
            // Inner rounded rectangle matching the card's position and rounding
            var rx = 80;
            var ry = 80;
            var rw = root.width;
            var rh = root.height;
            var r = root.radius;
            
            ctx.moveTo(rx + r, ry);
            ctx.arcTo(rx, ry, rx, ry + r, r);
            ctx.lineTo(rx, ry + rh - r);
            ctx.arcTo(rx, ry + rh, rx + r, ry + rh, r);
            ctx.lineTo(rx + rw - r, ry + rh);
            ctx.arcTo(rx + rw, ry + rh, rx + rw, ry + rh - r, r);
            ctx.lineTo(rx + rw, ry + r);
            ctx.arcTo(rx + rw, ry, rx + rw - r, ry, r);
            ctx.lineTo(rx + r, ry);
            
            ctx.closePath();
            ctx.fill("evenodd");
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    // DropShadow casting inward from the mask frame, creating the inner shadow effect
    DropShadow {
        id: innerShadow
        x: -80
        y: -80
        width: shadowMaskCanvas.width
        height: shadowMaskCanvas.height
        source: shadowMaskCanvas
        radius: 40 // high radius for soft blur
        samples: 81 // high samples for smooth blur
        color: Qt.rgba(0, 0, 0, 0.25) // high opacity, deep shadow
        horizontalOffset: 0
        verticalOffset: 0
    }

    // Right-side time & date information
    ColumnLayout {
        anchors {
            right: parent.right
            rightMargin: 24
            left: parent.left
            leftMargin: clockCircle.width + clockCircle.anchors.leftMargin + 34 // Ensure layout doesn't collide with the clock face dynamically
            verticalCenter: parent.verticalCenter
        }
        spacing: -10

        // Time row separating digits from AM/PM suffix
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            // Time digits (HH:MM) - Custom Maximum Bold Weight (1000 wght axis)
            StyledText {
                id: timeText
                text: {
                    const timeStr = DateTime.time;
                    const match = timeStr.match(/^(\d{1,2}:\d{2})(?:\s*(AM|PM|am|pm))?$/);
                    return match ? match[1] : timeStr;
                }
                font.pixelSize: Math.min(72, root.width * 0.17)
                font.family: Appearance.font.family.title
                font.variableAxes: ({
                        "wght": 800
                    }) // Maximum bold weight for variable font
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.0
                scale: 0.9
                
                SequentialAnimation {
                    id: timeAnim
                    PauseAnimation { duration: 160 }
                    ParallelAnimation {
                        NumberAnimation { target: timeText; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                        NumberAnimation { target: timeText; property: "scale"; from: 0.9; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    }
                }
            }

            // AM/PM suffix - Smaller & Thin (200 wght axis)
            StyledText {
                id: ampmText
                text: {
                    const timeStr = DateTime.time;
                    const match = timeStr.match(/^(\d{1,2}:\d{2})(?:\s*(AM|PM|am|pm))?$/);
                    return (match && match[2]) ? match[2] : "";
                }
                visible: text !== ""
                font.pixelSize: Math.min(20, root.width * 0.048) // Smaller size
                font.family: Appearance.font.family.title
                font.variableAxes: ({
                        "wght": 400
                    }) // Thin weight for variable font
                color: Appearance.colors.colOnPrimaryContainer
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: Math.min(14, root.width * 0.033) // Align baseline to bottom of time digits
                opacity: 0.0
                scale: 0.9
                
                SequentialAnimation {
                    id: ampmAnim
                    PauseAnimation { duration: 220 }
                    ParallelAnimation {
                        NumberAnimation { target: ampmText; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                        NumberAnimation { target: ampmText; property: "scale"; from: 0.9; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                    }
                }
            }
        }

        // Date row centered underneath
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            StyledText {
                id: dayText
                property real translateX: 20
                text: Qt.locale().toString(DateTime.clock.date, "dddd")
                font.pixelSize: Math.min(20, root.width * 0.048)
                font.family: Appearance.font.family.title
                font.weight: Font.Normal
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.0
                transform: Translate { x: dayText.translateX }
                
                SequentialAnimation {
                    id: dayAnim
                    PauseAnimation { duration: 280 }
                    ParallelAnimation {
                        NumberAnimation { target: dayText; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                        NumberAnimation { target: dayText; property: "translateX"; from: 20; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }
            }

            StyledText {
                id: dateText
                property real translateX: 20
                text: Qt.locale().toString(DateTime.clock.date, "dd MMMM")
                font.pixelSize: Math.min(20, root.width * 0.048)
                font.family: Appearance.font.family.title
                font.weight: Font.Normal
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.0
                transform: Translate { x: dateText.translateX }
                
                SequentialAnimation {
                    id: dateAnim
                    PauseAnimation { duration: 320 }
                    ParallelAnimation {
                        NumberAnimation { target: dateText; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                        NumberAnimation { target: dateText; property: "translateX"; from: 20; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
