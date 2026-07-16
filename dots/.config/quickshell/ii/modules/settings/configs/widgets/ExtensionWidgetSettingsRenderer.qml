pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// ExtensionWidgetSettingsRenderer — auto-renders a configSchema object as
// interactive controls. Reads/writes via WidgetExtensionManager.
Item {
    id: root

    property string extId: ""
    property var schema: ({})

    readonly property var schemaKeys: Object.keys(root.schema || {})

    Layout.fillWidth: true
    width: parent ? parent.width : 0
    implicitHeight: schemaCol.implicitHeight

    ColumnLayout {
        id: schemaCol
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 2

        Repeater {
            model: root.schemaKeys.map(function(k) {
                return Object.assign({ _key: k }, root.schema[k]);
            })

            delegate: Item {
                id: controlItem
                width: parent.width
                Layout.fillWidth: true
                implicitHeight: mainControl.implicitHeight

                required property var modelData
                required property int index

                readonly property string cfgKey:   modelData._key   || ""
                readonly property string cfgType:  modelData.type   || "string"
                readonly property string cfgLabel: modelData.label  || modelData._key || ""

                readonly property bool isFirstItem: index === 0
                readonly property bool isLastItem:  index === (root.schemaKeys.length - 1)

                property var cfgValue: WidgetExtensionManager.getWidgetConfig(
                    root.extId, controlItem.cfgKey, modelData.default ?? null)

                function save(v) {
                    WidgetExtensionManager.setWidgetConfig(root.extId, controlItem.cfgKey, v);
                }

                // ── Dynamic Control Dispatcher ────────────────────────────────
                Item {
                    id: mainControl
                    width: parent.width
                    implicitHeight: {
                        if (cfgType === "bool") return boolControl.implicitHeight;
                        if (cfgType === "slider" || cfgType === "int" || cfgType === "float") return sliderControl.implicitHeight;
                        if (cfgType === "enum") return enumControl.implicitHeight;
                        return stringControl.implicitHeight;
                    }

                    // 1. Boolean Toggle -> Direct ConfigSwitch
                    ConfigSwitch {
                        id: boolControl
                        visible: cfgType === "bool"
                        text: cfgLabel
                        checked: controlItem.cfgValue ?? (controlItem.modelData.default ?? false)
                        onCheckedChanged: controlItem.save(checked)
                        isFirst: controlItem.isFirstItem
                        isLast: controlItem.isLastItem
                        anchors.fill: parent
                    }

                    // 2. Slider -> Direct ConfigSlider
                    ConfigSlider {
                        id: sliderControl
                        visible: cfgType === "slider" || cfgType === "int" || cfgType === "float"
                        text: cfgLabel
                        value: controlItem.cfgValue ?? (controlItem.modelData.default ?? 0)
                        from: controlItem.modelData.min ?? 0
                        to:   controlItem.modelData.max ?? 100
                        stepSize: cfgType === "int" ? 1.0 : (cfgType === "float" ? 0.1 : 0.0)
                        onValueChanged: controlItem.save(value)
                        isFirst: controlItem.isFirstItem
                        isLast: controlItem.isLastItem
                        anchors.fill: parent
                    }

                    // 3. Enum Selection -> Styled Container + ConfigSelectionArray
                    Rectangle {
                        id: enumControl
                        visible: cfgType === "enum"
                        anchors.fill: parent
                        color: Appearance.colors.colLayer2Base
                        radius: Appearance.rounding.verysmall

                        readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)
                        topLeftRadius:     controlItem.isFirstItem ? Appearance.rounding.large : Appearance.rounding.verysmall
                        topRightRadius:    controlItem.isFirstItem ? Appearance.rounding.large : Appearance.rounding.verysmall
                        bottomLeftRadius:  controlItem.isLastItem ? Appearance.rounding.large : Appearance.rounding.verysmall
                        bottomRightRadius: controlItem.isLastItem ? Appearance.rounding.large : Appearance.rounding.verysmall

                        implicitHeight: 48

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            StyledText {
                                Layout.fillWidth: true
                                text: controlItem.cfgLabel
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.normal
                                elide: Text.ElideRight
                            }

                            ConfigSelectionArray {
                                currentValue: controlItem.cfgValue ?? (controlItem.modelData.default ?? "")
                                onSelected: v => controlItem.save(v)
                                options: {
                                    var vals = controlItem.modelData.values || [];
                                    return vals.map(function(v) { return { displayName: v, value: v }; });
                                }
                            }
                        }
                    }

                    // 4. String Input -> Direct ConfigTextField
                    ConfigTextField {
                        id: stringControl
                        visible: cfgType === "string"
                        anchors.fill: parent
                        text: cfgLabel
                        inputText: controlItem.cfgValue ?? (controlItem.modelData.default ?? "")
                        placeholderText: controlItem.modelData.placeholder || ""
                        isFirst: controlItem.isFirstItem
                        isLast: controlItem.isLastItem
                        textField.onEditingFinished: controlItem.save(textField.text)
                    }
                }
            }
        }
    }
}

