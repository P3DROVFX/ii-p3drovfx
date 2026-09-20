import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

RowLayout {
    id: root
    anchors.fill: parent
    /**
     * One padding for every side.
     *
     * It used to inset 12px at the sides and nothing at the top or bottom, and the
     * shape was sized `height - 4` - so it nearly touched both edges while the text
     * beside it sat in far more air than it needed. Now the shape takes the height
     * less its own margin, which is the same margin it has at the edge.
     */
    readonly property real padding: 8
    anchors.margins: root.padding
    spacing: 10

    // Left side: Keyboard Icon inside Clover/Cookie shape
    MaterialShape {
        id: iconShape
        shapeString: "Cookie12Sided"
        color: Appearance.colors.colPrimaryContainer
        implicitWidth: Math.max(18, root.height - 2 * root.padding)
        implicitHeight: Math.max(18, root.height - 2 * root.padding)
        Layout.alignment: Qt.AlignVCenter

        MaterialSymbol {
            anchors.centerIn: parent
            text: "keyboard"
            iconSize: Math.max(11, Math.round(iconShape.implicitHeight * 0.58))
            color: Appearance.colors.colOnPrimaryContainer
        }
    }

    // Right side: Slide container for layout codes
    Item {
        id: layoutsContainer
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignVCenter

        readonly property int itemWidth: 70
        readonly property int spacingValue: 4
        
        // Track active indexes
        readonly property int activeIndex: getActiveIndex()
        property int previousActiveIndex: activeIndex
        property int highlightIndex: activeIndex

        onActiveIndexChanged: {
            highlightIndex = activeIndex;
            iconShapePulse.restart();
        }

        function getActiveIndex() {
            const current = (HyprlandXkb.currentLayoutCode || "").toLowerCase().trim();
            for (let i = 0; i < HyprlandXkb.layoutCodes.length; i++) {
                const code = HyprlandXkb.layoutCodes[i].toLowerCase().trim();
                if (current.startsWith(code) || code.startsWith(current)) {
                    return i;
                }
            }
            return 0;
        }

        // Generates beautiful two-line layout code and variant formatting
        function getLayoutDisplayString(code, isActive) {
            let fullCode = code;
            if (isActive && HyprlandXkb.currentLayoutCode) {
                fullCode = HyprlandXkb.currentLayoutCode;
            }
            
            fullCode = (fullCode || "").toLowerCase().trim();
            
            const parenMatch = fullCode.match(/^([a-zA-Z]{2,3})\((.+)\)$/);
            if (parenMatch) {
                return parenMatch[1].toUpperCase() + "\n" + parenMatch[2].toUpperCase();
            }
            
            if (fullCode.startsWith("br") && fullCode.length > 2) {
                return "BR\n" + fullCode.substring(2).toUpperCase();
            }
            if (fullCode.startsWith("us") && fullCode.length > 2) {
                const variant = fullCode.substring(2).toUpperCase();
                if (variant.startsWith("INTL")) {
                    return "US\nINTL";
                }
                return "US\n" + variant;
            }
            
            if (fullCode.includes("-")) {
                const parts = fullCode.split("-");
                return parts[0].toUpperCase() + "\n" + parts[1].toUpperCase();
            }
            if (fullCode.includes(":")) {
                const parts = fullCode.split(":");
                return parts[0].toUpperCase() + "\n" + parts[1].toUpperCase();
            }
            
            return fullCode.toUpperCase();
        }

        // Sliding capsule selection background
        Rectangle {
            id: highlightPill
            width: layoutsContainer.itemWidth
            height: Math.max(16, Math.min(32, root.height - 4))
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary
            anchors.verticalCenter: parent.verticalCenter

            x: layoutsContainer.highlightIndex * (layoutsContainer.itemWidth + layoutsContainer.spacingValue)

            Behavior on x {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutExpo
                }
            }
        }

        // Horizontal Row of Layout Labels
        Row {
            spacing: layoutsContainer.spacingValue
            anchors.fill: parent

            Repeater {
                model: HyprlandXkb.layoutCodes
                delegate: Item {
                    width: layoutsContainer.itemWidth
                    height: layoutsContainer.parent.height

                    required property int index
                    required property string modelData

                    StyledText {
                        anchors.centerIn: parent
                        text: layoutsContainer.getLayoutDisplayString(modelData, index === layoutsContainer.activeIndex)
                        font.family: Appearance.font.family.title
                        font.pixelSize: index === layoutsContainer.activeIndex ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.smallest
                        font.weight: index === layoutsContainer.activeIndex ? Font.Black : Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                        lineHeight: 0.85
                        color: index === layoutsContainer.activeIndex ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant

                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }
                }
            }
        }
    }

    SequentialAnimation {
        id: iconShapePulse
        NumberAnimation { target: iconShape; property: "scale"; to: 1.25; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: iconShape; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
    }
}
