pragma ComponentBehavior: Bound

import QtQuick

/**
 * Ephemeral, deterministic session state for one Typing Test panel instance.
 * It receives committed text from a real TextInput; no key events, I/O or
 * persistence occur in the hot input path.
 */
QtObject {
    id: root

    property string state: "loading" // loading, ready, running, finished
    property string mode: "time" // time, words, zen
    property int timeLimitSeconds: 30
    property int wordLimit: 50
    property bool punctuation: false
    property bool numbers: false
    property var languagePack: null

    property int seed: 1
    property int _randomState: 1
    property var targetWords: []
    property string targetText: ""
    property string inputText: ""
    property string previousInputText: ""
    property int currentWordIndex: 0
    property int correctInputEvents: 0
    property int incorrectInputEvents: 0
    property real startedAt: 0
    property real finishedAt: 0
    property real elapsedSeconds: 0
    property var samples: []
    property int _lastSampleSecond: -1

    readonly property bool isReady: root.state === "ready"
    readonly property bool isRunning: root.state === "running"
    readonly property bool isFinished: root.state === "finished"
    readonly property bool hasTarget: root.mode !== "zen"
    readonly property int rawCharacterCount: root.codePointCount(root.inputText)
    readonly property int correctCharacterCount: root.hasTarget
        ? root.countCharacterBreakdown().correct
        : root.rawCharacterCount
    readonly property real rawWpm: root.calculateWpm(root.rawCharacterCount, root.elapsedSeconds)
    readonly property real wpm: root.calculateWpm(root.correctCharacterCount, root.elapsedSeconds)
    readonly property real accuracy: {
        const total = root.correctInputEvents + root.incorrectInputEvents;
        return total > 0 ? root.correctInputEvents / total * 100 : 100;
    }
    readonly property var characterBreakdown: root.countCharacterBreakdown()
    readonly property string currentWordInput: {
        const words = root.inputText.split(" ");
        return words.length > 0 ? words[words.length - 1] : "";
    }

    signal resetRequested()
    signal finished()

    onLanguagePackChanged: {
        if (languagePack?.words?.length > 0)
            root.reset(false);
        else
            root.state = "loading";
    }

    function now() {
        return Date.now();
    }

    function codePoints(text) {
        return Array.from(String(text ?? ""));
    }

    function codePointCount(text) {
        return root.codePoints(text).length;
    }

    function normalizeSeed(value) {
        const unsigned = Number(value) >>> 0;
        return unsigned === 0 ? 1 : unsigned;
    }

    function nextRandom() {
        let x = root._randomState >>> 0;
        x ^= x << 13;
        x ^= x >>> 17;
        x ^= x << 5;
        root._randomState = x >>> 0;
        return root._randomState / 4294967296;
    }

    function randomIndex(length) {
        return Math.max(0, Math.min(length - 1, Math.floor(root.nextRandom() * length)));
    }

    function decorateWord(word, index) {
        let output = word;
        if (root.numbers && index > 0 && index % 13 === 0)
            output = String(10 + root.randomIndex(990));
        if (root.punctuation && index > 0 && index % 9 === 0) {
            const marks = [",", ".", ";", "!", "?"];
            output += marks[root.randomIndex(marks.length)];
        }
        return output;
    }

    function makeTarget(wordCount, startIndex) {
        const source = Array.from(root.languagePack?.words ?? []);
        if (source.length === 0)
            return [];
        const generated = [];
        let previous = "";
        for (let index = 0; index < wordCount; index++) {
            let word = source[root.randomIndex(source.length)];
            if (source.length > 1 && word === previous)
                word = source[(root.randomIndex(source.length - 1) + 1) % source.length];
            previous = word;
            generated.push(root.decorateWord(word, startIndex + index));
        }
        return generated;
    }

    function reset(reuseSeed) {
        if (root.mode !== "zen" && !(root.languagePack?.words?.length > 0)) {
            root.state = "loading";
            return;
        }
        root.seed = reuseSeed ? root.seed : root.normalizeSeed(Math.floor(root.now()));
        root._randomState = root.seed;
        root.targetWords = root.mode === "zen" ? [] : root.makeTarget(root.mode === "words"
            ? root.wordLimit : 220, 0);
        root.targetText = root.targetWords.join(" ");
        root.inputText = "";
        root.previousInputText = "";
        root.currentWordIndex = 0;
        root.correctInputEvents = 0;
        root.incorrectInputEvents = 0;
        root.startedAt = 0;
        root.finishedAt = 0;
        root.elapsedSeconds = 0;
        root.samples = [];
        root._lastSampleSecond = -1;
        root.state = "ready";
        root.resetRequested();
    }

    function start() {
        if (!root.isReady)
            return;
        root.startedAt = root.now();
        root.state = "running";
    }

    function updateInput(value) {
        if (root.isFinished)
            return;
        const next = String(value ?? "");
        if (next === root.previousInputText)
            return;
        if (root.isReady && root.codePointCount(next) > 0)
            root.start();
        if (!root.isReady && !root.isRunning)
            return;

        const before = root.codePoints(root.previousInputText);
        const after = root.codePoints(next);
        let prefix = 0;
        while (prefix < before.length && prefix < after.length && before[prefix] === after[prefix])
            prefix++;
        let suffix = 0;
        while (suffix < before.length - prefix && suffix < after.length - prefix
                && before[before.length - suffix - 1] === after[after.length - suffix - 1])
            suffix++;
        const inserted = after.slice(prefix, after.length - suffix);
        const target = root.codePoints(root.targetText);
        for (let offset = 0; offset < inserted.length; offset++) {
            if (!root.hasTarget || inserted[offset] === target[prefix + offset])
                root.correctInputEvents++;
            else
                root.incorrectInputEvents++;
        }

        root.inputText = next;
        root.previousInputText = next;
        root.currentWordIndex = root.hasTarget ? Math.min(root.targetWords.length - 1,
            Math.max(0, next.split(" ").length - 1)) : 0;
        root.tick();
        if (root.isFinished)
            return;
        root.extendTimeTargetIfNeeded();
        if (root.mode === "words" && root.completedWords() >= root.wordLimit)
            root.finish();
    }

    function extendTimeTargetIfNeeded() {
        if (root.mode !== "time" || root.currentWordIndex < root.targetWords.length - 30)
            return;
        root.targetWords = root.targetWords.concat(root.makeTarget(100, root.targetWords.length));
        root.targetText = root.targetWords.join(" ");
    }

    function completedWords() {
        if (!root.inputText)
            return 0;
        return Math.max(0, root.inputText.split(" ").length - 1);
    }

    function tick() {
        if (!root.isRunning)
            return;
        root.elapsedSeconds = Math.max(0, (root.now() - root.startedAt) / 1000);
        if (root.mode === "time" && root.elapsedSeconds >= root.timeLimitSeconds) {
            root.elapsedSeconds = root.timeLimitSeconds;
            root.finish();
            return;
        }
        const sampleSecond = Math.floor(root.elapsedSeconds);
        if (sampleSecond > root._lastSampleSecond) {
            root._lastSampleSecond = sampleSecond;
            root.samples = root.samples.concat([{
                t: sampleSecond,
                wpm: root.wpm,
                raw: root.rawWpm,
                errors: root.incorrectInputEvents
            }]);
        }
    }

    function finish() {
        if (root.isFinished)
            return;
        if (root.startedAt > 0) {
            root.finishedAt = root.now();
            if (root.mode !== "time")
                root.elapsedSeconds = Math.max(0, (root.finishedAt - root.startedAt) / 1000);
        }
        root.state = "finished";
        root.finished();
    }

    function calculateWpm(characters, seconds) {
        return seconds > 0 ? characters / 5 / (seconds / 60) : 0;
    }

    function countCharacterBreakdown(): var {
        if (root.mode === "zen") {
            const raw = root.rawCharacterCount;
            return { correct: raw, incorrect: 0, extra: 0, missed: 0 };
        }

        const inputWords = root.inputText.split(" ");
        const targets = root.targetWords ?? [];
        let correct = 0;
        let incorrect = 0;
        let extra = 0;
        let missed = 0;

        const evaluatedWordCount = inputWords.length;
        for (let i = 0; i < evaluatedWordCount; i++) {
            if (i >= targets.length && root.mode !== "time")
                break;
            const typed = root.codePoints(inputWords[i]);
            const target = i < targets.length ? root.codePoints(targets[i]) : [];
            const isLast = (i === evaluatedWordCount - 1);
            const hasSpace = (i < evaluatedWordCount - 1) || (isLast && root.inputText.endsWith(" "));

            if (isLast && typed.length === 0 && root.inputText.endsWith(" "))
                continue;

            const minLen = Math.min(typed.length, target.length);
            for (let c = 0; c < minLen; c++) {
                if (typed[c] === target[c])
                    correct++;
                else
                    incorrect++;
            }

            if (typed.length > target.length)
                extra += (typed.length - target.length);
            else if (typed.length < target.length)
                missed += (target.length - typed.length);

            if (hasSpace && i < targets.length) {
                if (inputWords[i] === targets[i])
                    correct++;
                else
                    incorrect++;
            }
        }

        if (root.mode === "words") {
            for (let i = evaluatedWordCount; i < Math.min(targets.length, root.wordLimit); i++) {
                missed += root.codePoints(targets[i]).length;
                if (i < Math.min(targets.length, root.wordLimit) - 1)
                    missed++;
            }
        }

        return {
            correct: correct,
            incorrect: incorrect,
            extra: extra,
            missed: missed
        };
    }
}
