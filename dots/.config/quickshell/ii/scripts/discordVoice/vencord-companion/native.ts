/*
 * Quickshell/II Discord Voice companion for Vencord
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import type { IpcMainInvokeEvent } from "electron";
import { createConnection, Socket } from "net";
import { join } from "path";

const uid = typeof process.getuid === "function" ? process.getuid() : 1000;
const runtime = process.env.XDG_RUNTIME_DIR || `/run/user/${uid}`;
const socketPath = join(runtime, "ii-discord-voice-vencord.sock");

let socket: Socket | undefined;
let connecting = false;
let latestState = "";
let input = "";
const commands: string[] = [];
let commandWaiter: ((command: string) => void) | undefined;

function deliver(command: string) {
    if (commandWaiter) {
        const resolve = commandWaiter;
        commandWaiter = undefined;
        resolve(command);
    } else {
        commands.push(command);
    }
}

function connect() {
    if (!socketPath || connecting || (socket && !socket.destroyed)) return;
    connecting = true;
    // A dropped connection can leave a partial line buffered. Carrying it into
    // the next session would corrupt that session's first command.
    input = "";
    console.log("[iiDiscordVoice] Connecting to socket:", socketPath);
    const candidate = createConnection(socketPath);
    socket = candidate;
    candidate.setEncoding("utf8");
    candidate.on("connect", () => {
        connecting = false;
        console.log("[iiDiscordVoice] Connected to Quickshell socket!");
        if (latestState) candidate.write(latestState);
    });
    candidate.on("data", chunk => {
        input += chunk;
        let newline;
        while ((newline = input.indexOf("\n")) >= 0) {
            const line = input.slice(0, newline);
            input = input.slice(newline + 1);
            if (line) deliver(line);
        }
    });
    candidate.on("error", (err) => {
        console.error("[iiDiscordVoice] Socket error:", err);
        connecting = false;
        candidate.destroy();
    });
    candidate.on("close", () => {
        connecting = false;
        if (socket === candidate) socket = undefined;
    });
}

export function publishState(_: IpcMainInvokeEvent, json: string) {
    latestState = JSON.stringify({ type: "state", state: JSON.parse(json) }) + "\n";
    connect();
    if (socket?.writable && !connecting) socket.write(latestState);
}

// One-off events (message notices). Unlike the state they are not replayed on
// reconnect: a toast for a message that arrived while the shell was down would
// only be stale.
export function publishEvent(_: IpcMainInvokeEvent, json: string) {
    connect();
    if (socket?.writable && !connecting)
        socket.write(JSON.stringify({ type: "event", event: JSON.parse(json) }) + "\n");
}

// This promise resolves only when the bridge pushes a command. The renderer
// immediately awaits another one afterward, giving us reactive bidirectional
// delivery without a command-file polling timer.
export function nextCommand(_: IpcMainInvokeEvent): Promise<string> {
    if (commands.length) return Promise.resolve(commands.shift()!);
    return new Promise(resolve => { commandWaiter = resolve; });
}

export function disconnect(_: IpcMainInvokeEvent) {
    socket?.destroy();
    socket = undefined;
    connecting = false;
    if (commandWaiter) {
        commandWaiter("");
        commandWaiter = undefined;
    }
}
