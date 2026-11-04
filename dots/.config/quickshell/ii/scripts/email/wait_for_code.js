#!/usr/bin/env node
/**
 * Waits for a verification code to arrive in a Gmail account connected to the
 * shell, and prints it on stdout.
 *
 * Reuses what the cheatsheet Email tab already has: the connected accounts in
 * the keyring (KeyringStorage, `gmail_accounts`), fetch_emails.py /
 * fetch_email_body.py for the Gmail API, and EmailDetections.js — the same
 * detector that puts the "copy code" chip on a message — to read the code.
 *
 * Usage:
 *   wait_for_code.js [--to ADDRESS] [--query GMAIL_QUERY] [--since EPOCH_MS]
 *                    [--timeout SEC] [--interval SEC] [--latest]
 *
 *   --to        connected account to read (default: the first one); an
 *               address that is not connected fails instead of guessing
 *   --query     Gmail search, e.g. "from:accountprotection.microsoft.com"
 *   --since     ignore messages received before this moment (default: now - 2 min)
 *   --timeout   give up after this many seconds (default 180)
 *   --interval  seconds between polls (default 5)
 *   --latest    read the newest matching message once, ignoring --since
 *
 * Exit status: 0 with the code on stdout; 1 no code in time; 2 setup problem.
 * Diagnostics go to stderr.
 */
"use strict";

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const SCRIPT_DIR = __dirname;
const DETECTIONS = path.resolve(SCRIPT_DIR, "../../modules/common/functions/EmailDetections.js");

function fail(status, message) {
    process.stderr.write(`wait_for_code: ${message}\n`);
    process.exit(status);
}

function parseArgs(argv) {
    const out = { to: "", query: "", since: Date.now() - 120000, timeout: 180, interval: 5, latest: false };
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i];
        const next = () => {
            if (i + 1 >= argv.length)
                fail(2, `${arg} needs a value`);
            return argv[++i];
        };
        switch (arg) {
        case "--to": out.to = next().trim(); break;
        case "--query": out.query = next().trim(); break;
        case "--since": {
            const n = Number(next());
            if (Number.isFinite(n) && n > 0)
                out.since = n;
            break;
        }
        case "--timeout": out.timeout = Math.max(1, Number(next()) || out.timeout); break;
        case "--interval": out.interval = Math.max(1, Number(next()) || out.interval); break;
        case "--latest": out.latest = true; break;
        case "-h":
        case "--help":
            process.stdout.write(fs.readFileSync(__filename, "utf8").split("*/")[0] + "*/\n");
            process.exit(0);
            break;
        default: fail(2, `unknown argument ${arg}`);
        }
    }
    return out;
}

function loadDetector() {
    const sandbox = {};
    const source = fs.readFileSync(DETECTIONS, "utf8");
    vm.runInNewContext(source + "\nthis.detectAll = detectAll;", sandbox, { filename: DETECTIONS });
    return sandbox.detectAll;
}

function connectedAccounts() {
    let raw;
    try {
        raw = execFileSync("secret-tool", ["lookup", "application", "illogical-impulse"], { encoding: "utf8" });
    } catch {
        fail(2, "keyring is locked or has no shell data (secret-tool lookup failed)");
    }
    let data;
    try {
        data = JSON.parse(raw);
    } catch {
        fail(2, "keyring data is not JSON");
    }
    const list = Array.isArray(data.gmail_accounts) ? data.gmail_accounts.filter(a => a && a.refreshToken) : [];
    if (!list.length && data.gmail_refresh_token)
        list.push({ email: data.gmail_user_email || "", refreshToken: data.gmail_refresh_token });
    return list;
}

function pickAccount(accounts, to) {
    if (!accounts.length)
        fail(2, "no Gmail account is connected in the shell (cheatsheet > Email)");
    if (!to)
        return accounts[0];
    const wanted = to.toLowerCase();
    const found = accounts.find(a => String(a.email || "").toLowerCase() === wanted);
    if (!found)
        fail(2, `${to} is not connected in the shell; connected: ${accounts.map(a => a.email).join(", ")}`);
    return found;
}

function python(script, args) {
    const out = execFileSync("python3", [path.join(SCRIPT_DIR, script), ...args], {
        encoding: "utf8",
        timeout: 60000,
        stdio: ["ignore", "pipe", "ignore"]
    });
    return JSON.parse(out);
}

function listMessages(account, query) {
    const q = query ? `${query} newer_than:1d` : "newer_than:1d";
    const res = python("fetch_emails.py", [account.refreshToken, `SEARCH:${q}`, "5"]);
    return Array.isArray(res.messages) ? res.messages : [];
}

function messageCode(detectAll, account, message) {
    let body = "";
    try {
        body = python("fetch_email_body.py", [account.refreshToken, message.id]).body || "";
    } catch {
        body = message.snippet || "";
    }
    const codes = Array.from(detectAll(body, message.subject || "").codes || []);
    return codes.length ? String(codes[0]) : "";
}

function sleep(ms) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function main() {
    const opts = parseArgs(process.argv.slice(2));
    const detectAll = loadDetector();
    const account = pickAccount(connectedAccounts(), opts.to);
    const deadline = Date.now() + opts.timeout * 1000;
    const seen = new Set();

    process.stderr.write(`wait_for_code: watching ${account.email || "connected account"}`
        + `${opts.query ? ` for "${opts.query}"` : ""}\n`);

    for (;;) {
        let messages = [];
        try {
            messages = listMessages(account, opts.query);
        } catch (e) {
            process.stderr.write(`wait_for_code: fetch failed (${e.message.split("\n")[0]}), retrying\n`);
        }
        // Newest first; a message sent before the request belongs to an older sign-in.
        messages.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
        for (const message of messages) {
            if (seen.has(message.id))
                continue;
            seen.add(message.id);
            if (!opts.latest && (message.timestamp || 0) * 1000 < opts.since)
                continue;
            const code = messageCode(detectAll, account, message);
            if (code) {
                process.stdout.write(code + "\n");
                return;
            }
            if (opts.latest)
                break;
        }
        if (opts.latest)
            fail(1, "the newest matching message has no code");
        if (Date.now() + opts.interval * 1000 > deadline)
            fail(1, `no code arrived within ${opts.timeout}s`);
        sleep(opts.interval * 1000);
    }
}

main();
