pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

/**
 * The assistant's view of System Health: read-only tools over HealthService, plus one
 * tool that proposes a fix as a button.
 *
 * Every read goes through HealthService, which asks the helper; nothing here touches
 * the system. Text that leaves through a tool result is redacted first when
 * `health.assistant.redact` is on. The crash tool returns the journal message that
 * systemd-coredump wrote — the stack trace as text — and there is no tool, and no helper
 * request, that returns the bytes of a core dump.
 *
 * `health_propose_fix` changes nothing either: it validates the verb against the
 * finding and emits `proposed`, and the System Health surface shows it as a button.
 * Only the user's click runs it, through `runProposal`.
 */
QtObject {
    id: root

    /// An asynchronous tool finished; Ai settles the broker call with it.
    signal resultReady(string key, var outcome)
    /// The model proposed a fix for the subject being explained.
    signal proposed(var proposal)

    /// The subject the System Health assistant is explaining, while it runs.
    property string activeKey: ""

    function clean(value): var {
        if (!HealthService.redact)
            return value;
        return JSON.parse(HealthService.redactText(JSON.stringify(value ?? null)));
    }

    function brief(f): var {
        return {
            id: f.id,
            kind: f.kind,
            severity: f.sev,
            title: HealthText.title(f),
            detail: HealthText.detail(f, Date.now()),
            since: f.since ? new Date(Number(f.since)).toISOString() : null,
            count: f.count
        };
    }

    // ── Synchronous reads ───────────────────────────────────────────────
    function overview(): var {
        if (!HealthService.running)
            return { status: "error", summary: Translation.tr("System Health is not running"), data: null };
        const items = HealthService.findings.slice(0, 30).map(f => root.brief(f));
        return {
            status: "success",
            summary: Translation.tr("%1 findings").arg(items.length),
            data: root.clean({
                findings: items,
                crashes: HealthService.crashGroups.slice(0, 10).map(g => ({ program: g.name, exe: g.exe, count: g.count, signal: g.signalName, package: g.package, version: g.version })),
                kernel: HealthService.system?.kernel ?? null,
                journalAccess: HealthService.journalAccess
            })
        };
    }

    function finding(args): var {
        const f = HealthService.finding(String(args?.id ?? ""));
        if (!f)
            return { status: "error", summary: Translation.tr("No such finding"), data: null, retryable: true };
        const out = Object.assign(root.brief(f), { data: f.data ?? {} });
        if (f.kind === "crash")
            out.crash = HealthService.crashGroup(String(f.data?.exe ?? ""));
        return { status: "success", summary: HealthText.title(f), data: root.clean(out) };
    }

    // ── Asynchronous reads (the helper answers) ─────────────────────────
    function relay(key, ok, data, error, summary): void {
        root.resultReady(key, ok
            ? { status: "success", summary: summary, data: root.clean(data) }
            : { status: "error", summary: Translation.tr("System Health could not read it (%1)").arg(error || "?"), data: null });
    }

    function unitLog(key, args): var {
        const unit = String(args?.unit ?? "");
        if (unit.length === 0)
            return { status: "error", summary: Translation.tr("No unit given"), data: null, retryable: true };
        const scope = String(args?.scope ?? "system") === "user" ? "user" : "system";
        const lines = Math.max(5, Math.min(80, Number(args?.lines ?? 40)));
        HealthService.query("unitLog", { scope: scope, unit: unit, lines: lines },
            (ok, data, error) => root.relay(key, ok, data, error, Translation.tr("Log of %1").arg(unit)));
        return { status: "pending" };
    }

    function crashTrace(key, args): var {
        const exe = String(args?.exe ?? "");
        if (!HealthService.crashGroup(exe))
            return { status: "error", summary: Translation.tr("No crash of that program in the last 7 days"), data: null, retryable: true };
        HealthService.query("crashInfo", { exe: exe }, (ok, data, error) => {
            // Only the message text and the COREDUMP_* metadata; the helper has no way to
            // return a dump's bytes, and the file path is dropped as well.
            const fields = Object.assign({}, data?.fields ?? {});
            delete fields.COREDUMP_FILENAME;
            root.relay(key, ok, { message: String(data?.message ?? ""), fields: fields }, error, Translation.tr("Stack trace read"));
        });
        return { status: "pending" };
    }

    function journalSearch(key, args): var {
        const q = {
            unit: String(args?.unit ?? ""),
            identifier: String(args?.identifier ?? ""),
            grep: String(args?.grep ?? ""),
            priority: Math.max(0, Math.min(7, Number(args?.priority ?? 4))),
            sinceHours: Math.max(1, Math.min(168, Number(args?.sinceHours ?? 24))),
            limit: Math.max(1, Math.min(100, Number(args?.limit ?? 40)))
        };
        HealthService.query("journalSearch", q,
            (ok, data, error) => root.relay(key, ok, data, error, Translation.tr("%1 journal lines").arg((data?.lines ?? []).length)));
        return { status: "pending" };
    }

    function packageOf(key, args): var {
        const path = String(args?.path ?? "");
        if (!path.startsWith("/"))
            return { status: "error", summary: Translation.tr("Give an absolute path"), data: null, retryable: true };
        HealthService.query("package", { path: path },
            (ok, data, error) => root.relay(key, ok, data, error, Translation.tr("Package read")));
        return { status: "pending" };
    }

    // ── Proposals ───────────────────────────────────────────────────────
    function verbsFor(f): var {
        switch (f?.kind) {
        case "unit":
        case "appLaunch":
        case "restartLoop":
            return ["restart", "stop", "disable", "resetFailed"];
        case "crash":
            return ["copyReport", "muteProgram"];
        case "journal":
            return ["markKnown", "mute"];
        case "drive":
            return ["selftest"];
        case "disk":
            return ["cleanJournal", "cleanPacmanCache", "emptyTrash"];
        case "reboot":
            return ["reboot"];
        case "firmware":
            return ["updateFirmware"];
        default:
            return [];
        }
    }

    function verbLabel(verb, f): string {
        const d = f?.data ?? {};
        switch (verb) {
        case "restart": return Translation.tr("Restart %1").arg(d.unit ?? "");
        case "stop": return Translation.tr("Stop %1").arg(d.unit ?? "");
        case "disable": return Translation.tr("Disable %1").arg(d.unit ?? "");
        case "resetFailed": return Translation.tr("Clear the failure");
        case "copyReport": return Translation.tr("Copy a bug report");
        case "muteProgram": return Translation.tr("Ignore crashes of %1").arg(d.name ?? "");
        case "markKnown": return Translation.tr("Mark as known");
        case "mute": return Translation.tr("Mute this message");
        case "selftest": return Translation.tr("Run a drive self-test");
        case "cleanJournal": return Translation.tr("Clean old journal archives");
        case "cleanPacmanCache": return Translation.tr("Clean the package cache");
        case "emptyTrash": return Translation.tr("Empty the trash");
        case "reboot": return Translation.tr("Restart the computer");
        case "updateFirmware": return Translation.tr("Update the firmware");
        default: return verb;
        }
    }

    function proposeFix(args): var {
        // A button needs a surface to appear on: outside a System Health explanation
        // (the sidebar chat) there is none, and saying "shown" would be untrue.
        if (root.activeKey.length === 0)
            return { status: "error", summary: Translation.tr("Only available while explaining a System Health finding"), data: null };
        const f = HealthService.finding(String(args?.findingId ?? ""));
        if (!f)
            return { status: "error", summary: Translation.tr("No such finding"), data: null, retryable: true };
        const verb = String(args?.action ?? "");
        const allowed = root.verbsFor(f);
        if (!allowed.includes(verb))
            return { status: "error", summary: Translation.tr("That action does not apply"), data: { allowed: allowed }, retryable: true };
        const proposal = { findingId: f.id, verb: verb, label: root.verbLabel(verb, f) };
        root.proposed(proposal);
        return {
            status: "success",
            summary: Translation.tr("Shown to the user as a button"),
            data: { shown: true, label: proposal.label, note: "Nothing was run. The user decides." }
        };
    }

    /// Runs a proposal. Called only from the user's click on its button.
    function runProposal(p): void {
        const f = HealthService.finding(String(p?.findingId ?? ""));
        if (!f)
            return;
        const d = f.data ?? {};
        switch (p.verb) {
        case "restart":
        case "stop":
        case "disable":
        case "resetFailed":
        case "selftest":
        case "copyReport":
            // Through runAction, so the card shows how it went.
            HealthService.runAction(f.id, p.verb);
            break;
        case "muteProgram":
            HealthService.muteProgram(String(d.exe ?? ""));
            break;
        case "markKnown":
            HealthService.markKnown(f.fp);
            break;
        case "mute":
            HealthService.mute(f.fp);
            break;
        case "cleanJournal":
            HealthService.cleanup("journal");
            break;
        case "cleanPacmanCache":
            HealthService.cleanup("pacmanCache");
            break;
        case "emptyTrash":
            HealthService.cleanup("trash");
            break;
        case "reboot":
            GlobalStates.sessionOpen = true;
            break;
        case "updateFirmware":
            HealthService.runInTerminal(["fwupdmgr", "update"]);
            break;
        }
    }
}
