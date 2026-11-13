#!/usr/bin/env python3
"""Run offscreen Qt6 interaction tests against the real DisplaysConfig.qml."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    runner = shutil.which('qmltestrunner6') or next((str(p) for p in (
        Path('/usr/lib64/qt6/bin/qmltestrunner'),
        Path('/usr/lib/qt6/bin/qmltestrunner'),
    ) if p.exists()), None) or shutil.which('qmltestrunner')
    if not runner:
        raise SystemExit('Qt 6 qmltestrunner is required')

    with tempfile.TemporaryDirectory(prefix='ii-displays-canvas-') as directory:
        tmp = Path(directory)

        def module(name, files):
            path = tmp / name.replace('.', '/')
            path.mkdir(parents=True, exist_ok=True)
            entries = ['module ' + name]
            for fname, body in files.items():
                (path / (fname + '.qml')).write_text(body)
                entries.append(('singleton ' if 'pragma Singleton' in body else '') + fname + ' 1.0 ' + fname + '.qml')
            (path / 'qmldir').write_text('\n'.join(entries) + '\n')

        def singleton(body):
            return 'pragma Singleton\nimport QtQuick\nQtObject {\n' + body + '\n}'

        src_text = (ROOT / 'modules/settings/configs/DisplaysConfig.qml').read_text()
        colors = {key: '#807090' for key in set(re.findall(r'(?:colors|m3colors)\.([A-Za-z0-9_]+)', src_text))}

        module('qs.modules.common', {
            'Appearance': singleton(
                'property var colors: ' + json.dumps(colors)
                + '\nproperty var m3colors: colors'
                + '\nproperty bool reducedMotion: false'
                + '\nproperty var rounding: ({verysmall:6,small:8,normal:14,large:20,full:9999})'
                + '\nproperty var font: ({family:{numbers:"sans-serif"},pixelSize:{small:13,normal:15}})'
            ),
            'Config': singleton(
                'property bool ready: true'
                + '\nproperty var options: ({oledSaver:{enable:true,antiBurnIn:true,cursorHideDelay:5,lockTimeout:0},interactions:{deadPixelWorkaround:{enable:false}}})'
            ),
        })
        module('qs', {
            'GlobalStates': singleton('property var oledSaverMonitors: []'),
        })
        module('qs.modules.common.functions', {
            'ColorUtils': singleton('function transparentize(c, a) { return c; }'),
        })
        module('qs.services', {
            'Translation': singleton('function tr(text) { return text; }'),
            'ScreenShader': singleton('property bool active: false\nproperty string statusText: ""'),
            'DisplayCalibration': singleton(
                'property bool ddcutilAvailable: false\nproperty bool detecting: false\nproperty bool detectionComplete: true\nproperty bool detectionFailed: false'
                + '\nfunction monitorForName(n) { return null; }\nfunction refreshMonitor(n) {}'
            ),
            'DisplayColorFilter': singleton(
                'property bool applied: false\nproperty string errorMessage: ""'
                + '\nfunction profileForMonitor(n) { return null; }\nfunction isMonitorNeutral(n) { return true; }'
                + '\nfunction setSaturation(n,v) {}\nfunction setContrast(n,v) {}\nfunction setRed(n,v) {}\nfunction setGreen(n,v) {}\nfunction setBlue(n,v) {}\nfunction resetMonitor(n) {}'
            ),
        })
        module('qs.modules.common.models.hyprland', {
            'MonitorConfigOption': '''import QtQuick
QtObject {
    id: root
    property var monitors: []
    property var profiles: []
    readonly property int activeMonitorCount: monitors ? monitors.filter(m => m && !m.disabled).length : 0
    property int saveCalls: 0
    function updateMonitor(index, changes) {
        let m = root.monitors.slice();
        m[index] = Object.assign({}, m[index], changes);
        root.monitors = m;
    }
    function save() { saveCalls += 1; }
    function applyAndSave(index) { save(); }
    function logicalWidth(m) {
        const s = (m && m.scale) ? m.scale : 1;
        const w = (m.transform === 1 || m.transform === 3) ? m.height : m.width;
        return Math.round(w / s);
    }
    function logicalHeight(m) {
        const s = (m && m.scale) ? m.scale : 1;
        const h = (m.transform === 1 || m.transform === 3) ? m.width : m.height;
        return Math.round(h / s);
    }
    function reloadFromHyprland() {}
    function saveToHyprland() {}
    function applyProfile(n) {}
    function deleteProfile(n) {}
    function saveProfile(n) {}
}'''
        })
        module('qs.modules.common.widgets', {
            'ContentPage': 'import QtQuick\nimport QtQuick.Layouts\nItem { property bool forceWidth: false; default property alias pageChildren: col.data; ColumnLayout { id: col; anchors.left: parent.left; anchors.right: parent.right; spacing: 12 } }',
            'ContentSection': 'import QtQuick\nimport QtQuick.Layouts\nColumnLayout { property string icon; property string title; spacing: 8 }',
            'ContentSubsection': 'import QtQuick\nimport QtQuick.Layouts\nColumnLayout { property string icon; property string title; spacing: 4 }',
            'ContentSubsectionLabel': 'import QtQuick\nText {}',
            'NoticeBox': 'import QtQuick\nimport QtQuick.Layouts\nRowLayout { property string text; property string materialIcon }',
            'DashedBorder': 'import QtQuick\nRectangle { property real borderWidth: 1; property real dashLength: 4; property real gapLength: 4; color: "transparent" }',
            'StyledText': 'import QtQuick\nText {}',
            'MaterialSymbol': 'import QtQuick\nText { property real iconSize: 16; font.pixelSize: iconSize }',
            'StyledToolTip': 'import QtQuick\nItem { property string text }',
            'RippleButton': '''import QtQuick
import QtQuick.Controls
Button {
    property real buttonRadius: 0
    property color colBackground: "transparent"
}''',
            'RippleButtonWithIcon': '''import QtQuick
import QtQuick.Controls
Button {
    property real buttonRadius: 0
    property string materialIcon: ""
    property string mainText: ""
}''',
            'StyledComboBox': 'import QtQuick\nItem { property string buttonIcon; property var model; property string textRole; property int currentIndex: 0; signal activated(int index) }',
            'ConfigSlider': 'import QtQuick\nItem { property string buttonIcon; property string text; property real value: 1; property real from: 0; property real to: 1; property real stepSize: 0.1; property int snapMode: 0; property var stopIndicatorValues: []; property bool usePercentTooltip: false; property string tooltipContent: "" }',
            'ConfigSelectionArray': 'import QtQuick\nItem { property int currentValue: 0; property var options: []; signal selected(int newValue) }',
            'ConfigSpinBox': 'import QtQuick\nItem { property string icon; property string text; property int value: 0; property int from: 0; property int to: 100; property int stepSize: 1 }',
            'ConfigSwitch': 'import QtQuick\nItem { property string buttonIcon; property string text; property bool checked: false; property string description: "" }',
            'FloatingActionButton': 'import QtQuick\nItem { property string iconText; property string buttonText; property bool hovered: false; property bool expanded: false; signal clicked() }',
            'WindowDialog': 'import QtQuick\nItem { property bool show: false; property real backgroundWidth: 300; signal dismiss() }',
            'WindowDialogTitle': 'import QtQuick\nText {}',
            'WindowDialogParagraph': 'import QtQuick\nText {}',
            'MaterialTextField': 'import QtQuick\nimport QtQuick.Controls\nTextField {}',
            'WindowDialogButtonRow': 'import QtQuick\nRow {}',
            'DialogButton': 'import QtQuick\nItem { property string buttonText; signal clicked() }',
            'RelatedChip': 'import QtQuick\nItem { property string pageId; property string label; property string sectionHighlight }',
        })
        module('Quickshell', {
            'Quickshell': singleton('function execDetached(cmd) {}'),
        })
        module('Quickshell.Io', {
            'Process': 'import QtQuick\nQtObject { property var command: []; property bool running: false; property var stdout: null }',
            'StdioCollector': 'import QtQuick\nQtObject { signal streamFinished(); property string text: "" }',
        })

        # Copy DisplaysConfig.qml, MonitorLayoutUtils.js, and tst_DisplaysCanvas.qml preserving relative path
        work = tmp / 'workspace'
        cfg_dir = work / 'modules/settings/configs'
        utils_dir = work / 'modules/common/models/hyprland'
        cfg_dir.mkdir(parents=True)
        utils_dir.mkdir(parents=True)
        shutil.copy2(ROOT / 'modules/settings/configs/DisplaysConfig.qml', cfg_dir / 'DisplaysConfig.qml')
        shutil.copy2(ROOT / 'modules/common/models/hyprland/MonitorLayoutUtils.js', utils_dir / 'MonitorLayoutUtils.js')
        shutil.copy2(ROOT / 'tests/displayLayout/tst_DisplaysCanvas.qml', cfg_dir / 'tst_DisplaysCanvas.qml')

        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
        result = subprocess.run([
            runner,
            '-input', str(cfg_dir / 'tst_DisplaysCanvas.qml'),
            '-import', str(tmp),
        ], env=env, timeout=30)
        raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
