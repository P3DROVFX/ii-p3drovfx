pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions as CF

/**
 * One request to a model endpoint, from script generation to exit.
 *
 * The caller fills in the inputs (model, strategy, message, endpoint,
 * payload), calls `start()`, and listens to `line`/`finished`. Everything
 * about the transport itself lives here: the generated bash script, the
 * process, the HTTP status, the timeout, the retries and the cancellation.
 *
 * The HTTP status is not otherwise observable — curl writes the body to
 * stdout and nothing else — so the script asks for it with `-w` and it
 * arrives as a trailing marker line, which is stripped before `line` fires.
 */
Scope {
    id: root

    // ── Inputs ────────────────────────────────────────────────────────────
    property AiModel model
    property ApiStrategy strategy
    property AiMessageData message
    property string endpoint: ""
    property var requestData: ({})
    property string apiKey: ""
    property string apiKeyEnvVarName: "API_KEY"
    property string scriptPath: ""
    /** Helper that writes attachments into the body. See `buildScript`. */
    property string attachScriptPath: ""

    /**
     * The request body is written next to the script and handed to curl as a
     * file. Nothing large is ever passed as an argument that way — a single
     * base64 image is already past what one may hold — and the body needs no
     * shell escaping at all.
     */
    readonly property string bodyPath: CF.FileUtils.trimFileProtocol(root.scriptPath) + ".json"

    // ── Tunables ──────────────────────────────────────────────────────────
    readonly property int connectTimeout: Math.max(1, Config.options?.ai?.connectTimeout ?? 15)
    readonly property int requestTimeout: Math.max(0, Config.options?.ai?.requestTimeout ?? 300)
    // A value of exactly 0 only reaches this file by hand-editing config.json
    // outside the Settings UI's [30, 1800] clamp. Zero must never mean "no
    // timeout at all" for a network call: that would drop both the watchdog
    // and curl's own --max-time together, leaving only the TCP handshake
    // bound (--connect-timeout) to catch a server that connects and then
    // goes silent forever.
    readonly property int hardMaxRequestSeconds: 1800
    readonly property int effectiveRequestTimeout: root.requestTimeout > 0 ? root.requestTimeout : root.hardMaxRequestSeconds
    // Not readonly: a caller whose request is not worth retrying — testing
    // whether a key works — says so by setting it to zero.
    property int maxRetries: Math.max(0, Config.options?.ai?.maxRetries ?? 2)

    // ── State ─────────────────────────────────────────────────────────────
    readonly property bool running: requestProc.running || retryTimer.running
    readonly property string statusMarker: "@@II_HTTP_STATUS:"
    property int attempt: 0
    property int httpStatus: 0
    property int exitCode: 0
    property bool aborted: false
    readonly property int attachmentFailureExitCode: 65
    readonly property string attachmentErrorMarker: "@@II_ATTACHMENT_ERROR:"
    property string attachmentError: ""
    property bool parsedAny: false

    // Where the message stood when the current attempt started, so a retry
    // can drop whatever the failed attempt wrote before trying again.
    property int contentMark: 0
    property int rawContentMark: 0
    property var messageSnapshot: null

    signal line(string data)
    signal retrying(int attempt, int delaySeconds, int status)
    /** reason: "done" | "error" | "aborted" | "attachmentError" */
    signal finished(string reason, int status, int code)

    /**
     * Starts the request. Returns false when one is already in flight —
     * a second send never silently replaces the first.
     */
    function start(): bool {
        if (root.running)
            return false;
        if (!root.strategy || !root.model)
            return false;
        root.aborted = false;
        root.attempt = 0;
        root.httpStatus = 0;
        root.exitCode = 0;
        root.attachmentError = "";
        root.contentMark = root.message?.content.length ?? 0;
        root.rawContentMark = root.message?.rawContent.length ?? 0;
        root.strategy.reset();
        root.messageSnapshot = root.snapshotMessage();
        root.launch();
        return true;
    }

    function snapshotMessage(): var {
        const message = root.message;
        if (!message)
            return null;
        return {
            content: message.content,
            rawContent: message.rawContent,
            thought: message.thought,
            thoughtSignature: message.thoughtSignature,
            thinkingBlocks: JSON.parse(JSON.stringify(message.thinkingBlocks ?? [])),
            thoughtDurationMs: message.thoughtDurationMs,
            thoughtTokens: message.thoughtTokens,
            thinking: message.thinking,
            done: message.done,
            annotations: JSON.parse(JSON.stringify(message.annotations ?? [])),
            annotationSources: JSON.parse(JSON.stringify(message.annotationSources ?? [])),
            searchQueries: JSON.parse(JSON.stringify(message.searchQueries ?? [])),
            functionName: message.functionName,
            functionCall: message.functionCall ? JSON.parse(JSON.stringify(message.functionCall)) : null,
            functionCalls: JSON.parse(JSON.stringify(message.functionCalls ?? [])),
            toolCalls: JSON.parse(JSON.stringify(message.toolCalls ?? [])),
            functionCallId: message.functionCallId,
            functionResponse: message.functionResponse,
            functionPending: message.functionPending,
            toolCards: JSON.parse(JSON.stringify(message.toolCards ?? [])),
            toolCallSerial: message.toolCallSerial,
            errorKind: message.errorKind,
            errorText: message.errorText,
            errorStatus: message.errorStatus,
            errorDetails: message.errorDetails
        };
    }

    /**
     * Cancels the request, whether it is streaming or waiting to retry.
     */
    function abort(): bool {
        if (!root.running)
            return false;
        root.aborted = true;
        retryTimer.stop();
        watchdog.stop();
        if (requestProc.running) {
            requestProc.running = false; // onExited reports it
            return true;
        }
        root.finish("aborted", root.httpStatus, root.exitCode);
        return true;
    }

    function launch() {
        // A retry is a new parse attempt. Provider-specific fragment buffers
        // and the facade's parsed flag must not leak into it.
        root.strategy.reset();
        root.parsedAny = false;
        const scriptFilePath = CF.FileUtils.trimFileProtocol(root.scriptPath);
        // Written before the script that reads it, and rewritten on every
        // attempt: a retry re-runs the attachment step over a fresh body.
        //
        // The path is dropped first because these files are deleted once the
        // request ends, and a view still pointing at the old path writes
        // nothing when asked for bytes it believes are already there — the
        // script is the same every time, so from the second request on there
        // was no file left to run and curl was never reached at all. The views
        // write synchronously; see below for why that matters here.
        bodyFile.path = "";
        bodyFile.path = Qt.resolvedUrl(root.bodyPath);
        bodyFile.setText(JSON.stringify(root.requestData));
        scriptFile.path = "";
        scriptFile.path = Qt.resolvedUrl(scriptFilePath);
        scriptFile.setText(root.buildScript());
        // Rebuilt every launch: a key must never outlive the model it
        // belongs to, and an unused variable must not linger either.
        requestProc.environment = root.model.requires_key ? ({
                [root.apiKeyEnvVarName]: root.apiKey
            }) : ({});
        requestProc.command = ["bash", scriptFilePath];
        requestProc.running = true;
        // curl bounds itself with --max-time; the watchdog only catches the
        // case where curl or the shell around it stops responding entirely.
        watchdog.interval = (root.effectiveRequestTimeout + 15) * 1000;
        watchdog.restart();
    }

    function buildScript(): string {
        const headers = {
            "Content-Type": "application/json"
        };
        const headerString = Object.entries(headers).filter(([k, v]) => v && v.length > 0).map(([k, v]) => `-H '${k}: ${v}'`).join(" ");
        const authHeader = root.strategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
        const quotedEndpoint = `'${CF.StringUtils.shellSingleQuoteEscape(root.endpoint)}'`;

        const quotedBody = `'${CF.StringUtils.shellSingleQuoteEscape(root.bodyPath)}'`;
        let content = "#!/usr/bin/env bash\n";

        // Attachments are put into the body here rather than when it was
        // built: a file is read once, at the last moment, and its bytes never
        // pass through QML.
        const injections = root.strategy.attachmentInjections ?? [];
        if (injections.length > 0 && root.attachScriptPath.length > 0) {
            const spec = CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(injections));
            const attachScript = `'${CF.StringUtils.shellSingleQuoteEscape(CF.FileUtils.trimFileProtocol(root.attachScriptPath))}'`;
            content += `attachResult=$(python3 ${attachScript} inject ${quotedBody} '${spec}'); attachExit=$?; if [ $attachExit -ne 0 ]; then printf '%s%s\\n' '${root.attachmentErrorMarker}' "$attachResult"; exit ${root.attachmentFailureExitCode}; fi\n`;
        }

        content += "curl --no-buffer -sS" + ` --connect-timeout ${root.connectTimeout}` + ` --max-time ${root.effectiveRequestTimeout}` + ` -w '\\n${root.statusMarker}%{http_code}@@\\n'` + ` ${quotedEndpoint}` + ` ${headerString}` + (authHeader ? ` ${authHeader}` : "") + ` --data-binary @${quotedBody}` + "\n";

        return content;
    }

    /**
     * One line of curl's output. Everything here assumes a single line; see
     * the parser below for why that has to be arranged rather than assumed.
     */
    function readLine(data: string) {
        if (data.startsWith(root.statusMarker)) {
            root.httpStatus = parseInt(data.slice(root.statusMarker.length)) || 0;
            return;
        }
        if (data.startsWith(root.attachmentErrorMarker)) {
            root.attachmentError = data.slice(root.attachmentErrorMarker.length);
            return;
        }
        if (data.length === 0)
            return;
        watchdog.restart();
        root.line(data);
    }

    function retryable(): bool {
        if (root.aborted || root.attachmentError.length > 0 || root.attempt >= root.maxRetries)
            return false;
        if (root.httpStatus === 429 || root.httpStatus >= 500)
            return true;
        // No status at all means curl never got a reply: DNS, connection
        // refused, TLS, or its own timeout.
        return root.httpStatus === 0 && root.exitCode !== 0;
    }

    function rollbackMessage() {
        if (!root.message || !root.messageSnapshot)
            return;
        const message = root.message;
        const snapshot = root.messageSnapshot;
        Object.keys(snapshot).forEach(key => {
            const value = snapshot[key];
            if (Array.isArray(value) || (value && typeof value === "object"))
                message[key] = JSON.parse(JSON.stringify(value));
            else
                message[key] = value;
        });
        message.thinking = true;
        message.done = false;
    }

    function cleanupTemporaryFiles() {
        const scriptFilePath = CF.FileUtils.trimFileProtocol(root.scriptPath);
        const bodyFilePath = CF.FileUtils.trimFileProtocol(root.bodyPath);
        const files = [];
        if (scriptFilePath.length > 0)
            files.push(scriptFilePath);
        if (bodyFilePath.length > 0)
            files.push(bodyFilePath);
        if (files.length > 0)
            Quickshell.execDetached(["rm", "-f", "--", ...files]);
    }

    function finish(reason: string, status: int, code: int) {
        root.cleanupTemporaryFiles();
        root.finished(reason, status, code);
    }

    // Both are written synchronously, because the process below is started the
    // moment the write returns. An asynchronous write has not necessarily
    // reached the disk by then, and bash handed a script that is still empty
    // reads no command, calls no curl and exits cleanly — a request that
    // reported neither an answer nor a failure.
    //
    // Read errors are not printed: the path is reassigned before every write,
    // which makes each of them try to read a file the previous request deleted.
    // A write that fails is still worth hearing about.
    FileView {
        id: scriptFile
        blockWrites: true
        printErrors: false
        onSaveFailed: error => console.log(`[AiRequest] Could not write the request script: ${error}`)
    }

    FileView {
        id: bodyFile
        blockWrites: true
        printErrors: false
        onSaveFailed: error => console.log(`[AiRequest] Could not write the request body: ${error}`)
    }

    Timer {
        id: retryTimer
        onTriggered: root.launch()
    }

    Timer {
        id: watchdog
        onTriggered: {
            if (!requestProc.running)
                return;
            console.log("[AiRequest] No answer within the timeout, killing the request");
            root.httpStatus = 0;
            requestProc.running = false;
        }
    }

    Process {
        id: requestProc

        // A chunk is not one line. When several lines arrive in the same read
        // they can be handed over glued together, newlines and all, and which
        // way it falls changes from one request to the next. The status is only
        // recognisable at the start of a line, so a glued chunk lost it and the
        // request ended without ever knowing what the server answered.
        stdout: SplitParser {
            onRead: data => data.split("\n").forEach(line => root.readLine(line))
        }

        // curl runs with -sS, which keeps it quiet but still says what went
        // wrong. That went nowhere before, which is why a request that failed
        // outside HTTP left nothing at all to read.
        stderr: SplitParser {
            onRead: data => {
                if (data.trim().length === 0)
                    return;
                console.log(`[AiRequest] ${data}`);
            }
        }

        onExited: (exitCode, exitStatus) => {
            watchdog.stop();
            root.exitCode = exitCode;

            if (root.aborted) {
                root.finish("aborted", root.httpStatus, exitCode);
                return;
            }
            if (root.attachmentError.length > 0) {
                root.finish("attachmentError", root.httpStatus, exitCode);
                return;
            }
            if (root.retryable()) {
                root.attempt += 1;
                const delay = Math.min(8, Math.pow(2, root.attempt - 1));
                root.rollbackMessage();
                root.retrying(root.attempt, delay, root.httpStatus);
                retryTimer.interval = delay * 1000;
                retryTimer.restart();
                return;
            }
            // Every request is made by curl with `-w`, so an answer always
            // carries a status. No status means the request never happened,
            // which used to pass for success and told a key that was never
            // sent anywhere that it works.
            const ok = exitCode === 0 && root.httpStatus >= 200 && root.httpStatus < 300;
            root.finish(ok ? "done" : "error", root.httpStatus, exitCode);
        }
    }
}
