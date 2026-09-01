import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Rounded-column trend chart for compact dashboard cards.
 * Values are rendered with a shared scale so zero-value periods remain visible.
 */
Item {
    id: root

    required property list<real> values
    required property list<string> labels
    property list<string> tooltipLabels: root.labels
    property color barColor: Appearance.colors.colPrimary
    property color emptyColor: Appearance.colors.colLayer2
    property color axisColor: Appearance.colors.colSubtext
    property var formatValue: value => String(Math.round(Number(value || 0)))
    property real barWidth: 40
    property real minimumBarWidth: 14
    property real barSpacing: Appearance.rounding.verysmall
    property real barRadius: Appearance.rounding.full
    property int labelStride: 1
    property list<int> labelIndices: []
    property bool showLabels: true
    property bool showGridLines: true
    property int gridLineCount: 4
    property color gridLineColor: Appearance.colors.colOnLayer2
    property real gridLineOpacity: 0.28
    property color textureColor: Appearance.colors.colOnLayer2
    property real textureOpacity: 0.28
    property int hoveredIndex: -1

    readonly property real maxValue: {
        let max = 0;
        for (const value of root.values)
            max = Math.max(max, Number(value || 0));
        return max > 0 ? max : 1;
    }

    implicitHeight: 190

    ColumnLayout {
        anchors.fill: parent
        spacing: root.showLabels ? 8 : 0

        Item {
            id: plotArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Canvas {
                id: gridLines
                anchors.fill: parent
                clip: true

                function paintGrid() {
                    const context = getContext("2d");
                    context.clearRect(0, 0, width, height);
                    if (!root.showGridLines || width <= 0 || height <= 0)
                        return;

                    context.strokeStyle = ColorUtils.transparentize(root.gridLineColor, 1 - root.gridLineOpacity);
                    context.lineWidth = 1;
                    const levels = Math.max(1, root.gridLineCount);
                    const dashLength = Math.max(4, Math.min(12, width / 28));
                    const gapLength = dashLength * 0.75;

                    for (let level = 0; level <= levels; ++level) {
                        const y = height - height * level / levels;
                        for (let x = 0; x < width; x += dashLength + gapLength) {
                            context.beginPath();
                            context.moveTo(x, y);
                            context.lineTo(Math.min(width, x + dashLength), y);
                            context.stroke();
                        }
                    }
                }

                onPaint: paintGrid()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: root
                    function onShowGridLinesChanged() { gridLines.requestPaint(); }
                    function onGridLineCountChanged() { gridLines.requestPaint(); }
                    function onGridLineColorChanged() { gridLines.requestPaint(); }
                    function onGridLineOpacityChanged() { gridLines.requestPaint(); }
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: root.barSpacing

                Repeater {
                    model: root.values

                    delegate: Item {
                        required property real modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            id: barShape
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                bottom: parent.bottom
                            }
                            width: Math.min(root.barWidth, Math.max(root.minimumBarWidth, parent.width * 0.68))
                            height: Number(modelData || 0) > 0
                                ? Math.max(6, parent.height * Math.max(0, Number(modelData || 0)) / root.maxValue)
                                : 4
                            radius: root.barRadius
                            clip: true
                            color: Number(modelData || 0) > 0
                                ? root.barColor
                                : root.emptyColor
                            opacity: root.hoveredIndex < 0
                                ? Number(modelData || 0) > 0 ? 1 : 0.64
                                : index === root.hoveredIndex
                                    ? 1
                                    : Number(modelData || 0) > 0 ? 0.34 : 0.24

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            Canvas {
                                id: columnTexture
                                anchors.fill: parent
                                clip: true
                                visible: Number(modelData || 0) > 0
                                property color textureColor: root.textureColor
                                opacity: root.textureOpacity

                                function paintTexture() {
                                    const context = getContext("2d");
                                    context.clearRect(0, 0, width, height);
                                    context.save();
                                    context.beginPath();
                                    const cornerRadius = Math.min(parent.radius, width / 2, height / 2);
                                    context.moveTo(cornerRadius, 0);
                                    context.lineTo(width - cornerRadius, 0);
                                    context.quadraticCurveTo(width, 0, width, cornerRadius);
                                    context.lineTo(width, height - cornerRadius);
                                    context.quadraticCurveTo(width, height, width - cornerRadius, height);
                                    context.lineTo(cornerRadius, height);
                                    context.quadraticCurveTo(0, height, 0, height - cornerRadius);
                                    context.lineTo(0, cornerRadius);
                                    context.quadraticCurveTo(0, 0, cornerRadius, 0);
                                    context.clip();
                                    context.strokeStyle = textureColor;
                                    context.lineWidth = Math.max(1, Math.min(2, Math.min(width, height) / 16));
                                    const textureSpacing = Math.max(4, Math.min(10, Math.min(width, height) * 0.22));
                                    for (let x = -height; x < width + height; x += textureSpacing) {
                                        context.beginPath();
                                        context.moveTo(x, height);
                                        context.lineTo(x + height, 0);
                                        context.stroke();
                                    }
                                    context.restore();
                                }

                                onPaint: paintTexture()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onTextureColorChanged: requestPaint()
                            }
                        }

                        MouseArea {
                            id: columnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onContainsMouseChanged: {
                                if (containsMouse)
                                    root.hoveredIndex = index;
                                else if (root.hoveredIndex === index)
                                    root.hoveredIndex = -1;
                            }

                            StyledToolTip {
                                extraVisibleCondition: columnArea.containsMouse
                                text: {
                                    const label = root.tooltipLabels[index] || root.labels[index] || "";
                                    return label + " · " + root.formatValue(modelData);
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.showLabels
            spacing: root.barSpacing

            Repeater {
                model: root.labels

                delegate: StyledText {
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    text: root.labelIndices.length > 0
                        ? root.labelIndices.indexOf(index) >= 0 ? modelData : ""
                        : index % Math.max(1, root.labelStride) === 0 ? modelData : ""
                    color: root.axisColor
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }
}
