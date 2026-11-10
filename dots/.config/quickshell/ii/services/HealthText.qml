pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Every word System Health shows about a finding.
 *
 * The helper sends codes and facts (`why: "exec-missing"`, `exitStatus: 203`); this turns
 * them into sentences through `Translation.tr`, so they can be translated and so the app,
 * the island strip, the notification fallback and the assistant all say the same thing.
 * Nothing here formats layout: callers decide how much of it fits.
 */
Singleton {
    id: root

    // ── Small formatters ────────────────────────────────────────────────
    function plural(n, one, many) {
        return (Number(n) === 1 ? one : many).arg(n);
    }

    /// "3 h", "1 d 22 h", "12 min", "now" — the age of something, compact.
    function age(ms, now) {
        const t = Number(ms ?? 0);
        if (!(t > 0))
            return "";
        const diff = Math.max(0, (now ?? Date.now()) - t);
        const min = Math.floor(diff / 60000);
        if (min < 1)
            return Translation.tr("now");
        if (min < 60)
            return Translation.tr("%1 min").arg(min);
        const h = Math.floor(min / 60);
        if (h < 24)
            return Translation.tr("%1 h").arg(h);
        const d = Math.floor(h / 24);
        const rest = h % 24;
        return rest > 0 && d < 7 ? Translation.tr("%1 d %2 h").arg(d).arg(rest) : Translation.tr("%1 d").arg(d);
    }

    /// The day a crash or an update happened, relative to today: "Today", "Yesterday", "Thu".
    function dayName(ms, now) {
        const d = new Date(Number(ms));
        const today = new Date(now ?? Date.now());
        const start = t => new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
        const days = Math.round((start(today) - start(d)) / 86400000);
        if (days === 0)
            return Translation.tr("Today");
        if (days === 1)
            return Translation.tr("Yesterday");
        return Qt.locale().dayName(d.getDay(), Locale.ShortFormat);
    }

    /// Binary sizes, the way a disk tool shows them: 477 GiB, 96 MiB.
    function bytes(b) {
        let v = Number(b ?? 0);
        if (!(v > 0))
            return Translation.tr("0 B");
        const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return `${v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
    }

    /// Decimal terabytes for SMART "data written", as drive makers rate endurance.
    function terabytes(b) {
        const tb = Number(b ?? 0) / 1e12;
        return tb >= 10 ? `${Math.round(tb)} TB` : `${tb.toFixed(1)} TB`;
    }

    function unitName(unit) {
        // app-com.anthropic.Claude.OpenInCode@d893….service → com.anthropic.Claude.OpenInCode
        const s = String(unit ?? "");
        const m = s.match(/^app-(?:[^-]+-)?(.+?)(?:@[0-9a-f]+)?\.(?:service|scope)$/);
        return m ? m[1] : s;
    }

    function signalName(sig, name) {
        if (name && String(name).length > 0)
            return String(name);
        const names = { 1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGBUS", 8: "SIGFPE", 9: "SIGKILL", 11: "SIGSEGV", 13: "SIGPIPE", 15: "SIGTERM", 31: "SIGSYS" };
        return names[Number(sig)] ?? `SIG${sig}`;
    }

    /// What a signal means, as the one phrase a crash card leads with.
    function signalMeaning(sig) {
        switch (Number(sig)) {
        case 6:
            return Translation.tr("Aborted itself on purpose");
        case 11:
            return Translation.tr("Touched memory it did not own");
        case 7:
            return Translation.tr("Read memory that was not there");
        case 4:
            return Translation.tr("Ran an invalid instruction");
        case 8:
            return Translation.tr("Did an impossible calculation");
        case 5:
            return Translation.tr("Stopped at a debug trap");
        case 31:
            return Translation.tr("Made a forbidden system call");
        case 3:
            return Translation.tr("Was told to quit and dump");
        default:
            return Translation.tr("Crashed");
        }
    }

    // ── Units ───────────────────────────────────────────────────────────
    /// The plain reason a unit failed, from the helper's `why` code.
    function unitWhy(d) {
        const why = String(d?.why ?? "unknown");
        switch (why) {
        case "exec-missing":
            return Translation.tr("The program it starts does not exist");
        case "exec-perm":
            return Translation.tr("The program it starts cannot be run");
        case "user":
            return Translation.tr("The user it runs as does not exist");
        case "namespace":
            return Translation.tr("Its sandbox could not be set up");
        case "start-limit":
            return Translation.tr("It failed too often, so systemd stopped retrying");
        case "timeout":
            return Translation.tr("It took too long to start or stop");
        case "oom":
            return Translation.tr("The kernel killed it to free memory");
        case "signal":
            return Translation.tr("It was killed by %1").arg(root.signalName(d?.exitStatus));
        case "core":
            return Translation.tr("It crashed");
        case "dependency":
            return Translation.tr("Something it needs failed first");
        case "exit":
            return Translation.tr("It exited with status %1").arg(d?.exitStatus ?? "?");
        default:
            return Translation.tr("It stopped with an error");
        }
    }

    /// "203/EXEC · start-limit-hit", the technical line under the plain one.
    function unitStatus(d) {
        const parts = [];
        const st = d?.exitStatus;
        const code = String(d?.exitCode ?? "");
        if (code === "killed" || code === "dumped")
            parts.push(root.signalName(st));
        else if (st !== undefined && st !== null && Number(st) !== 0) {
            const names = { 200: "CHDIR", 203: "EXEC", 209: "STDOUT", 217: "USER", 226: "NAMESPACE", 126: "", 127: "" };
            const label = names[Number(st)];
            parts.push(label ? `${st}/${label}` : String(st));
        }
        const result = String(d?.result ?? "");
        if (result.length > 0 && result !== "success" && result !== "exit-code")
            parts.push(result);
        return parts.join(" · ");
    }

    // ── Findings ────────────────────────────────────────────────────────
    /// The one-line title of a finding.
    function title(f) {
        const d = f?.data ?? {};
        switch (String(f?.kind ?? "")) {
        case "unit":
            return Translation.tr("%1 failed").arg(d.unit ?? "");
        case "appLaunch":
            return Translation.tr("%1 did not start").arg(d.description && d.description.length > 0 ? d.description : root.unitName(d.unit));
        case "restartLoop":
            return Translation.tr("%1 keeps restarting").arg(d.unit ?? "");
        case "crash":
            return f.count > 1 ? Translation.tr("%1 crashed %2 times").arg(d.name ?? "").arg(f.count)
                               : Translation.tr("%1 crashed").arg(d.name ?? "");
        case "journal":
            return Translation.tr("New error from %1").arg(root.sourceLabel(d.source));
        case "disk":
            return Translation.tr("%1 is %2 % full").arg(d.mount ?? "").arg(Math.round(Number(d.usedPct ?? 0)));
        case "drive":
            return Translation.tr("%1 needs attention").arg(d.model ?? Translation.tr("A drive"));
        case "firmware":
            return Translation.tr("Firmware update for %1").arg(d.name ?? d.device ?? "");
        case "security":
            return Translation.tr("Platform security: level %1").arg(d.hsiLevel ?? 0);
        case "reboot":
            return Translation.tr("Restart to finish the kernel update");
        case "deletedLibs":
            return root.plural((d.processes ?? []).length, Translation.tr("%1 program uses replaced libraries"), Translation.tr("%1 programs use replaced libraries"));
        case "pacnew":
            return root.plural((d.files ?? []).length, Translation.tr("%1 config file to merge"), Translation.tr("%1 config files to merge"));
        case "timesync":
            return Translation.tr("The clock is not synchronised");
        case "pressure":
            return d.resource === "memory" ? Translation.tr("The system is short of memory")
                 : d.resource === "io" ? Translation.tr("The disks cannot keep up")
                 : Translation.tr("The processor is overloaded");
        case "thermal":
            return Translation.tr("The processor is throttling");
        case "rebuild": {
            const pkgs = Array.from(d.packages ?? []);
            return pkgs.some(p => p.reason === "quickshell")
                ? Translation.tr("Rebuild Quickshell before you log out")
                : root.plural(pkgs.length, Translation.tr("%1 package needs a rebuild"), Translation.tr("%1 packages need a rebuild"));
        }
        case "shellHelper":
            return Translation.tr("%1 is out of date").arg(d.name ?? "");
        case "shellMemory":
            return Translation.tr("The shell is using %1 of memory").arg(root.bytes(Number(d.rssMb ?? 0) * 1048576));
        case "shellErrors":
            return root.plural(d.kinds ?? f.count, Translation.tr("The shell logged %1 QML error"), Translation.tr("The shell logged %1 QML errors"));
        case "slowBoot":
            return Translation.tr("This boot took %1").arg(root.seconds(d.total));
        case "config":
            return d.state === "malformed" ? Translation.tr("The shell's settings file is broken") : Translation.tr("The shell's settings were repaired");
        case "battery":
            return Translation.tr("The battery holds %1 % of its design charge").arg(Math.round(Number(d.healthPct ?? 0)));
        case "peripheralBattery":
            return Translation.tr("%1 is at %2 %").arg(d.model || d.name || Translation.tr("A wireless device")).arg(Math.round(Number(d.capacity ?? 0)));
        case "mce":
            return Translation.tr("The processor reported hardware errors");
        case "gpu":
            return root.plural(d.count ?? f.count, Translation.tr("The GPU was reset %1 time this boot"), Translation.tr("The GPU was reset %1 times this boot"));
        case "oom":
            return root.plural(d.count ?? f.count, Translation.tr("%1 program was killed for memory"), Translation.tr("%1 programs were killed for memory"));
        case "edac":
            return Number(d.ue ?? 0) > 0 ? Translation.tr("Memory errors that could not be corrected") : Translation.tr("Memory errors were corrected");
        case "radioFw":
            return Translation.tr("%1 firmware crashed").arg(d.device ?? "");
        case "usb":
            return Translation.tr("USB errors on port %1").arg(d.port ?? "");
        case "aer":
            return d.fatal ? Translation.tr("PCIe errors that were not corrected") : Translation.tr("Many corrected PCIe errors");
        case "overheat":
            return Translation.tr("The machine reached a critical temperature");
        case "fan":
            return Translation.tr("A fan stopped while the processor is hot");
        default:
            return Translation.tr("Something needs attention");
        }
    }

    /// A unit action's verb as the button that ran it says it.
    function verbLabel(verb) {
        switch (String(verb ?? "")) {
        case "restart": return Translation.tr("Restart");
        case "stop": return Translation.tr("Stop");
        case "start": return Translation.tr("Start");
        case "resetFailed": return Translation.tr("Clear the failure");
        case "disable": return Translation.tr("Disable");
        case "enable": return Translation.tr("Enable");
        default: return String(verb ?? "");
        }
    }

    /// "17.5 s", "1 min 3 s" from milliseconds.
    function seconds(ms) {
        const s = Number(ms ?? 0) / 1000;
        if (s < 60)
            return Translation.tr("%1 s").arg(s < 10 ? s.toFixed(1) : Math.round(s));
        return Translation.tr("%1 min %2 s").arg(Math.floor(s / 60)).arg(Math.round(s % 60));
    }

    /// One package of a `rebuild` finding, in words: why it needs the rebuild.
    function rebuildReason(p) {
        switch (String(p?.reason ?? "")) {
        case "quickshell":
            return p.built && p.installed ? Translation.tr("built for Qt %1, Qt %2 is installed").arg(p.built).arg(p.installed)
                : Translation.tr("built for another Qt");
        case "lib":
            return p.prebuilt
                ? Translation.tr("cannot find %1; it ships prebuilt, so install what provides it rather than rebuilding").arg(Array.from(p.libs ?? []).slice(0, 3).join(", "))
                : Translation.tr("cannot find %1").arg(Array.from(p.libs ?? []).slice(0, 3).join(", "));
        case "qt":
            return Translation.tr("uses Qt internals and was built before Qt %1").arg(p.qt ?? "");
        case "python":
            return Translation.tr("installed for %1, %2 is installed now").arg(Array.from(p.python ?? []).join(", ")).arg(p.current ?? "");
        default:
            return "";
        }
    }

    /// The second line: why, in words, and how long.
    function detail(f, now) {
        const d = f?.data ?? {};
        const since = root.age(f?.since, now);
        switch (String(f?.kind ?? "")) {
        case "unit":
        case "appLaunch":
            return [root.unitWhy(d), since].filter(s => s.length > 0).join(" · ");
        case "restartLoop":
            return Translation.tr("%1 restarts in 10 minutes").arg(d.nRestarts ?? f.count);
        case "crash":
            return [root.signalMeaning(d.signal), d.package ? `${d.package} ${d.version ?? ""}`.trim() : ""].filter(s => s.length > 0).join(" · ");
        case "journal":
            return String(d.sample ?? d.template ?? "");
        case "disk":
            return d.etaDays !== null && d.etaDays !== undefined
                ? Translation.tr("%1 free · full in about %2 days").arg(root.bytes(d.avail)).arg(Math.max(1, Math.round(d.etaDays)))
                : Translation.tr("%1 free").arg(root.bytes(d.avail));
        case "drive":
            return root.driveProblems(d).join(" · ");
        case "firmware":
            return d.newVersion ? Translation.tr("%1 → %2").arg(d.version ?? "?").arg(d.newVersion) : "";
        case "security":
            return d.runtimeIssue ? Translation.tr("fwupd reports a runtime issue") : Translation.tr("Some platform checks fail");
        case "reboot":
            return Translation.tr("Running %1, its modules are gone from disk").arg(d.running ?? "");
        case "deletedLibs":
            return (d.processes ?? []).slice(0, 3).map(p => p.comm).join(", ");
        case "pacnew":
            return (d.files ?? []).slice(0, 2).join(", ");
        case "timesync":
            return Translation.tr("Logins, TLS and two-factor codes can fail");
        case "pressure":
            return Translation.tr("%1 % of the last minute was spent waiting").arg(Number(d.avg60 ?? 0).toFixed(1));
        case "thermal":
            return Translation.tr("%1 slowdowns in 5 minutes").arg(d.events5min ?? 0);
        case "rebuild": {
            const pkgs = Array.from(d.packages ?? []);
            const qs = pkgs.find(p => p.reason === "quickshell");
            return qs ? Translation.tr("It was %1; the shell may not start again").arg(root.rebuildReason(qs))
                : pkgs.slice(0, 3).map(p => p.name).join(", ");
        }
        case "shellHelper":
            return Translation.tr("Built from older sources than the shell's");
        case "shellErrors":
            return String(Array.from(d.errors ?? [])[0]?.message ?? "");
        case "shellMemory":
            return d.grown ? Translation.tr("%1 more than in its first hour").arg(root.bytes((Number(d.rssMb ?? 0) - Number(d.baseMb ?? 0)) * 1048576))
                : Translation.tr("Above the %1 limit").arg(root.bytes(Number(d.limitMb ?? 0) * 1048576));
        case "slowBoot":
            return d.unit ? Translation.tr("Usually %1; %2 took %3").arg(root.seconds(d.median)).arg(d.unit).arg(root.seconds(d.unitMs))
                : Translation.tr("Usually %1").arg(root.seconds(d.median));
        case "config":
            return d.state === "malformed" ? Translation.tr("Defaults are in use until it is fixed") : Translation.tr("Some values were reset to their defaults");
        case "battery":
            return d.cycles ? Translation.tr("After %1 charge cycles; plan a replacement below %2 %").arg(Math.round(d.cycles)).arg(Math.max(0, Number(d.limit ?? 80) - 20))
                : Translation.tr("It runs out sooner than it used to");
        case "peripheralBattery":
            return Translation.tr("Charge it soon");
        case "mce":
            return Translation.tr("%1 machine-check errors: often a failing processor, memory or overclock").arg(d.count ?? f.count);
        case "gpu":
            return Translation.tr("Driver %1: hangs that reset the GPU, often a driver bug").arg(Object.keys(d.drivers ?? {}).join(", "));
        case "oom":
            return Object.keys(d.killed ?? {}).slice(0, 3).join(", ");
        case "edac":
            return Translation.tr("%1 corrected, %2 not").arg(d.ce ?? 0).arg(d.ue ?? 0);
        case "radioFw":
            return Translation.tr("%1 times this boot: the device restarted its firmware").arg(d.count ?? f.count);
        case "usb":
            return Translation.tr("%1 errors this boot: often a cable, hub or port").arg(d.count ?? f.count);
        case "aer":
            return Translation.tr("%1 this boot").arg(d.count ?? f.count);
        case "overheat":
            return Translation.tr("The kernel said so %1 times this boot").arg(d.count ?? f.count);
        case "fan":
            return d.tempC ? Translation.tr("Processor at %1 °C").arg(Math.round(d.tempC)) : "";
        default:
            return "";
        }
    }

    // ── In plain words ──────────────────────────────────────────────────
    // What a finding means for someone who does not know Linux's vocabulary, without
    // the assistant: what happened, whether it matters, what to do. Each part is one
    // or two sentences, and "what to do" names the buttons the sheet really has.

    function lowerFirst(s) {
        const t = String(s ?? "");
        return t.length > 0 ? t[0].toLowerCase() + t.slice(1) : t;
    }

    function plain(what, matters, todo) {
        return { what: String(what ?? ""), matters: String(matters ?? ""), todo: String(todo ?? "") };
    }

    /// { what, matters, todo } for a finding, or null for a kind with nothing to say.
    function explain(f) {
        const d = f?.data ?? {};
        const count = Number(d.count ?? f?.count ?? 0);
        switch (String(f?.kind ?? "")) {
        case "unit": {
            const gone = d.why === "exec-missing" || d.why === "user";
            return root.plain(
                Translation.tr("%1 is a background service: a program the system starts on its own to do one job. It stopped: %2.").arg(d.unit ?? "").arg(root.lowerFirst(root.unitWhy(d))),
                Translation.tr("Whatever it does is not happening right now. Many services are optional extras: if you do not know what it is for and nothing seems broken, it can wait."),
                gone ? Translation.tr("Its program was probably removed along with a package. Disable it so it stops trying; reinstall the package if you still want it.")
                     : Translation.tr("Press Restart. If it fails again, “Show in terminal” shows its last messages, which usually say why."));
        }
        case "appLaunch":
            return root.plain(
                Translation.tr("%1 was opened, and it closed straight away with an error.").arg(d.description && d.description.length > 0 ? d.description : root.unitName(d.unit)),
                Translation.tr("Only that app is affected; the rest of the system is fine."),
                Translation.tr("Try opening it again. If it keeps failing, “Show in terminal” shows its last messages; updating the system or reinstalling the app often fixes it."));
        case "restartLoop":
            return root.plain(
                Translation.tr("%1 keeps failing, and the system keeps starting it again: %2 times in ten minutes.").arg(d.unit ?? "").arg(d.nRestarts ?? f?.count ?? 0),
                Translation.tr("Each restart costs a little processor time and battery, and whatever it does keeps breaking."),
                Translation.tr("Stop it to end the loop, then read “Show in terminal” for why it fails."));
        case "crash":
            return root.explainCrash(Object.assign({}, d, { count: f?.count ?? 1 }));
        case "journal":
            return root.explainJournal({ source: d.source, state: "new", bootsSeen: d.bootsSeen, bootsWindow: d.bootsWindow });
        case "disk": {
            const where = d.mount === "/" ? Translation.tr("The system drive") : Translation.tr("The drive at %1").arg(d.mount ?? "");
            const eta = d.etaDays !== null && d.etaDays !== undefined;
            return root.plain(
                Translation.tr("%1 is %2 % full; %3 is left.").arg(where).arg(Math.round(Number(d.usedPct ?? 0))).arg(root.bytes(d.avail)),
                [Translation.tr("When a drive is full, programs cannot save files, updates fail and the system can stop working properly."),
                 eta ? Translation.tr("At this pace it is full in about %1 days.").arg(Math.max(1, Math.round(d.etaDays))) : ""].filter(s => s.length > 0).join(" "),
                Translation.tr("“Free up space” safely clears caches, old logs and the trash. Big files you no longer need, like downloads and videos, are the next place to look."));
        }
        case "drive": {
            const wearOnly = Array.from(d.problems ?? []).every(p => p === "wear");
            return root.plain(
                Translation.tr("%1 checks its own health (this is called SMART), and it reports a problem: %2.").arg(d.model ?? Translation.tr("A drive")).arg(root.driveProblems(d).join(", ")),
                wearOnly ? Translation.tr("Drives wear out as they are written to. It still works, but it is ageing.")
                         : Translation.tr("A drive that reports problems can fail without warning, and the files on it could be lost."),
                Translation.tr("Back up what matters on it now. “Run a self-test” checks it more thoroughly; plan to replace it if the problems grow."));
        }
        case "firmware":
            return root.plain(
                Translation.tr("Firmware is the small program built into a device, here %1. Its maker has published an update.").arg(d.name ?? d.device ?? ""),
                Translation.tr("Firmware updates fix bugs and security holes in the hardware itself. It is rarely urgent."),
                Translation.tr("“Update in a terminal” installs it. Some devices finish after a restart; keep a laptop plugged in meanwhile."));
        case "security":
            return root.plain(
                Translation.tr("fwupd checks how well the computer protects itself before the system starts: Secure Boot, memory encryption and similar. It scores level %1; higher is better.").arg(d.hsiLevel ?? 0),
                Translation.tr("A low level is common, especially on laptops running Linux. It does not mean anything was attacked, only that some protections are off or not supported."),
                Translation.tr("Most of these are switched in the firmware settings (the BIOS). “Open the fwupd report” lists each check; nothing has to change unless you want stronger protection."));
        case "reboot":
            return root.plain(
                Translation.tr("The kernel, the core of the system, was updated. The old one keeps running until you restart."),
                Translation.tr("Until then, things you plug in or turn on later, like USB drives, Bluetooth or a VPN, may not work: the old kernel's parts were removed from disk."),
                Translation.tr("Save your work and restart when it suits you."));
        case "deletedLibs":
            return root.plain(
                root.plural((d.processes ?? []).length, Translation.tr("An update replaced shared code that %1 program still uses in its old version, because it was already running."), Translation.tr("An update replaced shared code that %1 programs still use in its old version, because they were already running.")),
                Translation.tr("They keep working, but with the old code, including any security hole the update fixed. It is not urgent."),
                Translation.tr("Close and reopen them, or restart the computer, and they load the new code."));
        case "pacnew":
            return root.plain(
                Translation.tr("An update brought new versions of settings files you had changed. It kept yours and saved the new ones beside them, ending in .pacnew."),
                Translation.tr("Usually harmless. Sometimes the new version has a setting a program needs, and it misbehaves until the two are merged."),
                Translation.tr("“Merge in a terminal” shows both side by side so you can choose. If unsure, leave it: nothing breaks right away."));
        case "timesync":
            return root.plain(
                Translation.tr("The computer's clock is not being checked against a time server on the internet."),
                Translation.tr("A clock that drifts breaks secure websites, sign-ins and two-factor codes."),
                Translation.tr("“Turn on network time” sets it right and keeps it right."));
        case "pressure":
            return root.plain(
                d.resource === "memory" ? Translation.tr("Programs are using nearly all the memory, so the system spends its time shuffling data around instead of working.")
                : d.resource === "io" ? Translation.tr("Programs are waiting for the disk, which cannot read and write fast enough.")
                : Translation.tr("More work is asked of the processor than it can do."),
                Translation.tr("Everything feels slow while it lasts. It passes unless it keeps coming back."),
                Translation.tr("“Open the task manager” shows which program uses the most. Close what you do not need."));
        case "thermal":
            return root.plain(
                Translation.tr("The processor got hot and slowed itself down to cool off, %1 times in five minutes.").arg(d.events5min ?? 0),
                Translation.tr("It protects the hardware, so nothing breaks, but everything runs slower."),
                Translation.tr("Keep the air vents free (not on a bed or a lap) and close heavy programs. If it happens while idle, the fan may need cleaning."));
        case "rebuild": {
            const pkgs = Array.from(d.packages ?? []);
            if (pkgs.some(p => p.reason === "quickshell"))
                return root.plain(
                    Translation.tr("Quickshell, the program that draws this shell (bar, panels and this app), was built for an older version of Qt, the toolkit it uses. Qt has been updated."),
                    Translation.tr("It keeps running for now, but the next time it starts, after logging out or restarting, the shell may not appear."),
                    Translation.tr("Rebuild it before you log out. The button opens a terminal and asks before doing anything."));
            const rebuildable = pkgs.filter(p => p.prebuilt !== true).length;
            return root.plain(
                Translation.tr("Some programs installed from the AUR, the community's package collection, were built on this computer against parts of the system that an update has since changed or removed."),
                Translation.tr("They may not start, or may crash, until fixed. Only those programs are affected."),
                rebuildable > 0 ? Translation.tr("The rebuild button rebuilds them in a terminal. Any marked as prebuilt cannot be rebuilt: install the libraries they miss instead.")
                                : Translation.tr("These come prebuilt, so rebuilding them changes nothing. “Install the missing libraries” finds what they need and installs it."));
        }
        case "shellHelper":
            return root.plain(
                Translation.tr("%1 is a small helper program of this shell, compiled on this computer. The shell was updated, but the helper still runs its older version.").arg(d.name ?? ""),
                Translation.tr("The feature it powers may misbehave until it is rebuilt."),
                Translation.tr("Press Rebuild. It takes about a minute and needs nothing from you."));
        case "shellMemory":
            return root.plain(
                [Translation.tr("The shell (bar, panels and these apps) is using %1 of memory.").arg(root.bytes(Number(d.rssMb ?? 0) * 1048576)),
                 d.grown ? Translation.tr("It grew by %1 since its first hour, which can be a leak.").arg(root.bytes((Number(d.rssMb ?? 0) - Number(d.baseMb ?? 0)) * 1048576)) : ""].filter(s => s.length > 0).join(" "),
                Translation.tr("Harmless by itself, but it leaves less memory for your programs."),
                Translation.tr("Restarting the shell frees it: press Ctrl+Super+R. Your windows stay open."));
        case "shellErrors":
            return root.plain(
                root.plural(d.kinds ?? f?.count ?? 0, Translation.tr("The shell hit %1 error in its own code. QML is the language it is written in."), Translation.tr("The shell hit %1 errors in its own code. QML is the language it is written in.")),
                Translation.tr("Usually one small part of the interface misbehaves while the rest works. Your files and programs are not affected."),
                Translation.tr("If something looks broken, these messages help the shell's developers. Restarting the shell (Ctrl+Super+R) often clears it."));
        case "slowBoot":
            return root.plain(
                [Translation.tr("This start took %1; it usually takes %2.").arg(root.seconds(d.total)).arg(root.seconds(d.median)),
                 d.unit ? Translation.tr("Most of the extra time went to %1.").arg(d.unit) : ""].filter(s => s.length > 0).join(" "),
                Translation.tr("Only the wait is affected."),
                Translation.tr("Once is nothing to worry about. If every start is slow, the service named here is usually waiting for a network or a disk that is not there."));
        case "config":
            return d.state === "malformed"
                ? root.plain(
                    Translation.tr("The shell's settings file has a mistake in it and cannot be read, so the shell uses its default settings."),
                    Translation.tr("Your own settings are not lost: they are still in the file, just not applied."),
                    Translation.tr("“Open Settings” to fix it, or restore a backup of the file."))
                : root.plain(
                    Translation.tr("Some values in the shell's settings file were invalid and were reset to their defaults."),
                    Translation.tr("Only those settings changed; the rest are still yours."),
                    Translation.tr("Check the settings listed here and set them again if needed."));
        case "battery":
            return root.plain(
                Translation.tr("The battery now holds %1 % of the charge it held when new.").arg(Math.round(Number(d.healthPct ?? 0))),
                Translation.tr("Batteries wear with use; this is normal ageing. It means less time unplugged, not danger."),
                Translation.tr("Nothing to do now. A charge limit, if the laptop supports one, slows the wear. Replace it when the time unplugged gets too short."));
        case "peripheralBattery":
            return root.plain(
                Translation.tr("%1 is low on battery: %2 %.").arg(d.model || d.name || Translation.tr("A wireless device")).arg(Math.round(Number(d.capacity ?? 0))),
                Translation.tr("It stops working when it runs out."),
                Translation.tr("Charge it, or change its batteries."));
        case "mce":
            return root.plain(
                Translation.tr("The processor reported %1 errors inside the hardware itself (machine-check errors).").arg(count),
                Translation.tr("They can point to a failing processor or memory, or to an unstable overclock or undervolt. Take it seriously if it repeats."),
                Translation.tr("Undo any overclock or undervolt. If it keeps happening, test the memory with memtest86+, and contact the maker if it is under warranty."));
        case "gpu":
            return root.plain(
                root.plural(count, Translation.tr("The graphics chip froze and its driver restarted it, %1 time this boot."), Translation.tr("The graphics chip froze and its driver restarted it, %1 times this boot.")),
                Translation.tr("The screen may have frozen or flickered for a moment, and some apps may have closed. It is usually a driver bug, not broken hardware."),
                Translation.tr("Update the system: driver fixes arrive with updates. If it is frequent, note which app was open; it helps a bug report."));
        case "oom":
            return root.plain(
                root.plural(count, Translation.tr("Memory ran out, so the system closed %1 program to keep going."), Translation.tr("Memory ran out, so the system closed %1 programs to keep going.")),
                Translation.tr("Those programs lost any unsaved work."),
                Translation.tr("Close programs you do not need, and watch the task manager for one that keeps growing. If it happens often, more swap or memory helps."));
        case "edac":
            return Number(d.ue ?? 0) > 0
                ? root.plain(
                    Translation.tr("The memory (RAM) reported errors it could not correct."),
                    Translation.tr("Data in memory may have been damaged, which can crash programs or corrupt files. Failing memory is likely."),
                    Translation.tr("Save your work and back up. Test the memory with memtest86+ and replace the faulty module."))
                : root.plain(
                    Translation.tr("The memory (RAM) found and fixed %1 errors on its own.").arg(d.ce ?? 0),
                    Translation.tr("Corrected errors are harmless by themselves, but many of them can be the first sign of a failing module."),
                    Translation.tr("Keep an eye on it. If the number keeps rising, test the memory with memtest86+."));
        case "radioFw":
            return root.plain(
                root.plural(count, Translation.tr("The built-in program of %2, a wireless chip, crashed and restarted itself %1 time."), Translation.tr("The built-in program of %2, a wireless chip, crashed and restarted itself %1 times.")).arg(d.device ?? ""),
                Translation.tr("The connection drops for a few seconds each time."),
                Translation.tr("Update the system: fixes for these chips arrive in the linux-firmware package."));
        case "usb":
            return root.plain(
                Translation.tr("A device on USB port %1 had %2 connection errors.").arg(d.port ?? "").arg(count),
                Translation.tr("It may disconnect or be slow. The cause is usually a cable, a hub or a loose plug, rarely the computer."),
                Translation.tr("Try another cable or port, and plug the device in directly rather than through a hub."));
        case "aer":
            return root.plain(
                Translation.tr("PCIe is the internal link to parts like the graphics chip, the SSD and Wi-Fi. It reported %1 errors.").arg(count),
                d.fatal ? Translation.tr("Errors it could not correct can freeze or crash the computer.")
                        : Translation.tr("They were corrected, so nothing was lost, but this many can slow the device down."),
                Translation.tr("Update the system and the firmware; these are often a power-saving quirk that updates fix."));
        case "overheat":
            return root.plain(
                Translation.tr("The computer got so hot that the kernel had to step in, %1 times this boot.").arg(count),
                Translation.tr("At that heat it can switch itself off to protect the hardware, and heat shortens the hardware's life."),
                Translation.tr("Free the air vents and clean the fan, and avoid heavy work on soft surfaces. If it happens while idle, have the cooling checked."));
        case "fan":
            return root.plain(
                d.tempC ? Translation.tr("A fan is not turning while the processor is at %1 °C.").arg(Math.round(d.tempC)) : Translation.tr("A fan is not turning while the processor is hot."),
                Translation.tr("Without it the computer overheats, slows down and can switch itself off."),
                Translation.tr("Dust or a stuck fan is common. If it never spins, it needs cleaning or replacing."));
        default:
            return null;
        }
    }

    /// A crash group (the Crashes page's stage, or a `crash` finding's data) in plain words.
    function explainCrash(g) {
        const name = String(g?.name ?? "");
        const n = Number(g?.count ?? 1);
        let what;
        switch (Number(g?.signal)) {
        case 11:
        case 7:
            what = Translation.tr("A bug in %1 made it use memory it had no right to, so the system stopped it at once.").arg(name);
            break;
        case 6:
            what = Translation.tr("%1 found something wrong inside itself and stopped on purpose, rather than carry on and do damage.").arg(name);
            break;
        case 4:
        case 8:
        case 31:
            what = Translation.tr("%1 tried something the processor or the system does not allow, so it was stopped.").arg(name);
            break;
        default:
            what = Translation.tr("%1 stopped suddenly: it crashed.").arg(name);
        }
        const matters = [
            n > 1 ? Translation.tr("It crashed %1 times, so this is a bug that repeats, not bad luck.").arg(n)
                  : Translation.tr("One crash is usually harmless: the program closed, and only unsaved work in it was lost."),
            g?.root ? Translation.tr("It is part of the system, so something that relies on it may have stopped working too.") : "",
            g?.afterUpdate ? Translation.tr("It began after an update to %1, the likely cause.").arg(g.afterUpdate.name ?? "") : ""
        ].filter(s => s.length > 0).join(" ");
        const todo = g?.afterUpdate
            ? Translation.tr("Fixes usually come as updates: update the system. If it keeps crashing, “Copy report” gives its developers what they need.")
            : Translation.tr("If it keeps happening, update the system first. Then “Copy report” gives its developers what they need. Not something you use? The bell button ignores its crashes.");
        return root.plain(what, matters, todo);
    }

    /// A journal message group in plain words.
    function explainJournal(g) {
        const source = String(g?.source ?? "") === "kernel" ? Translation.tr("The kernel, the core of the system,") : root.sourceLabel(g?.source);
        const every = Number(g?.bootsSeen ?? 0) >= Number(g?.bootsWindow ?? 5);
        return root.plain(
            Translation.tr("The journal is the system's diary: programs write down what they do in it. %1 wrote an error there.").arg(source),
            [Translation.tr("Most of these are noise: programs complain about things that do not affect you. It matters only if something you use misbehaves at the same time."),
             every ? Translation.tr("It shows up at every start, so it is most likely a harmless habit.") : ""].filter(s => s.length > 0).join(" "),
            g?.state === "muted" ? Translation.tr("It is muted, so it will not alert you again. The message itself is the clue to search for if something breaks.")
                : g?.state === "known" ? Translation.tr("It is filed as known noise. If something breaks, the message itself is the clue to search for.")
                : Translation.tr("If nothing is broken, “Mark as known” files it as noise. If something is, the message itself is the clue to search for."));
    }

    function driveProblems(d) {
        const out = [];
        for (const p of Array.from(d?.problems ?? [])) {
            if (p === "spare") out.push(Translation.tr("spare blocks running out"));
            else if (p === "media") out.push(Translation.tr("media errors"));
            else if (p === "wear") out.push(Translation.tr("%1 % of its rated life used").arg(d.percentUsed ?? "?"));
            else if (p === "critical-warning") out.push(Translation.tr("the drive raised a critical warning"));
            else if (p === "ata-failing") out.push(Translation.tr("SMART predicts failure"));
            else if (p === "selftest") out.push(Translation.tr("the last self-test failed"));
            else if (p === "temperature") out.push(Translation.tr("too hot"));
        }
        return out;
    }

    function sourceLabel(src) {
        const s = String(src ?? "");
        if (s === "kernel")
            return Translation.tr("the kernel");
        const m = s.match(/^user@\d+(?:\.service)?\/(.+)$/);
        return m ? m[1] : s;
    }

    function severityLabel(sev) {
        return sev === "critical" ? Translation.tr("Needs attention") : sev === "warning" ? Translation.tr("Worth a look") : Translation.tr("For your information");
    }

    function journalSeen(g) {
        const seen = Number(g?.bootsSeen ?? 0);
        const window = Number(g?.bootsWindow ?? 5);
        if (seen <= 1)
            return Translation.tr("this boot only");
        if (seen >= window)
            return Translation.tr("every boot");
        return Translation.tr("%1 of %2 boots").arg(seen).arg(window);
    }

    /// A one-sentence summary of what needs attention, for the Overview hero.
    function summary(items, now) {
        const list = Array.from(items ?? []);
        if (list.length === 0)
            return Translation.tr("Services are running, nothing crashed this week and no new errors appeared.");
        return list.slice(0, 2).map(f => `${root.title(f)}: ${root.detail(f, now)}.`).join(" ");
    }
}
