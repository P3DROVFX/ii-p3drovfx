"""Exercise WindowsConfig, real sliders and the blur queue in Qt offscreen.

Only platform services, process execution and decorative widgets are replaced.
No Quickshell instance, compositor calls, screen capture or user config writes.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def block(text, marker, start=0):
    begin = text.index(marker, start)
    opening = text.index('{', begin)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[begin:end]


def main():
    runner = next((str(p) for p in (
        Path('/usr/lib64/qt6/bin/qmltestrunner'),
        Path('/usr/lib/qt6/bin/qmltestrunner'),
    ) if p.exists()), None) or shutil.which('qmltestrunner6')
    if not runner:
        raise SystemExit('Qt 6 qmltestrunner is required')

    with tempfile.TemporaryDirectory(prefix='ii-windows-blur-') as directory:
        out = Path(directory)

        def put(name, text):
            path = out / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

        config = (ROOT / 'modules/common/Config.qml').read_text()
        blur = block(config, 'property JsonObject blur: JsonObject', config.index('property int blurSize:'))
        put('qs/modules/common/Config.qml', '''pragma Singleton
import QtQuick
QtObject {
    property bool ready: false
    property QtObject options: QtObject {
        property QtObject appearance: QtObject {
            %s
            property int blurSize: 10
            property real ignoreAlpha: 0.5
            property bool sharpMode: false
            property bool colorfulScrollbar: false
            property bool borderless: false
            property int borderWidth: 1
            property int gapsIn: 4
            property int gapsOut: 5
            property string borderColorType: "primary"
            property QtObject transparency: QtObject {
                property bool enable: true
                property bool automatic: false
                property bool popups: true
                property real backgroundTransparency: 0.48
                property real contentTransparency: 0.38
            }
            property QtObject appLaunchAnimation: QtObject {
                property bool enable: false
                property int startPercent: 20
                property real speed: 3.2
                property string curve: "default"
            }
        }
    }
}
''' % blur.replace('JsonObject', 'QtObject'))

        # Keep the real slider wrapper and Qt Quick Controls implementation.
        visual_sources = ''
        for name in ('ConfigSlider', 'StyledSlider'):
            source = (ROOT / f'modules/common/widgets/{name}.qml').read_text()
            visual_sources += source
            put(f'qs/modules/common/widgets/{name}.qml', source.replace('import Quickshell.Widgets\n', ''))
        colors = sorted(set(re.findall(r'Appearance\.colors\.(\w+)', visual_sources)) | {'colSubtext'})
        put('qs/modules/common/Appearance.qml', '''pragma Singleton
import QtQuick
QtObject {
    property QtObject colors: QtObject { %s }
    property var m3colors: ({m3onSecondaryContainer: "white", m3onPrimary: "white"})
    property var rounding: ({scale: 1, large: 23, verysmall: 4, unsharpen: 0, full: 9999})
    property var font: ({family: {numbers: "sans-serif"}, variableAxes: {numbers: {}}, pixelSize: {smaller: 14, smallest: 12}})
    property QtObject animation: QtObject {
        property QtObject elementMoveFast: QtObject {
            property Component numberAnimation: NumberAnimation { duration: 0 }
            property Component colorAnimation: ColorAnimation { duration: 0 }
        }
    }
}
''' % '\n'.join(f'property color {key}: "gray"' for key in colors))
        put('qs/modules/common/PanelFamily.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property bool touchFirst: false }')
        put('qs/modules/common/Recorder.qml', '''pragma Singleton
import QtQuick
QtObject {
    property var commands: []
    property int active: 0
    property int maxActive: 0
}
''')
        put('qs/services/Translation.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }')
        put('qs/services/SearchRegistry.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property string currentSearch: "" }')
        put('qs/services/HyprlandSettings.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function updateAppLaunchAnimation(a,b,c,d) {} }')
        put('qs/modules/common/widgets/MaterialShape.qml', 'pragma Singleton\nimport QtQuick\nQtObject { enum Shape { Circle, Cookie6Sided } }')
        widgets = {
            'ContentPage': 'ColumnLayout { property bool forceWidth: false }',
            'ContentSection': 'ColumnLayout { property string title; property string icon }',
            'ContentSubsection': 'ColumnLayout { property string title; property string icon }',
            'ConfigSwitch': 'Button { property string buttonIcon; property string description; onClicked: checked = !checked }',
            'ConfigSelectionArray': 'Item { property var currentValue; property var options; signal selected(var newValue) }',
            'NoticeBox': 'Text { property string materialIcon; property bool isFirst; property bool isLast; wrapMode: Text.WordWrap }',
            'WarningBox': 'Text { property bool isFirst; wrapMode: Text.WordWrap }',
            'StyledText': 'Text {}',
            'RelatedChip': 'Button { property string pageId; property string label; property string sectionHighlight }',
            'StyledToolTip': 'ToolTip { property bool extraVisibleCondition: false; visible: false }',
            'ScrollAnimate': 'Item {}',
            'WavyLine': 'Item { property real frequency; property real fullLength; property real lineWidth; property real amplitudeMultiplier; property color color; property bool animateWave }',
            'MaterialShapeWrappedMaterialSymbol': 'Text { property var shape; property real iconSize; property color colSymbol }',
            'HighlightOverlay': 'Item { property real topLeftRadius; property real topRightRadius; property real bottomLeftRadius; property real bottomRightRadius; opacity: 0; function startAnimation() {} }',
        }
        for name, body in widgets.items():
            put(f'qs/modules/common/widgets/{name}.qml', 'import QtQuick\nimport QtQuick.Controls\nimport QtQuick.Layouts\n' + body)

        # Run the production controller code with a slow, observable Process.
        appearance = (ROOT / 'modules/common/Appearance.qml').read_text()
        controller = appearance[appearance.index('    property int blurSize:'):appearance.index('    property bool _isApplyingRules:')]
        put('tests/BlurController.qml', 'import QtQuick\nimport qs.modules.common\nimport "HyprlandBlur.js" as HyprlandBlur\nItem {\nid: root\nproperty real backgroundTransparency: 0.48\n' + controller + '\n}')
        put('tests/HyprlandBlur.js', (ROOT / 'modules/common/HyprlandBlur.js').read_text())
        put('tests/StdioCollector.qml', 'import QtQuick\nQtObject { property string text: "" }')
        put('tests/Process.qml', '''import QtQuick
import qs.modules.common
QtObject {
    id: proc
    property var command: []
    property bool running: false
    property QtObject stdout
    property QtObject stderr
    signal exited(int exitCode, int exitStatus)
    property Connections lifecycle: Connections {
        target: proc
        function onRunningChanged() {
            if (!proc.running) return;
            Recorder.commands = Recorder.commands.concat([proc.command.slice()]);
            Recorder.active += 1;
            Recorder.maxActive = Math.max(Recorder.maxActive, Recorder.active);
            completion.start();
        }
    }
    property Timer completion: Timer {
        id: completion
        interval: 100
        onTriggered: {
            Recorder.active -= 1;
            proc.running = false;
            proc.exited(0, 0);
        }
    }
}
''')
        put('tests/WindowsConfig.qml', (ROOT / 'modules/settings/configs/WindowsConfig.qml').read_text().replace('import Quickshell\n', ''))
        put('tests/tst_WindowsBlur.qml', (ROOT / 'tests/blur/tst_WindowsBlur.qml').read_text())
        for folder in sorted((out / 'qs').rglob('*')):
            if not folder.is_dir():
                continue
            entries = []
            for qml in sorted(folder.glob('*.qml')):
                singleton = 'singleton ' if 'pragma Singleton' in qml.read_text() else ''
                entries.append(f'{singleton}{qml.stem} 1.0 {qml.name}')
            if entries:
                put(str(folder.relative_to(out) / 'qmldir'), '\n'.join(entries) + '\n')
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_QUICK_CONTROLS_STYLE='Basic')
        result = subprocess.run([runner, '-input', str(out / 'tests'), '-import', str(out)], env=env, capture_output=True, text=True, timeout=40)
        print(result.stdout, end='')
        print(result.stderr, end='')
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
