pragma Singleton
import Quickshell

Singleton {
    id: root

    // Quickshell only kills its children when it is shut down cleanly (`qs kill`).
    // A SIGTERM'd, SIGINT'd or crashed instance leaves them reparented to init,
    // and any child that stays silent long enough to avoid a SIGPIPE on its dead
    // stdout — an event monitor with nothing to report — then lives forever. Long
    // lived children are given the kernel's parent-death signal instead, which
    // fires no matter how the shell went down.
    //
    // setpriv is util-linux and effectively always present, but the fallback keeps
    // the child working rather than failing to spawn if it ever isn't. bash execs
    // itself away either way, so the child's parent stays Quickshell, which is
    // what the parent-death signal keys on.
    readonly property string pdeathWrapper: 'if command -v setpriv >/dev/null; then exec setpriv --pdeathsig TERM -- "$@"; else exec "$@"; fi'

    /**
     * Wraps a command so it is killed when Quickshell dies, however it dies.
     * Use for processes meant to live as long as the shell, not for one-shots.
     */
    function pdeath(argv) {
        return ["bash", "-c", root.pdeathWrapper, "--", ...argv];
    }

    readonly property string nativeLauncher: Quickshell.shellPath("scripts/native_or_python.sh")

    /**
     * Runs a prebuilt native helper, falling back to its Python twin
     * (<helper>.py) when the binary cannot load here (old glibc, musl, NixOS).
     * `pyFlags` are interpreter flags for the fallback only, e.g. ["-I"].
     */
    function nativeHelper(helperPath, args, pyFlags) {
        const flags = [];
        for (const f of (pyFlags || []))
            flags.push("--py-flag", f);
        return ["sh", root.nativeLauncher, ...flags, helperPath, ...(args || [])];
    }

    /** Shell snippet exiting 0 when the native helper at `helperPath` can load. */
    function nativeProbeCommand(helperPath) {
        return `sh '${root.nativeLauncher}' --probe '${helperPath}'`;
    }
}
