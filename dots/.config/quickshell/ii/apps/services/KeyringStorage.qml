pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Slim KeyringStorage for standalone apps.
 * Same secret-tool schema as the shell's KeyringStorage so accounts and API keys
 * stay in sync with the shell without pulling in any other shell services.
 */
Singleton {
    id: root

    signal dataChanged()

    property bool loaded: false
    property var keyringData: ({})

    property var properties: {
        "application": "illogical-impulse",
        "explanation": Translation.tr("For storing API keys and other sensitive information"),
    }
    property var propertiesAsArgs: Object.keys(root.properties).reduce(
        function(arr, key) {
            return arr.concat([key, root.properties[key]]);
        }, []
    )
    property string keyringLabel: Translation.tr("%1 Safe Storage").arg("illogical-impulse")

    property bool _pendingSave: false

    function setNestedField(path, value) {
        setNestedFields([{ path: path, value: value }]);
    }

    function setNestedFields(entries) {
        if (!entries || entries.length === 0) return;
        if (!root.keyringData) root.keyringData = {};

        for (let j = 0; j < entries.length; ++j) {
            let item = entries[j];
            if (!item || !item.path) continue;
            let keys = item.path;
            let value = item.value;
            let obj = root.keyringData;
            let parents = [obj];

            for (let i = 0; i < keys.length - 1; ++i) {
                if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                    obj[keys[i]] = {};
                }
                obj = obj[keys[i]];
                parents.push(obj);
            }

            obj[keys[keys.length - 1]] = value;

            for (let i = keys.length - 2; i >= 0; --i) {
                let parent = parents[i];
                let key = keys[i];
                parent[key] = Object.assign({}, parent[key]);
            }
        }

        root.keyringData = Object.assign({}, root.keyringData);
        saveKeyringData();
    }

    function fetchKeyringData() {
        getData.running = true;
    }

    function saveKeyringData() {
        if (saveData.running) {
            root._pendingSave = true;
            return;
        }
        root._pendingSave = false;
        saveData.stdinEnabled = true;
        saveData.running = true;
    }

    Process {
        id: saveData
        command: [
            "secret-tool", "store", "--label=" + root.keyringLabel,
            ...root.propertiesAsArgs,
        ]
        onRunningChanged: {
            if (saveData.running) {
                saveData.write(JSON.stringify(root.keyringData) + "\n");
                root.dataChanged();
                stdinEnabled = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root._pendingSave) {
                root._pendingSave = false;
                Qt.callLater(function() {
                    root.saveKeyringData();
                });
            }
        }
    }

    Component.onCompleted: {
        root.fetchKeyringData();
    }

    Timer {
        id: retryTimer
        interval: 3000
        repeat: false
        onTriggered: root.fetchKeyringData()
    }

    Process {
        id: getData
        command: [
            "bash", "-c", `${Directories.scriptPath}/keyring/try_lookup.sh 2> /dev/null`,
        ]
        stdout: StdioCollector {
            id: keyringDataOutputCollector
            onStreamFinished: {
                const data = keyringDataOutputCollector.text;
                if (data.length === 0 || !data.startsWith("{")) return;
                try {
                    root.keyringData = JSON.parse(data);
                } catch (e) {
                    console.error("[apps KeyringStorage] Failed to parse keyring data, reinitializing.");
                    root.keyringData = {};
                    root.saveKeyringData();
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) {
                root.keyringData = {};
            }
            if (exitCode === 2) {
                retryTimer.start();
                return;
            }
            root.loaded = true;
        }
    }
}
