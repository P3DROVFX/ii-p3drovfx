import QtQuick

/**
 * The lock's typed characters: one Material shape per character, popping in
 * with an overshoot and settling from primary to the field's text colour,
 * behind a 2 px primary cursor. The row scrolls to keep the cursor in view.
 */
Flickable {
    id: root

    required property int length
    property int selectionStart
    property int selectionEnd
    property int cursorPosition
    property color color: Theme.m3primary
    property color selectedTextColor: Theme.m3onSecondaryContainer
    property color selectionColor: Theme.m3secondaryContainer
    property int charSize: 20

    readonly property var charShapes: ["Clover4Leaf", "Arrow", "Pill", "SoftBurst", "Diamond", "ClamShell", "Pentagon"]

    function syncChars() {
        if (chars.count > root.length)
            chars.remove(root.length, chars.count - root.length);
        while (chars.count < root.length)
            chars.append({});
    }
    onLengthChanged: syncChars()
    Component.onCompleted: syncChars()

    interactive: false
    clip: true
    contentWidth: dotsRow.implicitWidth
    contentHeight: height
    contentX: Math.max(contentWidth - width, 0)
    Behavior on contentX {
        NumberAnimation {
            duration: Theme.ms(400)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emphasizedDecel
        }
    }

    Rectangle {
        id: cursor
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: root.charSize * root.cursorPosition
        }
        color: root.color
        implicitWidth: 2
        implicitHeight: root.charSize
        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Theme.ms(400)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.emphasizedDecel
            }
        }
    }

    Row {
        id: dotsRow
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 4 - 5 // the char cells' own width stands in for spacing
        }
        spacing: 0

        Repeater {
            // Not `model: root.length`: a number model rebuilds every delegate
            // when it changes, replaying each shape's entrance on every key.
            // The shell's ScriptModel keeps them; this does the same by only
            // adding or dropping shapes at the end.
            model: ListModel {
                id: chars
            }

            delegate: Rectangle {
                id: charItem
                required property int index
                implicitWidth: root.charSize
                implicitHeight: root.charSize
                readonly property bool selected: index >= root.selectionStart && index < root.selectionEnd
                color: Theme.transparentize(root.selectionColor, selected ? 0 : 1)

                MaterialShape {
                    id: materialShape
                    anchors.centerIn: parent
                    // A removed shape briefly reads index -1 on its way out.
                    shape: root.charShapes[Math.max(0, charItem.index) % root.charShapes.length]
                    color: charItem.selected ? root.selectedTextColor : root.color
                    implicitSize: 0
                    opacity: 0
                    scale: 0.5
                    Component.onCompleted: appearAnim.start()

                    ParallelAnimation {
                        id: appearAnim
                        NumberAnimation {
                            target: materialShape
                            property: "opacity"
                            to: 1
                            duration: 50
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveEffects
                        }
                        NumberAnimation {
                            target: materialShape
                            property: "scale"
                            to: 1
                            duration: 200
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveFastSpatial
                        }
                        NumberAnimation {
                            target: materialShape
                            property: "implicitSize"
                            to: 18
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveFastSpatial
                        }
                        ColorAnimation {
                            target: materialShape
                            property: "color"
                            from: Theme.m3primary
                            to: Theme.colOnLayer1
                            duration: 1000
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveEffects
                        }
                    }
                }
            }
        }
    }
}
